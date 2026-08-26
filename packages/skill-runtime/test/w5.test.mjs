import test from 'node:test';
import assert from 'node:assert/strict';
import { calendarWritePlanDigest } from '@mobile-ai-keyboard/contracts';
import { CalendarWriteExecutor, W5Error } from '../dist/index.js';

const owner = { user_id: 'usr_1234567890abcdef', device_id: 'dev_1234567890abcdef' };
const otherOwner = { user_id: 'usr_2234567890abcdef', device_id: 'dev_2234567890abcdef' };
const grant = { grant_id: 'grant_1234567890abcdef', ...owner, connection_epoch: 7, provider: 'google_calendar', scopes: ['calendar.events.create_private'], status: 'active' };
const clockFixture = () => { let value = new Date('2026-08-26T00:05:00.000Z'); return { clock: () => new Date(value), advance: (ms) => { value = new Date(value.getTime() + ms); } }; };
const makePlan = (overrides = {}) => {
  const unsigned = { plan_id: 'plan_calendar_1', plan_version: 1, run_id: 'run_calendar_1', step_id: 'step_calendar', ...owner, grant_id: grant.grant_id, connection_epoch: 7, operation: 'calendar.event.create_private', risk_class: 'R3', scope: 'calendar.events.create_private', summary: 'private appointment', input: { title: 'Appointment', start: '2026-08-26T01:00:00.000Z', end: '2026-08-26T01:30:00.000Z', timezone: 'UTC', attendees: [], send_updates: 'none' }, confirmation_required: true, expires_at: '2026-08-26T00:30:00.000Z', ...overrides };
  const { canonical_digest: _ignored, ...withoutDigest } = unsigned;
  return { ...unsigned, canonical_digest: calendarWritePlanDigest(withoutDigest) };
};
const makeRequest = (plan, overrides = {}) => ({ plan, confirmation: { plan_id: plan.plan_id, run_id: plan.run_id, ...owner, grant_id: plan.grant_id, connection_epoch: plan.connection_epoch, plan_digest: plan.canonical_digest, confirmation_method: 'explicit_tap', confirmed_at: '2026-08-26T00:00:00.000Z', expires_at: '2026-08-26T00:20:00.000Z', client_idempotency_key: 'client-key-1', ...overrides } });
const adapterFixture = (createOutcome = { status: 'succeeded', provider_operation_key: 'provider-op-1', resource_key: 'google:event-1' }, deleteOutcome = { status: 'succeeded' }) => { const calls = { create: 0, delete: 0, keys: [] }; return { calls, adapter: { createPrivateEvent: async (_input, key) => { calls.create += 1; calls.keys.push(key); return createOutcome; }, deleteOwnEvent: async (resource, key) => { calls.delete += 1; calls.keys.push(`${resource}:${key}`); return deleteOutcome; } } }; };

test('rejects digest mutation, expired confirmation, replay, and ownership/grant confusion', async () => {
  const f = clockFixture(); const fixture = adapterFixture(); const executor = new CalendarWriteExecutor(fixture.adapter, f.clock);
  const plan = makePlan(); const first = await executor.execute(makeRequest(plan), grant, owner); assert.equal(first.status, 'succeeded');
  await assert.rejects(executor.execute(makeRequest({ ...plan, input: { ...plan.input, title: 'mutated' } }), grant, owner), (error) => error instanceof W5Error && error.code === 'PLAN_DIGEST_MISMATCH');
  await assert.rejects(executor.execute(makeRequest(plan, { client_idempotency_key: 'client-key-2' }), grant, owner), (error) => error instanceof W5Error && error.code === 'CONFIRMATION_REPLAYED');
  await assert.rejects(executor.execute(makeRequest(plan), { ...grant, connection_epoch: 8 }, owner), (error) => error instanceof W5Error && error.code === 'OWNER_GRANT_MISMATCH');
  await assert.rejects(executor.execute(makeRequest(plan), grant, otherOwner), (error) => error instanceof W5Error && error.code === 'OWNER_GRANT_MISMATCH');
  const expiredClock = clockFixture(); expiredClock.advance(31 * 60_000); const expiredExecutor = new CalendarWriteExecutor(adapterFixture().adapter, expiredClock.clock);
  await assert.rejects(expiredExecutor.execute(makeRequest(makePlan({ run_id: 'run_expired', plan_id: 'plan_expired', step_id: 'step_expired' })), grant, owner), (error) => error instanceof W5Error && error.code === 'PLAN_EXPIRED');
});

