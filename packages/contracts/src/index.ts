import { createHash } from "node:crypto";
import { z } from "zod";

export const RiskClass = z.enum(["R0", "R1", "R2", "R3", "R4", "R5"]);
export type RiskClass = z.infer<typeof RiskClass>;

export const InputSource = z.enum(["command", "selection", "surrounding_text", "clipboard", "current_datetime", "locale", "location"]);
export type InputSource = z.infer<typeof InputSource>;
export const Platform = z.enum(["ios", "android"]);
export const SideEffect = z.enum(["none", "creates_private_event", "updates_private_resource", "external_communication", "destructive"]);

export const ClientContext = z.object({
  platform: Platform,
  app_version: z.string().min(1).max(64),
  keyboard_version: z.string().min(1).max(64),
  locale: z.string().regex(/^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$/),
  timezone: z.string().min(1).max(64)
}).strict();

export const SkillRef = z.object({ id: z.string().regex(/^[a-z][a-z0-9_.-]{1,63}$/), version: z.number().int().positive() }).strict();
export const CreateRunRequest = z.object({
  skill: SkillRef,
  client: ClientContext,
  available_input_sources: z.array(InputSource).max(7),
  target_capabilities: z.array(z.enum(["insert_text", "replace_selection", "copy"])).max(3)
}).strict();
export type CreateRunRequest = z.infer<typeof CreateRunRequest>;

export const Disclosure = z.object({
  accepted_sources: z.array(InputSource),
  rejected_sources: z.array(InputSource),
  max_characters: z.record(z.number().int().nonnegative().max(100_000)),
  destinations: z.array(z.string().min(1).max(80)),
  retention_class: z.enum(["none", "transient_content", "receipt_metadata"]),
  external_access: z.array(z.string().min(1).max(120))
}).strict();
export type Disclosure = z.infer<typeof Disclosure>;

export const CreateRunResponse = z.object({
  request_id: z.string().min(1), run_id: z.string().min(1), status: z.literal("awaiting_input_disclosure"), disclosure: Disclosure,
  expires_at: z.string().datetime({ offset: true })
}).strict();

export const InputItem = z.object({ source: InputSource, text: z.string().max(10_000) }).strict();
export const SubmitInputRequest = z.object({
  disclosure_acknowledgement: z.string().regex(/^sha256:[a-f0-9]{64}$/),
  inputs: z.array(InputItem).max(7),
  user_locks: z.array(z.string().max(200)).max(100)
}).strict();

export const PlanStep = z.object({
  step_id: z.string().regex(/^step_[a-zA-Z0-9_-]{1,64}$/), operation: z.string().regex(/^[a-z][a-z0-9_.-]{2,100}$/),
  risk_class: RiskClass, arguments: z.record(z.unknown()), side_effect: SideEffect, reversible: z.boolean().optional()
}).strict();
export const ActionPlan = z.object({
  plan_id: z.string().min(1), plan_version: z.number().int().positive(), run_id: z.string().min(1), risk_class: RiskClass,
  summary: z.string().min(1).max(1_000), resolved_facts: z.record(z.unknown()), steps: z.array(PlanStep).max(50),
  output: z.object({ type: z.enum(["insert_text", "replace_selection", "copy"]), template: z.string().max(10_000) }).strict(),
  confirmation: z.object({ required: z.boolean(), reason: z.enum(["none", "external_read", "external_write", "enhanced_confirmation"]), expires_at: z.string().datetime({ offset: true }) }).strict(),
  canonical_digest: z.string().regex(/^sha256:[a-f0-9]{64}$/)
}).strict();
export type ActionPlan = z.infer<typeof ActionPlan>;

export const ConfirmationRequest = z.object({ plan_id: z.string().min(1), canonical_digest: z.string().regex(/^sha256:[a-f0-9]{64}$/), confirmation_method: z.enum(["explicit_tap", "explicit_voice", "passcode"]), client_confirmed_at: z.string().datetime({ offset: true }) }).strict();

export const RunStatus = z.enum(["awaiting_input_disclosure", "awaiting_input", "planning", "awaiting_review", "awaiting_confirmation", "queued", "executing", "succeeded", "partial", "failed", "unknown", "cancelled", "expired"]);
export type RunStatus = z.infer<typeof RunStatus>;
export const ReceiptStatus = z.enum(["pending", "executing", "succeeded", "partial", "failed", "unknown", "undo_pending", "undone", "undo_failed"]);
export type ReceiptStatus = z.infer<typeof ReceiptStatus>;

