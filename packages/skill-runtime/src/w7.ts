import { randomUUID } from "node:crypto";
import {
  IncidentRecord,
  KillSwitchState,
  KillSwitchTarget,
  MigrationRequest,
  MigrationState,
  QualificationDecision,
  ReleaseQualityDecision,
  ReleaseCandidate,
  canonicalJson,
  type IncidentRecord as IncidentRecordData,
  type KillSwitchState as KillSwitchStateData,
  type KillSwitchTarget as KillSwitchTargetData,
  type MigrationRequest as MigrationRequestData,
  type MigrationState as MigrationStateData,
  type QualificationDecision as QualificationDecisionData,
  type ReleaseCandidate as ReleaseCandidateData,
  type UserId
} from "@mobile-ai-keyboard/contracts";
import {
  assertKillSwitchTransition,
  assertMigrationRequest,
  evaluateQualificationEvidence,
  validateIncidentRecord,
  validateReleaseCandidate,
  validateQualificationEvidence
} from "@mobile-ai-keyboard/policy";
import { PolicyViolation } from "@mobile-ai-keyboard/policy";

export type W7ErrorCode =
  | "INVALID_CONTRACT"
  | "CANDIDATE_DIGEST_MISMATCH"
  | "EVIDENCE_NOT_PROVEN"
  | "QUALITY_NOT_PROVEN"
  | "KILL_SWITCH_OWNER_MISMATCH"
  | "KILL_SWITCH_REVISION_CONFLICT"
  | "ORDINARY_TYPING_PROTECTED"
  | "INCIDENT_CONFLICT"
  | "MIGRATION_OWNER_MISMATCH"
  | "MIGRATION_TARGET_MISMATCH"
  | "ROLLBACK_TARGET_MISMATCH"
  | "MIGRATION_CONFLICT";

export class W7Error extends Error {
  constructor(readonly code: W7ErrorCode, message: string) {
    super(message);
    this.name = "W7Error";
  }
}

const clone = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;
const policyCode = (error: unknown): W7ErrorCode => {
  if (!(error instanceof PolicyViolation)) return "INVALID_CONTRACT";
  const code = String(error.details.code ?? "INVALID_CONTRACT");
  const known: W7ErrorCode[] = ["CANDIDATE_DIGEST_MISMATCH", "KILL_SWITCH_OWNER_MISMATCH", "KILL_SWITCH_REVISION_CONFLICT", "MIGRATION_OWNER_MISMATCH", "MIGRATION_TARGET_MISMATCH", "ROLLBACK_TARGET_MISMATCH"];
  return known.includes(code as W7ErrorCode) ? code as W7ErrorCode : "INVALID_CONTRACT";
};
const policyCall = <T>(operation: () => T): T => {
  try { return operation(); } catch (error) { if (error instanceof W7Error) throw error; throw new W7Error(policyCode(error), error instanceof Error ? error.message : "W7 policy rejected the request"); }
};
const incidentId = (): string => `inc_${randomUUID().replaceAll("-", "")}`;
const targetKey = (owner: UserId, epoch: number, target: KillSwitchTargetData): string => `${owner}:${epoch}:${target.kind}:${target.identifier}`;
const exact = (left: unknown, right: unknown): boolean => canonicalJson(left) === canonicalJson(right);

/** Production qualification is intentionally impossible without an injected, trusted protected-runner evidence set. */
export class QualificationGate {
  constructor(private readonly trustedEvidenceIds: ReadonlySet<string> = new Set(), private readonly clock: () => Date = () => new Date()) {}
  evaluate(value: unknown, candidateValue: unknown): QualificationDecisionData {
    const candidate = policyCall(() => validateReleaseCandidate(candidateValue));
    return policyCall(() => evaluateQualificationEvidence(value, candidate, this.trustedEvidenceIds, this.clock()));
  }
  assertProduction(value: unknown, candidateValue: unknown): QualificationDecisionData {
    const decision = this.evaluate(value, candidateValue);
    if (decision.status !== "passed") throw new W7Error("EVIDENCE_NOT_PROVEN", `Release candidate qualification is ${decision.status}: ${decision.reason}`);
    return decision;
  }
}

/** In-memory kill-switch fixture. Incidents are append-only and contain no content payload. */
export class KillSwitchRegistry {
  private readonly states = new Map<string, KillSwitchStateData>();
  private readonly log: IncidentRecordData[] = [];
  constructor(private readonly clock: () => Date = () => new Date()) {}