test('deduplicates same run/digest/step/client key, but detects digest collision and isolates runs/steps', async () => {
  const f = clockFixture(); const fixture = adapterFixture(); const executor = new CalendarWriteExecutor(fixture.adapter, f.clock);
  const plan = makePlan(); const request = makeRequest(plan); const [first, second] = await Promise.all([executor.execute(request, grant, owner), executor.execute(request, grant, owner)]); assert.equal(first.receipt_id, second.receipt_id); assert.equal(fixture.calls.create, 1);
  const conflicting = makePlan({ plan_id: 'plan_calendar_2', summary: 'different plan' }); await assert.rejects(executor.execute(makeRequest(conflicting), grant, owner), (error) => error instanceof W5Error && error.code === 'IDEMPOTENCY_CONFLICT');
  const otherRun = makePlan({ run_id: 'run_calendar_2', plan_id: 'plan_calendar_2', step_id: 'step_calendar_2' }); await executor.execute(makeRequest(otherRun), grant, owner); assert.equal(fixture.calls.create, 2);
});

test('unknown outcome persists an executor key, blocks blind retry, and reconciles only with exact key/resource', async () => {
  const f = clockFixture(); const fixture = adapterFixture({ status: 'unknown' }); const executor = new CalendarWriteExecutor(fixture.adapter, f.clock); const plan = makePlan();
  const unknown = await executor.execute(makeRequest(plan), grant, owner); assert.equal(unknown.status, 'unknown'); assert.match(unknown.provider_operation_key, /:provider$/);
  await assert.rejects(executor.execute(makeRequest(plan, { client_idempotency_key: 'client-key-2' }), grant, owner), (error) => error instanceof W5Error && error.code === 'UNKNOWN_RETRY_BLOCKED');
  await assert.rejects(executor.reconcile(unknown.receipt_id, owner, 'wrong-operation-key', { status: 'succeeded', resource_key: 'google:event-1' }), (error) => error instanceof W5Error && error.code === 'RECONCILIATION_MISMATCH');
  const settled = await executor.reconcile(unknown.receipt_id, owner, unknown.provider_operation_key, { status: 'succeeded', resource_key: 'google:event-1' }); assert.equal(settled.status, 'succeeded'); assert.equal(settled.resource_key, 'google:event-1');
});

test('undo is exact-resource, bounded, idempotent, and cannot be replayed or misused', async () => {
  const f = clockFixture(); const fixture = adapterFixture(); const executor = new CalendarWriteExecutor(fixture.adapter, f.clock); const plan = makePlan(); const receipt = await executor.execute(makeRequest(plan), grant, owner);
  const undo = { receipt_id: receipt.receipt_id, run_id: receipt.run_id, plan_digest: receipt.plan_digest, ...owner, grant_id: receipt.grant_id, connection_epoch: receipt.connection_epoch, operation: 'calendar.event.delete_own', scope: 'calendar.events.delete_own', resource_key: receipt.resource_key, idempotency_key: 'undo-key-1' };
  const result = await executor.undo(undo, owner); assert.equal(result.status, 'succeeded'); assert.equal(fixture.calls.delete, 1); assert.equal((await executor.undo(undo, owner)).receipt_id, result.receipt_id);
  await assert.rejects(executor.undo({ ...undo, idempotency_key: 'undo-key-2' }, owner), (error) => error instanceof W5Error && error.code === 'UNDO_ALREADY_USED');
  const f2 = clockFixture(); const e2 = new CalendarWriteExecutor(adapterFixture().adapter, f2.clock, 1_000); const r2 = await e2.execute(makeRequest(makePlan({ run_id: 'run_calendar_2', plan_id: 'plan_calendar_2', step_id: 'step_calendar_2' })), grant, owner); f2.advance(2_000);
  await assert.rejects(e2.undo({ ...undo, receipt_id: r2.receipt_id, run_id: r2.run_id, plan_digest: r2.plan_digest, resource_key: r2.resource_key }, owner), (error) => error instanceof W5Error && error.code === 'UNDO_EXPIRED');
  const e3 = new CalendarWriteExecutor(adapterFixture().adapter, f.clock); const r3 = await e3.execute(makeRequest(makePlan({ run_id: 'run_calendar_3', plan_id: 'plan_calendar_3', step_id: 'step_calendar_3' })), grant, owner);
  await assert.rejects(e3.undo({ ...undo, receipt_id: r3.receipt_id, run_id: r3.run_id, plan_digest: r3.plan_digest, resource_key: 'google:other-resource', idempotency_key: 'undo-key-3' }, owner), (error) => error instanceof W5Error && error.code === 'RESOURCE_MISMATCH');
});
