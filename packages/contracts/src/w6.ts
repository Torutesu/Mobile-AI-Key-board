import { createHash } from "node:crypto";
import { z } from "zod";
import { DeviceId, UserId } from "./w3.js";
import { canonicalJson } from "./index.js";

const Digest = z.string().regex(/^sha256:[a-f0-9]{64}$/);
const Opaque = (prefix: string) => z.string().regex(new RegExp(`^${prefix}_[A-Za-z0-9_-]{16,128}$`));
const SkillId = Opaque("skill");
const DraftId = Opaque("sdraft");
const VersionId = Opaque("sv");
const BindingId = Opaque("bind");
const ShareId = Opaque("share");
const ReservationId = Opaque("qres");
const NonBlank = (max: number) => z.string().max(max).refine((value) => value.trim().length > 0, { message: "value must not be blank" });

export const SkillInputSource = z.enum(["command", "selection", "surrounding_text", "clipboard", "current_datetime", "locale", "location"]);
export type SkillInputSource = z.infer<typeof SkillInputSource>;
export const SkillInputType = z.enum(["text", "number", "boolean", "datetime", "json"]);
export const SkillInput = z.object({ name: z.string().regex(/^[a-z][a-z0-9_]{1,63}$/), type: SkillInputType, sources: z.array(SkillInputSource).min(1).max(7), required: z.boolean(), max_characters: z.number().int().positive().max(100_000).optional() }).strict();
export type SkillInput = z.infer<typeof SkillInput>;
export const SkillOutput = z.object({ type: z.enum(["insert_text", "replace_selection", "copy", "json"]), template: z.string().max(2_000).refine((value) => value.trim().length > 0, { message: "template must not be blank" }).optional() }).strict();
export type SkillOutput = z.infer<typeof SkillOutput>;
export const SkillTrigger = z.discriminatedUnion("kind", [z.object({ kind: z.literal("shortcut"), value: z.string().regex(/^[A-Za-z0-9][A-Za-z0-9_.-]{1,31}$/) }).strict(), z.object({ kind: z.literal("phrase"), value: NonBlank(80).refine((value) => value.trim().length >= 2, { message: "phrase must contain two non-whitespace characters" }) }).strict()]);
export type SkillTrigger = z.infer<typeof SkillTrigger>;
export const SkillTool = z.object({ operation: z.string().regex(/^[a-z][a-z0-9_.-]{2,100}$/), required_scopes: z.array(z.string().regex(/^[a-z][a-z0-9_.-]{2,100}$/)).max(5), side_effect: z.enum(["none", "creates_private_event", "updates_private_resource", "external_communication", "destructive"]) }).strict();
export type SkillTool = z.infer<typeof SkillTool>;
export const SkillTestExpected = z.object({ requires_absolute_date_preview: z.boolean().optional(), protected_entities_preserved: z.boolean().optional(), output_text: NonBlank(4_000).optional(), status: z.enum(["success", "partial", "failed", "unknown"]).optional() }).strict().superRefine((value, context) => { if (Object.keys(value).length === 0) context.addIssue({ code: z.ZodIssueCode.custom, message: "expected fixture must declare a typed expectation" }); });
export type SkillTestExpected = z.infer<typeof SkillTestExpected>;
export const SkillTestExample = z.object({ name: NonBlank(120), input_fixture: NonBlank(4_000), expected: SkillTestExpected }).strict();
export type SkillTestExample = z.infer<typeof SkillTestExample>;

export const SkillDefinition = z.object({
  schema_version: z.literal(1), name: NonBlank(80), description: NonBlank(1_000), trigger: SkillTrigger,
  inputs: z.array(SkillInput).min(1).max(16), tools: z.array(SkillTool).max(16), risk_ceiling: z.enum(["R0", "R1", "R2", "R3"]),
  confirmation: z.enum(["none", "policy_required"]), output: SkillOutput, retention: z.enum(["none", "transient_content", "receipt_metadata"]),
  instruction: NonBlank(8_000), tests: z.array(SkillTestExample).max(50)
}).strict();
export type SkillDefinition = z.infer<typeof SkillDefinition>;

export const SkillDraftStatus = z.enum(["draft", "validated", "tested", "published"]);
export type SkillDraftStatus = z.infer<typeof SkillDraftStatus>;
export const SkillDraft = z.object({ draft_id: DraftId, skill_id: SkillId, owner_user_id: UserId, owner_device_id: DeviceId, revision: z.number().int().positive(), definition: SkillDefinition, status: SkillDraftStatus, contract_digest: Digest, created_at: z.string().datetime({ offset: true }), updated_at: z.string().datetime({ offset: true }) }).strict();
export type SkillDraft = z.infer<typeof SkillDraft>;

