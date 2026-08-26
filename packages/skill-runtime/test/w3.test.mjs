import test from 'node:test';
import assert from 'node:assert/strict';
import { DeviceRegistry, SessionManager, PlanBindingStore, AppendOnlyReceiptStore, AppendOnlyAuditStore, AccountDeletionStateMachine, RetentionStore, W3Error } from '../dist/index.js';

const user = 'usr_1234567890abcdef';
const device = 'dev_1234567890abcdef';
const request = (challenge, deviceId = device) => ({ device_id: deviceId, platform: 'ios', public_key_algorithm: 'ed25519', public_key: 'A'.repeat(43), challenge_id: challenge.challenge_id, challenge_nonce: challenge.nonce, proof_signature: 'B'.repeat(86), app_version: '0.1.0' });
const clockFixture = () => { let time = new Date('2026-08-26T00:00:00.000Z'); return { clock: () => new Date(time), advance: (ms) => { time = new Date(time.getTime() + ms); } }; };

test('requires challenge-bound device proof and rejects challenge replay', () => {
  const fixture = clockFixture(); const registry = new DeviceRegistry(fixture.clock, () => true); const challenge = registry.issueChallenge(user);
  const registered = registry.register(request(challenge), user); assert.equal(registered.user_id, user);
  assert.throws(() => registry.register(request(challenge, 'dev_2234567890abcdef'), user), (error) => error instanceof W3Error && error.code === 'CHALLENGE_NOT_FOUND');
  const expired = registry.issueChallenge(user, 1); fixture.advance(2); assert.throws(() => registry.register(request(expired, 'dev_3234567890abcdef'), user), (error) => error instanceof W3Error && error.code === 'CHALLENGE_EXPIRED');
});

test('rotates sessions and revokes a family on stale-token replay', () => {
  const fixture = clockFixture(); const registry = new DeviceRegistry(fixture.clock, () => true); const challenge = registry.issueChallenge(user); registry.register(request(challenge), user); const sessions = new SessionManager(registry, fixture.clock);
  const first = sessions.issue(user, device); assert.equal(sessions.authenticate(first.access_token, user).generation, 1);
  const next = sessions.rotate(first.family_id, first.access_token, user); assert.equal(sessions.authenticate(next.access_token, user).generation, 2);
  assert.throws(() => sessions.rotate(first.family_id, first.access_token, user), (error) => error instanceof W3Error && error.code === 'SESSION_REPLAY');
  assert.throws(() => sessions.authenticate(next.access_token, user), (error) => error instanceof W3Error && error.code === 'SESSION_REVOKED');
});

test('binds one immutable plan and enforces authenticated run owner', () => {
  const store = new PlanBindingStore(); const base = { binding_id: 'bind_1234567890abcdef', run_id: 'run_1', user_id: user, device_id: device, plan_id: 'p', plan_version: 1, plan_digest: 'sha256:' + 'a'.repeat(64), policy_epoch: 'policy-1', bound_at: '2026-08-26T00:00:00.000Z' };
  assert.equal(store.bind(base).plan_version, 1); const returned = store.bind({ ...base }); returned.plan_version = 99; assert.equal(store.get('run_1', user, device).plan_version, 1); assert.throws(() => store.bind({ ...base, plan_version: 2 }), (error) => error instanceof W3Error && error.code === 'BINDING_CONFLICT'); assert.equal(store.get('run_1', user, device).plan_id, 'p'); assert.throws(() => store.get('run_1', 'usr_2234567890abcdef', device), (error) => error instanceof W3Error && error.code === 'SESSION_OWNER_MISMATCH');
});

test('receipt and audit metadata are append-only and content-free', () => {
  const receipts = new AppendOnlyReceiptStore(); const base = { receipt_id: 'rcpt_1234567890abcdef', run_id: 'run_1', user_id: user, device_id: device, status: 'pending', step_metadata: [], plan_digest: 'sha256:' + 'a'.repeat(64), request_id: 'req_1', occurred_at: '2026-08-26T00:00:00.000Z' };
  receipts.append({ ...base, event_id: 'aud_1234567890abcdef', sequence: 1 }); assert.throws(() => receipts.append({ ...base, event_id: 'aud_2234567890abcdef', sequence: 3 }), (error) => error instanceof W3Error && error.code === 'RECEIPT_APPEND_CONFLICT'); assert.throws(() => receipts.append({ ...base, event_id: 'aud_2234567890abcdef', sequence: 2, text: 'secret' }), (error) => error instanceof W3Error && error.code === 'INVALID_CONTRACT'); assert.throws(() => receipts.append({ ...base, event_id: 'aud_3234567890abcdef', sequence: 2, user_id: 'usr_2234567890abcdef' }), (error) => error instanceof W3Error && error.code === 'RECEIPT_APPEND_CONFLICT'); assert.throws(() => receipts.append({ ...base, receipt_id: 'rcpt_2234567890abcdef', event_id: 'aud_1234567890abcdef', sequence: 1 }), (error) => error instanceof W3Error && error.code === 'RECEIPT_APPEND_CONFLICT');
  const audit = new AppendOnlyAuditStore(); const event = { event_id: 'aud_3234567890abcdef', actor_user_id: user, actor_device_id: device, actor_session_id: 'ses_1234567890abcdef', action: 'run_created', object_type: 'run', object_id: 'run_1', outcome: 'accepted', request_id: 'req_1', occurred_at: '2026-08-26T00:00:00.000Z' }; audit.append(event); assert.throws(() => audit.append({ ...event, text: 'secret' }), (error) => error instanceof W3Error && error.code === 'INVALID_CONTRACT');
});

test('deletion follows explicit state transitions and retention expiry', () => {
  const fixture = clockFixture(); const deletion = new AccountDeletionStateMachine(user, fixture.clock); assert.throws(() => deletion.transition('deleted'), (error) => error instanceof W3Error && error.code === 'INVALID_DELETION_TRANSITION'); assert.equal(deletion.transition('requested').status, 'requested'); assert.equal(deletion.transition('grace_period', 1).status, 'grace_period'); assert.throws(() => deletion.transition('deleted'), (error) => error instanceof W3Error && error.code === 'INVALID_DELETION_TRANSITION'); deletion.transition('deleting'); assert.equal(deletion.transition('deleted').status, 'deleted');
  const retention = new RetentionStore(fixture.clock); const scheduled = retention.schedule('content-1', { record_type: 'content', retention_class: 'transient_content', max_age_seconds: 1, purge_strategy: 'scheduled' }); scheduled.expiresAt = 0; assert.throws(() => retention.schedule('content-1', scheduled.rule), (error) => error instanceof W3Error && error.code === 'RETENTION_CONFLICT'); fixture.advance(1_001); const due = retention.due(); assert.equal(due.length, 1); due[0].expiresAt = Number.MAX_SAFE_INTEGER; assert.equal(retention.due().length, 1); retention.apply('content-1'); assert.equal(retention.due().length, 0);
});
