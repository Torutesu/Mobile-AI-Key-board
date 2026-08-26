import test from 'node:test';
import assert from 'node:assert/strict';
import { canonicalJson, defaultLocalCaptureSources, LocalTextResult, planDigest, TelemetryEvent } from '../dist/index.js';

test('canonical JSON is independent of object insertion order', () => {
  assert.equal(canonicalJson({ z: 1, a: { y: true, x: null } }), '{"a":{"x":null,"y":true},"z":1}');
  assert.equal(planDigest({ plan_id: 'p', plan_version: 1, run_id: 'r', risk_class: 'R0', summary: 'x', resolved_facts: {}, steps: [], output: { type: 'insert_text', template: 'x' }, confirmation: { required: false, reason: 'none', expires_at: '2026-08-26T12:00:00Z' } }), planDigest({ plan_id: 'p', plan_version: 1, run_id: 'r', risk_class: 'R0', summary: 'x', resolved_facts: {}, steps: [], output: { type: 'insert_text', template: 'x' }, confirmation: { required: false, reason: 'none', expires_at: '2026-08-26T12:00:00Z' } }));
});
test('telemetry rejects content-bearing fields', () => assert.equal(TelemetryEvent.safeParse({ name: 'keyboard_opened', platform: 'ios', version: '1', locale: 'ja-JP', cold: true, text: 'secret' }).success, false));
test('clipboard and surrounding text are disabled by default', () => {
  const sources = defaultLocalCaptureSources();
  assert.equal(sources.find((entry) => entry.source === 'clipboard').enabled, false);
  assert.equal(sources.find((entry) => entry.source === 'surrounding_text').enabled, false);
});
test('content-derived capture fingerprints are not telemetry fields', () => assert.equal(TelemetryEvent.safeParse({ name: 'local_text_action_started', action_id: 'act_1234567890abcdef', operation: 'rewrite', preview_mode: 'exact', source_types: ['selection'], result_revision: 1, capture_fingerprint: 'sha256:' + 'a'.repeat(64) }).success, false));
test('undo state and token metadata must agree', () => {
  assert.equal(LocalTextResult.safeParse({ result_revision: 1, text: 'ok', apply_method: 'insert_text', undo: { state: 'available' } }).success, false);
  assert.equal(LocalTextResult.safeParse({ result_revision: 1, text: 'ok', apply_method: 'insert_text', undo: { state: 'unavailable', token: 'undo_1234567890abcdef', expires_at: '2026-08-26T12:00:00+09:00' } }).success, false);
  assert.equal(LocalTextResult.safeParse({ result_revision: 1, text: 'ok', apply_method: 'insert_text', undo: { state: 'used', token: 'undo_1234567890abcdef', expires_at: '2026-08-26T12:00:00+09:00' } }).success, false);
  assert.equal(LocalTextResult.safeParse({ result_revision: 1, text: 'ok', apply_method: 'insert_text', undo: { state: 'expired', token: 'undo_1234567890abcdef', expires_at: '2026-08-26T12:00:00+09:00' } }).success, false);
});
test('W2 text limits count Unicode code points instead of UTF-16 code units', () => {
  const astral = '😀'.repeat(10_000);
  assert.equal(LocalTextResult.safeParse({ result_revision: 1, text: astral, apply_method: 'copy', undo: { state: 'unavailable' } }).success, true);
  assert.equal(LocalTextResult.safeParse({ result_revision: 1, text: astral + '😀', apply_method: 'copy', undo: { state: 'unavailable' } }).success, false);
});
