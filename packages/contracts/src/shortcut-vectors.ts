import { ShortcutSnapshot, shortcutSnapshotDigest, type ShortcutSnapshotUnsigned } from "./shortcuts.js";

const user = "usr_1234567890abcdef";
const device = "dev_1234567890abcdef";
const skillDigest = `sha256:${"a".repeat(64)}`;
const time = "2026-08-26T00:00:00.000Z";

export type ShortcutGoldenVector = {
  id: string;
  kind: "shortcut_snapshot";
  input: unknown;
  expected: { contract_valid: boolean; content_digest: string | null; rejection: string | null };
};

export type ShortcutGoldenFixture = {
  schema_version: "mobile-ai-keyboard.shortcut-golden.v1";
  authority: "typescript-contracts";
  native_consumption_status: "not_proven";
  canonicalization: "RFC8785-like canonicalJson from packages/contracts";
  vectors: ShortcutGoldenVector[];
};

function binding(id: string, skillId: string, keyCode = "KeyH") {
  return {
    schema_version: 1 as const, binding_id: id, user_id: user, device_id: device,
    skill_id: skillId, version_id: `sv_${skillId.slice(-16)}`, skill_version: 1, skill_digest: skillDigest,
    trigger_key: { layout_id: "latin_qwerty_v1" as const, key_code: keyCode, display_label: keyCode.slice(-1), activation_gesture: "long_press" as const },
    presentation: { icon_kind: "system" as const, icon_value: "wand.and.stars", short_label: "翻訳", accessibility_label: "画面翻訳", accessibility_hint: "長押しで実行", tint_token: "accent" as const },
    enabled: true, local_eligibility: "local" as const, required_connection_ids: [] as string[], created_at: time, updated_at: time
  };
}

function projection(skillId: string, versionId: string, route = "keyboard_local", tools: unknown[] = []) {
  return { skill_id: skillId, version_id: versionId, skill_version: 1, skill_digest: skillDigest, name: "翻訳", description: "選択範囲を翻訳", input_sources: ["selection" as const], output_type: "insert_text" as const, risk_ceiling: "R1" as const, confirmation: "none" as const, retention: "none" as const, tool_summaries: tools, execution_route: route };
}

function snapshot({ secondBinding = false, route = "keyboard_local", tools = [], mutate }: { secondBinding?: boolean; route?: string; tools?: unknown[]; mutate?: (value: Record<string, unknown>) => Record<string, unknown> } = {}) {
  const first = binding("bind_1234567890abcdef", "skill_1234567890abcdef");
  const bindings = [first];
  const skills = [projection(first.skill_id, first.version_id, route, tools)];
  const keyBindingIds = [first.binding_id];
  if (secondBinding) {
    const second = binding("bind_abcdefabcdefabcd", "skill_abcdefabcdefabcd", "KeyH");
    bindings.push(second);
    skills.push(projection(second.skill_id, second.version_id));
    keyBindingIds.push(second.binding_id);
  }
  const unsigned = {
    schema_version: 1 as const, snapshot_id: "ss_1234567890abcdef", generation: 1, user_subject_hash: null, device_id: device,
    layout: { schema_version: 1 as const, layout_id: "layout_1234567890abcdef", user_id: user, device_id: device, revision: 1, key_binding_ids: keyBindingIds, palette_binding_ids: [] as string[], long_press_duration_ms: 450 as const, cancellation_distance: 10 as const, command_position: "leading" as const, overflow_enabled: true as const, updated_at: time },
    bindings, skills, connection_states: [] as unknown[], policy_epoch: 1, created_at: time, expires_at: null, tombstone_reason: null
  };
  const value = { ...unsigned, content_digest: shortcutSnapshotDigest(unsigned as ShortcutSnapshotUnsigned) } as Record<string, unknown>;
  return mutate ? mutate(value) : value;
}

function vector(id: string, input: unknown, contractValid: boolean, reason: string | null): ShortcutGoldenVector {
  const contentDigest = (input as { content_digest?: unknown } | null)?.content_digest;
  return { id, kind: "shortcut_snapshot", input, expected: { contract_valid: contractValid, content_digest: contractValid && typeof contentDigest === "string" ? contentDigest : null, rejection: reason } };
}

export function buildShortcutGoldenVectors(): ShortcutGoldenFixture {
  return {
    schema_version: "mobile-ai-keyboard.shortcut-golden.v1",
    authority: "typescript-contracts",
    native_consumption_status: "not_proven",
    canonicalization: "RFC8785-like canonicalJson from packages/contracts",
    vectors: [
      vector("valid_local_snapshot", snapshot(), true, null),
      vector("schema_version_rejects_unknown_version", snapshot({ mutate: (value) => ({ ...value, schema_version: 2 }) }), false, "schema"),
      vector("key_normalization_rejects_lowercase_physical_key", snapshot({ mutate: (value) => {
        const first = (value.bindings as Array<Record<string, unknown>>)[0]!;
        return { ...value, bindings: [{ ...first, trigger_key: { ...(first.trigger_key as Record<string, unknown>), key_code: "Keyh" } }] };
      } }), false, "key_normalization"),
      vector("digest_rejects_tampered_content", snapshot({ mutate: (value) => ({ ...value, content_digest: `sha256:${"f".repeat(64)}` }) }), false, "digest"),
      vector("duplicate_physical_key_conflict_rejects_distinct_bindings", snapshot({ secondBinding: true }), false, "duplicate_conflict"),
      vector("local_route_authority_rejects_host_handoff", snapshot({ route: "host_handoff" }), false, "local_route_authority"),
      vector("local_route_authority_rejects_tools", snapshot({ tools: [{ operation: "calendar.availability.read", required_scopes: ["calendar.availability.read"], side_effect: "none" }] }), false, "local_route_authority")
    ]
  };
}

export { ShortcutSnapshot };
