import { randomUUID } from "node:crypto";
import { CalendarConfirmation, type CalendarConfirmation as CalendarConfirmationData, CalendarPrivateWritePlan, type CalendarPrivateWritePlan as CalendarPrivateWritePlanData, CalendarUndoReceipt, type CalendarUndoReceipt as CalendarUndoReceiptData, CalendarUndoRequest, type CalendarUndoRequest as CalendarUndoRequestData, CalendarWriteGrant, type CalendarWriteGrant as CalendarWriteGrantData, CalendarWriteReceipt, type CalendarWriteReceipt as CalendarWriteReceiptData, CalendarWriteRequest } from "@mobile-ai-keyboard/contracts";
import { assertCalendarConfirmation, assertCalendarReceipt, assertCalendarUndo, assertCalendarWriteGrant, PolicyViolation, validateCalendarWritePlan } from "@mobile-ai-keyboard/policy";
import type { DeviceId, UserId } from "@mobile-ai-keyboard/contracts";
import type { Clock } from "./w3.js";

export type CalendarProviderCreateOutcome = { status: "succeeded"; provider_operation_key: string; resource_key: string } | { status: "failed"; error_kind?: "provider_error" | "timeout" } | { status: "partial"; provider_operation_key?: string } | { status: "unknown"; provider_operation_key?: string };
export type CalendarProviderDeleteOutcome = { status: "succeeded" } | { status: "failed"; error_kind?: "provider_error" | "timeout" } | { status: "unknown" };
export interface CalendarWriteAdapter { createPrivateEvent(input: CalendarPrivateWritePlanData["input"], operationKey: string): Promise<CalendarProviderCreateOutcome>; deleteOwnEvent(resourceKey: string, operationKey: string): Promise<CalendarProviderDeleteOutcome>; }
export type W5ErrorCode = "INVALID_CONTRACT" | "PLAN_DIGEST_MISMATCH" | "PLAN_EXPIRED" | "CONFIRMATION_EXPIRED" | "CONFIRMATION_BINDING_MISMATCH" | "CONFIRMATION_REPLAYED" | "OWNER_GRANT_MISMATCH" | "SCOPE_MISSING" | "AUTHORITY_MISMATCH" | "ATTENDEES_FORBIDDEN" | "IDEMPOTENCY_CONFLICT" | "UNKNOWN_RETRY_BLOCKED" | "RECONCILIATION_REQUIRED" | "RECONCILIATION_MISMATCH" | "RECEIPT_NOT_FOUND" | "RESOURCE_MISMATCH" | "UNDO_EXPIRED" | "UNDO_ALREADY_USED" | "PROVIDER_FAILURE" | "PROVIDER_UNKNOWN";
export class W5Error extends Error { constructor(readonly code: W5ErrorCode, message: string) { super(message); this.name = "W5Error"; } }
const defaultClock: Clock = () => new Date();
const clone = <T>(value: T): T => structuredClone(value);
const receiptId = (): string => `rcpt_${randomUUID().replaceAll("-", "")}`;

export class CalendarWriteExecutor {
  private readonly receipts = new Map<string, CalendarWriteReceiptData>();
  private readonly undoReceipts = new Map<string, CalendarUndoReceiptData>();
  private readonly clientKeys = new Map<string, string>();
  private readonly confirmationKeys = new Set<string>();
  private readonly inFlight = new Map<string, Promise<CalendarWriteReceiptData>>();
  constructor(private readonly adapter: CalendarWriteAdapter, private readonly clock: Clock = defaultClock, private readonly undoTtlMs = 10 * 60_000) {}

