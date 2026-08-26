import test from 'node:test';
import assert from 'node:assert/strict';
import { classifyPlan, evaluatePlan } from '../dist/index.js';

const step = (operation, risk_class, side_effect = 'none') => ({ step_id: 'step_1', operation, risk_class, arguments: {}, side_effect });
test('recomputes write risk server-side', () => assert.equal(classifyPlan({ steps: [step('calendar.event.create_private', 'R0', 'creates_private_event')] }), 'R3'));
test('prohibits destructive operations', () => assert.deepEqual(evaluatePlan({ steps: [step('payment.create', 'R5', 'destructive')], risk_class: 'R5', confirmation: { required: true } }), { allowed: false, risk_class: 'R5', reason: 'prohibited_operation', operation: 'payment.create' }));
