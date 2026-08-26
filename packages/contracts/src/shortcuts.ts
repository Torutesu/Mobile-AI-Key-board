import { z } from "zod";
import { DeviceId, UserId } from "./w3.js";
import { canonicalJson } from "./canonical.js";
import { createHash } from "node:crypto";

const Digest = z.string().regex(/^sha256:[a-f0-9]{64}$/);
const Opaque = (prefix: string) => z.string().regex(new RegExp(`^${prefix}_[A-Za-z0-9_-]{16,128}$`));
const BindingId = Opaque("bind");
const SkillId = Opaque("skill");
const VersionId = Opaque("sv");
const SnapshotId = Opaque("ss");
const ActivationId = Opaque("act");
const ConnectionId = z.string().regex(/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/);
const SafeText = (max: number) => z.string().max(max).refine((value) => value.trim().length > 0 && !/[\u0000-\u001f\u007f]/u.test(value), { message: "text must be nonblank and free of control characters" });

export const ShortcutPresentation = z.object({
  icon_kind: z.enum(["system", "text"]),
  icon_value: z.string().min(1).max(80).refine((value) => !/[\u0000-\u001f\u007f]/u.test(value) && !/^(?:https?:|data:|file:)/iu.test(value), { message: "icon must be an allowlisted local identifier" }),
  short_label: SafeText(120),
  accessibility_label: SafeText(320),
  accessibility_hint: SafeText(640),
  tint_token: z.enum(["neutral", "accent", "read", "write"])
}).strict().superRefine((value, context) => {
  const iconLength = Array.from(value.icon_value).length;
  if (value.icon_kind === "system" && !/^[a-z][a-z0-9_.-]{1,79}$/u.test(value.icon_value)) context.addIssue({ code: z.ZodIssueCode.custom, path: ["icon_value"], message: "system icon must be an allowlisted semantic identifier" });
  if (value.icon_kind === "text" && (iconLength < 1 || iconLength > 3)) context.addIssue({ code: z.ZodIssueCode.custom, path: ["icon_value"], message: "text icon must contain 1 to 3 graphemes" });
  if (Array.from(value.short_label).length > 24) context.addIssue({ code: z.ZodIssueCode.custom, path: ["short_label"], message: "short label must contain at most 24 graphemes" });
  if (Array.from(value.accessibility_label).length < 2 || Array.from(value.accessibility_label).length > 80) context.addIssue({ code: z.ZodIssueCode.custom, path: ["accessibility_label"], message: "accessibility label must contain 2 to 80 graphemes" });
  if (Array.from(value.accessibility_hint).length < 1 || Array.from(value.accessibility_hint).length > 160) context.addIssue({ code: z.ZodIssueCode.custom, path: ["accessibility_hint"], message: "accessibility hint must contain 1 to 160 graphemes" });
});
export type ShortcutPresentation = z.infer<typeof ShortcutPresentation>;

export const TriggerKeyBinding = z.object({
  schema_version: z.literal(1),
  binding_id: BindingId,
  user_id: UserId,
  device_id: DeviceId,
  skill_id: SkillId,
  version_id: VersionId,
  skill_version: z.number().int().positive(),
  skill_digest: Digest,
  trigger_key: z.object({
    layout_id: z.literal("latin_qwerty_v1"),
    key_code: z.string().regex(/^Key[A-Z]$/),
    display_label: z.string().regex(/^[A-Z]$/),
    activation_gesture: z.literal("long_press")
  }).strict(),
  presentation: ShortcutPresentation,
  enabled: z.boolean(),
  local_eligibility: z.enum(["local", "connected_read", "confirmed_write"]),
  required_connection_ids: z.array(ConnectionId).max(5),
  created_at: z.string().datetime({ offset: true }),
  updated_at: z.string().datetime({ offset: true })
}).strict().superRefine((value, context) => {
  if (value.trigger_key.display_label !== value.trigger_key.key_code.slice(-1)) context.addIssue({ code: z.ZodIssueCode.custom, path: ["trigger_key", "display_label"], message: "display label must be derived from key code" });
  if (new Set(value.required_connection_ids).size !== value.required_connection_ids.length) context.addIssue({ code: z.ZodIssueCode.custom, path: ["required_connection_ids"], message: "connection IDs must be unique" });
  if (Date.parse(value.updated_at) < Date.parse(value.created_at)) context.addIssue({ code: z.ZodIssueCode.custom, path: ["updated_at"], message: "updated_at cannot precede created_at" });
});
export type TriggerKeyBinding = z.infer<typeof TriggerKeyBinding>;
/** Architecture-document name retained as an explicit alias. */
export const ShortcutBindingV1 = TriggerKeyBinding;
export type ShortcutBindingV1 = TriggerKeyBinding;

export const ShortcutLayout = z.object({
  schema_version: z.literal(1),
  layout_id: z.string().regex(/^layout_[A-Za-z0-9_-]{16,128}$/),
  user_id: UserId,
  device_id: DeviceId,
  revision: z.number().int().positive(),
  key_binding_ids: z.array(BindingId).max(26),
  palette_binding_ids: z.array(BindingId).max(32),
  long_press_duration_ms: z.literal(450),
  cancellation_distance: z.union([z.literal(10), z.literal(12)]),
  command_position: z.literal("leading"),
  overflow_enabled: z.literal(true),
  updated_at: z.string().datetime({ offset: true })
}).strict().superRefine((value, context) => {
  if (new Set(value.key_binding_ids).size !== value.key_binding_ids.length) context.addIssue({ code: z.ZodIssueCode.custom, path: ["key_binding_ids"], message: "key binding IDs must be unique" });
  if (new Set(value.palette_binding_ids).size !== value.palette_binding_ids.length) context.addIssue({ code: z.ZodIssueCode.custom, path: ["palette_binding_ids"], message: "palette binding IDs must be unique" });
});
export type ShortcutLayout = z.infer<typeof ShortcutLayout>;
export const ShortcutLayoutV1 = ShortcutLayout;
export type ShortcutLayoutV1 = ShortcutLayout;