  async execute(request: unknown, grantValue: unknown, owner: { user_id: UserId; device_id: DeviceId }): Promise<CalendarWriteReceiptData> {
    let parsed: { plan: CalendarPrivateWritePlanData; confirmation: CalendarConfirmationData };
    try { parsed = CalendarWriteRequestSafe(request); } catch (error) { throw new W5Error("INVALID_CONTRACT", error instanceof Error ? error.message : "Calendar write request is invalid"); }
    let plan: CalendarPrivateWritePlanData; let grant: CalendarWriteGrantData; let confirmation: CalendarConfirmationData;
    try {
      plan = validateCalendarWritePlan(parsed.plan);
      grant = assertCalendarWriteGrant(grantValue, plan, owner);
      confirmation = assertCalendarConfirmation(parsed.confirmation, plan, owner, this.clock());
    } catch (error) { throw policyToW5Error(error); }
    const scope = `${plan.run_id}:${plan.canonical_digest}:${plan.step_id}:calendar.event.create_private:${confirmation.client_idempotency_key}`;
    const clientScope = `${plan.run_id}:${plan.step_id}:${confirmation.client_idempotency_key}`;
    const existingDigest = this.clientKeys.get(clientScope);
    if (existingDigest !== undefined && existingDigest !== plan.canonical_digest) throw new W5Error("IDEMPOTENCY_CONFLICT", "Client idempotency key collided with another plan digest");
    const existing = this.receipts.get(scope); if (existing) return clone(existing);
    const active = this.inFlight.get(scope); if (active) return clone(await active);
    if ([...this.receipts.values()].some((receipt) => receipt.run_id === plan.run_id && receipt.plan_digest === plan.canonical_digest && receipt.status === "unknown")) throw new W5Error("UNKNOWN_RETRY_BLOCKED", "Unknown provider outcome requires reconciliation before retry");
    const confirmationKey = `${plan.run_id}:${plan.canonical_digest}:${plan.step_id}:${plan.user_id}:${plan.device_id}:${plan.grant_id}:${plan.connection_epoch}`;
    if (this.confirmationKeys.has(confirmationKey)) throw new W5Error("CONFIRMATION_REPLAYED", "Confirmation has already been consumed");
    this.confirmationKeys.add(confirmationKey); this.clientKeys.set(clientScope, plan.canonical_digest);
    const operationKey = `${scope}:provider`;
    const execution = (async (): Promise<CalendarWriteReceiptData> => {
      let outcome: CalendarProviderCreateOutcome;
      try { outcome = await this.adapter.createPrivateEvent(plan.input, operationKey); } catch { outcome = { status: "unknown" }; }
      const status = outcome.status; const now = this.clock().toISOString();
      const receipt = CalendarWriteReceipt.parse({ receipt_id: receiptId(), run_id: plan.run_id, step_id: plan.step_id, plan_digest: plan.canonical_digest, user_id: plan.user_id, device_id: plan.device_id, grant_id: grant.grant_id, connection_epoch: plan.connection_epoch, operation: "calendar.event.create_private", status, provider_operation_key: status === "unknown" ? operationKey : ("provider_operation_key" in outcome ? outcome.provider_operation_key : undefined), resource_key: status === "succeeded" ? outcome.resource_key : undefined, idempotency_key: confirmation.client_idempotency_key, error_kind: status === "unknown" ? "unknown_outcome" : status === "failed" || status === "partial" ? ("error_kind" in outcome ? outcome.error_kind : undefined) ?? "provider_error" : undefined, plan_expires_at: plan.expires_at, undo_expires_at: status === "succeeded" ? new Date(Math.min(Date.parse(plan.expires_at), this.clock().getTime() + this.undoTtlMs)).toISOString() : undefined, undo_state: status === "succeeded" ? "available" : "unavailable" });
      this.receipts.set(scope, receipt); return clone(receipt);
    })();
    this.inFlight.set(scope, execution);
    try { return await execution; } finally { this.inFlight.delete(scope); }
  }

  async reconcile(receiptIdValue: string, owner: { user_id: UserId; device_id: DeviceId; grant_id?: string; connection_epoch?: number }, providerOperationKey: string, outcome: { status: "succeeded"; resource_key: string } | { status: "failed" }): Promise<CalendarWriteReceiptData> {
    const receipt = [...this.receipts.values()].find((candidate) => candidate.receipt_id === receiptIdValue); if (!receipt) throw new W5Error("RECEIPT_NOT_FOUND", "Calendar write receipt was not found");
    if (receipt.user_id !== owner.user_id || receipt.device_id !== owner.device_id || (owner.grant_id !== undefined && receipt.grant_id !== owner.grant_id) || (owner.connection_epoch !== undefined && receipt.connection_epoch !== owner.connection_epoch)) throw new W5Error("OWNER_GRANT_MISMATCH", "Receipt does not belong to owner or connection grant");
    if (receipt.status !== "unknown") throw new W5Error("RECONCILIATION_REQUIRED", "Only unknown outcomes can be reconciled");
    if (receipt.provider_operation_key !== undefined && receipt.provider_operation_key !== providerOperationKey) throw new W5Error("RECONCILIATION_MISMATCH", "Provider operation key does not match unknown receipt");
    const undoExpiry = Math.min(Date.parse(receipt.plan_expires_at), this.clock().getTime() + this.undoTtlMs);
    const undoAvailable = outcome.status === "succeeded" && undoExpiry > this.clock().getTime();
    const updated = CalendarWriteReceipt.parse({ ...receipt, status: outcome.status, provider_operation_key: providerOperationKey, resource_key: outcome.status === "succeeded" ? outcome.resource_key : undefined, error_kind: outcome.status === "failed" ? "provider_error" : undefined, reconciled_at: this.clock().toISOString(), undo_expires_at: undoAvailable ? new Date(undoExpiry).toISOString() : undefined, undo_state: undoAvailable ? "available" : outcome.status === "succeeded" ? "expired" : "unavailable" });
    for (const [key, value] of this.receipts) if (value.receipt_id === receiptIdValue) this.receipts.set(key, updated); return clone(updated);
  }