/** RFC 8785-like canonical JSON for the limited JSON value domain used by plans. */
export function canonicalJson(value: unknown): string {
  if (value === null || typeof value === "boolean" || typeof value === "number" || typeof value === "string") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>).filter(([, v]) => v !== undefined).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0);
    return `{${entries.map(([key, val]) => `${JSON.stringify(key)}:${canonicalJson(val)}`).join(",")}}`;
  }
  throw new TypeError("Plan values must be JSON-compatible");
}

export function planDigest(plan: Omit<ActionPlan, "canonical_digest">): string {
  return `sha256:${createHash("sha256").update(canonicalJson(plan), "utf8").digest("hex")}`;
}

export const TelemetryEvent = z.discriminatedUnion("name", [
  z.object({ name: z.literal("keyboard_opened"), platform: Platform, version: z.string(), locale: z.string(), cold: z.boolean() }).strict(),
  z.object({ name: z.literal("command_started"), skill_id: z.string(), skill_version: z.number().int().positive(), input_source_types: z.array(InputSource), risk_class: RiskClass }).strict(),
  z.object({ name: z.literal("plan_reviewed"), plan_type: z.enum(["text", "external_read", "external_write"]), outcome: z.enum(["accepted", "edited", "cancelled"]), latency_bucket: z.enum(["0_100ms", "100_500ms", "500_2000ms", "over_2000ms"]) }).strict(),
  z.object({ name: z.literal("execution_finished"), operations: z.array(z.string()), outcome: z.enum(["success", "partial", "failed", "unknown"]), latency_bucket: z.enum(["0_100ms", "100_500ms", "500_2000ms", "over_2000ms"]), retry_count: z.number().int().nonnegative() }).strict(),
  z.object({ name: z.literal("result_applied"), method: z.enum(["insertion", "replacement", "copy"]), character_count_bucket: z.enum(["0", "1_32", "33_256", "257_2000", "over_2000"]) }).strict(),
  z.object({ name: z.literal("local_text_action_started"), action_id: z.string().regex(/^act_[A-Za-z0-9_-]{16,128}$/), operation: z.enum(["rewrite", "translate", "shorten", "custom"]), preview_mode: z.enum(["exact", "locally_redacted"]), source_types: z.array(z.enum(["command", "selection", "surrounding_text", "clipboard"])), result_revision: z.number().int().positive() }).strict()
]);
export type TelemetryEvent = z.infer<typeof TelemetryEvent>;

export const LocalCaptureSource = z.enum(["command", "selection", "surrounding_text", "clipboard"]);
export type LocalCaptureSource = z.infer<typeof LocalCaptureSource>;
export const LocalPreviewMode = z.enum(["exact", "locally_redacted"]);
export type LocalPreviewMode = z.infer<typeof LocalPreviewMode>;
export const LocalApplyMethod = z.enum(["insert_text", "replace_selection", "copy"]);
export type LocalApplyMethod = z.infer<typeof LocalApplyMethod>;
export const UndoState = z.enum(["unavailable", "available", "used", "expired"]);
export type UndoState = z.infer<typeof UndoState>;

export const LocalCaptureLimits = z.object({
  command_max_characters: z.number().int().nonnegative().max(500),
  selection_max_characters: z.number().int().nonnegative().max(4_000),
  surrounding_before_max_characters: z.number().int().nonnegative().max(1_000),
  surrounding_after_max_characters: z.number().int().nonnegative().max(500),
  clipboard_max_characters: z.number().int().nonnegative().max(4_000)
}).strict();
export type LocalCaptureLimits = z.infer<typeof LocalCaptureLimits>;

export const LocalCaptureSourceSelection = z.object({
  source: LocalCaptureSource,
  enabled: z.boolean(),
  explicit_opt_in: z.boolean()
}).strict();
export type LocalCaptureSourceSelection = z.infer<typeof LocalCaptureSourceSelection>;

export const LocalDisclosure = z.object({
  sources: z.array(LocalCaptureSourceSelection).min(1).max(4),
  limits: LocalCaptureLimits,
  destination: z.literal("local_device"),
  network_required: z.literal(false),
  retention: z.literal("none"),
  issued_at: z.string().datetime({ offset: true })
}).strict();
export type LocalDisclosure = z.infer<typeof LocalDisclosure>;

