import test from 'node:test';
import assert from 'node:assert/strict';
import {
  evaluateQualityBudget,
  evaluateReleaseQualityBudget,
  evaluateQualificationEvidence,
  validateReleaseCandidate
} from '../dist/index.js';
import { releaseCandidateDigest } from '@mobile-ai-keyboard/contracts';

const owner = 'usr_1234567890abcdef';
const digest = (hex) => `sha256:${hex.repeat(64 / hex.length)}`;
const candidate = (overrides = {}) => {
  const unsigned = { candidate_id: 'cand_1234567890abcdef', source_commit: 'a'.repeat(40), artifact_digest: digest('b'), schema_version: 'v1.0', test_run_ids: ['tst_1234567890abcdef'], privacy_declaration_digest: digest('c'), owner_user_id: owner, release_epoch: 3, environment: 'protected_production', ...overrides };
  return { ...unsigned, candidate_digest: releaseCandidateDigest(unsigned) };
};
const evidence = (overrides = {}) => ({ evidence_id: 'evid_1234567890abcdef', candidate_id: candidate().candidate_id, candidate_digest: candidate().candidate_digest, source_commit: candidate().source_commit, artifact_digest: candidate().artifact_digest, test_run_ids: candidate().test_run_ids, evidence_kind: 'fixture', qualification_status: 'not_proven', verifier_kind: 'self_attested', verifier_id: 'local-fixture', observed_at: '2026-08-26T00:10:00.000Z', ...overrides });
const budgets = { keyboard_cold_start_p50_max_ms: 100, keyboard_cold_start_p95_max_ms: 250, keyboard_warm_open_p95_max_ms: 120, keyboard_key_to_commit_p95_max_ms: 80, keyboard_crash_free_sessions_min: 0.999 };
const metrics = (candidateDigest, environment = 'protected_production') => [
  { kind: 'performance', metric: 'keyboard_cold_start_p50_ms', candidate_digest: candidateDigest, environment, platform: 'ios', value_ms: 50, sample_count: 10, recorded_at: '2026-08-26T00:10:00.000Z', test_run_id: 'tst_1234567890abcdef', verifier_kind: environment === 'protected_production' ? 'protected_runner' : 'self_attested', verifier_id: 'runner-1' },
  { kind: 'performance', metric: 'keyboard_cold_start_p95_ms', candidate_digest: candidateDigest, environment, platform: 'ios', value_ms: 150, sample_count: 10, recorded_at: '2026-08-26T00:10:00.000Z', test_run_id: 'tst_1234567890abcdef', verifier_kind: environment === 'protected_production' ? 'protected_runner' : 'self_attested', verifier_id: 'runner-1' },
  { kind: 'performance', metric: 'keyboard_warm_open_p95_ms', candidate_digest: candidateDigest, environment, platform: 'ios', value_ms: 80, sample_count: 10, recorded_at: '2026-08-26T00:10:00.000Z', test_run_id: 'tst_1234567890abcdef', verifier_kind: environment === 'protected_production' ? 'protected_runner' : 'self_attested', verifier_id: 'runner-1' },
  { kind: 'performance', metric: 'keyboard_key_to_commit_p95_ms', candidate_digest: candidateDigest, environment, platform: 'ios', value_ms: 50, sample_count: 10, recorded_at: '2026-08-26T00:10:00.000Z', test_run_id: 'tst_1234567890abcdef', verifier_kind: environment === 'protected_production' ? 'protected_runner' : 'self_attested', verifier_id: 'runner-1' },
  { kind: 'crash', metric: 'keyboard_crash_free_sessions_rate', candidate_digest: candidateDigest, environment, platform: 'ios', crash_free_sessions_rate: 1, sessions: 100, crashes: 0, recorded_at: '2026-08-26T00:10:00.000Z', test_run_id: 'tst_1234567890abcdef', verifier_kind: environment === 'protected_production' ? 'protected_runner' : 'self_attested', verifier_id: 'runner-1' }
].flatMap((metric) => [{ ...metric, platform: 'ios' }, { ...metric, platform: 'android' }]);

