import { LocalDisclosure, LocalTextCapture, LocalTextPlan, localCaptureFingerprint, localDisclosureDigest, localTextPlanDigest } from "@mobile-ai-keyboard/contracts";
import type { ActionPlan, LocalCaptureLimits, LocalDisclosure as LocalDisclosureData, LocalTextCapture as LocalTextCaptureData, LocalTextPlan as LocalTextPlanData, RiskClass } from "@mobile-ai-keyboard/contracts";

export class PolicyViolation extends Error {
  readonly code = "POLICY_VIOLATION" as const;
  constructor(message: string, readonly details: Record<string, unknown> = {}) { super(message); this.name = "PolicyViolation"; }
}

const rank: Record<RiskClass, number> = { R0: 0, R1: 1, R2: 2, R3: 3, R4: 4, R5: 5 };
const prohibited = new Set(["calendar.event.delete_own", "payment.create", "credentials.read", "permissions.change", "message.send", "email.send", "account.delete"]);

export function maxRisk(...risks: RiskClass[]): RiskClass {
  let highest: RiskClass = "R0";
  for (const current of risks) if ((rank[current] ?? 0) > (rank[highest] ?? 0)) highest = current;
  return highest;
}

export function classifyPlan(plan: Pick<ActionPlan, "steps">): RiskClass {
  return maxRisk(...plan.steps.map((step) => {
    if (prohibited.has(step.operation) || step.side_effect === "destructive") return "R5" as const;
    if (step.side_effect === "external_communication") return "R4" as const;
    if (step.side_effect !== "none") return "R3" as const;
    return step.risk_class;
  }));
}

export type PolicyDecision = { allowed: true; risk_class: RiskClass; confirmation_required: boolean; reason: "none" | "external_read" | "external_write" | "enhanced_confirmation" } | { allowed: false; risk_class: "R5"; reason: "prohibited_operation" | "risk_ceiling_exceeded"; operation?: string };

export function evaluatePlan(plan: Pick<ActionPlan, "steps" | "risk_class" | "confirmation">, riskCeiling: RiskClass = "R3"): PolicyDecision {
  const forbidden = plan.steps.find((step) => prohibited.has(step.operation) || step.side_effect === "destructive");
  if (forbidden) return { allowed: false, risk_class: "R5", reason: "prohibited_operation", operation: forbidden.operation };
  const risk = classifyPlan(plan);
  if ((rank[risk] ?? 0) > (rank[riskCeiling] ?? 0)) return { allowed: false, risk_class: "R5", reason: "risk_ceiling_exceeded" };
  if (risk === "R0" || risk === "R1") return { allowed: true, risk_class: risk, confirmation_required: false, reason: "none" };
  if (risk === "R2") return { allowed: true, risk_class: risk, confirmation_required: true, reason: "external_read" };
  if (risk === "R3") return { allowed: true, risk_class: risk, confirmation_required: true, reason: "external_write" };
  return { allowed: true, risk_class: risk, confirmation_required: true, reason: "enhanced_confirmation" };
}

export function assertPlanPolicy(plan: ActionPlan, riskCeiling: RiskClass = "R3"): void {
  const recomputed = classifyPlan(plan);
  if (recomputed !== plan.risk_class) throw new PolicyViolation("Plan risk class does not match its steps", { declared: plan.risk_class, recomputed });
  const decision = evaluatePlan(plan, riskCeiling);
  if (!decision.allowed) throw new PolicyViolation("Plan contains a prohibited operation", decision);
  if (decision.confirmation_required !== plan.confirmation.required) throw new PolicyViolation("Confirmation requirement does not match policy", { expected: decision.confirmation_required, actual: plan.confirmation.required });
}

export type LocalTextPolicyDecision =
  | { allowed: true; risk_class: "R1"; destination: "local_device"; network_required: false }
  | { allowed: false; reason: "invalid_contract" | "external_tool" | "network_required" | "wrong_destination" | "digest_mismatch" | "capture_source_not_opted_in" | "capture_limit_exceeded" | "capture_acknowledgement_mismatch" | "capture_fingerprint_mismatch" };

