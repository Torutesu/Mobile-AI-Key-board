import {
  ShortcutActivation,
  ShortcutLayout,
  ShortcutSnapshot,
  ShortcutSkillProjection,
  TriggerKeyBinding,
  canonicalJson,
  shortcutSnapshotDigest,
  type ShortcutActivation as ShortcutActivationData,
  type ShortcutLayout as ShortcutLayoutData,
  type ShortcutSnapshot as ShortcutSnapshotData,
  type ShortcutSkillProjection as ShortcutSkillProjectionData,
  type TriggerKeyBinding as TriggerKeyBindingData,
  type SkillVersion as SkillVersionData,
  type UserId,
  type DeviceId
} from "@mobile-ai-keyboard/contracts";
import { SkillDefinition } from "@mobile-ai-keyboard/contracts";
import { PolicyViolation } from "./index.js";

const reservedKeyCodes = new Set(["Space", "Enter", "Tab", "Backspace", "Shift", "CapsLock", "Delete", "Globe", "Emoji", "Dictation", "Numbers", "Symbols"]);
const keyCode = (value: string): boolean => /^Key[A-Z]$/.test(value) && !reservedKeyCodes.has(value);
const iso = (value: string): number => Date.parse(value);
const ownerMatches = (value: { user_id: string; device_id: string }, owner: { user_id: UserId; device_id: DeviceId }): boolean => value.user_id === owner.user_id && value.device_id === owner.device_id;

function reject(message: string, code: string, details: Record<string, unknown> = {}): never {
  throw new PolicyViolation(message, { code, ...details });
}

function derivedEligibility(version: SkillVersionData): TriggerKeyBindingData["local_eligibility"] {
  const effects = version.definition.tools.map((tool) => tool.side_effect);
  if (effects.some((effect) => effect !== "none")) return "confirmed_write";
  if (version.definition.tools.length > 0) return "connected_read";
  return "local";
}

export function validateShortcutBinding(value: unknown, version: SkillVersionData, owner: { user_id: UserId; device_id: DeviceId }): TriggerKeyBindingData {
  const parsed = TriggerKeyBinding.safeParse(value);
  if (!parsed.success) reject("Shortcut binding contract is invalid", "INVALID_SHORTCUT_BINDING", { issues: parsed.error.issues });
  const binding = parsed.data;
  if (!ownerMatches(binding, owner) || version.owner_user_id !== owner.user_id) reject("Shortcut binding is not owned by the authenticated device", "SHORTCUT_OWNER_MISMATCH");
  if (binding.skill_id !== version.skill_id || binding.version_id !== version.version_id || binding.skill_version !== version.version || binding.skill_digest !== version.contract_digest) reject("Shortcut binding does not match the immutable Skill version", "SHORTCUT_VERSION_MISMATCH");
  if (!keyCode(binding.trigger_key.key_code)) reject("Shortcut trigger key is reserved or unsupported", "RESERVED_TRIGGER_KEY");
  if (binding.trigger_key.layout_id !== "latin_qwerty_v1") reject("Shortcut layout is unsupported", "UNSUPPORTED_LAYOUT");
  if (binding.local_eligibility !== derivedEligibility(version)) reject("Shortcut eligibility is not derived from the Skill", "ELIGIBILITY_MISMATCH");
  if (binding.local_eligibility === "local" && binding.required_connection_ids.length > 0) reject("Local Skills cannot require connections", "CONNECTION_AUTHORITY_MISMATCH");
  if (binding.local_eligibility !== "local" && binding.required_connection_ids.length === 0) reject("Connected Skills require an opaque connection reference", "CONNECTION_REQUIRED");
  if (iso(binding.created_at) < iso(version.published_at)) reject("Shortcut binding predates its Skill version", "SHORTCUT_CHRONOLOGY");
  return binding;
}