export const ShortcutSkillProjection = z.object({
  skill_id: SkillId,
  version_id: VersionId,
  skill_version: z.number().int().positive(),
  skill_digest: Digest,
  name: SafeText(240),
  description: SafeText(2_000),
  input_sources: z.array(z.enum(["command", "selection", "surrounding_text", "clipboard", "current_datetime", "locale", "location"])).max(7),
  output_type: z.enum(["insert_text", "replace_selection", "copy", "json"]),
  risk_ceiling: z.enum(["R0", "R1", "R2", "R3"]),
  confirmation: z.enum(["none", "policy_required"]),
  retention: z.enum(["none", "transient_content", "receipt_metadata"]),
  tool_summaries: z.array(z.object({ operation: z.string().regex(/^[a-z][a-z0-9_.-]{2,100}$/), required_scopes: z.array(z.string().regex(/^[a-z][a-z0-9_.-]{2,100}$/)).max(5), side_effect: z.enum(["none", "creates_private_event", "updates_private_resource"]) }).strict()).max(16),
  execution_route: z.enum(["keyboard_local", "keyboard_network", "host_handoff"])
}).strict().superRefine((value, context) => {
  if (new Set(value.input_sources).size !== value.input_sources.length) context.addIssue({ code: z.ZodIssueCode.custom, path: ["input_sources"], message: "input sources must be unique" });
});
export type ShortcutSkillProjection = z.infer<typeof ShortcutSkillProjection>;
export const ShortcutSkillProjectionV1 = ShortcutSkillProjection;
export type ShortcutSkillProjectionV1 = ShortcutSkillProjection;

const ConnectionState = z.object({ connection_id: ConnectionId, state: z.enum(["active", "expired", "revoked", "missing"]), epoch: z.number().int().nonnegative() }).strict();

export const ShortcutSnapshot = z.object({
  schema_version: z.literal(1),
  snapshot_id: SnapshotId,
  generation: z.number().int().positive(),
  user_subject_hash: Digest.nullable(),
  device_id: DeviceId,
  layout: ShortcutLayout,
  bindings: z.array(TriggerKeyBinding).max(32),
  skills: z.array(ShortcutSkillProjection).max(32),
  connection_states: z.array(ConnectionState).max(32),
  policy_epoch: z.number().int().nonnegative(),
  created_at: z.string().datetime({ offset: true }),
  expires_at: z.string().datetime({ offset: true }).nullable(),
  tombstone_reason: z.enum(["signed_out", "account_deleted", "device_revoked"]).nullable(),
  content_digest: Digest
}).strict().superRefine((value, context) => {
  if (value.expires_at !== null && Date.parse(value.expires_at) <= Date.parse(value.created_at)) context.addIssue({ code: z.ZodIssueCode.custom, path: ["expires_at"], message: "snapshot expiry must follow creation" });
  if (new Set(value.connection_states.map((entry) => entry.connection_id)).size !== value.connection_states.length) context.addIssue({ code: z.ZodIssueCode.custom, path: ["connection_states"], message: "connection IDs must be unique" });
  if (value.tombstone_reason !== null && (value.bindings.length > 0 || value.skills.length > 0 || value.connection_states.length > 0 || value.layout.key_binding_ids.length > 0 || value.layout.palette_binding_ids.length > 0)) context.addIssue({ code: z.ZodIssueCode.custom, message: "tombstones cannot retain executable shortcut content" });
});
export type ShortcutSnapshot = z.infer<typeof ShortcutSnapshot>;
export const ShortcutSnapshotV1 = ShortcutSnapshot;
export type ShortcutSnapshotV1 = ShortcutSnapshot;

export const ShortcutActivation = z.object({
  schema_version: z.literal(1),
  activation_id: ActivationId,
  binding_id: BindingId,
  skill_id: SkillId,
  version_id: VersionId,
  skill_digest: Digest,
  snapshot_generation: z.number().int().positive(),
  device_id: DeviceId,
  editor_session_id: z.string().regex(/^[A-Za-z0-9_-]{16,128}$/),
  field_safety: z.enum(["safe", "sensitive", "unsupported"]),
  requested_at: z.string().datetime({ offset: true }),
  expires_at: z.string().datetime({ offset: true })
}).strict().superRefine((value, context) => {
  const requested = Date.parse(value.requested_at); const expires = Date.parse(value.expires_at);
  if (expires <= requested) context.addIssue({ code: z.ZodIssueCode.custom, path: ["expires_at"], message: "activation expiry must follow request" });
  if (expires - requested > 120_000) context.addIssue({ code: z.ZodIssueCode.custom, path: ["expires_at"], message: "activation lifetime exceeds two minutes" });
});
export type ShortcutActivation = z.infer<typeof ShortcutActivation>;
export const ShortcutActivationV1 = ShortcutActivation;
export type ShortcutActivationV1 = ShortcutActivation;

export type ShortcutSnapshotUnsigned = Omit<ShortcutSnapshot, "content_digest">;
export function shortcutSnapshotDigest(snapshot: ShortcutSnapshotUnsigned): string {
  return `sha256:${createHash("sha256").update(canonicalJson(snapshot), "utf8").digest("hex")}`;
}
export const computeShortcutSnapshotDigest = shortcutSnapshotDigest;
