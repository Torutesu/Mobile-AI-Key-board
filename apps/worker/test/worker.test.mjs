import test from 'node:test';
import assert from 'node:assert/strict';
import { planDigest } from '@mobile-ai-keyboard/contracts';
import { executeConfirmedPlan, WorkerError } from '../dist/index.js';

const step = (step_id, operation = 'calendar.event.create_private') => ({
  step_id, operation, risk_class: 'R3', arguments: { title: '打ち合わせ' }, side_effect: 'creates_private_event', reversible: true
});
const makePlan = (steps, run_id = 'run_worker_test') => {
  const unsigned = {
    plan_id: `plan_${run_id}`, plan_version: 1, run_id, risk_class: 'R3',
    summary: '非公開予定を作成', resolved_facts: {}, steps,
    output: { type: 'insert_text', template: '予定を作成しました' },
    confirmation: { required: true, reason: 'external_write', expires_at: '2026-08-26T12:00:00+09:00' }
  };
  return { ...unsigned, canonical_digest: planDigest(unsigned) };
};
const adapterFor = (operation, execute) => new Map([[operation, { operation, execute }]]);

test('rejects an unconfirmed or altered plan before any adapter call', async () => {
  let calls = 0;
  const plan = makePlan([step('step_1')]);
  await assert.rejects(
    executeConfirmedPlan(plan, 'sha256:' + '0'.repeat(64), 'test-unconfirmed', adapterFor(plan.steps[0].operation, async () => { calls += 1; })),
    (error) => error instanceof WorkerError && error.code === 'DIGEST_MISMATCH'
  );
  assert.equal(calls, 0);
});

test('retries the same idempotency key without duplicating an external side effect', async () => {
  let calls = 0;
  const plan = makePlan([step('step_1')]);
  const adapters = adapterFor(plan.steps[0].operation, async (_args, key) => { calls += 1; return { provider_key: key }; });
  const ledger = new Map();
  const first = await executeConfirmedPlan(plan, plan.canonical_digest, 'same-request', adapters, ledger);
  const second = await executeConfirmedPlan(plan, plan.canonical_digest, 'same-request', adapters, ledger);
  assert.equal(calls, 1);
  assert.equal(first.status, 'succeeded');
  assert.deepEqual(second.completed_steps, ['step_1']);
});

test('does not deduplicate the same client key across independent runs', async () => {
  let calls = 0;
  const planA = makePlan([step('step_1')], 'run_a');
  const planB = makePlan([step('step_1')], 'run_b');
  const adapters = adapterFor(planA.steps[0].operation, async () => { calls += 1; });
  const ledger = new Map();
  await executeConfirmedPlan(planA, planA.canonical_digest, 'same-client-key', adapters, ledger);
  await executeConfirmedPlan(planB, planB.canonical_digest, 'same-client-key', adapters, ledger);
  assert.equal(calls, 2);
});

test('projects completed, failed, and not-started steps on partial execution', async () => {
  const first = step('step_1', 'calendar.availability.read');
  const second = step('step_2', 'calendar.event.create_private');
  const third = step('step_3', 'calendar.event.create_private');
  const plan = makePlan([first, second, third]);
  const adapters = new Map([
    [first.operation, { operation: first.operation, execute: async () => ({ available: true }) }],
    [second.operation, { operation: second.operation, execute: async () => { throw new Error('provider rejected'); } }]
  ]);
  const receipt = await executeConfirmedPlan(plan, plan.canonical_digest, 'partial-request', adapters, new Map());
  assert.equal(receipt.status, 'partial');
  assert.deepEqual(receipt.completed_steps, ['step_1']);
  assert.deepEqual(receipt.failed_steps, ['step_2']);
  assert.deepEqual(receipt.not_started_steps, ['step_3']);
});