  apply(owner: UserId, releaseEpoch: number, value: unknown, candidateDigest: string, reasonCode: string): KillSwitchStateData {
    const candidate = value as { target?: { kind?: unknown; identifier?: unknown } } | null;
    if (candidate?.target?.kind === "ordinary_typing" || candidate?.target?.identifier === "ordinary_typing") throw new W7Error("ORDINARY_TYPING_PROTECTED", "Ordinary typing is outside the kill-switch authority ceiling");
    const next = policyCall(() => KillSwitchState.parse(value));
    const key = targetKey(owner, releaseEpoch, next.target);
    const previous = this.states.get(key);
    if (previous && exact(previous, next)) return clone(previous);
    const accepted = policyCall(() => assertKillSwitchTransition(previous, next, owner, releaseEpoch));
    const record = policyCall(() => validateIncidentRecord({ incident_id: incidentId(), target: accepted.target, owner_user_id: owner, release_epoch: releaseEpoch, kill_switch_revision: accepted.revision, action: accepted.status, reason_code: reasonCode, candidate_digest: candidateDigest, occurred_at: this.clock().toISOString() }, owner, releaseEpoch));
    this.states.set(key, clone(accepted));
    this.log.push(clone(record));
    return clone(accepted);
  }

  get(owner: UserId, releaseEpoch: number, targetValue: unknown): KillSwitchStateData | undefined {
    const target = policyCall(() => KillSwitchTarget.parse(targetValue));
    const state = this.states.get(targetKey(owner, releaseEpoch, target));
    return state ? clone(state) : undefined;
  }
  isDisabled(owner: UserId, releaseEpoch: number, targetValue: unknown): boolean { return this.get(owner, releaseEpoch, targetValue)?.status === "disabled"; }
  incidents(): readonly IncidentRecordData[] { return this.log.map(clone); }
}

type StoredMigrationRequest = { request: string; state: MigrationStateData };

/** Beta migration fixture. Request IDs are idempotent and state transitions are candidate-bound. */
export class BetaMigrationManager {
  private state: MigrationStateData;
  private readonly requests = new Map<string, StoredMigrationRequest>();
  constructor(
    initial: MigrationStateData,
    private readonly clock: () => Date = () => new Date(),
    private readonly trustedQualificationDecisions: ReadonlySet<string> = new Set(),
    private readonly trustedQualityDecisions: ReadonlySet<string> = new Set()
  ) { this.state = policyCall(() => MigrationState.parse(initial)); }

  current(): MigrationStateData { return clone(this.state); }

  apply(requestValue: unknown, candidateValue: unknown, qualificationValue?: unknown, qualityValue?: unknown): MigrationStateData {
    const request = policyCall(() => MigrationRequest.parse(requestValue));
    const requestCanonical = canonicalJson(request);
    const prior = this.requests.get(request.request_id);
    if (prior) { if (prior.request !== requestCanonical) throw new W7Error("MIGRATION_CONFLICT", "Migration request ID was reused with a different payload"); return clone(prior.state); }
    const candidate = policyCall(() => validateReleaseCandidate(candidateValue));
    policyCall(() => assertMigrationRequest(this.state, request, request.action === "forward" ? candidate : undefined, request.action === "rollback" ? candidate : undefined));
    if (request.action === "forward" && this.state.environment === "production") {
      const qualification = QualificationDecision.safeParse(qualificationValue);
      if (!qualification.success || qualification.data.candidate_id !== candidate.candidate_id || qualification.data.candidate_digest !== candidate.candidate_digest || qualification.data.status !== "passed" || qualification.data.reason !== "protected_evidence") throw new W7Error("EVIDENCE_NOT_PROVEN", "Production forward migration requires exact protected qualification evidence");
      if (!this.trustedQualificationDecisions.has(canonicalJson(qualification.data))) throw new W7Error("EVIDENCE_NOT_PROVEN", "Qualification decision was not injected by a trusted authority");
      const quality = ReleaseQualityDecision.safeParse(qualityValue);
      const exactQualityRuns = quality.success && quality.data.test_run_ids.length === candidate.test_run_ids.length && quality.data.test_run_ids.every((id, index) => id === [...candidate.test_run_ids].sort()[index]);
      if (!quality.success || quality.data.candidate_digest !== candidate.candidate_digest || quality.data.environment !== "protected_production" || quality.data.status !== "passed" || quality.data.budget_source !== "fixed_release_policy" || !exactQualityRuns) throw new W7Error("QUALITY_NOT_PROVEN", "Production forward migration requires an exact-run, passed fixed-policy quality decision");
      if (!this.trustedQualityDecisions.has(canonicalJson(quality.data))) throw new W7Error("QUALITY_NOT_PROVEN", "Quality decision was not injected by a trusted authority");
    }
    const next: MigrationStateData = MigrationState.parse({
      ...this.state,
      revision: this.state.revision + 1,
      status: request.action === "forward" ? "forwarded" : "rolled_back",
      current_candidate_id: candidate.candidate_id,
      current_candidate_digest: candidate.candidate_digest,
      schema_version: request.schema_version,
      rollback_target_candidate_id: request.action === "forward" ? this.state.rollback_target_candidate_id : undefined,
      rollback_target_digest: request.action === "forward" ? this.state.rollback_target_digest : undefined,
      updated_at: this.clock().toISOString()
    });
    this.state = next;
    this.requests.set(request.request_id, { request: requestCanonical, state: clone(next) });
    return clone(next);
  }
}