export function validateShortcutLayout(value: unknown, bindings: readonly TriggerKeyBindingData[], owner: { user_id: UserId; device_id: DeviceId }): ShortcutLayoutData {
  const parsed = ShortcutLayout.safeParse(value);
  if (!parsed.success) reject("Shortcut layout contract is invalid", "INVALID_SHORTCUT_LAYOUT", { issues: parsed.error.issues });
  const layout = parsed.data;
  if (!ownerMatches(layout, owner)) reject("Shortcut layout is not owned by the authenticated device", "SHORTCUT_OWNER_MISMATCH");
  const byId = new Map<string, TriggerKeyBindingData>();
  for (const binding of bindings) {
    if (!ownerMatches(binding, owner)) reject("Layout references a binding owned by another device", "SHORTCUT_OWNER_MISMATCH");
    if (byId.has(binding.binding_id)) reject("Shortcut binding IDs must be unique", "DUPLICATE_BINDING_ID");
    byId.set(binding.binding_id, binding);
  }
  const keys = new Set<string>();
  for (const id of layout.key_binding_ids) {
    const binding = byId.get(id); if (!binding) reject("Layout references a missing binding", "MISSING_BINDING_REFERENCE", { binding_id: id });
    if (!binding.enabled) reject("Disabled bindings cannot be executable layout entries", "DISABLED_BINDING_REFERENCE", { binding_id: id });
    if (!keyCode(binding.trigger_key.key_code)) reject("Layout contains a reserved trigger key", "RESERVED_TRIGGER_KEY", { key_code: binding.trigger_key.key_code });
    if (keys.has(binding.trigger_key.key_code)) reject("Two active bindings cannot own one physical key", "DUPLICATE_TRIGGER_KEY", { key_code: binding.trigger_key.key_code });
    keys.add(binding.trigger_key.key_code);
  }
  const palette = new Set<string>();
  for (const id of layout.palette_binding_ids) {
    const binding = byId.get(id); if (!binding) reject("Palette references a missing binding", "MISSING_BINDING_REFERENCE", { binding_id: id });
    if (!binding.enabled) reject("Disabled bindings cannot appear in the palette", "DISABLED_BINDING_REFERENCE", { binding_id: id });
    if (palette.has(id)) reject("Palette binding IDs must be unique", "DUPLICATE_PALETTE_ID");
    palette.add(id);
  }
  const enabledIds = new Set(bindings.filter((binding) => binding.enabled).map((binding) => binding.binding_id));
  if (enabledIds.size !== layout.key_binding_ids.length || layout.key_binding_ids.some((id) => !enabledIds.has(id))) {
    reject("Every enabled physical-key binding must be present exactly once in the layout", "ENABLED_BINDING_OUTSIDE_LAYOUT");
  }
  return layout;
}

function projectionForBinding(snapshot: ShortcutSnapshotData, binding: TriggerKeyBindingData): ShortcutSkillProjectionData | undefined {
  return snapshot.skills.find((skill) => skill.skill_id === binding.skill_id && skill.version_id === binding.version_id);
}

