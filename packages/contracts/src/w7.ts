import { createHash } from "node:crypto";
import { z } from "zod";
import { DeviceId, UserId } from "./w3.js";
import { canonicalJson } from "./canonical.js";

const Digest = z.string().regex(/^sha256:[a-f0-9]{64}$/);
const Opaque = (prefix: string) => z.string().regex(new RegExp(`^${prefix}_[A-Za-z0-9_-]{16,128}$`));
const CandidateId = Opaque("cand");
const EvidenceId = Opaque("evid");
const TestRunId = Opaque("tst");
const IncidentId = Opaque("inc");
const MigrationId = Opaque("mig");
const NonBlank = (max: number) => z.string().max(max).refine((value) => value.trim().length > 0, { message: "value must not be blank" });

export const ReleaseEnvironment = z.enum(["fixture", "simulator", "protected_production"]);
export type ReleaseEnvironment = z.infer<typeof ReleaseEnvironment>;
export const ReleaseCandidate = z.object({ candidate_id: CandidateId, source_commit: z.string().regex(/^[a-f0-9]{40}$/), artifact_digest: Digest, schema_version: z.string().regex(/^v[0-9]+(?:\.[0-9]+){0,2}$/), test_run_ids: z.array(TestRunId).min(1).max(100), privacy_declaration_digest: Digest, rollback_target_digest: Digest.optional(), owner_user_id: UserId, release_epoch: z.number().int().positive(), environment: ReleaseEnvironment, candidate_digest: Digest }).strict().superRefine((value, context) => { if (new Set(value.test_run_ids).size !== value.test_run_ids.length) context.addIssue({ code: z.ZodIssueCode.custom, message: "test_run_ids must be unique" }); });
export type ReleaseCandidate = z.infer<typeof ReleaseCandidate>;
export const QualificationEvidence = z.object({ evidence_id: EvidenceId, candidate_id: CandidateId, candidate_digest: Digest, source_commit: z.string().regex(/^[a-f0-9]{40}$/), artifact_digest: Digest, test_run_ids: z.array(TestRunId).min(1).max(100), evidence_kind: z.enum(["fixture", "simulator", "mock", "protected_external"]), qualification_status: z.enum(["passed", "not_proven"]), verifier_kind: z.enum(["self_attested", "protected_runner"]).optional(), verifier_id: NonBlank(128).optional(), observed_at: z.string().datetime({ offset: true }) }).strict().superRefine((value, context) => {
  if (["fixture", "simulator", "mock"].includes(value.evidence_kind) && value.qualification_status === "passed") context.addIssue({ code: z.ZodIssueCode.custom, message: "fixture evidence cannot qualify production" });
  if (value.qualification_status === "passed" && (value.evidence_kind !== "protected_external" || value.verifier_kind !== "protected_runner" || value.verifier_id === undefined)) context.addIssue({ code: z.ZodIssueCode.custom, message: "production pass requires protected runner evidence" });
  if (value.verifier_kind === "self_attested" && value.qualification_status === "passed") context.addIssue({ code: z.ZodIssueCode.custom, message: "self-attested evidence cannot qualify production" });
});
export type QualificationEvidence = z.infer<typeof QualificationEvidence>;
export const QualificationDecision = z.object({ candidate_id: CandidateId, candidate_digest: Digest, status: z.enum(["passed", "not_proven", "failed"]), reason: z.enum(["protected_evidence", "fixture_not_proven", "simulator_not_proven", "mock_not_proven", "untrusted_evidence", "candidate_binding_mismatch", "missing_evidence", "evidence_future", "evidence_stale"]), evaluated_at: z.string().datetime({ offset: true }) }).strict();
export type QualificationDecision = z.infer<typeof QualificationDecision>;

export const KillSwitchTargetKind = z.enum(["skill_version", "tool_operation", "provider", "model"]);
export type KillSwitchTargetKind = z.infer<typeof KillSwitchTargetKind>;
export const KillSwitchTarget = z.object({ kind: KillSwitchTargetKind, identifier: NonBlank(256) }).strict().superRefine((value, context) => { const patterns: Record<KillSwitchTargetKind, RegExp> = { skill_version: /^skill_[A-Za-z0-9_-]{16,128}(?:[@:]v[0-9]+(?:\.[0-9]+){0,2})$/, tool_operation: /^[a-z][a-z0-9_.-]{2,100}$/, provider: /^[a-z][a-z0-9_-]{1,63}$/, model: /^[a-z][a-z0-9._:-]{2,127}$/ }; if (!patterns[value.kind].test(value.identifier)) context.addIssue({ code: z.ZodIssueCode.custom, message: "kill-switch target identifier is invalid for its kind" }); });
export type KillSwitchTarget = z.infer<typeof KillSwitchTarget>;
export const KillSwitchState = z.object({ target: KillSwitchTarget, owner_user_id: UserId, release_epoch: z.number().int().positive(), revision: z.number().int().positive(), status: z.enum(["enabled", "disabled"]), updated_at: z.string().datetime({ offset: true }) }).strict();
export type KillSwitchState = z.infer<typeof KillSwitchState>;
export const IncidentRecord = z.object({ incident_id: IncidentId, target: KillSwitchTarget, owner_user_id: UserId, release_epoch: z.number().int().positive(), kill_switch_revision: z.number().int().positive(), action: z.enum(["disabled", "enabled"]), reason_code: z.string().regex(/^[A-Z0-9_]{3,64}$/), candidate_digest: Digest, occurred_at: z.string().datetime({ offset: true }) }).strict();
export type IncidentRecord = z.infer<typeof IncidentRecord>;

