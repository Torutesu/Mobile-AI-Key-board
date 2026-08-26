import test from 'node:test';
import assert from 'node:assert/strict';
import { skillDefinitionDigest, ShortcutSnapshot, shortcutSnapshotDigest } from '@mobile-ai-keyboard/contracts';
import { PolicyViolation, validateShortcutActivation, validateShortcutBinding, validateShortcutLayout, validateShortcutSnapshot } from '../dist/index.js';

const user = 'usr_1234567890abcdef';
const device = 'dev_1234567890abcdef';
const definition = { schema_version: 1, name: '翻訳', description: '選択範囲を翻訳', trigger: { kind: 'phrase', value: '翻訳' }, inputs: [{ name: 'text', type: 'text', sources: ['selection'], required: true, max_characters: 4000 }], tools: [], risk_ceiling: 'R1', confirmation: 'none', output: { type: 'insert_text', template: '翻訳結果' }, retention: 'none', instruction: '選択範囲を翻訳する', tests: [{ name: 'basic', input_fixture: 'hello', expected: { output_text: 'こんにちは' } }] };
const digest = skillDefinitionDigest(definition);
const version = { version_id: 'sv_1234567890abcdef', skill_id: 'skill_1234567890abcdef', version: 1, owner_user_id: user, definition, contract_digest: digest, visibility: 'private', published_at: '2026-08-25T00:00:00.000Z', source_draft_id: 'sdraft_1234567890abcdef' };
const binding = { schema_version: 1, binding_id: 'bind_1234567890abcdef', user_id: user, device_id: device, skill_id: version.skill_id, version_id: version.version_id, skill_version: 1, skill_digest: digest, trigger_key: { layout_id: 'latin_qwerty_v1', key_code: 'KeyH', display_label: 'H', activation_gesture: 'long_press' }, presentation: { icon_kind: 'system', icon_value: 'wand.and.stars', short_label: '翻訳', accessibility_label: '画面翻訳', accessibility_hint: '長押しで実行', tint_token: 'accent' }, enabled: true, local_eligibility: 'local', required_connection_ids: [], created_at: '2026-08-26T00:00:00.000Z', updated_at: '2026-08-26T00:00:00.000Z' };
const layout = { schema_version: 1, layout_id: 'layout_1234567890abcdef', user_id: user, device_id: device, revision: 1, key_binding_ids: [binding.binding_id], palette_binding_ids: [binding.binding_id], long_press_duration_ms: 450, cancellation_distance: 10, command_position: 'leading', overflow_enabled: true, updated_at: '2026-08-26T00:00:00.000Z' };
const projection = { skill_id: version.skill_id, version_id: version.version_id, skill_version: 1, skill_digest: digest, name: '翻訳', description: '選択範囲を翻訳', input_sources: ['selection'], output_type: 'insert_text', risk_ceiling: 'R1', confirmation: 'none', retention: 'none', tool_summaries: [], execution_route: 'keyboard_local' };
const makeSnapshot = (overrides = {}) => { const unsigned = { schema_version: 1, snapshot_id: 'ss_1234567890abcdef', generation: 1, user_subject_hash: null, device_id: device, layout, bindings: [binding], skills: [projection], connection_states: [], policy_epoch: 1, created_at: '2026-08-26T00:00:00.000Z', expires_at: null, tombstone_reason: null, ...overrides }; return { ...unsigned, content_digest: shortcutSnapshotDigest(unsigned) }; };

test('binding policy binds owner, exact immutable version, and rejects reserved keys', () => {
  assert.equal(validateShortcutBinding(binding, version, { user_id: user, device_id: device }).binding_id, binding.binding_id);
  assert.throws(() => validateShortcutBinding({ ...binding, skill_digest: `sha256:${'0'.repeat(64)}` }, version, { user_id: user, device_id: device }), (error) => error instanceof PolicyViolation && error.details.code === 'SHORTCUT_VERSION_MISMATCH');
  assert.throws(() => validateShortcutBinding({ ...binding, trigger_key: { ...binding.trigger_key, key_code: 'Space', display_label: 'S' } }, version, { user_id: user, device_id: device }), /contract|reserved/);
  assert.throws(() => validateShortcutBinding(binding, version, { user_id: 'usr_abcdefabcdefabcd', device_id: device }), /owned|owner/);
});

test('layout detects duplicate physical keys and missing/disabled references', () => {
  assert.doesNotThrow(() => validateShortcutLayout(layout, [binding], { user_id: user, device_id: device }));
  const other = { ...binding, binding_id: 'bind_abcdefabcdefabcd' };
  assert.throws(() => validateShortcutLayout({ ...layout, key_binding_ids: [binding.binding_id, other.binding_id] }, [binding, { ...other, trigger_key: binding.trigger_key }], { user_id: user, device_id: device }), /physical key|physical|one physical|duplicate/i);
  assert.throws(() => validateShortcutLayout({ ...layout, key_binding_ids: ['bind_abcdefabcdefabcd'] }, [binding], { user_id: user, device_id: device }), /missing/i);
  const outside = { ...binding, binding_id: 'bind_fedcbafedcbafedc', trigger_key: { ...binding.trigger_key, key_code: 'KeyM', display_label: 'M' } };
  assert.throws(() => validateShortcutLayout(layout, [binding, outside], { user_id: user, device_id: device }), /enabled physical-key binding/i);
});

test('snapshot rejects digest replay, generation replay, and device confusion', () => {
  const snapshot = makeSnapshot();
  assert.equal(validateShortcutSnapshot(snapshot, 0, { user_id: user, device_id: device }).generation, 1);
  assert.throws(() => validateShortcutSnapshot(snapshot, 1, { user_id: user, device_id: device }), /monotonic|generation/i);
  assert.throws(() => validateShortcutSnapshot({ ...snapshot, generation: 2 }, 0, { user_id: user, device_id: device }), /digest/i);
  assert.throws(() => validateShortcutSnapshot(snapshot, 0, { user_id: user, device_id: 'dev_abcdefabcdefabcd' }), /device/i);
});

test('activation is exact editor/generation bound and cannot run in sensitive fields', () => {
  const snapshot = makeSnapshot();
  const activation = { schema_version: 1, activation_id: 'act_1234567890abcdef', binding_id: binding.binding_id, skill_id: binding.skill_id, version_id: binding.version_id, skill_digest: binding.skill_digest, snapshot_generation: 1, device_id: device, editor_session_id: 'editor_1234567890abcd', field_safety: 'safe', requested_at: '2026-08-26T00:00:00.000Z', expires_at: '2026-08-26T00:01:00.000Z' };
  assert.equal(validateShortcutActivation(activation, snapshot, { editor_session_id: activation.editor_session_id, device_id: device, field_safety: 'safe' }, new Date('2026-08-26T00:00:10.000Z')).binding_id, binding.binding_id);
  assert.throws(() => validateShortcutActivation({ ...activation, snapshot_generation: 2 }, snapshot, { editor_session_id: activation.editor_session_id, device_id: device, field_safety: 'safe' }, new Date('2026-08-26T00:00:10.000Z')), /generation/i);
  assert.throws(() => validateShortcutActivation(activation, snapshot, { editor_session_id: activation.editor_session_id, device_id: device, field_safety: 'sensitive' }, new Date('2026-08-26T00:00:10.000Z')), /field/i);
});
