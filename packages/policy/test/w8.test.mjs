import test from 'node:test';
import assert from 'node:assert/strict';
import {
  contextualSuggestionDigest,
  publisherIdentityDigest,
  safetyMetadataDigest,
  skillReportDigest,
  signedSkillPackageDigest,
  teamPolicyPackageDigest
} from '@mobile-ai-keyboard/contracts';
import {
  evaluatePublisherEvidence,
  validateContextualSuggestion,
  validateSafetyMetadata,
  validateSkillReport,
  validateSignedSkillPackage,
  validateTeamPolicyPackage,
  validateTeamPolicyRevocation
} from '../dist/index.js';

const user = 'usr_1234567890abcdef';
const digest = (hex) => `sha256:${hex.repeat(64 / hex.length)}`;
const identity = () => { const unsigned = { publisher_id: 'pub_1234567890abcdef', kind: 'individual', owner_user_id: user, display_name: 'Verified publisher', signing_key_id: 'pkey_1234567890abcdef', public_key_digest: digest('a') }; return { ...unsigned, identity_digest: publisherIdentityDigest(unsigned) }; };
const pkg = () => { const unsigned = { package_id: 'spkg_1234567890abcdef', skill_id: 'skill_1234567890abcdef', version_id: 'sv_1234567890abcdef', skill_version: 1, publisher_id: identity().publisher_id, definition_digest: digest('b'), package_schema_version: 1, signing_key_id: identity().signing_key_id, signed_at: '2026-08-26T00:10:00.000Z' }; return { ...unsigned, package_digest: signedSkillPackageDigest(unsigned), signature: 'signed-fixture' }; };
const teamPolicy = (overrides = {}) => { const unsigned = { policy_id: 'tpol_1234567890abcdef', team_id: 'team_1234567890abcdef', owner_user_id: user, version: 1, policy_epoch: 1, allowed_tools: [{ operation: 'calendar.availability.read', required_scopes: ['calendar.availability.read'] }], risk_ceiling: 'R2', confirmation: 'policy_required', created_at: '2026-08-26T00:10:00.000Z', ...overrides }; return { ...unsigned, package_digest: teamPolicyPackageDigest(unsigned) }; };
const suggestion = () => { const unsigned = { suggestion_id: 'sugg_1234567890abcdef', owner_user_id: user, device_id: 'dev_1234567890abcdef', skill_id: 'skill_1234567890abcdef', version_id: 'sv_1234567890abcdef', package_digest: pkg().package_digest, source_types: ['selection'], suggestion_kind: 'skill_hint', local_only: true, network_required: false, auto_execute: false, requires_user_action: true, expires_at: '2026-08-26T00:20:00.000Z', generated_at: '2026-08-26T00:10:00.000Z' }; return { ...unsigned, suggestion_digest: contextualSuggestionDigest(unsigned) }; };
const metadata = (overrides = {}) => { const unsigned = { metadata_id: 'smeta_1234567890abcdef', skill_id: pkg().skill_id, version_id: pkg().version_id, package_digest: pkg().package_digest, publisher_id: identity().publisher_id, publisher_name: 'Verified publisher', publisher_verification: 'not_proven', requested_operations: ['calendar.availability.read'], requested_scopes: ['calendar.availability.read'], input_types: ['text'], risk_class: 'R2', version: 1, last_reviewed_at: '2026-08-25T00:10:00.000Z', installs: 20, completion_numerator: 8, completion_denominator: 10, completion_rate: 0.8, confidence: 'low', issue_counts: { security: 1, privacy: 1, malware: 0, quality: 0, policy: 0, resolved: 1, critical: 0 }, provenance: 'not_proven', ...overrides }; return { ...unsigned, metadata_digest: safetyMetadataDigest(unsigned) }; };

test('publisher package digest and trusted verification are exact, stale-safe, and not self-attested', () => {
  const publisher = identity(); const packageValue = pkg(); assert.equal(validateSignedSkillPackage(packageValue, publisher).package_digest, packageValue.package_digest);
  assert.throws(() => validateSignedSkillPackage({ ...packageValue, definition_digest: digest('c') }, publisher), /digest/);
  const fixture = { evidence_id: 'pve_1234567890abcdef', publisher_id: publisher.publisher_id, package_id: packageValue.package_id, package_digest: packageValue.package_digest, identity_digest: publisher.identity_digest, signing_key_id: publisher.signing_key_id, verification_status: 'not_proven', verifier_kind: 'fixture', observed_at: '2026-08-26T00:10:00.000Z' };
  assert.equal(evaluatePublisherEvidence(fixture, packageValue, publisher).status, 'not_proven');
  const protectedEvidence = { ...fixture, verification_status: 'verified', verifier_kind: 'protected_verifier', verifier_id: 'runner-1' };
  const decision = evaluatePublisherEvidence(protectedEvidence, packageValue, publisher, new Set([fixture.evidence_id])); assert.equal(decision.status, 'verified'); assert.equal(decision.valid_until, '2026-09-02T00:10:00.000Z');
  assert.equal(evaluatePublisherEvidence(protectedEvidence, packageValue, publisher, new Set([fixture.evidence_id]), new Date('2026-08-26T00:10:01.000Z')).status, 'verified');
  assert.equal(evaluatePublisherEvidence({ ...protectedEvidence, observed_at: '2026-08-01T00:10:00.000Z' }, packageValue, publisher, new Set([fixture.evidence_id])).status, 'not_proven');
  assert.throws(() => evaluatePublisherEvidence({ ...protectedEvidence, package_digest: digest('d') }, packageValue, publisher), /bound/);
});

