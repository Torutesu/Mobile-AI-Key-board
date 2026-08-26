import { randomUUID } from "node:crypto";
import type { ActionPlan, ReceiptEvent, ReceiptStatus, UserId, DeviceId } from "@mobile-ai-keyboard/contracts";
import { planDigest, ReceiptEvent as ReceiptEventSchema } from "@mobile-ai-keyboard/contracts";
import { validateAndBindPlan } from "@mobile-ai-keyboard/skill-runtime";

export type Receipt = { receipt_id: string; run_id: string; status: ReceiptStatus; completed_steps: string[]; failed_steps: string[]; not_started_steps: string[] };
export type ToolAdapter = { operation: string; execute: (args: Record<string, unknown>, idempotencyKey: string) => Promise<unknown> };
export type ExecutionLedger = Map<string, unknown>;
export class WorkerError extends Error { constructor(readonly code: "DIGEST_MISMATCH" | "ADAPTER_MISSING" | "EXECUTION_UNKNOWN", message: string) { super(message); this.name = "WorkerError"; } }

const defaultLedger: ExecutionLedger = new Map();

export async function executeConfirmedPlan(plan: ActionPlan, confirmedDigest: string, idempotencyKey: string, adapters: ReadonlyMap<string, ToolAdapter>, ledger: ExecutionLedger = defaultLedger): Promise<Receipt> {
  const unsigned = { ...plan } as Partial<ActionPlan>; delete unsigned.canonical_digest;
  if (plan.canonical_digest !== confirmedDigest || planDigest(unsigned as Omit<ActionPlan, "canonical_digest">) !== confirmedDigest) throw new WorkerError("DIGEST_MISMATCH", "Confirmation digest does not match plan");
  validateAndBindPlan(plan);
  const completed: string[] = []; const failed: string[] = []; const notStarted: string[] = [];
  for (const [index, step] of plan.steps.entries()) {
    const adapter = adapters.get(step.operation);
    if (!adapter) { failed.push(step.step_id); notStarted.push(...plan.steps.slice(index + 1).map((item) => item.step_id)); break; }
    // Scope deduplication to the immutable execution identity. A client-generated
    // key is only unique within its run; it must never let another run skip work.
    const stepIdempotencyKey = `${plan.run_id}:${confirmedDigest}:${idempotencyKey}:${step.step_id}`;
    if (ledger.has(stepIdempotencyKey)) { completed.push(step.step_id); continue; }
    try { const result = await adapter.execute(step.arguments, stepIdempotencyKey); ledger.set(stepIdempotencyKey, result); completed.push(step.step_id); }
    catch { failed.push(step.step_id); notStarted.push(...plan.steps.slice(index + 1).map((item) => item.step_id)); break; }
  }
  const status: ReceiptStatus = failed.length === 0 ? "succeeded" : completed.length > 0 ? "partial" : "failed";
  return { receipt_id: `rcpt_${randomUUID()}`, run_id: plan.run_id, status, completed_steps: completed, failed_steps: failed, not_started_steps: notStarted };
}

/** Projects execution into append-only, content-free receipt metadata. */
export function projectReceiptEvent(receipt: Receipt, owner: { user_id: UserId; device_id: DeviceId }, planDigestValue: string, requestId: string, sequence: number, occurredAt = new Date().toISOString()): ReceiptEvent {
  return ReceiptEventSchema.parse({ event_id: `aud_${randomUUID().replaceAll("-", "")}`, receipt_id: receipt.receipt_id, run_id: receipt.run_id, user_id: owner.user_id, device_id: owner.device_id, sequence, status: receipt.status, step_metadata: [
    ...receipt.completed_steps.map((step_id) => ({ step_id, operation: "execution.step", status: "succeeded" as const, completed_at: occurredAt })),
    ...receipt.failed_steps.map((step_id) => ({ step_id, operation: "execution.step", status: "failed" as const, completed_at: occurredAt })),
    ...receipt.not_started_steps.map((step_id) => ({ step_id, operation: "execution.step", status: "not_started" as const }))
  ], plan_digest: planDigestValue, request_id: requestId, occurred_at: occurredAt });
}
