import { createHash } from "node:crypto";
import { z } from "zod";
import { DeviceId, UserId } from "./w3.js";
import { GrantId } from "./w4_ids.js";
import { canonicalJson } from "./canonical.js";

export const CalendarWriteOperation = z.literal("calendar.event.create_private");
export const CalendarUndoOperation = z.literal("calendar.event.delete_own");
export const CalendarWriteScope = z.literal("calendar.events.create_private");
export const CalendarUndoScope = z.literal("calendar.events.delete_own");
export const CalendarWriteProvider = z.literal("google_calendar");
export const CalendarWriteStatus = z.enum(["succeeded", "failed", "partial", "unknown"]);
export type CalendarWriteStatus = z.infer<typeof CalendarWriteStatus>;
export const CalendarWriteErrorKind = z.enum(["scope_missing", "owner_mismatch", "plan_digest_mismatch", "confirmation_expired", "confirmation_replayed", "plan_expired", "idempotency_conflict", "provider_error", "timeout", "unknown_outcome", "reconciliation_required", "resource_mismatch", "undo_expired", "undo_already_used"]);
export type CalendarWriteErrorKind = z.infer<typeof CalendarWriteErrorKind>;

export const CalendarPrivateEventInput = z.object({
  title: z.string().min(1).max(500), start: z.string().datetime({ offset: true }), end: z.string().datetime({ offset: true }), timezone: z.string().min(1).max(64),
  attendees: z.array(z.never()).max(0), send_updates: z.literal("none")
}).strict().superRefine((value, context) => { if (Date.parse(value.end) <= Date.parse(value.start)) context.addIssue({ code: z.ZodIssueCode.custom, message: "calendar event end must be after start" }); });
export type CalendarPrivateEventInput = z.infer<typeof CalendarPrivateEventInput>;

