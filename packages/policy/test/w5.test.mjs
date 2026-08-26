import test from 'node:test';
import assert from 'node:assert/strict';
import { calendarWritePlanDigest, CalendarPrivateWritePlan, CalendarWriteReceipt } from '@mobile-ai-keyboard/contracts';
import { assertCalendarConfirmation, assertCalendarWriteGrant, validateCalendarWritePlan } from '../dist/index.js';

const owner = { user_id: 'usr_1234567890abcdef', device_id: 'dev_1234567890abcdef' };
const grant = { grant_id: 'grant_1234567890abcdef', ...owner, connection_epoch: 7, provider: 'google_calendar', scopes: ['calendar.events.create_private'], status: 'active' };
const basePlan = () => {
  const unsigned = { plan_id: 'plan_calendar_1', plan_version: 1, run_id: 'run_calendar_1', step_id: 'step_calendar', ...owner, grant_id: grant.grant_id, connection_epoch: 7, operation: 'calendar.event.create_private', risk_class: 'R3', scope: 'calendar.events.create_private', summary: 'private appointment', input: { title: 'Appointment', start: '2026-08-26T01:00:00.000Z', end: '2026-08-26T01:30:00.000Z', timezone: 'UTC', attendees: [], send_updates: 'none' }, confirmation_required: true, expires_at: '2026-08-26T00:30:00.000Z' };
  return { ...unsigned, canonical_digest: calendarWritePlanDigest(unsigned) };
};
const confirmation = (plan, extra = {}) => ({ plan_id: plan.plan_id, run_id: plan.run_id, ...owner, grant_id: plan.grant_id, connection_epoch: plan.connection_epoch, plan_digest: plan.canonical_digest, confirmation_method: 'explicit_tap', confirmed_at: '2026-08-26T00:00:00.000Z', expires_at: '2026-08-26T00:20:00.000Z', client_idempotency_key: 'client-key-1', ...extra });

test('canonical digest binds every mutable plan field and rejects tampering', () => {
  const plan = basePlan(); assert.equal(validateCalendarWritePlan(plan).canonical_digest, plan.canonical_digest);
  assert.throws(() => validateCalendarWritePlan({ ...plan, input: { ...plan.input, title: 'tampered' } }), /digest/);
  assert.throws(() => validateCalendarWritePlan({ ...plan, input: { ...plan.input, attendees: ['invite@example.test'] } }), /invalid|attendees/i);
  assert.throws(() => CalendarPrivateWritePlan.parse({ ...plan, confirmation_required: false }), /true/);
});

test('R3 confirmation is explicit, owner/grant/epoch bound, and time bounded', () => {
  const plan = basePlan();
  assert.doesNotThrow(() => { assertCalendarWriteGrant(grant, plan, owner); assertCalendarConfirmation(confirmation(plan), plan, owner, new Date('2026-08-26T00:05:00.000Z')); });
  assert.throws(() => assertCalendarWriteGrant({ ...grant, connection_epoch: 8 }, plan, owner), /epoch|match/);
  assert.throws(() => assertCalendarConfirmation(confirmation(plan, { connection_epoch: 8 }), plan, owner, new Date('2026-08-26T00:05:00.000Z')), /bound/);
  assert.throws(() => assertCalendarConfirmation(confirmation(plan, { confirmed_at: '2026-08-26T00:06:00.000Z' }), plan, owner, new Date('2026-08-26T00:05:00.000Z')), /future/);
  assert.throws(() => assertCalendarConfirmation(confirmation(plan, { expires_at: '2026-08-26T00:40:00.000Z' }), plan, owner, new Date('2026-08-26T00:05:00.000Z')), /expired/);
});

test('receipt metadata cannot carry event content and undo invariants are fail closed', () => {
  const base = { receipt_id: 'rcpt_1234567890abcdef', run_id: 'run_calendar_1', step_id: 'step_calendar', plan_digest: 'sha256:' + 'a'.repeat(64), ...owner, grant_id: grant.grant_id, connection_epoch: 7, operation: 'calendar.event.create_private', status: 'succeeded', provider_operation_key: 'provider-op-1', resource_key: 'google:event-1', idempotency_key: 'client-key-1', plan_expires_at: '2026-08-26T00:30:00.000Z', undo_expires_at: '2026-08-26T00:20:00.000Z', undo_state: 'available' };
  assert.equal(CalendarWriteReceipt.parse(base).resource_key, 'google:event-1');
  assert.throws(() => CalendarWriteReceipt.parse({ ...base, title: 'secret' }), /unrecognized|unknown/i);
  assert.throws(() => CalendarWriteReceipt.parse({ ...base, undo_state: 'unavailable' }), /expiry/);
  assert.throws(() => CalendarWriteReceipt.parse({ ...base, undo_state: 'available', undo_expires_at: undefined }), /available/);
  assert.throws(() => CalendarWriteReceipt.parse({ ...base, status: 'unknown', resource_key: undefined, provider_operation_key: undefined, error_kind: 'unknown_outcome', undo_state: 'unavailable', undo_expires_at: undefined }), /operation key/);
  assert.throws(() => CalendarWriteReceipt.parse({ ...base, status: 'partial', resource_key: undefined, error_kind: undefined, undo_state: 'unavailable', undo_expires_at: undefined }), /typed error/);
});