  async undo(request: unknown, owner: { user_id: UserId; device_id: DeviceId }): Promise<CalendarUndoReceiptData> {
    let parsed: CalendarUndoRequestData; try { parsed = CalendarUndoRequest.parse(request); } catch (error) { throw new W5Error("INVALID_CONTRACT", error instanceof Error ? error.message : "Calendar undo request is invalid"); }
    const receipt = [...this.receipts.values()].find((candidate) => candidate.receipt_id === parsed.receipt_id); if (!receipt) throw new W5Error("RECEIPT_NOT_FOUND", "Calendar write receipt was not found");
    const existing = this.undoReceipts.get(receipt.receipt_id); if (existing) { if (existing.idempotency_key === parsed.idempotency_key) return clone(existing); throw new W5Error("UNDO_ALREADY_USED", "Calendar undo has already been consumed"); }
    try { assertCalendarUndo(parsed, receipt, owner, this.clock()); } catch (error) { throw policyToW5Error(error); }
    let outcome: CalendarProviderDeleteOutcome; try { outcome = await this.adapter.deleteOwnEvent(parsed.resource_key, `${receipt.receipt_id}:${parsed.idempotency_key}`); } catch { outcome = { status: "unknown" }; }
    const undoReceipt = CalendarUndoReceipt.parse({ receipt_id: receiptId(), original_receipt_id: receipt.receipt_id, run_id: receipt.run_id, plan_digest: receipt.plan_digest, user_id: receipt.user_id, device_id: receipt.device_id, grant_id: receipt.grant_id, connection_epoch: receipt.connection_epoch, operation: "calendar.event.delete_own", status: outcome.status, resource_key: parsed.resource_key, idempotency_key: parsed.idempotency_key, error_kind: outcome.status === "unknown" ? "unknown_outcome" : outcome.status === "failed" ? outcome.error_kind ?? "provider_error" : undefined });
    this.undoReceipts.set(receipt.receipt_id, undoReceipt); if (outcome.status === "succeeded") for (const [key, value] of this.receipts) if (value.receipt_id === receipt.receipt_id) this.receipts.set(key, CalendarWriteReceipt.parse({ ...value, undo_state: "used", undo_expires_at: undefined })); return clone(undoReceipt);
  }
}

function CalendarWriteRequestSafe(value: unknown): { plan: CalendarPrivateWritePlanData; confirmation: CalendarConfirmationData } { return CalendarWriteRequest.parse(value); }

function policyToW5Error(error: unknown): W5Error {
  if (!(error instanceof PolicyViolation)) return new W5Error("INVALID_CONTRACT", error instanceof Error ? error.message : "Calendar write contract is invalid");
  const code = String(error.details.code ?? "");
  if (code === "PLAN_DIGEST_MISMATCH") return new W5Error("PLAN_DIGEST_MISMATCH", error.message);
  if (code === "PLAN_EXPIRED") return new W5Error("PLAN_EXPIRED", error.message);
  if (code === "CONFIRMATION_EXPIRED") return new W5Error("CONFIRMATION_EXPIRED", error.message);
  if (code === "CONFIRMATION_BINDING_MISMATCH") return new W5Error("CONFIRMATION_BINDING_MISMATCH", error.message);
  if (code === "OWNER_GRANT_MISMATCH") return new W5Error("OWNER_GRANT_MISMATCH", error.message);
  if (code === "SCOPE_MISSING") return new W5Error("SCOPE_MISSING", error.message);
  if (code === "AUTHORITY_MISMATCH") return new W5Error("AUTHORITY_MISMATCH", error.message);
  if (code === "ATTENDEES_FORBIDDEN") return new W5Error("ATTENDEES_FORBIDDEN", error.message);
  if (code === "UNDO_EXPIRED") return new W5Error("UNDO_EXPIRED", error.message);
  if (code === "UNDO_ALREADY_USED") return new W5Error("UNDO_ALREADY_USED", error.message);
  if (code === "RESOURCE_MISMATCH") return new W5Error("RESOURCE_MISMATCH", error.message);
  if (code === "INVALID_CONFIRMATION" || code === "INVALID_CALENDAR_GRANT" || code === "INVALID_CALENDAR_WRITE_PLAN") return new W5Error("INVALID_CONTRACT", error.message);
  return new W5Error("INVALID_CONTRACT", error.message);
}