export const CalendarWriteGrant = z.object({ grant_id: GrantId, user_id: UserId, device_id: DeviceId, connection_epoch: z.number().int().positive(), provider: CalendarWriteProvider, scopes: z.array(CalendarWriteScope).length(1), status: z.literal("active") }).strict();
export type CalendarWriteGrant = z.infer<typeof CalendarWriteGrant>;
export const CalendarPrivateWritePlan = z.object({
  plan_id: z.string().min(1).max(128), plan_version: z.number().int().positive(), run_id: z.string().min(1).max(128), step_id: z.string().regex(/^step_[A-Za-z0-9_-]{1,64}$/), user_id: UserId, device_id: DeviceId, grant_id: GrantId, connection_epoch: z.number().int().positive(),
  operation: CalendarWriteOperation, risk_class: z.literal("R3"), scope: CalendarWriteScope, summary: z.string().min(1).max(1_000), input: CalendarPrivateEventInput,
  confirmation_required: z.literal(true), expires_at: z.string().datetime({ offset: true }), canonical_digest: z.string().regex(/^sha256:[a-f0-9]{64}$/)
}).strict();
export type CalendarPrivateWritePlan = z.infer<typeof CalendarPrivateWritePlan>;
export const CalendarConfirmation = z.object({ plan_id: z.string().min(1).max(128), run_id: z.string().min(1).max(128), user_id: UserId, device_id: DeviceId, grant_id: GrantId, connection_epoch: z.number().int().positive(), plan_digest: z.string().regex(/^sha256:[a-f0-9]{64}$/), confirmation_method: z.enum(["explicit_tap", "passcode"]), confirmed_at: z.string().datetime({ offset: true }), expires_at: z.string().datetime({ offset: true }), client_idempotency_key: z.string().min(8).max(200) }).strict().superRefine((value, context) => {
  if (Date.parse(value.expires_at) <= Date.parse(value.confirmed_at)) context.addIssue({ code: z.ZodIssueCode.custom, message: "calendar confirmation must expire after it was confirmed" });
});
export type CalendarConfirmation = z.infer<typeof CalendarConfirmation>;
export const CalendarWriteRequest = z.object({ plan: CalendarPrivateWritePlan, confirmation: CalendarConfirmation }).strict();
export const CalendarWriteReceipt = z.object({ receipt_id: z.string().regex(/^rcpt_[A-Za-z0-9_-]{16,128}$/), run_id: z.string().min(1).max(128), step_id: z.string().regex(/^step_[A-Za-z0-9_-]{1,64}$/), plan_digest: z.string().regex(/^sha256:[a-f0-9]{64}$/), user_id: UserId, device_id: DeviceId, grant_id: GrantId, connection_epoch: z.number().int().positive(), operation: CalendarWriteOperation, status: CalendarWriteStatus, provider_operation_key: z.string().min(1).max(512).optional(), resource_key: z.string().min(1).max(512).optional(), idempotency_key: z.string().min(8).max(200), error_kind: CalendarWriteErrorKind.optional(), reconciled_at: z.string().datetime({ offset: true }).optional(), plan_expires_at: z.string().datetime({ offset: true }), undo_expires_at: z.string().datetime({ offset: true }).optional(), undo_state: z.enum(["available", "used", "expired", "unavailable"]) }).strict().superRefine((value, context) => {
  if (value.status === "succeeded" && (value.resource_key === undefined || value.provider_operation_key === undefined)) context.addIssue({ code: z.ZodIssueCode.custom, message: "succeeded calendar write requires operation and resource keys" });
  if (value.status !== "succeeded" && value.resource_key !== undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "non-succeeded calendar write cannot claim a resource key" });
  if (value.status === "succeeded" && value.error_kind !== undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "succeeded calendar write cannot carry an error" });
  if (value.status !== "succeeded" && value.error_kind === undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "non-succeeded calendar write requires a typed error" });
  if (value.status === "unknown" && value.provider_operation_key === undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "unknown calendar write requires an operation key for reconciliation" });
  if (value.status === "unknown" && value.reconciled_at !== undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "unknown receipt cannot already be reconciled" });
  if (value.undo_state === "available" && (value.status !== "succeeded" || value.undo_expires_at === undefined)) context.addIssue({ code: z.ZodIssueCode.custom, message: "available calendar undo requires a succeeded receipt and expiry" });
  if (value.undo_state !== "available" && value.undo_expires_at !== undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "inactive calendar undo cannot carry expiry" });
  if (value.undo_expires_at !== undefined && Date.parse(value.undo_expires_at) > Date.parse(value.plan_expires_at)) context.addIssue({ code: z.ZodIssueCode.custom, message: "calendar undo expiry cannot exceed plan expiry" });
});
export type CalendarWriteReceipt = z.infer<typeof CalendarWriteReceipt>;
export const CalendarReconciliationResult = z.object({ receipt_id: z.string().regex(/^rcpt_[A-Za-z0-9_-]{16,128}$/), run_id: z.string().min(1).max(128), plan_digest: z.string().regex(/^sha256:[a-f0-9]{64}$/), provider_operation_key: z.string().min(1).max(512), outcome: z.enum(["succeeded", "failed"]), resource_key: z.string().min(1).max(512).optional(), reconciled_at: z.string().datetime({ offset: true }) }).strict().superRefine((value, context) => {
  if (value.outcome === "succeeded" && value.resource_key === undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "successful reconciliation requires exact resource key" });
  if (value.outcome === "failed" && value.resource_key !== undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "failed reconciliation cannot authorize a resource" });
});
export const CalendarUndoRequest = z.object({ receipt_id: z.string().regex(/^rcpt_[A-Za-z0-9_-]{16,128}$/), run_id: z.string().min(1).max(128), plan_digest: z.string().regex(/^sha256:[a-f0-9]{64}$/), user_id: UserId, device_id: DeviceId, grant_id: GrantId, connection_epoch: z.number().int().positive(), operation: CalendarUndoOperation, scope: CalendarUndoScope, resource_key: z.string().min(1).max(512), idempotency_key: z.string().min(8).max(200) }).strict();
export type CalendarUndoRequest = z.infer<typeof CalendarUndoRequest>;
export const CalendarUndoReceipt = z.object({ receipt_id: z.string().regex(/^rcpt_[A-Za-z0-9_-]{16,128}$/), original_receipt_id: z.string().regex(/^rcpt_[A-Za-z0-9_-]{16,128}$/), run_id: z.string().min(1).max(128), plan_digest: z.string().regex(/^sha256:[a-f0-9]{64}$/), user_id: UserId, device_id: DeviceId, grant_id: GrantId, connection_epoch: z.number().int().positive(), operation: CalendarUndoOperation, status: z.enum(["succeeded", "failed", "unknown"]), resource_key: z.string().min(1).max(512), idempotency_key: z.string().min(8).max(200), error_kind: CalendarWriteErrorKind.optional() }).strict().superRefine((value, context) => {
  if (value.status === "succeeded" && value.error_kind !== undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "succeeded calendar undo cannot carry an error" });
  if (value.status !== "succeeded" && value.error_kind === undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "non-succeeded calendar undo requires a typed error" });
});
export type CalendarUndoReceipt = z.infer<typeof CalendarUndoReceipt>;
export function calendarWritePlanDigest(plan: Omit<CalendarPrivateWritePlan, "canonical_digest">): string { return `sha256:${createHash("sha256").update(canonicalJson(plan), "utf8").digest("hex")}`; }