test('release candidate digest and evidence are exact and fail closed', () => {
  const value = candidate();
  assert.equal(validateReleaseCandidate(value).candidate_digest, value.candidate_digest);
  assert.throws(() => validateReleaseCandidate({ ...value, artifact_digest: digest('d') }), /digest/);
  assert.throws(() => validateReleaseCandidate({ ...value, candidate_digest: digest('d') }), /digest/);
  assert.throws(() => validateReleaseCandidate({ ...value, test_run_ids: [value.test_run_ids[0], value.test_run_ids[0]] }), /invalid|contract/);
  assert.throws(() => evaluateQualificationEvidence(evidence({ test_run_ids: ['tst_2234567890abcdef'] }), value), /exact candidate/);
  assert.equal(evaluateQualificationEvidence(evidence(), value).status, 'not_proven');
  const protectedEvidence = evidence({ evidence_kind: 'protected_external', qualification_status: 'passed', verifier_kind: 'protected_runner', verifier_id: 'runner-1' });
  assert.equal(evaluateQualificationEvidence(protectedEvidence, value).reason, 'untrusted_evidence');
  assert.equal(evaluateQualificationEvidence(protectedEvidence, value, new Set([protectedEvidence.evidence_id])).status, 'passed');
  assert.equal(evaluateQualificationEvidence(protectedEvidence, { ...value, environment: 'simulator' }, new Set([protectedEvidence.evidence_id])).status, 'not_proven');
  assert.equal(evaluateQualificationEvidence(protectedEvidence, value, new Set([protectedEvidence.evidence_id]), new Date('2026-08-26T00:10:01.000Z')).status, 'passed');
  assert.equal(evaluateQualificationEvidence({ ...protectedEvidence, observed_at: '2026-08-17T00:10:00.000Z' }, value, new Set([protectedEvidence.evidence_id]), new Date('2026-08-26T00:10:00.000Z')).reason, 'evidence_stale');
  assert.equal(evaluateQualificationEvidence({ ...protectedEvidence, observed_at: '2026-08-26T00:11:00.000Z' }, value, new Set([protectedEvidence.evidence_id]), new Date('2026-08-26T00:10:00.000Z')).reason, 'evidence_future');
  assert.throws(() => evaluateQualificationEvidence({ ...protectedEvidence, candidate_digest: digest('d') }, value), /exact candidate/);
});

test('fixture quality and content-bearing telemetry are never production proof', () => {
  const value = candidate();
  assert.equal(evaluateQualityBudget(metrics(value.candidate_digest, 'fixture'), budgets, value.candidate_digest, 'fixture').status, 'not_proven');
  assert.equal(evaluateQualityBudget(metrics(value.candidate_digest), budgets, value.candidate_digest, 'protected_production').status, 'not_proven');
  assert.equal(evaluateReleaseQualityBudget(metrics(value.candidate_digest), value, 'protected_production', 'beta').status, 'not_proven');
  assert.equal(evaluateReleaseQualityBudget(metrics(value.candidate_digest), value, 'protected_production', 'beta', new Date('2026-08-26T00:10:00.000Z'), new Set(value.test_run_ids)).status, 'passed');
  const broadMetrics = metrics(value.candidate_digest).map((metric) => metric.metric === 'keyboard_crash_free_sessions_rate' ? { ...metric, crash_free_sessions_rate: 0.999, crashes: 1, sessions: 1000 } : metric);
  assert.equal(evaluateReleaseQualityBudget(broadMetrics, value, 'protected_production', 'broad', new Date('2026-08-26T00:10:00.000Z'), new Set(value.test_run_ids)).status, 'failed');
  assert.equal(evaluateQualityBudget(metrics(value.candidate_digest).slice(0, 4), budgets, value.candidate_digest, 'protected_production').status, 'not_proven');
  assert.equal(evaluateQualityBudget([...metrics(value.candidate_digest), { text: 'private clipboard text' }], budgets, value.candidate_digest, 'protected_production').status, 'not_proven');
  assert.equal(evaluateQualityBudget(metrics(value.candidate_digest).map((metric) => metric.metric === 'keyboard_crash_free_sessions_rate' ? { ...metric, crashes: 1 } : metric), budgets, value.candidate_digest, 'protected_production').status, 'not_proven');
  assert.equal(evaluateReleaseQualityBudget([...metrics(value.candidate_digest), metrics(value.candidate_digest)[0]], value, 'protected_production', 'beta', new Date(), new Set(value.test_run_ids)).status, 'not_proven');
  assert.equal(evaluateReleaseQualityBudget(metrics(value.candidate_digest).filter((metric) => metric.platform !== 'android'), value, 'protected_production', 'beta', new Date(), new Set(value.test_run_ids)).missing_metrics.every((name) => name.startsWith('android:')), true);
  assert.equal(evaluateReleaseQualityBudget(metrics(value.candidate_digest).map((metric) => metric.platform === 'android' && metric.metric === 'keyboard_cold_start_p50_ms' ? { ...metric, value_ms: 999 } : metric), value, 'protected_production', 'beta', new Date(), new Set(value.test_run_ids)).failed_metrics.includes('android:keyboard_cold_start_p50_ms'), true);
  const reversed = metrics(value.candidate_digest).map((metric) => metric.platform === 'ios' && metric.metric === 'keyboard_cold_start_p50_ms' ? { ...metric, value_ms: 200 } : metric.platform === 'ios' && metric.metric === 'keyboard_cold_start_p95_ms' ? { ...metric, value_ms: 150 } : metric);
  assert.equal(evaluateReleaseQualityBudget(reversed, value, 'protected_production', 'beta', new Date(), new Set(value.test_run_ids)).failed_metrics.includes('ios:keyboard_cold_start_p50_ms'), true);
});
