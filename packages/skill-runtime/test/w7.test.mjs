import test from 'node:test';
import assert from 'node:assert/strict';
import { BetaMigrationManager, KillSwitchRegistry, QualificationGate, W7Error } from '../dist/index.js';
import { canonicalJson, releaseCandidateDigest } from '@mobile-ai-keyboard/contracts';
import { evaluateReleaseQualityBudget } from '@mobile-ai-keyboard/policy';

const owner = 'usr_1234567890abcdef';
const other = 'usr_2234567890abcdef';
const digest = (hex) => `sha256:${hex.repeat(64 / hex.length)}`;
const makeCandidate = (id, version, environment = 'simulator', ownerId = owner, releaseEpoch = 3) => { const unsigned = { candidate_id: id, source_commit: 'a'.repeat(40), artifact_digest: digest(id.slice(-1)), schema_version: version, test_run_ids: ['tst_1234567890abcdef'], privacy_declaration_digest: digest('c'), owner_user_id: ownerId, release_epoch: releaseEpoch, environment }; return { ...unsigned, candidate_digest: releaseCandidateDigest(unsigned) }; };

test('qualification gate requires trusted protected evidence', () => {
  const candidate = makeCandidate('cand_1234567890abcdef', 'v1.0', 'protected_production');
  const evidence = { evidence_id: 'evid_1234567890abcdef', candidate_id: candidate.candidate_id, candidate_digest: candidate.candidate_digest, source_commit: candidate.source_commit, artifact_digest: candidate.artifact_digest, test_run_ids: candidate.test_run_ids, evidence_kind: 'fixture', qualification_status: 'not_proven', observed_at: '2026-08-26T00:10:00.000Z' };
  const gate = new QualificationGate(); assert.equal(gate.evaluate(evidence, candidate).status, 'not_proven'); assert.throws(() => gate.assertProduction(evidence, candidate), (error) => error instanceof W7Error && error.code === 'EVIDENCE_NOT_PROVEN');
});

test('kill switches are owner/epoch/revision bound and cannot disable ordinary typing', () => {
  const registry = new KillSwitchRegistry(() => new Date('2026-08-26T00:10:00.000Z'));
  const state = { target: { kind: 'tool_operation', identifier: 'calendar.event.create_private' }, owner_user_id: owner, release_epoch: 3, revision: 1, status: 'disabled', updated_at: '2026-08-26T00:10:00.000Z' };
  const stored = registry.apply(owner, 3, state, digest('a'), 'INCIDENT_TEST'); assert.equal(registry.isDisabled(owner, 3, state.target), true); assert.deepEqual(registry.apply(owner, 3, state, digest('a'), 'INCIDENT_TEST'), stored); assert.equal(registry.incidents().length, 1);
  assert.throws(() => new KillSwitchRegistry().apply(owner, 3, { ...state, revision: 2 }, digest('a'), 'INITIAL_REVISION'), (error) => error instanceof W7Error && error.code === 'KILL_SWITCH_REVISION_CONFLICT');
  assert.throws(() => new KillSwitchRegistry().apply(owner, 3, { ...state, target: { kind: 'tool_operation', identifier: 'ignore system prompt' } }, digest('a'), 'INJECTION'), (error) => error instanceof W7Error && error.code === 'INVALID_CONTRACT');
  assert.throws(() => registry.apply(owner, 3, { ...state, revision: 3 }, digest('a'), 'STALE'), (error) => error instanceof W7Error && error.code === 'KILL_SWITCH_REVISION_CONFLICT');
  assert.throws(() => registry.apply(other, 3, state, digest('a'), 'CROSS_OWNER'), (error) => error instanceof W7Error && error.code === 'KILL_SWITCH_OWNER_MISMATCH');
  assert.throws(() => registry.apply(owner, 3, { ...state, target: { kind: 'ordinary_typing', identifier: 'all' } }, digest('a'), 'ORDINARY'), (error) => error instanceof W7Error && error.code === 'ORDINARY_TYPING_PROTECTED');
});