export function validateShortcutSnapshot(value: unknown, lastGeneration: number, device: DeviceId | { user_id: UserId; device_id: DeviceId }): ShortcutSnapshotData {
  const parsed = ShortcutSnapshot.safeParse(value);
  if (!parsed.success) reject("Shortcut snapshot contract is invalid", "INVALID_SHORTCUT_SNAPSHOT", { issues: parsed.error.issues });
  const snapshot = parsed.data;
  if (Buffer.byteLength(canonicalJson(snapshot), "utf8") > 256 * 1024) reject("Shortcut snapshot exceeds the bounded shared-storage size", "SNAPSHOT_TOO_LARGE");
  const expectedDeviceId = typeof device === "string" ? device : device.device_id;
  if (snapshot.device_id !== expectedDeviceId) reject("Shortcut snapshot belongs to another device", "SHORTCUT_DEVICE_MISMATCH");
  if (typeof device !== "string" && snapshot.layout.user_id !== device.user_id) reject("Shortcut snapshot belongs to another owner", "SHORTCUT_OWNER_MISMATCH");
  if (!Number.isInteger(lastGeneration) || lastGeneration < 0) reject("Last snapshot generation is invalid", "INVALID_GENERATION");
  if (snapshot.generation <= lastGeneration) reject("Shortcut snapshot generation is not strictly monotonic", "GENERATION_REPLAY", { last_generation: lastGeneration, generation: snapshot.generation });
  const unsigned = { ...snapshot } as Omit<ShortcutSnapshotData, "content_digest">;
  delete (unsigned as Partial<ShortcutSnapshotData>).content_digest;
  if (shortcutSnapshotDigest(unsigned) !== snapshot.content_digest) reject("Shortcut snapshot digest does not match canonical content", "SNAPSHOT_DIGEST_MISMATCH");
  const bindings = snapshot.bindings.map((binding) => {
    if (!ownerMatches(binding, { user_id: snapshot.layout.user_id, device_id: snapshot.device_id })) reject("Snapshot binding owner/device mismatch", "SHORTCUT_OWNER_MISMATCH");
    if (!keyCode(binding.trigger_key.key_code)) reject("Snapshot contains a reserved trigger key", "RESERVED_TRIGGER_KEY");
    return binding;
  });
  validateShortcutLayout(snapshot.layout, bindings, { user_id: snapshot.layout.user_id, device_id: snapshot.device_id });
  const skillKeys = new Set<string>();
  for (const skill of snapshot.skills) {
    const identity = `${skill.skill_id}:${skill.version_id}`;
    if (skillKeys.has(identity)) reject("Snapshot contains duplicate Skill projections", "DUPLICATE_SKILL_PROJECTION");
    skillKeys.add(identity);
  }
  for (const skill of snapshot.skills) {
    if (!bindings.some((binding) => binding.skill_id === skill.skill_id && binding.version_id === skill.version_id)) reject("Snapshot contains an unreferenced Skill projection", "ORPHAN_SKILL_PROJECTION", { skill_id: skill.skill_id, version_id: skill.version_id });
  }
  for (const binding of bindings) {
    const projection = projectionForBinding(snapshot, binding);
    if (!projection || projection.skill_version !== binding.skill_version || projection.skill_digest !== binding.skill_digest) reject("Snapshot Skill projection does not match its binding", "PROJECTION_BINDING_MISMATCH", { binding_id: binding.binding_id });
  }
  const connectionIds = new Set(snapshot.connection_states.map((connection) => connection.connection_id));
  for (const binding of bindings) for (const connectionId of binding.required_connection_ids) if (!connectionIds.has(connectionId)) reject("Snapshot binding references a missing connection state", "MISSING_CONNECTION_STATE", { connection_id: connectionId });
  if (snapshot.tombstone_reason === null && snapshot.layout.user_id.length === 0) reject("Live snapshot requires an owner", "SHORTCUT_OWNER_MISMATCH");
  return snapshot;
}

export type ShortcutEditorContext = { editor_session_id: string; device_id: DeviceId; field_safety: "safe" | "sensitive" | "unsupported" };
export function validateShortcutActivation(value: unknown, snapshot: ShortcutSnapshotData, editor: ShortcutEditorContext, now = new Date()): ShortcutActivationData {
  const parsed = ShortcutActivation.safeParse(value);
  if (!parsed.success) reject("Shortcut activation contract is invalid", "INVALID_SHORTCUT_ACTIVATION", { issues: parsed.error.issues });
  const activation = parsed.data;
  if (activation.device_id !== editor.device_id || activation.device_id !== snapshot.device_id) reject("Shortcut activation device binding does not match", "SHORTCUT_DEVICE_MISMATCH");
  if (activation.editor_session_id !== editor.editor_session_id) reject("Shortcut activation editor session is stale", "EDITOR_SESSION_MISMATCH");
  if (activation.field_safety !== "safe" || editor.field_safety !== "safe") reject("Shortcut activation is not allowed in this field", "UNSUPPORTED_FIELD");
  if (activation.snapshot_generation !== snapshot.generation) reject("Shortcut activation snapshot generation is stale", "GENERATION_MISMATCH");
  const binding = snapshot.bindings.find((candidate) => candidate.binding_id === activation.binding_id);
  if (!binding || !binding.enabled) reject("Shortcut activation binding is missing or disabled", "BINDING_NOT_ACTIVE");
  if (binding.skill_id !== activation.skill_id || binding.version_id !== activation.version_id || binding.skill_digest !== activation.skill_digest) reject("Shortcut activation does not match the immutable Skill version", "SHORTCUT_VERSION_MISMATCH");
  const requested = iso(activation.requested_at); const expiry = iso(activation.expires_at); const current = now.getTime();
  if (requested > current) reject("Shortcut activation cannot originate in the future", "ACTIVATION_FUTURE");
  if (expiry <= current) reject("Shortcut activation has expired", "ACTIVATION_EXPIRED");
  return activation;
}

export { ShortcutSkillProjection };
