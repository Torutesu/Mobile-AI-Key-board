import test from 'node:test';
import assert from 'node:assert/strict';
import { canonicalJson, planDigest, TelemetryEvent } from '../dist/index.js';

test('canonical JSON is independent of object insertion order', () => {
  assert.equal(canonicalJson({ z: 1, a: { y: true, x: null } }), '{"a":{"x":null,"y":true},"z":1}');
  assert.equal(planDigest({ plan_id: 'p', plan_version: 1, run_id: 'r', risk_class: 'R0', summary: 'x', resolved_facts: {}, steps: [], output: { type: 'insert_text', template: 'x' }, confirmation: { required: false, reason: 'none', expires_at: '2026-08-26T12:00:00Z' } }), planDigest({ plan_id: 'p', plan_version: 1, run_id: 'r', risk_class: 'R0', summary: 'x', resolved_facts: {}, steps: [], output: { type: 'insert_text', template: 'x' }, confirmation: { required: false, reason: 'none', expires_at: '2026-08-26T12:00:00Z' } }));
});
test('telemetry rejects content-bearing fields', () => assert.equal(TelemetryEvent.safeParse({ name: 'keyboard_opened', platform: 'ios', version: '1', locale: 'ja-JP', cold: true, text: 'secret' }).success, false));
