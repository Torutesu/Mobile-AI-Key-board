import test from 'node:test';
import assert from 'node:assert/strict';
import { IdentityService } from '../dist/identity.js';

const user = 'usr_1234567890abcdef';
const device = 'dev_1234567890abcdef';
test('identity service composes challenge proof, rotating sessions, and owner-bound plans', () => {
  const identity = new IdentityService(() => true); const challenge = identity.issueDeviceChallenge(user);
  identity.registerDevice(user, { device_id: device, platform: 'android', public_key_algorithm: 'ed25519', public_key: 'A'.repeat(43), challenge_id: challenge.challenge_id, challenge_nonce: challenge.nonce, proof_signature: 'B'.repeat(86), app_version: '0.1.0' });
  const session = identity.issueSession(user, device); const rotated = identity.rotateSession(session.family_id, session.access_token, user); assert.equal(identity.authenticate(rotated.access_token, user).user_id, user);
  const binding = { binding_id: 'bind_1234567890abcdef', run_id: 'run_identity', user_id: user, device_id: device, plan_id: 'local', plan_version: 1, plan_digest: 'sha256:' + 'a'.repeat(64), policy_epoch: 'w3', bound_at: new Date().toISOString() };
  const bound = identity.bindPlan(binding); assert.equal(identity.assertRunOwner('run_identity', user, device).run_id, bound.run_id);
  const receipt = { event_id: 'aud_1234567890abcdef', receipt_id: 'rcpt_1234567890abcdef', run_id: binding.run_id, user_id: user, device_id: device, sequence: 1, status: 'succeeded', step_metadata: [], plan_digest: binding.plan_digest, request_id: 'req_1', occurred_at: new Date().toISOString() };
  assert.equal(identity.appendReceipt(receipt).sequence, 1);
  assert.throws(() => identity.appendReceipt({ ...receipt, event_id: 'aud_2234567890abcdef', receipt_id: 'rcpt_2234567890abcdef', plan_digest: 'sha256:' + 'b'.repeat(64) }), /immutable run binding/);
  assert.equal(identity.requestDeletion(user).status, 'requested'); assert.equal(identity.devices.get(device).status, 'revoked'); assert.throws(() => identity.authenticate(rotated.access_token, user), /Session is no longer current/);
});