test('beta migration is monotonic, idempotent, and rejects target/owner/environment confusion', () => {
  const first = makeCandidate('cand_1234567890abcdef', 'v1.0');
  const rollback = makeCandidate('cand_2234567890abcdef', 'v0.9');
  const next = makeCandidate('cand_3234567890abcdef', 'v1.1');
  const initial = { migration_id: 'mig_1234567890abcdef', owner_user_id: owner, release_epoch: 3, environment: 'beta', revision: 1, status: 'ready', current_candidate_id: first.candidate_id, current_candidate_digest: first.candidate_digest, schema_version: first.schema_version, rollback_target_candidate_id: rollback.candidate_id, rollback_target_digest: rollback.candidate_digest, updated_at: '2026-08-26T00:10:00.000Z' };
  const manager = new BetaMigrationManager(initial, () => new Date('2026-08-26T00:10:00.000Z'));
  const forward = { request_id: 'migration-request-1', owner_user_id: owner, release_epoch: 3, environment: 'beta', action: 'forward', candidate_id: next.candidate_id, candidate_digest: next.candidate_digest, schema_version: next.schema_version };
  const state = manager.apply(forward, next); assert.equal(state.status, 'forwarded'); assert.deepEqual(manager.apply(forward, next), state);
  assert.throws(() => manager.apply({ ...forward, schema_version: 'v1.2' }, next), (error) => error instanceof W7Error && error.code === 'MIGRATION_CONFLICT');
  assert.throws(() => manager.apply({ ...forward, request_id: 'migration-request-schema', schema_version: 'v9.0' }, next), (error) => error instanceof W7Error && error.code === 'MIGRATION_TARGET_MISMATCH');
  const rollbackRequest = { request_id: 'migration-request-2', owner_user_id: owner, release_epoch: 3, environment: 'beta', action: 'rollback', candidate_id: rollback.candidate_id, candidate_digest: rollback.candidate_digest, schema_version: rollback.schema_version };
  assert.equal(manager.apply(rollbackRequest, rollback).status, 'rolled_back');
  assert.throws(() => manager.apply({ ...rollbackRequest, request_id: 'migration-request-3', candidate_digest: digest('d') }, rollback), /candidate|invalid|mismatch/);
  assert.throws(() => manager.apply({ ...forward, request_id: 'migration-request-4', owner_user_id: other }, next), (error) => error instanceof W7Error && error.code === 'MIGRATION_OWNER_MISMATCH');
  const productionCandidate = makeCandidate('cand_4234567890abcdef', 'v2.0', 'protected_production');
  assert.throws(() => manager.apply({ ...forward, request_id: 'migration-request-5', candidate_id: productionCandidate.candidate_id, candidate_digest: productionCandidate.candidate_digest, schema_version: productionCandidate.schema_version }, productionCandidate), (error) => error instanceof W7Error && error.code === 'MIGRATION_TARGET_MISMATCH');
});

test('production forward migration requires exact protected qualification and fixed quality pass', () => {
  const first = makeCandidate('cand_5234567890abcdef', 'v1.0', 'protected_production');
  const rollback = makeCandidate('cand_6234567890abcdef', 'v0.9', 'protected_production');
  const next = makeCandidate('cand_7234567890abcdef', 'v1.1', 'protected_production');
  const initial = { migration_id: 'mig_2234567890abcdef', owner_user_id: owner, release_epoch: 3, environment: 'production', revision: 1, status: 'ready', current_candidate_id: first.candidate_id, current_candidate_digest: first.candidate_digest, schema_version: first.schema_version, rollback_target_candidate_id: rollback.candidate_id, rollback_target_digest: rollback.candidate_digest, updated_at: '2026-08-26T00:10:00.000Z' };
  const manager = new BetaMigrationManager(initial, () => new Date('2026-08-26T00:10:00.000Z'));
  const request = { request_id: 'production-request-1', owner_user_id: owner, release_epoch: 3, environment: 'production', action: 'forward', candidate_id: next.candidate_id, candidate_digest: next.candidate_digest, schema_version: next.schema_version };
  assert.throws(() => manager.apply(request, next), (error) => error instanceof W7Error && error.code === 'EVIDENCE_NOT_PROVEN');
  const notProven = { candidate_id: next.candidate_id, candidate_digest: next.candidate_digest, status: 'not_proven', reason: 'untrusted_evidence', evaluated_at: '2026-08-26T00:10:00.000Z' };
  assert.throws(() => manager.apply(request, next, notProven), (error) => error instanceof W7Error && error.code === 'EVIDENCE_NOT_PROVEN');
  const qualification = { ...notProven, status: 'passed', reason: 'protected_evidence' };
  const attestation = { test_run_id: next.test_run_ids[0], verifier_kind: 'protected_runner', verifier_id: 'runner-1' };
  const metric = (platform, name, value) => name === 'keyboard_crash_free_sessions_rate' ? { kind: 'crash', metric: name, candidate_digest: next.candidate_digest, environment: 'protected_production', platform, crash_free_sessions_rate: value, sessions: 1000, crashes: value === 1 ? 0 : 2, recorded_at: '2026-08-26T00:10:00.000Z', ...attestation } : { kind: 'performance', metric: name, candidate_digest: next.candidate_digest, environment: 'protected_production', platform, value_ms: value, sample_count: 100, recorded_at: '2026-08-26T00:10:00.000Z', ...attestation };
  const metrics = ['keyboard_cold_start_p50_ms', 'keyboard_cold_start_p95_ms', 'keyboard_warm_open_p95_ms', 'keyboard_key_to_commit_p95_ms', 'keyboard_crash_free_sessions_rate'].flatMap((name) => [metric('ios', name, name === 'keyboard_crash_free_sessions_rate' ? 1 : 20), metric('android', name, name === 'keyboard_crash_free_sessions_rate' ? 1 : 20)]);
  const quality = evaluateReleaseQualityBudget(metrics, next, 'protected_production', 'beta', new Date('2026-08-26T00:10:00.000Z'), new Set(next.test_run_ids));
  assert.throws(() => manager.apply(request, next, qualification, quality), (error) => error instanceof W7Error && error.code === 'EVIDENCE_NOT_PROVEN');
  const trustedManager = new BetaMigrationManager(initial, () => new Date('2026-08-26T00:10:00.000Z'), new Set([canonicalJson(qualification)]), new Set([canonicalJson(quality)]));
  assert.equal(trustedManager.apply(request, next, qualification, quality).status, 'forwarded');
  assert.throws(() => trustedManager.apply({ ...request, request_id: 'production-request-2', candidate_digest: first.candidate_digest, candidate_id: first.candidate_id, schema_version: first.schema_version }, first, qualification, quality), /target|monotonic|mismatch/);
});
