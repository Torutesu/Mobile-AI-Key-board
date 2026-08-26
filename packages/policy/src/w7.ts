import { IncidentRecord, KillSwitchState, MigrationRequest, MigrationState, QualityBudget, QualityDecision, QualityMetric, QualificationDecision, QualificationEvidence, ReleaseCandidate, ReleaseQualityDecision, ReleaseStage, SkillVersion, releaseCandidateDigest } from "@mobile-ai-keyboard/contracts";
import type { IncidentRecord as IncidentRecordData, KillSwitchState as KillSwitchStateData, MigrationRequest as MigrationRequestData, MigrationState as MigrationStateData, QualityBudget as QualityBudgetData, QualityDecision as QualityDecisionData, QualityMetric as QualityMetricData, QualificationDecision as QualificationDecisionData, QualificationEvidence as QualificationEvidenceData, ReleaseCandidate as ReleaseCandidateData, ReleaseQualityDecision as ReleaseQualityDecisionData, ReleaseStage as ReleaseStageData, UserId } from "@mobile-ai-keyboard/contracts";
import { PolicyViolation } from "./index.js";

const versionNumber = (value: string): number[] => value.slice(1).split(".").map(Number);
const compareVersion = (left: string, right: string): number => { const a = versionNumber(left); const b = versionNumber(right); for (let index = 0; index < Math.max(a.length, b.length); index += 1) { const difference = (a[index] ?? 0) - (b[index] ?? 0); if (difference !== 0) return difference; } return 0; };
export const PROTECTED_EVIDENCE_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1_000;

export function validateReleaseCandidate(value: unknown): ReleaseCandidateData {
  const parsed = ReleaseCandidate.safeParse(value); if (!parsed.success) throw new PolicyViolation("Release candidate contract is invalid", { code: "INVALID_RELEASE_CANDIDATE" });
  const { candidate_digest: _digest, ...unsigned } = parsed.data; if (releaseCandidateDigest(unsigned) !== parsed.data.candidate_digest) throw new PolicyViolation("Release candidate digest does not match its source/artifact binding", { code: "CANDIDATE_DIGEST_MISMATCH" }); return parsed.data;
}

export function validateQualificationEvidence(value: unknown, candidate: ReleaseCandidateData): QualificationEvidenceData {
  const parsed = QualificationEvidence.safeParse(value); if (!parsed.success) throw new PolicyViolation("Qualification evidence contract is invalid", { code: "INVALID_QUALIFICATION_EVIDENCE" });
  if (parsed.data.candidate_id !== candidate.candidate_id || parsed.data.candidate_digest !== candidate.candidate_digest || parsed.data.source_commit !== candidate.source_commit || parsed.data.artifact_digest !== candidate.artifact_digest || parsed.data.test_run_ids.length !== candidate.test_run_ids.length || parsed.data.test_run_ids.some((id, index) => id !== candidate.test_run_ids[index])) throw new PolicyViolation("Qualification evidence is not bound to the exact candidate and test run set", { code: "EVIDENCE_CANDIDATE_MISMATCH" });
  return parsed.data;
}

export function evaluateQualificationEvidence(value: unknown, candidate: ReleaseCandidateData, trustedEvidenceIds: ReadonlySet<string> = new Set(), now = new Date()): QualificationDecisionData {
  const evidence = validateQualificationEvidence(value, candidate); let status: QualificationDecisionData["status"]; let reason: QualificationDecisionData["reason"];
  const observedAt = Date.parse(evidence.observed_at); const age = now.getTime() - observedAt;
  if (evidence.qualification_status === "passed" && candidate.environment === "protected_production" && evidence.evidence_kind === "protected_external" && evidence.verifier_kind === "protected_runner" && evidence.verifier_id !== undefined && trustedEvidenceIds.has(evidence.evidence_id) && age >= 0 && age <= PROTECTED_EVIDENCE_MAX_AGE_MS) { status = "passed"; reason = "protected_evidence"; } else if (age < 0) { status = "not_proven"; reason = "evidence_future"; } else if (age > PROTECTED_EVIDENCE_MAX_AGE_MS) { status = "not_proven"; reason = "evidence_stale"; } else if (evidence.evidence_kind === "fixture") { status = "not_proven"; reason = "fixture_not_proven"; } else if (evidence.evidence_kind === "simulator") { status = "not_proven"; reason = "simulator_not_proven"; } else if (evidence.evidence_kind === "mock") { status = "not_proven"; reason = "mock_not_proven"; } else { status = "not_proven"; reason = "untrusted_evidence"; }
  return QualificationDecision.parse({ candidate_id: candidate.candidate_id, candidate_digest: candidate.candidate_digest, status, reason, evaluated_at: now.toISOString() });
}