test('team policies are exact, explicit, R4-closed, and suggestions carry no content or execution authority', () => {
  const policy = teamPolicy(); assert.equal(validateTeamPolicyPackage(policy).version, 1); assert.throws(() => validateTeamPolicyPackage(teamPolicy({ allowed_tools: [{ operation: 'calendar.availability.read', required_scopes: ['calendar.write'] }] })), /allowlist|scope/);
  assert.throws(() => validateTeamPolicyPackage(teamPolicy({ risk_ceiling: 'R4', allowed_tools: [] })), /R4/);
  assert.throws(() => validateTeamPolicyPackage(teamPolicy({ allowed_tools: [{ operation: 'email.send', required_scopes: ['email.send'] }] })), /R4|prohibited/);
  assert.throws(() => validateTeamPolicyPackage({ ...policy, package_digest: digest('d') }), /digest/);
  const value = suggestion(); assert.equal(validateContextualSuggestion(value, new Date('2026-08-26T00:10:01.000Z')).suggestion_digest, value.suggestion_digest); assert.throws(() => validateContextualSuggestion({ ...value, suggestion_digest: digest('d') }, new Date('2026-08-26T00:10:01.000Z')), /digest/); assert.throws(() => validateContextualSuggestion({ ...value, text: 'private text' }, new Date('2026-08-26T00:10:01.000Z')), /invalid/);
});

test('safety metadata derives rate/confidence and never upgrades unproven provenance', () => {
  const value = metadata(); assert.equal(validateSafetyMetadata(value, new Date('2026-08-26T00:10:00.000Z')).confidence, 'low'); assert.throws(() => validateSafetyMetadata({ ...value, completion_rate: 0.9 }), /invalid|digest|derived/); assert.throws(() => validateSafetyMetadata({ ...value, confidence: 'high' }), /digest|confidence/);
  const protectedValue = metadata({ publisher_verification: 'verified', provenance: 'protected_verified', completion_denominator: 100, completion_numerator: 90, completion_rate: 0.9, confidence: 'high' }); assert.throws(() => validateSafetyMetadata(protectedValue), /trusted|proven/); assert.equal(validateSafetyMetadata(protectedValue, new Date('2026-08-26T00:10:00.000Z'), new Set([protectedValue.metadata_id])).provenance, 'protected_verified');
  const { metadata_digest: _discardedDigest, ...valueUnsigned } = value; const noSampleUnsigned = { ...valueUnsigned, completion_numerator: 0, completion_denominator: 0 }; delete noSampleUnsigned.completion_rate; const noSample = { ...noSampleUnsigned, metadata_digest: safetyMetadataDigest(noSampleUnsigned) }; assert.equal(validateSafetyMetadata(noSample, new Date('2026-08-26T00:10:00.000Z')).completion_rate, undefined); assert.throws(() => validateSafetyMetadata({ ...noSample, completion_rate: 0, metadata_digest: safetyMetadataDigest({ ...noSampleUnsigned, completion_rate: 0 }) }), /invalid|absent/);
  const critical = metadata({ issue_counts: { security: 1, privacy: 0, malware: 0, quality: 0, policy: 0, resolved: 0, critical: 2 } }); assert.throws(() => validateSafetyMetadata(critical), /invalid|reported/); assert.throws(() => validateSafetyMetadata(metadata({ issue_counts: { security: 0, privacy: 0, malware: 0, quality: 0, policy: 0, resolved: 1, critical: 0 } }), new Date('2026-08-26T00:10:00.000Z')), /invalid|reported/); assert.throws(() => validateSafetyMetadata(metadata({ last_reviewed_at: '2026-07-25T00:10:00.000Z' }), new Date('2026-08-26T00:10:00.000Z')), /stale|bounded/); assert.throws(() => validateSafetyMetadata(metadata({ last_reviewed_at: '2026-08-27T00:10:00.000Z' }), new Date('2026-08-26T00:10:00.000Z')), /future|bounded/);
});

test('skill reports bind their content-free digest before moderation can reference them', () => {
  const unsigned = { report_id: 'srep_1234567890abcdef', skill_id: pkg().skill_id, version_id: pkg().version_id, package_digest: pkg().package_digest, reporter_user_id: user, category: 'security', created_at: '2026-08-26T00:10:00.000Z' }; const report = { ...unsigned, report_digest: skillReportDigest(unsigned) }; assert.equal(validateSkillReport(report).report_id, report.report_id); assert.throws(() => validateSkillReport({ ...report, category: 'privacy' }), /digest/);
});

test('team policy revocations are exact, owner/epoch bound, and revisioned', () => {
  const policy = teamPolicy(); const action = { revocation_id: 'trev_1234567890abcdef', team_id: policy.team_id, owner_user_id: user, policy_id: policy.policy_id, version: policy.version, policy_epoch: policy.policy_epoch, package_digest: policy.package_digest, revoked: true, revision: 1, occurred_at: '2026-08-26T00:10:00.000Z' }; assert.equal(validateTeamPolicyRevocation(action, policy, user).revision, 1); assert.throws(() => validateTeamPolicyRevocation({ ...action, owner_user_id: 'usr_2234567890abcdef' }, policy, user), /owner|exact/); assert.throws(() => validateTeamPolicyRevocation({ ...action, policy_epoch: 2 }, policy, user), /epoch|exact/); assert.equal(validateTeamPolicyRevocation({ ...action, revocation_id: 'trev_2234567890abcdef', revision: 2 }, policy, user, action).revision, 2);
});