const localLimitFor = (source: "command" | "selection" | "surrounding_text" | "clipboard", limits: LocalCaptureLimits): number => {
  if (source === "command") return limits.command_max_characters;
  if (source === "selection") return limits.selection_max_characters;
  if (source === "clipboard") return limits.clipboard_max_characters;
  return limits.surrounding_before_max_characters + limits.surrounding_after_max_characters;
};

export function validateLocalDisclosure(value: unknown): LocalDisclosureData {
  const parsed = LocalDisclosure.safeParse(value);
  if (!parsed.success) throw new PolicyViolation("Local disclosure contract is invalid", { code: "invalid_contract" });
  const seen = new Set<string>();
  for (const source of parsed.data.sources) {
    if (seen.has(source.source)) throw new PolicyViolation("Local disclosure contains duplicate capture sources", { code: "invalid_contract" });
    seen.add(source.source);
    if ((source.source === "clipboard" || source.source === "surrounding_text") && source.enabled && !source.explicit_opt_in) {
      throw new PolicyViolation("Clipboard and surrounding text require explicit opt-in", { code: "capture_source_not_opted_in", source: source.source });
    }
  }
  return parsed.data;
}

export function validateLocalCapture(disclosure: LocalDisclosureData, value: unknown): LocalTextCaptureData {
  validateLocalDisclosure(disclosure);
  const parsed = LocalTextCapture.safeParse(value);
  if (!parsed.success) throw new PolicyViolation("Local capture contract is invalid", { code: "invalid_contract" });
  if (parsed.data.disclosure_acknowledgement !== localDisclosureDigest(disclosure)) throw new PolicyViolation("Local disclosure acknowledgement digest does not match", { code: "capture_acknowledgement_mismatch" });
  if (localCaptureFingerprint({ items: parsed.data.items, field_fingerprint: parsed.data.field_fingerprint, disclosure_acknowledgement: parsed.data.disclosure_acknowledgement }) !== parsed.data.capture_fingerprint) throw new PolicyViolation("Local capture fingerprint does not match immutable capture", { code: "capture_fingerprint_mismatch" });
  const capturedSources = new Set<string>();
  for (const item of parsed.data.items) {
    if (capturedSources.has(item.source)) throw new PolicyViolation("Local capture contains duplicate sources", { code: "invalid_contract", source: item.source });
    capturedSources.add(item.source);
    const source = disclosure.sources.find((entry) => entry.source === item.source);
    if (!source?.enabled) throw new PolicyViolation("Capture source was not disclosed and enabled", { code: "capture_source_not_opted_in", source: item.source });
    if (Array.from(item.text).length > localLimitFor(item.source, disclosure.limits)) throw new PolicyViolation("Capture source exceeds its hard character limit", { code: "capture_limit_exceeded", source: item.source });
  }
  return parsed.data;
}

export function evaluateLocalTextPlan(value: unknown): LocalTextPolicyDecision {
  const parsed = LocalTextPlan.safeParse(value);
  if (!parsed.success) {
    const input = value as { tools?: unknown; network_required?: unknown; destination?: unknown } | null;
    if (Array.isArray(input?.tools) && input.tools.length > 0) return { allowed: false, reason: "external_tool" };
    if (input?.network_required === true) return { allowed: false, reason: "network_required" };
    if (input?.destination !== undefined && input.destination !== "local_device") return { allowed: false, reason: "wrong_destination" };
    return { allowed: false, reason: "invalid_contract" };
  }
  const plan = parsed.data;
  if (localTextPlanDigest({ ...plan, canonical_digest: undefined } as Omit<LocalTextPlanData, "canonical_digest">) !== plan.canonical_digest) return { allowed: false, reason: "digest_mismatch" };
  return { allowed: true, risk_class: "R1", destination: "local_device", network_required: false };
}

export function assertLocalTextPlan(plan: LocalTextPlanData): void {
  const decision = evaluateLocalTextPlan(plan);
  if (!decision.allowed) throw new PolicyViolation("Local text plan is not allowed", decision);
}

export * from "./w4.js";
export * from "./w5.js";
export * from "./w6.js";
export * from "./w7.js";