export function assertKillSwitchTransition(previous: KillSwitchStateData | undefined, nextValue: unknown, owner: UserId, releaseEpoch: number): KillSwitchStateData {
  const next = KillSwitchState.safeParse(nextValue); if (!next.success) throw new PolicyViolation("Kill switch state is invalid", { code: "INVALID_KILL_SWITCH" });
  if (next.data.owner_user_id !== owner || next.data.release_epoch !== releaseEpoch) throw new PolicyViolation("Kill switch owner or release epoch mismatch", { code: "KILL_SWITCH_OWNER_MISMATCH" });
  if (previous === undefined && next.data.revision !== 1) throw new PolicyViolation("Initial kill switch revision must be 1", { code: "KILL_SWITCH_REVISION_CONFLICT" });
  if (previous) { if (previous.target.kind !== next.data.target.kind || previous.target.identifier !== next.data.target.identifier || previous.owner_user_id !== next.data.owner_user_id || previous.release_epoch !== next.data.release_epoch || next.data.revision !== previous.revision + 1) throw new PolicyViolation("Kill switch revision or target is stale", { code: "KILL_SWITCH_REVISION_CONFLICT" }); }
  return next.data;
}
export function validateIncidentRecord(value: unknown, owner: UserId, releaseEpoch: number): IncidentRecordData { const parsed = IncidentRecord.safeParse(value); if (!parsed.success) throw new PolicyViolation("Incident record is invalid", { code: "INVALID_INCIDENT" }); if (parsed.data.owner_user_id !== owner || parsed.data.release_epoch !== releaseEpoch) throw new PolicyViolation("Incident record owner or epoch mismatch", { code: "KILL_SWITCH_OWNER_MISMATCH" }); return parsed.data; }

export function assertMigrationRequest(state: MigrationStateData, requestValue: unknown, candidate?: ReleaseCandidateData, rollbackTarget?: ReleaseCandidateData): MigrationRequestData {
  const parsed = MigrationRequest.safeParse(requestValue); if (!parsed.success) throw new PolicyViolation("Migration request is invalid", { code: "INVALID_MIGRATION_REQUEST" }); const request = parsed.data;
  if (request.owner_user_id !== state.owner_user_id || request.release_epoch !== state.release_epoch || request.environment !== state.environment) throw new PolicyViolation("Migration request crosses owner, epoch, or environment", { code: "MIGRATION_OWNER_MISMATCH" });
  const candidateMatchesOwner = (value: ReleaseCandidateData): boolean => value.owner_user_id === state.owner_user_id && value.release_epoch === state.release_epoch;
  const environmentAllows = (value: ReleaseCandidateData): boolean => state.environment === "production" ? value.environment === "protected_production" : state.environment === "staging" ? value.environment === "simulator" || value.environment === "protected_production" : value.environment !== "protected_production";
  if (request.action === "forward") { if (!candidate || !candidateMatchesOwner(candidate) || !environmentAllows(candidate) || candidate.candidate_id !== request.candidate_id || candidate.candidate_digest !== request.candidate_digest || candidate.schema_version !== request.schema_version || compareVersion(request.schema_version, state.schema_version) <= 0) throw new PolicyViolation("Forward migration candidate, owner, environment, or version is not exact and monotonic", { code: "MIGRATION_TARGET_MISMATCH" }); }
  if (request.action === "rollback") { if (!rollbackTarget || !candidateMatchesOwner(rollbackTarget) || !environmentAllows(rollbackTarget) || rollbackTarget.candidate_id !== request.candidate_id || rollbackTarget.candidate_digest !== request.candidate_digest || rollbackTarget.schema_version !== request.schema_version || state.rollback_target_candidate_id !== request.candidate_id || state.rollback_target_digest !== request.candidate_digest || compareVersion(request.schema_version, state.schema_version) >= 0) throw new PolicyViolation("Rollback target does not match the recorded candidate", { code: "ROLLBACK_TARGET_MISMATCH" }); }
  return request;
}

const fixedBudgets: Record<ReleaseStageData, QualityBudgetData> = {
  beta: { keyboard_cold_start_p50_max_ms: 250, keyboard_cold_start_p95_max_ms: 400, keyboard_warm_open_p95_max_ms: 150, keyboard_key_to_commit_p95_max_ms: 50, keyboard_crash_free_sessions_min: 0.998 },
  broad: { keyboard_cold_start_p50_max_ms: 250, keyboard_cold_start_p95_max_ms: 400, keyboard_warm_open_p95_max_ms: 150, keyboard_key_to_commit_p95_max_ms: 50, keyboard_crash_free_sessions_min: 0.9995 }
};

