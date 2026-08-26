import test from 'node:test';
import assert from 'node:assert/strict';
import { classifyPlan, evaluateLocalTextPlan, evaluatePlan, validateLocalDisclosure } from '../dist/index.js';

const step = (operation, risk_class, side_effect = 'none') => ({ step_id: 'step_1', operation, risk_class, arguments: {}, side_effect });
test('recomputes write risk server-side', () => assert.equal(classifyPlan({ steps: [step('calendar.event.create_private', 'R0', 'creates_private_event')] }), 'R3'));
test('prohibits destructive operations', () => assert.deepEqual(evaluatePlan({ steps: [step('payment.create', 'R5', 'destructive')], risk_class: 'R5', confirmation: { required: true } }), { allowed: false, risk_class: 'R5', reason: 'prohibited_operation', operation: 'payment.create' }));
test('fails closed when a local R1 plan contains an external tool', () => {
  const result = evaluateLocalTextPlan({ plan_id: 'p', plan_version: 1, run_id: 'r', operation: 'rewrite', risk_class: 'R1', summary: 'rewrite', capture_fingerprint: 'sha256:' + 'a'.repeat(64), result_revision: 1, destination: 'local_device', network_required: false, tools: ['calendar.event.create_private'], apply_method: 'insert_text', canonical_digest: 'sha256:' + 'b'.repeat(64) });
  assert.deepEqual(result, { allowed: false, reason: 'external_tool' });
});
test('fails closed when local plan network or destination boundary is changed', () => {
  const base = { plan_id: 'p', plan_version: 1, run_id: 'r', operation: 'rewrite', risk_class: 'R1', summary: 'rewrite', capture_fingerprint: 'sha256:' + 'a'.repeat(64), result_revision: 1, destination: 'local_device', network_required: false, tools: [], apply_method: 'insert_text', canonical_digest: 'sha256:' + 'b'.repeat(64) };
  assert.deepEqual(evaluateLocalTextPlan({ ...base, network_required: true }), { allowed: false, reason: 'network_required' });
  assert.deepEqual(evaluateLocalTextPlan({ ...base, destination: 'remote_service' }), { allowed: false, reason: 'wrong_destination' });
});
test('rejects clipboard disclosure without explicit opt-in', () => assert.throws(() => validateLocalDisclosure({ sources: [{ source: 'clipboard', enabled: true, explicit_opt_in: false }], limits: { command_max_characters: 500, selection_max_characters: 4000, surrounding_before_max_characters: 1000, surrounding_after_max_characters: 500, clipboard_max_characters: 4000 }, destination: 'local_device', network_required: false, retention: 'none', issued_at: '2026-08-26T12:00:00+09:00' }), /explicit opt-in/));