const UnicodeText = (maximum: number) => z.string().refine((value) => Array.from(value).length <= maximum, { message: `Text exceeds ${maximum} Unicode code points` });
export const LocalTextCaptureItem = z.object({ source: LocalCaptureSource, text: UnicodeText(4_000) }).strict();
export type LocalTextCaptureItem = z.infer<typeof LocalTextCaptureItem>;
export const LocalTextCapture = z.object({
  items: z.array(LocalTextCaptureItem).min(1).max(4),
  field_fingerprint: z.string().regex(/^sha256:[a-f0-9]{64}$/),
  disclosure_acknowledgement: z.string().regex(/^sha256:[a-f0-9]{64}$/),
  capture_fingerprint: z.string().regex(/^sha256:[a-f0-9]{64}$/)
}).strict();
export type LocalTextCapture = z.infer<typeof LocalTextCapture>;

export const LocalPreviewMetadata = z.object({
  mode: LocalPreviewMode,
  character_count: z.number().int().nonnegative(),
  content_digest: z.string().regex(/^sha256:[a-f0-9]{64}$/),
  redacted_character_count: z.number().int().nonnegative(),
  redaction_types: z.array(z.enum(["name", "number", "date", "url", "email", "handle", "product"])).max(20)
}).strict();
export type LocalPreviewMetadata = z.infer<typeof LocalPreviewMetadata>;
export const LocalTextPreview = z.object({ metadata: LocalPreviewMetadata, content: UnicodeText(10_000) }).strict();
export type LocalTextPreview = z.infer<typeof LocalTextPreview>;

export const LocalTextPlan = z.object({
  plan_id: z.string().min(1), plan_version: z.number().int().positive(), run_id: z.string().min(1),
  operation: z.enum(["rewrite", "translate", "shorten", "custom"]), risk_class: z.literal("R1"),
  summary: z.string().min(1).max(1_000), capture_fingerprint: z.string().regex(/^sha256:[a-f0-9]{64}$/),
  result_revision: z.number().int().positive(), destination: z.literal("local_device"), network_required: z.literal(false),
  tools: z.array(z.never()).max(0), apply_method: LocalApplyMethod,
  canonical_digest: z.string().regex(/^sha256:[a-f0-9]{64}$/)
}).strict();
export type LocalTextPlan = z.infer<typeof LocalTextPlan>;

export const LocalUndo = z.object({ token: z.string().regex(/^undo_[A-Za-z0-9_-]{16,128}$/).optional(), state: UndoState, expires_at: z.string().datetime({ offset: true }).optional() }).strict().superRefine((value, context) => {
  const hasToken = value.token !== undefined; const hasExpiry = value.expires_at !== undefined;
  if (value.state === "available" && (!hasToken || !hasExpiry)) context.addIssue({ code: z.ZodIssueCode.custom, message: "available undo requires token and expiry" });
  if (value.state !== "available" && (hasToken || hasExpiry)) context.addIssue({ code: z.ZodIssueCode.custom, message: "inactive undo cannot carry token or expiry" });
});
export type LocalUndo = z.infer<typeof LocalUndo>;
export const LocalTextResult = z.object({
  result_revision: z.number().int().positive(), text: UnicodeText(10_000), apply_method: LocalApplyMethod,
  undo: LocalUndo
}).strict();
export type LocalTextResult = z.infer<typeof LocalTextResult>;

export const DEFAULT_LOCAL_CAPTURE_LIMITS: LocalCaptureLimits = {
  command_max_characters: 500,
  selection_max_characters: 4_000,
  surrounding_before_max_characters: 1_000,
  surrounding_after_max_characters: 500,
  clipboard_max_characters: 4_000
};

export function defaultLocalCaptureSources(): LocalCaptureSourceSelection[] {
  return [
    { source: "command", enabled: true, explicit_opt_in: false },
    { source: "selection", enabled: true, explicit_opt_in: false },
    { source: "surrounding_text", enabled: false, explicit_opt_in: false },
    { source: "clipboard", enabled: false, explicit_opt_in: false }
  ];
}

export function localDisclosureDigest(disclosure: LocalDisclosure): string {
  return `sha256:${createHash("sha256").update(canonicalJson(disclosure), "utf8").digest("hex")}`;
}

export function localCaptureFingerprint(capture: Omit<LocalTextCapture, "capture_fingerprint">): string {
  return `sha256:${createHash("sha256").update(canonicalJson(capture), "utf8").digest("hex")}`;
}

export function localTextPlanDigest(plan: Omit<LocalTextPlan, "canonical_digest">): string {
  return `sha256:${createHash("sha256").update(canonicalJson(plan), "utf8").digest("hex")}`;
}

export function parseContract<T extends z.ZodTypeAny>(schema: T, value: unknown): z.infer<T> { return schema.parse(value); }

export * from "./w3.js";
export * from "./w4.js";
export * from "./w4_ids.js";
export * from "./w5.js";
export * from "./w6.js";
export * from "./w7.js";
export * from "./w8.js";
