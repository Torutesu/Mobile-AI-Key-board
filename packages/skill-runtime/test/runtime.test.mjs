import test from 'node:test';
import assert from 'node:assert/strict';
import { localDisclosureDigest, localTextPlanDigest } from '@mobile-ai-keyboard/contracts';
import { assertDisclosureAcknowledgement, assertResultRevision, assertUndoAvailable, createLocalCapture, createLocalDisclosure, createLocalPreview, createUndoResult, LocalTextActionError, parseJapaneseRelativeDate, RunStateMachine, validateLocalPlan } from '../dist/index.js';
test('resolves next Tuesday with explicit duration', () => {
  const result = parseJapaneseRelativeDate('来週火曜15時から30分', new Date('2026-08-26T09:00:00Z'), 'Asia/Tokyo');
  assert.equal(result?.start, '2026-09-01T15:00:00+09:00'); assert.equal(result?.end, '2026-09-01T15:30:00+09:00'); assert.equal(result?.requiresConfirmation, true);
});
test('resolves tomorrow without requiring a weekday', () => {
  const result = parseJapaneseRelativeDate('明日15時', new Date('2026-08-26T09:00:00Z'), 'Asia/Tokyo');
  assert.equal(result?.start, '2026-08-27T15:00:00+09:00');
});
test('rejects invalid run transition', () => { const run = new RunStateMachine(); assert.throws(() => run.transition('executing'), { code: 'INVALID_TRANSITION' }); });
test('requires the exact disclosure acknowledgement digest', () => {
  const disclosure = createLocalDisclosure(new Date('2026-08-26T03:00:00Z'));
  assert.equal(localDisclosureDigest(disclosure).startsWith('sha256:'), true);
  assert.throws(() => assertDisclosureAcknowledgement(disclosure, 'sha256:' + '0'.repeat(64)), (error) => error instanceof LocalTextActionError && error.code === 'ACK_DIGEST_MISMATCH');
});
test('captures only disclosed sources and enforces hard limits', () => {
  const disclosure = createLocalDisclosure(); const acknowledgement = localDisclosureDigest(disclosure); const field = 'sha256:' + 'f'.repeat(64);
  const capture = createLocalCapture(disclosure, [{ source: 'command', text: '短い指示' }], field, acknowledgement);
  assert.equal(capture.capture_fingerprint.startsWith('sha256:'), true);
  assert.throws(() => createLocalCapture(disclosure, [{ source: 'clipboard', text: 'secret' }], field, acknowledgement), (error) => error instanceof LocalTextActionError && error.code === 'SOURCE_NOT_OPTED_IN');
  assert.throws(() => createLocalCapture(disclosure, [{ source: 'command', text: 'x'.repeat(501) }], field, acknowledgement), (error) => error instanceof LocalTextActionError && error.code === 'CAPTURE_LIMIT_EXCEEDED');
  assert.throws(() => createLocalCapture(disclosure, [{ source: 'command', text: 'a' }, { source: 'command', text: 'b' }], field, acknowledgement), (error) => error instanceof LocalTextActionError);
});
test('local preview metadata carries no requirement to emit content into telemetry', () => {
  const preview = createLocalPreview('山田さん 090-1234-5678', 'locally_redacted', '山田さん ***********', ['name', 'number'], 12);
  assert.equal(preview.metadata.mode, 'locally_redacted'); assert.ok(preview.metadata.character_count > 0); assert.equal(preview.metadata.redacted_character_count, 12); assert.equal(preview.content.includes('090-'), false);
  assert.throws(() => createLocalPreview('secret', 'locally_redacted', '[redacted]', ['product']), (error) => error instanceof LocalTextActionError && error.code === 'INVALID_DISCLOSURE');
});
test('local R1 plan is immutable and revision/undo guarded', () => {
  const unsigned = { plan_id: 'p', plan_version: 1, run_id: 'r', operation: 'rewrite', risk_class: 'R1', summary: 'ローカル整形', capture_fingerprint: 'sha256:' + 'a'.repeat(64), result_revision: 1, destination: 'local_device', network_required: false, tools: [], apply_method: 'insert_text' };
  const plan = { ...unsigned, canonical_digest: localTextPlanDigest(unsigned) };
  assert.equal(validateLocalPlan(plan).canonical_digest, plan.canonical_digest);
  const result = createUndoResult('結果', 'insert_text', '2026-08-26T12:05:00+09:00', 1);
  assert.doesNotThrow(() => { assertResultRevision(1, result); assertUndoAvailable(result, new Date('2026-08-26T02:00:00Z')); });
  assert.throws(() => assertResultRevision(2, result), (error) => error instanceof LocalTextActionError && error.code === 'RESULT_REVISION_MISMATCH');
});
