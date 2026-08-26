import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { OAuthStateManager, GrantLifecycleManager, NoopEncryptedCredentialStore, PaginationGuard, W4Error, assertQueryForGrant, classifyConnectorError, validateReadOnlyOutcome } from '../dist/index.js';

const user = 'usr_1234567890abcdef'; const otherUser = 'usr_2234567890abcdef'; const device = 'dev_1234567890abcdef'; const session = 'ses_1234567890abcdef';
const fixture = () => { let value = new Date('2026-08-26T00:00:00.000Z'); return { clock: () => new Date(value), advance: (ms) => { value = new Date(value.getTime() + ms); } }; };
const verifier = 'a'.repeat(64); const challenge = createHash('sha256').update(verifier).digest('base64url');
const oauthRequest = { provider: 'notion', requested_scopes: ['notion.pages.search'], redirect_uri: 'https://app.example.test/oauth/callback', code_challenge: challenge, code_challenge_method: 'S256' };

test('binds OAuth state to PKCE and consumes it exactly once', () => {
  const f = fixture(); const oauth = new OAuthStateManager(f.clock); const state = oauth.start(user, device, session, oauthRequest); const nonce = state.nonce; state.nonce = 'x'.repeat(32); const completed = oauth.complete({ state: state.state, nonce, code: 'authorization-code', code_verifier: verifier }); assert.equal(completed.user_id, user);
  assert.throws(() => oauth.complete({ state: state.state, nonce: state.nonce, code: 'authorization-code', code_verifier: verifier }), (error) => error instanceof W4Error && error.code === 'OAUTH_STATE_NOT_FOUND');
  const replayState = oauth.start(user, device, session, oauthRequest); assert.throws(() => oauth.complete({ state: replayState.state, nonce: replayState.nonce, code: 'authorization-code', code_verifier: 'b'.repeat(64) }), (error) => error instanceof W4Error && error.code === 'PKCE_MISMATCH'); assert.throws(() => oauth.complete({ state: replayState.state, nonce: replayState.nonce, code: 'authorization-code', code_verifier: verifier }), (error) => error instanceof W4Error && error.code === 'OAUTH_STATE_NOT_FOUND');
});

test('enforces incremental scopes, owner isolation, rebind, disconnect, and revoke', () => {
  const f = fixture(); const grants = new GrantLifecycleManager(f.clock); const owner = { user_id: user, device_id: device }; const grant = grants.connect(owner, { provider: 'notion', requested_scopes: ['notion.pages.search'], explicit_incremental_consent: false }, 'cred_1234567890abcdef');
  assert.throws(() => grants.connect({ user_id: user, device_id: 'dev_2234567890abcdef' }, { provider: 'notion', requested_scopes: ['notion.pages.search'], explicit_incremental_consent: false }, 'cred_2234567890abcdef'), (error) => error instanceof W4Error && error.code === 'REBIND_OWNER_MISMATCH');
  assert.throws(() => grants.connect(owner, { provider: 'notion', requested_scopes: ['maps.places.search'], explicit_incremental_consent: true }, 'cred_2234567890abcdef'), (error) => error instanceof W4Error && error.code === 'SCOPE_WIDENING');
  assert.throws(() => grants.get(grant.grant_id, { user_id: otherUser }), (error) => error instanceof W4Error && error.code === 'GRANT_OWNER_MISMATCH');
  const rebound = grants.rebind(grant.grant_id, owner, 'dev_2234567890abcdef'); assert.equal(rebound.device_id, 'dev_2234567890abcdef');
  assert.throws(() => grants.rebind(grant.grant_id, { user_id: otherUser, device_id: 'dev_2234567890abcdef' }, 'dev_3234567890abcdef'), (error) => error instanceof W4Error && error.code === 'GRANT_OWNER_MISMATCH');
  assert.equal(grants.disconnect(grant.grant_id, { user_id: user }).status, 'disconnected'); assert.equal(grants.revoke(grant.grant_id, { user_id: user }).status, 'revoked');
});

test('credential store is an interface boundary and pagination is bounded', async () => {
  const store = new NoopEncryptedCredentialStore(); await assert.rejects(store.put({ credential_ref: 'cred_1234567890abcdef', ciphertext: 'placeholder-ciphertext', key_version: 'external', algorithm: 'provider-kms-envelope' }), (error) => error instanceof W4Error && error.code === 'CREDENTIAL_STORE_UNAVAILABLE');
  const pages = new PaginationGuard(2, 3); pages.accept(2, 'next'); assert.throws(() => pages.accept(2), (error) => error instanceof W4Error && error.code === 'PAGINATION_LIMIT');
});

test('read-only query and connector failures remain typed', () => {
  const grant = { grant_id: 'grant_1234567890abcdef', user_id: user, device_id: device, provider: 'maps', scopes: ['maps.places.search'], status: 'active', credential_ref: 'cred_1234567890abcdef', created_at: '2026-08-26T00:00:00.000Z', updated_at: '2026-08-26T00:00:00.000Z' };
  const query = assertQueryForGrant({ provider: 'maps', operation: 'maps.places.search', grant_id: grant.grant_id, query: '駅', page_size: 5 }, grant, user); assert.equal(query.operation, 'maps.places.search');
  const outcome = classifyConnectorError(new W4Error('CONNECTOR_UNKNOWN', 'provider outcome unknown'), 'maps', query.operation); assert.equal(outcome.status, 'unknown'); assert.equal(validateReadOnlyOutcome(outcome).receipt_status, 'unknown');
});
