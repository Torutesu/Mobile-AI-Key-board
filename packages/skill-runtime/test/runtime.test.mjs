import test from 'node:test';
import assert from 'node:assert/strict';
import { parseJapaneseRelativeDate, RunStateMachine } from '../dist/index.js';
test('resolves next Tuesday with explicit duration', () => {
  const result = parseJapaneseRelativeDate('来週火曜15時から30分', new Date('2026-08-26T09:00:00Z'), 'Asia/Tokyo');
  assert.equal(result?.start, '2026-09-01T15:00:00+09:00'); assert.equal(result?.end, '2026-09-01T15:30:00+09:00'); assert.equal(result?.requiresConfirmation, true);
});
test('resolves tomorrow without requiring a weekday', () => {
  const result = parseJapaneseRelativeDate('明日15時', new Date('2026-08-26T09:00:00Z'), 'Asia/Tokyo');
  assert.equal(result?.start, '2026-08-27T15:00:00+09:00');
});
test('rejects invalid run transition', () => { const run = new RunStateMachine(); assert.throws(() => run.transition('executing'), { code: 'INVALID_TRANSITION' }); });