export const MigrationEnvironment = z.enum(["beta", "staging", "production"]);
export type MigrationEnvironment = z.infer<typeof MigrationEnvironment>;
export const MigrationStatus = z.enum(["ready", "forwarded", "rolled_back", "failed"]);
export const MigrationState = z.object({ migration_id: MigrationId, owner_user_id: UserId, release_epoch: z.number().int().positive(), environment: MigrationEnvironment, revision: z.number().int().positive(), status: MigrationStatus, current_candidate_id: CandidateId, current_candidate_digest: Digest, schema_version: z.string().regex(/^v[0-9]+(?:\.[0-9]+){0,2}$/), rollback_target_candidate_id: CandidateId.optional(), rollback_target_digest: Digest.optional(), updated_at: z.string().datetime({ offset: true }) }).strict().superRefine((value, context) => { if ((value.rollback_target_candidate_id === undefined) !== (value.rollback_target_digest === undefined)) context.addIssue({ code: z.ZodIssueCode.custom, message: "rollback target id and digest must be paired" }); });
export type MigrationState = z.infer<typeof MigrationState>;
export const MigrationRequest = z.object({ request_id: z.string().min(8).max(200).refine((value) => value.trim().length > 0, { message: "request_id must not be blank" }), owner_user_id: UserId, release_epoch: z.number().int().positive(), environment: MigrationEnvironment, action: z.enum(["forward", "rollback"]), candidate_id: CandidateId, candidate_digest: Digest, schema_version: z.string().regex(/^v[0-9]+(?:\.[0-9]+){0,2}$/), rollback_target_digest: Digest.optional() }).strict();
export type MigrationRequest = z.infer<typeof MigrationRequest>;

const MetricAttestation = { test_run_id: TestRunId, verifier_kind: z.enum(["self_attested", "protected_runner"]), verifier_id: NonBlank(128).optional() };
export const PerformanceMetric = z.object({ kind: z.literal("performance"), metric: z.enum(["keyboard_cold_start_p50_ms", "keyboard_cold_start_p95_ms", "keyboard_warm_open_p95_ms", "keyboard_key_to_commit_p95_ms"]), candidate_digest: Digest, environment: ReleaseEnvironment, platform: z.enum(["ios", "android"]), value_ms: z.number().finite().nonnegative().max(60_000), sample_count: z.number().int().positive().max(10_000_000), recorded_at: z.string().datetime({ offset: true }), ...MetricAttestation }).strict().superRefine((value, context) => { if (value.environment === "protected_production" && (value.verifier_kind !== "protected_runner" || value.verifier_id === undefined)) context.addIssue({ code: z.ZodIssueCode.custom, message: "production metric requires protected runner attestation" }); });
export type PerformanceMetric = z.infer<typeof PerformanceMetric>;
export const CrashMetric = z.object({ kind: z.literal("crash"), metric: z.literal("keyboard_crash_free_sessions_rate"), candidate_digest: Digest, environment: ReleaseEnvironment, platform: z.enum(["ios", "android"]), crash_free_sessions_rate: z.number().finite().min(0).max(1), sessions: z.number().int().positive().max(10_000_000_000), crashes: z.number().int().nonnegative().max(10_000_000_000), recorded_at: z.string().datetime({ offset: true }), ...MetricAttestation }).strict().superRefine((value, context) => { if (value.crashes > value.sessions) context.addIssue({ code: z.ZodIssueCode.custom, message: "crashes cannot exceed sessions" }); const expected = (value.sessions - value.crashes) / value.sessions; if (Math.abs(value.crash_free_sessions_rate - expected) > 1e-9) context.addIssue({ code: z.ZodIssueCode.custom, message: "crash-free rate must match sessions and crashes" }); if (value.environment === "protected_production" && (value.verifier_kind !== "protected_runner" || value.verifier_id === undefined)) context.addIssue({ code: z.ZodIssueCode.custom, message: "production metric requires protected runner attestation" }); });
export type CrashMetric = z.infer<typeof CrashMetric>;
export const QualityMetric = z.union([PerformanceMetric, CrashMetric]);
export type QualityMetric = z.infer<typeof QualityMetric>;
export const QualityBudget = z.object({ keyboard_cold_start_p50_max_ms: z.number().finite().positive().max(60_000), keyboard_cold_start_p95_max_ms: z.number().finite().positive().max(60_000), keyboard_warm_open_p95_max_ms: z.number().finite().positive().max(60_000), keyboard_key_to_commit_p95_max_ms: z.number().finite().positive().max(60_000), keyboard_crash_free_sessions_min: z.number().finite().min(0).max(1) }).strict();
export type QualityBudget = z.infer<typeof QualityBudget>;
export const QualityDecision = z.object({ candidate_digest: Digest, environment: ReleaseEnvironment, status: z.enum(["passed", "failed", "not_proven"]), failed_metrics: z.array(z.string()).max(10), missing_metrics: z.array(z.string()).max(10), test_run_ids: z.array(TestRunId).max(100), evaluated_at: z.string().datetime({ offset: true }) }).strict();
export type QualityDecision = z.infer<typeof QualityDecision>;
export const ReleaseStage = z.enum(["beta", "broad"]);
export type ReleaseStage = z.infer<typeof ReleaseStage>;
export const ReleaseQualityDecision = QualityDecision.extend({ stage: ReleaseStage, budget_source: z.literal("fixed_release_policy") }).strict();
export type ReleaseQualityDecision = z.infer<typeof ReleaseQualityDecision>;

export function releaseCandidateDigest(candidate: Omit<ReleaseCandidate, "candidate_digest">): string { return `sha256:${createHash("sha256").update(canonicalJson(candidate), "utf8").digest("hex")}`; }
