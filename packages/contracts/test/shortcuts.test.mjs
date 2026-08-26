import test from 'node:test';
import assert from 'node:assert/strict';
import { ShortcutLayout, ShortcutSnapshot, TriggerKeyBinding, shortcutSnapshotDigest } from '../dist/index.js';

const user = 'usr_1234567890abcdef';
const device = 'dev_1234567890abcdef';
const base = {
  schema_version: 1, binding_id: 'bind_1234567890abcdef', user_id: user, device_id: device,
  skill_id: 'skill_1234567890abcdef', version_id: 'sv_1234567890abcdef', skill_version: 1,
  skill_digest: `sha256:${'a'.repeat(64)}`,
  trigger_key: { layout_id: 'latin_qwerty_v1', key_code: 'KeyH', display_label: 'H', activation_gesture: 'long_press' },
  presentation: { icon_kind: 'system', icon_value: 'wand.and.stars', short_label: '翻訳', accessibility_label: '画面翻訳', accessibility_hint: '長押しで実行', tint_token: 'accent' },
  enabled: true, local_eligibility: 'local', required_connection_ids: [],
  created_at: '2026-08-26T00:00:00.000Z', updated_at: '2026-08-26T00:00:00.000Z'
};

test('TriggerKeyBinding is strict and derives the display label from an A-Z physical key', () => {
  assert.equal(TriggerKeyBinding.safeParse(base).success, true);
  assert.equal(TriggerKeyBinding.safeParse({ ...base, trigger_key: { ...base.trigger_key, key_code: 'Keyh' } }).success, false);
  assert.equal(TriggerKeyBinding.safeParse({ ...base, trigger_key: { ...base.trigger_key, display_label: 'A' } }).success, false);
  assert.equal(TriggerKeyBinding.safeParse({ ...base, remote_icon_url: 'https://evil.invalid/icon' }).success, false);
});
test('ShortcutLayout rejects duplicate IDs at the contract boundary', () => {
  const layout = { schema_version: 1, layout_id: 'layout_1234567890abcdef', user_id: user, device_id: device, revision: 1, key_binding_ids: [base.binding_id, base.binding_id], palette_binding_ids: [], long_press_duration_ms: 450, cancellation_distance: 10, command_position: 'leading', overflow_enabled: true, updated_at: '2026-08-26T00:00:00.000Z' };
  assert.equal(ShortcutLayout.safeParse(layout).success, false);
});

test('snapshot digest is canonical and tamper evident', () => {
  const layout = { schema_version: 1, layout_id: 'layout_1234567890abcdef', user_id: user, device_id: device, revision: 1, key_binding_ids: [base.binding_id], palette_binding_ids: [base.binding_id], long_press_duration_ms: 450, cancellation_distance: 10, command_position: 'leading', overflow_enabled: true, updated_at: '2026-08-26T00:00:00.000Z' };
  const unsigned = { schema_version: 1, snapshot_id: 'ss_1234567890abcdef', generation: 1, user_subject_hash: null, device_id: device, layout, bindings: [base], skills: [{ skill_id: base.skill_id, version_id: base.version_id, skill_version: 1, skill_digest: base.skill_digest, name: '翻訳', description: '選択範囲を翻訳', input_sources: ['selection'], output_type: 'insert_text', risk_ceiling: 'R1', confirmation: 'none', retention: 'none', tool_summaries: [], execution_route: 'keyboard_local' }], connection_states: [], policy_epoch: 1, created_at: '2026-08-26T00:00:00.000Z', expires_at: null, tombstone_reason: null };
  const snapshot = { ...unsigned, content_digest: shortcutSnapshotDigest(unsigned) };
  assert.equal(ShortcutSnapshot.safeParse(snapshot).success, true);
  assert.equal(ShortcutSnapshot.safeParse({ ...snapshot, extra: true }).success, false);
  assert.notEqual(shortcutSnapshotDigest({ ...unsigned, generation: 2 }), snapshot.content_digest);
});
