import { CalendarConfirmation, CalendarPrivateWritePlan, CalendarWriteGrant, CalendarWriteReceipt, CalendarUndoRequest, calendarWritePlanDigest } from "@mobile-ai-keyboard/contracts";
import type { CalendarConfirmation as CalendarConfirmationData, CalendarPrivateWritePlan as CalendarPrivateWritePlanData, CalendarWriteGrant as CalendarWriteGrantData, CalendarWriteReceipt as CalendarWriteReceiptData, CalendarUndoRequest as CalendarUndoRequestData, UserId, DeviceId } from "@mobile-ai-keyboard/contracts";
import { PolicyViolation } from "./index.js";
import { assertProviderContentCannotAuthorize } from "./w4.js";

export const CALENDAR_WRITE_AUTHORITY = { operation: "calendar.event.create_private" as const, scope: "calendar.events.create_private" as const, risk_class: "R3" as const, side_effect: "creates_private_event" as const, attendees_allowed: false };
export function validateCalendarWritePlan(value: unknown): CalendarPrivateWritePlanData {
  const parsed = CalendarPrivateWritePlan.safeParse(value); if (!parsed.success) throw new PolicyViolation("Calendar private write plan is invalid", { code: "INVALID_CALENDAR_WRITE_PLAN" });
  if (calendarWritePlanDigest({ ...parsed.data, canonical_digest: undefined } as Omit<CalendarPrivateWritePlanData, "canonical_digest">) !== parsed.data.canonical_digest) throw new PolicyViolation("Calendar write plan digest does not match canonical plan", { code: "PLAN_DIGEST_MISMATCH" });
  if (parsed.data.operation !== CALENDAR_WRITE_AUTHORITY.operation || parsed.data.scope !== CALENDAR_WRITE_AUTHORITY.scope || parsed.data.risk_class !== CALENDAR_WRITE_AUTHORITY.risk_class || parsed.data.confirmation_required !== true) throw new PolicyViolation("Calendar plan is outside the exact R3 private-write authority", { code: "AUTHORITY_MISMATCH" });
  if (parsed.data.input.attendees.length !== 0 || parsed.data.input.send_updates !== "none") throw new PolicyViolation("Calendar private write cannot include attendees or invitations", { code: "ATTENDEES_FORBIDDEN" });
  return parsed.data;
}
export function assertCalendarWriteGrant(grantValue: unknown, plan: CalendarPrivateWritePlanData, owner: { user_id: UserId; device_id: DeviceId }): CalendarWriteGrantData {
  const grant = CalendarWriteGrant.safeParse(grantValue); if (!grant.success) throw new PolicyViolation("Calendar write grant is invalid", { code: "INVALID_CALENDAR_GRANT" });
  if (grant.data.grant_id !== plan.grant_id || grant.data.user_id !== owner.user_id || grant.data.device_id !== owner.device_id || grant.data.connection_epoch !== plan.connection_epoch || plan.user_id !== owner.user_id || plan.device_id !== owner.device_id) throw new PolicyViolation("Calendar write owner, grant, or connection epoch does not match plan", { code: "OWNER_GRANT_MISMATCH" });
  if (!grant.data.scopes.includes(CALENDAR_WRITE_AUTHORITY.scope)) throw new PolicyViolation("Calendar write scope is missing", { code: "SCOPE_MISSING" });
  return grant.data;
}
export function assertCalendarConfirmation(value: unknown, plan: CalendarPrivateWritePlanData, owner: { user_id: UserId; device_id: DeviceId }, now = new Date()): CalendarConfirmationData {
  const confirmation = CalendarConfirmation.safeParse(value); if (!confirmation.success) throw new PolicyViolation("Calendar confirmation is invalid", { code: "INVALID_CONFIRMATION" });
  if (confirmation.data.plan_id !== plan.plan_id || confirmation.data.run_id !== plan.run_id || confirmation.data.plan_digest !== plan.canonical_digest || confirmation.data.user_id !== owner.user_id || confirmation.data.device_id !== owner.device_id || confirmation.data.grant_id !== plan.grant_id || confirmation.data.connection_epoch !== plan.connection_epoch) throw new PolicyViolation("Calendar confirmation is not bound to the immutable plan and owner", { code: "CONFIRMATION_BINDING_MISMATCH" });
  if (Date.parse(confirmation.data.confirmed_at) > now.getTime()) throw new PolicyViolation("Calendar confirmation cannot be from the future", { code: "CONFIRMATION_EXPIRED" });
  if (Date.parse(plan.expires_at) <= now.getTime()) throw new PolicyViolation("Calendar write plan has expired", { code: "PLAN_EXPIRED" });
  if (Date.parse(confirmation.data.expires_at) <= now.getTime() || Date.parse(confirmation.data.expires_at) > Date.parse(plan.expires_at)) throw new PolicyViolation("Calendar confirmation is expired or exceeds plan expiry", { code: "CONFIRMATION_EXPIRED" });
  return confirmation.data;
}
export function assertCalendarReceipt(value: unknown): CalendarWriteReceiptData { const parsed = CalendarWriteReceipt.safeParse(value); if (!parsed.success) throw new PolicyViolation("Calendar receipt metadata is invalid", { code: "INVALID_RECEIPT" }); assertProviderContentCannotAuthorize(parsed.data); return parsed.data; }
export function assertCalendarUndo(value: unknown, receipt: CalendarWriteReceiptData, owner: { user_id: UserId; device_id: DeviceId }, now = new Date()): CalendarUndoRequestData {
  const request = CalendarUndoRequest.safeParse(value); if (!request.success) throw new PolicyViolation("Calendar undo request is invalid", { code: "INVALID_UNDO" });
  if (receipt.status !== "succeeded" || receipt.undo_state !== "available") throw new PolicyViolation("Calendar receipt is not undoable", { code: "UNDO_ALREADY_USED" });
  if (receipt.undo_expires_at === undefined || Date.parse(receipt.undo_expires_at) <= now.getTime()) throw new PolicyViolation("Calendar undo has expired", { code: "UNDO_EXPIRED" });
  if (request.data.receipt_id !== receipt.receipt_id || request.data.run_id !== receipt.run_id || request.data.plan_digest !== receipt.plan_digest || request.data.user_id !== owner.user_id || request.data.device_id !== owner.device_id || request.data.grant_id !== receipt.grant_id || request.data.connection_epoch !== receipt.connection_epoch || request.data.resource_key !== receipt.resource_key) throw new PolicyViolation("Calendar undo resource, connection epoch, or owner does not match receipt", { code: "RESOURCE_MISMATCH" });
  return request.data;
}