function evaluateQualityBudgetInternal(metrics: readonly QualityMetricData[], budget: QualityBudgetData, candidateDigest: string, environment: "fixture" | "simulator" | "protected_production", now: Date, trustedTestRunIds: ReadonlySet<string> = new Set()): QualityDecisionData {
  const parsedBudget = QualityBudget.parse(budget); let invalidMetric = false; const seenMetricKeys = new Set<string>(); const relevant = metrics.flatMap((metric) => { const parsed = QualityMetric.safeParse(metric); if (!parsed.success) { invalidMetric = true; return []; } if (parsed.data.candidate_digest === candidateDigest && parsed.data.environment === environment) { const key = `${parsed.data.platform}:${parsed.data.metric}`; if (seenMetricKeys.has(key)) invalidMetric = true; seenMetricKeys.add(key); return [parsed.data]; } return []; });
  const metricNames = ["keyboard_cold_start_p50_ms", "keyboard_cold_start_p95_ms", "keyboard_warm_open_p95_ms", "keyboard_key_to_commit_p95_ms", "keyboard_crash_free_sessions_rate"] as const; const platforms = ["ios", "android"] as const;
  const required = platforms.flatMap((platform) => metricNames.map((metric) => `${platform}:${metric}`));
  const byMetric = new Map(relevant.map((metric) => [`${metric.platform}:${metric.metric}`, metric])); const missing = required.filter((name) => !byMetric.has(name)); const failed: string[] = [];
  const performanceWithin = (platform: "ios" | "android", name: "keyboard_cold_start_p50_ms" | "keyboard_cold_start_p95_ms" | "keyboard_warm_open_p95_ms" | "keyboard_key_to_commit_p95_ms", maximum: number): boolean => { const metric = byMetric.get(`${platform}:${name}`); return metric?.kind === "performance" && metric.value_ms <= maximum; };
  const crashFreeWithin = (platform: "ios" | "android"): boolean => { const metric = byMetric.get(`${platform}:keyboard_crash_free_sessions_rate`); return metric?.kind === "crash" && metric.crash_free_sessions_rate >= parsedBudget.keyboard_crash_free_sessions_min; };
  for (const platform of platforms) { const p50 = byMetric.get(`${platform}:keyboard_cold_start_p50_ms`); const p95 = byMetric.get(`${platform}:keyboard_cold_start_p95_ms`); const chronologyValid = p50?.kind === "performance" && p95?.kind === "performance" && p50.value_ms <= p95.value_ms; const checks: Array<[string, boolean]> = [[`${platform}:keyboard_cold_start_p50_ms`, performanceWithin(platform, "keyboard_cold_start_p50_ms", parsedBudget.keyboard_cold_start_p50_max_ms) && chronologyValid], [`${platform}:keyboard_cold_start_p95_ms`, performanceWithin(platform, "keyboard_cold_start_p95_ms", parsedBudget.keyboard_cold_start_p95_max_ms) && chronologyValid], [`${platform}:keyboard_warm_open_p95_ms`, performanceWithin(platform, "keyboard_warm_open_p95_ms", parsedBudget.keyboard_warm_open_p95_max_ms)], [`${platform}:keyboard_key_to_commit_p95_ms`, performanceWithin(platform, "keyboard_key_to_commit_p95_ms", parsedBudget.keyboard_key_to_commit_p95_max_ms)], [`${platform}:keyboard_crash_free_sessions_rate`, crashFreeWithin(platform)]]; for (const [name, passed] of checks) if (!missing.includes(name) && !passed) failed.push(name); }
  const testRunIds = [...new Set(relevant.map((metric) => metric.test_run_id))].sort();
  const protectedAttestation = relevant.every((metric) => metric.verifier_kind === "protected_runner" && metric.verifier_id !== undefined && trustedTestRunIds.has(metric.test_run_id));
  const status = environment !== "protected_production" || invalidMetric || missing.length > 0 || !protectedAttestation ? "not_proven" : failed.length > 0 ? "failed" : "passed";
  return QualityDecision.parse({ candidate_digest: candidateDigest, environment, status, failed_metrics: failed, missing_metrics: missing, test_run_ids: testRunIds, evaluated_at: now.toISOString() });
}

/** Caller-selected budgets are diagnostic only and can never produce a qualification pass. */
export function evaluateQualityBudget(metrics: readonly QualityMetricData[], budget: QualityBudgetData, candidateDigest: string, environment: "fixture" | "simulator" | "protected_production", now = new Date()): QualityDecisionData {
  const decision = evaluateQualityBudgetInternal(metrics, budget, candidateDigest, environment, now); return QualityDecision.parse({ ...decision, status: "not_proven" });
}

/** The only quality evaluator usable for release qualification; ceilings are policy-owned. */
export function evaluateReleaseQualityBudget(metrics: readonly QualityMetricData[], candidateValue: unknown, environment: "fixture" | "simulator" | "protected_production", stageValue: unknown, now = new Date(), trustedTestRunIds: ReadonlySet<string> = new Set()): ReleaseQualityDecisionData {
  const candidate = validateReleaseCandidate(candidateValue); const stage = ReleaseStage.parse(stageValue); const decision = evaluateQualityBudgetInternal(metrics, fixedBudgets[stage], candidate.candidate_digest, environment, now, trustedTestRunIds); const exactRuns = decision.test_run_ids.length === candidate.test_run_ids.length && decision.test_run_ids.every((id, index) => id === [...candidate.test_run_ids].sort()[index]); return ReleaseQualityDecision.parse({ ...decision, status: exactRuns && candidate.environment === environment ? decision.status : "not_proven", stage, budget_source: "fixed_release_policy" });
}