export const SkillTestActual = z.object({ requires_absolute_date_preview: z.boolean().optional(), protected_entities_preserved: z.boolean().optional(), output_text: NonBlank(4_000).optional(), status: z.enum(["success", "partial", "failed", "unknown"]).optional() }).strict().superRefine((value, context) => { if (Object.keys(value).length === 0) context.addIssue({ code: z.ZodIssueCode.custom, message: "actual fixture result must declare typed fields" }); });
export type SkillTestActual = z.infer<typeof SkillTestActual>;
export const SkillTestResult = z.object({ test_name: NonBlank(120), fixture_digest: Digest, actual: SkillTestActual, user_visible_result: NonBlank(4_000) }).strict();
export type SkillTestResult = z.infer<typeof SkillTestResult>;
export const SkillTestRun = z.object({ test_run_id: Opaque("strun"), draft_id: DraftId, draft_revision: z.number().int().positive(), contract_digest: Digest, results: z.array(SkillTestResult).min(1).max(50), all_pass: z.literal(true), completed_at: z.string().datetime({ offset: true }) }).strict();
export type SkillTestRun = z.infer<typeof SkillTestRun>;

export const SkillVersion = z.object({ version_id: VersionId, skill_id: SkillId, version: z.number().int().positive(), owner_user_id: UserId, definition: SkillDefinition, contract_digest: Digest, visibility: z.literal("private"), published_at: z.string().datetime({ offset: true }), source_draft_id: DraftId }).strict();
export type SkillVersion = z.infer<typeof SkillVersion>;

export const SkillBinding = z.object({ binding_id: BindingId, user_id: UserId, device_id: DeviceId, skill_id: SkillId, version_id: VersionId, skill_version: z.number().int().positive(), skill_digest: Digest, trigger: SkillTrigger, accessibility_label: NonBlank(80).refine((value) => value.trim().length >= 2, { message: "accessibility label must contain two non-whitespace characters" }), accessibility_hint: NonBlank(160), accessibility_order: z.number().int().positive().max(1_000), enabled: z.boolean(), bound_at: z.string().datetime({ offset: true }) }).strict();
export type SkillBinding = z.infer<typeof SkillBinding>;

export const PrivateSkillShare = z.object({ share_id: ShareId, skill_id: SkillId, version_id: VersionId, skill_digest: Digest, owner_user_id: UserId, recipient_user_ids: z.array(UserId).min(1).max(50), visibility: z.literal("private"), public_publish: z.literal(false), expires_at: z.string().datetime({ offset: true }).optional(), created_at: z.string().datetime({ offset: true }) }).strict().superRefine((value, context) => {
  if (new Set(value.recipient_user_ids).size !== value.recipient_user_ids.length) context.addIssue({ code: z.ZodIssueCode.custom, message: "private share recipients must be unique" });
  if (value.expires_at !== undefined && Date.parse(value.expires_at) <= Date.parse(value.created_at)) context.addIssue({ code: z.ZodIssueCode.custom, message: "private share expiry must be after creation" });
});
export type PrivateSkillShare = z.infer<typeof PrivateSkillShare>;

export const SkillQuota = z.object({ user_id: UserId, period_start: z.string().datetime({ offset: true }), period_end: z.string().datetime({ offset: true }), max_runs: z.number().int().positive().max(1_000_000), max_input_characters: z.number().int().positive().max(100_000_000), max_output_characters: z.number().int().positive().max(100_000_000), max_cost_micros: z.number().int().nonnegative().max(10_000_000_000) }).strict().superRefine((value, context) => { if (Date.parse(value.period_end) <= Date.parse(value.period_start)) context.addIssue({ code: z.ZodIssueCode.custom, message: "quota period must end after it starts" }); });
export type SkillQuota = z.infer<typeof SkillQuota>;
export const SkillUsage = z.object({ user_id: UserId, period_start: z.string().datetime({ offset: true }), runs: z.number().int().nonnegative(), input_characters: z.number().int().nonnegative(), output_characters: z.number().int().nonnegative(), cost_micros: z.number().int().nonnegative() }).strict();
export type SkillUsage = z.infer<typeof SkillUsage>;
export const SkillReservation = z.object({ reservation_id: ReservationId, user_id: UserId, skill_id: SkillId, skill_version: z.number().int().positive(), period_start: z.string().datetime({ offset: true }), request_id: z.string().min(8).max(200), input_characters: z.number().int().nonnegative().max(100_000_000), estimated_output_characters: z.number().int().nonnegative().max(100_000_000), estimated_cost_micros: z.number().int().nonnegative().max(10_000_000_000), status: z.enum(["reserved", "committed", "released"]), reserved_at: z.string().datetime({ offset: true }) }).strict();
export type SkillReservation = z.infer<typeof SkillReservation>;

export function skillDefinitionDigest(definition: SkillDefinition): string { return `sha256:${createHash("sha256").update(canonicalJson(definition), "utf8").digest("hex")}`; }
export function skillTestFixtureDigest(fixture: SkillTestExample): string { return `sha256:${createHash("sha256").update(canonicalJson(fixture), "utf8").digest("hex")}`; }
