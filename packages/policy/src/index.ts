import type { ActionPlan, RiskClass } from "@mobile-ai-keyboard/contracts";

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
