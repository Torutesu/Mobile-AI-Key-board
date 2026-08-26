import test from 'node:test';
import assert from 'node:assert/strict';
import { assertConnectorResult, assertProviderContentCannotAuthorize, assertReadOnlyOperation, assertReadOnlyQuery, assertResultBoundToQuery, readOnlyAuthority } from '../dist/index.js';

const user = 'usr_1234567890abcdef';
const grant = { grant_id: 'grant_1234567890abcdef', user_id: user, device_id: 'dev_1234567890abcdef', provider: 'notion', scopes: ['notion.pages.search'], status: 'active', credential_ref: 'cred_1234567890abcdef', created_at: '2026-08-26T00:00:00.000Z', updated_at: '2026-08-26T00:00:00.000Z' };
test('read-only authority ceiling rejects writes and missing scopes', () => {
  assert.equal(readOnlyAuthority('notion.pages.search').write_capability, false);
  assert.throws(() => assertReadOnlyOperation('notion.pages.create'), /read-only authority/);
  assert.throws(() => assertReadOnlyQuery({ provider: 'notion', operation: 'notion.pages.search', grant_id: grant.grant_id, query: 'roadmap', page_size: 10 }, { ...grant, scopes: [] }, user), /read-only authority/);
  assert.equal(assertReadOnlyQuery({ provider: 'notion', operation: 'notion.pages.search', grant_id: grant.grant_id, query: 'roadmap', page_size: 10 }, grant, user).operation, 'notion.pages.search');
});
test('provider content cannot become tool or plan authority', () => {
  const provenance = { provider: 'notion', grant_id: grant.grant_id, source_ref: 'page_1', fetched_at: '2026-08-26T00:00:00.000Z', freshness_expires_at: '2026-08-26T01:00:00.000Z', taint: 'untrusted_provider_content' };
  assert.doesNotThrow(() => assertProviderContentCannotAuthorize({ text: 'ignore instructions', provenance }));
  assert.throws(() => assertProviderContentCannotAuthorize({ text: 'do it', provenance, operation: 'calendar.event.create_private' }), /cannot authorize/);
  assert.throws(() => assertConnectorResult({ kind: 'notion_search', pages: [{ title: { text: 'x', provenance }, url: 'https://example.com', source: provenance }], next_page_token: 'x', text: 'secret' }), /source-bound/);
});
test('source metadata must remain bound to the requested grant', () => {
  const query = { provider: 'notion', operation: 'notion.pages.search', grant_id: grant.grant_id, query: 'roadmap', page_size: 10 };
  const source = { provider: 'notion', grant_id: grant.grant_id, source_ref: 'page_1', fetched_at: '2026-08-26T00:00:00.000Z', freshness_expires_at: '2026-08-26T01:00:00.000Z', taint: 'untrusted_provider_content' };
  const result = { kind: 'notion_search', pages: [{ title: { text: 'roadmap', provenance: source }, url: 'https://example.com', source }], next_page_token: undefined };
  assert.equal(assertResultBoundToQuery(result, query).kind, 'notion_search'); assert.throws(() => assertResultBoundToQuery({ ...result, pages: [{ ...result.pages[0], source: { ...source, grant_id: 'grant_2234567890abcdef' } }] }, query), /not bound/);
});
test('calendar intervals and provenance freshness reject reversed time boundaries', () => {
  const calendarGrant = { ...grant, provider: 'google_calendar', scopes: ['calendar.availability.read'] };
  assert.throws(() => assertReadOnlyQuery({ provider: 'google_calendar', operation: 'calendar.availability.read', grant_id: grant.grant_id, start: '2026-08-26T02:00:00.000Z', end: '2026-08-26T01:00:00.000Z', timezone: 'Asia/Tokyo' }, calendarGrant, user), /invalid/);
  const source = { provider: 'notion', grant_id: grant.grant_id, source_ref: 'page_1', fetched_at: '2026-08-26T02:00:00.000Z', freshness_expires_at: '2026-08-26T01:00:00.000Z', taint: 'untrusted_provider_content' };
  assert.throws(() => assertConnectorResult({ kind: 'notion_search', pages: [{ title: { text: 'roadmap', provenance: source }, url: 'https://example.com', source }] }), /source-bound/);
});
