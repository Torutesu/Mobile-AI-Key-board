import { createHash } from "node:crypto";
import { z } from "zod";
import { DeviceId, UserId } from "./w3.js";
import { canonicalJson } from "./index.js";

const Digest = z.string().regex(/^sha256:[a-f0-9]{64}$/);
const Opaque = (prefix: string) => z.string().regex(new RegExp(`^${prefix}_[A-Za-z0-9_-]{16,128}$`));
const NonBlank = (max: number) => z.string().max(max).refine((value) => value.trim().length > 0, { message: "value must not be blank" });
const SkillId = Opaque("skill");
const VersionId = Opaque("sv");
const PublisherId = Opaque("pub");
const PublisherKeyId = Opaque("pkey");
const PackageId = Opaque("spkg");
const PublisherEvidenceId = Opaque("pve");
const TeamId = Opaque("team");
const TeamPolicyId = Opaque("tpol");
const TeamInstallId = Opaque("tinst");
const TeamRevocationId = Opaque("trev");
const SuggestionId = Opaque("sugg");
const SuggestionEventId = Opaque("sevt");
const SafetyMetadataId = Opaque("smeta");
const ReportId = Opaque("srep");
const ModerationId = Opaque("mod");
const ControlId = Opaque("sctl");
const RollbackId = Opaque("srb");
const ToolOperation = z.string().regex(/^[a-z][a-z0-9_.-]{2,100}$/);
const Scope = z.string().regex(/^[a-z][a-z0-9_.-]{2,100}$/);

export const PublisherIdentity = z.object({ publisher_id: PublisherId, kind: z.enum(["individual", "team"]), owner_user_id: UserId, team_id: TeamId.optional(), display_name: NonBlank(120), signing_key_id: PublisherKeyId, public_key_digest: Digest, identity_digest: Digest }).strict().superRefine((value, context) => { if (value.kind === "team" && value.team_id === undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "team publisher requires team_id" }); if (value.kind === "individual" && value.team_id !== undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "individual publisher cannot carry team_id" }); });
export type PublisherIdentity = z.infer<typeof PublisherIdentity>;
export function publisherIdentityDigest(value: Omit<PublisherIdentity, "identity_digest">): string { return `sha256:${createHash("sha256").update(canonicalJson(value), "utf8").digest("hex")}`; }

export const SignedSkillPackage = z.object({ package_id: PackageId, skill_id: SkillId, version_id: VersionId, skill_version: z.number().int().positive(), publisher_id: PublisherId, definition_digest: Digest, package_schema_version: z.number().int().positive(), package_digest: Digest, signature: NonBlank(4_096), signing_key_id: PublisherKeyId, signed_at: z.string().datetime({ offset: true }) }).strict();
export type SignedSkillPackage = z.infer<typeof SignedSkillPackage>;
export function signedSkillPackageDigest(value: Omit<SignedSkillPackage, "package_digest" | "signature">): string { return `sha256:${createHash("sha256").update(canonicalJson(value), "utf8").digest("hex")}`; }

export const PublisherVerificationEvidence = z.object({ evidence_id: PublisherEvidenceId, publisher_id: PublisherId, package_id: PackageId, package_digest: Digest, identity_digest: Digest, signing_key_id: PublisherKeyId, verification_status: z.enum(["verified", "not_proven"]), verifier_kind: z.enum(["self_attested", "fixture", "protected_verifier"]), verifier_id: NonBlank(128).optional(), observed_at: z.string().datetime({ offset: true }) }).strict().superRefine((value, context) => { if (value.verification_status === "verified" && (value.verifier_kind !== "protected_verifier" || value.verifier_id === undefined)) context.addIssue({ code: z.ZodIssueCode.custom, message: "verified publisher evidence requires protected verifier" }); });
export type PublisherVerificationEvidence = z.infer<typeof PublisherVerificationEvidence>;
export const PublisherVerificationDecision = z.object({ publisher_id: PublisherId, package_id: PackageId, package_digest: Digest, status: z.enum(["verified", "not_proven"]), reason: z.enum(["trusted_protected_verifier", "self_attested", "fixture", "stale", "future", "binding_mismatch"]), evaluated_at: z.string().datetime({ offset: true }), valid_until: z.string().datetime({ offset: true }) }).strict();
export type PublisherVerificationDecision = z.infer<typeof PublisherVerificationDecision>;

export const TeamAllowedTool = z.object({ operation: ToolOperation, required_scopes: z.array(Scope).max(5) }).strict();
export type TeamAllowedTool = z.infer<typeof TeamAllowedTool>;
export const TeamPolicyPackage = z.object({ policy_id: TeamPolicyId, team_id: TeamId, owner_user_id: UserId, version: z.number().int().positive(), policy_epoch: z.number().int().positive(), allowed_tools: z.array(TeamAllowedTool).max(32), risk_ceiling: z.enum(["R0", "R1", "R2", "R3", "R4", "R5"]), confirmation: z.enum(["none", "policy_required"]), package_digest: Digest, created_at: z.string().datetime({ offset: true }) }).strict().superRefine((value, context) => { if (new Set(value.allowed_tools.map((tool) => tool.operation)).size !== value.allowed_tools.length) context.addIssue({ code: z.ZodIssueCode.custom, message: "team tools must be unique" }); });
export type TeamPolicyPackage = z.infer<typeof TeamPolicyPackage>;
export function teamPolicyPackageDigest(value: Omit<TeamPolicyPackage, "package_digest">): string { return `sha256:${createHash("sha256").update(canonicalJson(value), "utf8").digest("hex")}`; }
export const TeamPolicyInstall = z.object({ install_id: TeamInstallId, team_id: TeamId, owner_user_id: UserId, policy_id: TeamPolicyId, version: z.number().int().positive(), policy_epoch: z.number().int().positive(), package_digest: Digest, explicit_consent: z.literal(true), installed_at: z.string().datetime({ offset: true }) }).strict();
export type TeamPolicyInstall = z.infer<typeof TeamPolicyInstall>;
export const TeamPolicyUpgrade = z.object({ request_id: NonBlank(200), team_id: TeamId, owner_user_id: UserId, current_policy_id: TeamPolicyId, current_version: z.number().int().positive(), current_package_digest: Digest, next_policy_id: TeamPolicyId, next_version: z.number().int().positive(), next_package_digest: Digest, policy_epoch: z.number().int().positive(), explicit_consent: z.literal(true), requested_at: z.string().datetime({ offset: true }) }).strict();
export type TeamPolicyUpgrade = z.infer<typeof TeamPolicyUpgrade>;
export const TeamPolicyRevocation = z.object({ revocation_id: TeamRevocationId, team_id: TeamId, owner_user_id: UserId, policy_id: TeamPolicyId, version: z.number().int().positive(), policy_epoch: z.number().int().positive(), package_digest: Digest, revoked: z.literal(true), revision: z.number().int().positive(), occurred_at: z.string().datetime({ offset: true }) }).strict();
export type TeamPolicyRevocation = z.infer<typeof TeamPolicyRevocation>;

export const ContextualSuggestion = z.object({ suggestion_id: SuggestionId, owner_user_id: UserId, device_id: DeviceId, skill_id: SkillId, version_id: VersionId, package_digest: Digest, source_types: z.array(z.enum(["selection", "surrounding_text", "clipboard", "locale", "current_datetime"])).min(1).max(5), suggestion_kind: z.enum(["skill_hint", "setup_hint"]), local_only: z.literal(true), network_required: z.literal(false), auto_execute: z.literal(false), requires_user_action: z.literal(true), expires_at: z.string().datetime({ offset: true }), generated_at: z.string().datetime({ offset: true }), suggestion_digest: Digest }).strict().superRefine((value, context) => { if (Date.parse(value.expires_at) <= Date.parse(value.generated_at)) context.addIssue({ code: z.ZodIssueCode.custom, message: "suggestion expiry must be after generation" }); });
export type ContextualSuggestion = z.infer<typeof ContextualSuggestion>;
export function contextualSuggestionDigest(value: Omit<ContextualSuggestion, "suggestion_digest">): string { return `sha256:${createHash("sha256").update(canonicalJson(value), "utf8").digest("hex")}`; }
export const SuggestionTelemetryEvent = z.object({ event_id: SuggestionEventId, suggestion_id: SuggestionId, owner_user_id: UserId, device_id: DeviceId, event: z.enum(["shown", "accepted", "dismissed", "expired"]), occurred_at: z.string().datetime({ offset: true }) }).strict();
export type SuggestionTelemetryEvent = z.infer<typeof SuggestionTelemetryEvent>;

const IssueCount = z.number().int().nonnegative().max(1_000_000);
export const SafetyIssueCounts = z.object({ security: IssueCount, privacy: IssueCount, malware: IssueCount, quality: IssueCount, policy: IssueCount, resolved: IssueCount, critical: IssueCount }).strict().superRefine((value, context) => { const reported = value.security + value.privacy + value.malware + value.quality + value.policy; if (reported > 1_000_000) context.addIssue({ code: z.ZodIssueCode.custom, message: "issue category total exceeds bound" }); if (value.resolved > reported) context.addIssue({ code: z.ZodIssueCode.custom, message: "resolved issues cannot exceed derived reported total" }); if (value.critical > reported) context.addIssue({ code: z.ZodIssueCode.custom, message: "critical issues cannot exceed derived reported total" }); });
export type SafetyIssueCounts = z.infer<typeof SafetyIssueCounts>;
export function safetyIssueReportedTotal(value: SafetyIssueCounts): number { return value.security + value.privacy + value.malware + value.quality + value.policy; }
export const SkillSafetyMetadata = z.object({ metadata_id: SafetyMetadataId, skill_id: SkillId, version_id: VersionId, package_digest: Digest, publisher_id: PublisherId, publisher_name: NonBlank(120), publisher_verification: z.enum(["verified", "not_proven"]), requested_operations: z.array(ToolOperation).max(50), requested_scopes: z.array(Scope).max(50), input_types: z.array(z.enum(["text", "number", "boolean", "datetime", "json"])).min(1).max(16), risk_class: z.enum(["R0", "R1", "R2", "R3"]), version: z.number().int().positive(), last_reviewed_at: z.string().datetime({ offset: true }), installs: z.number().int().nonnegative().max(1_000_000_000), completion_numerator: z.number().int().nonnegative().max(1_000_000_000), completion_denominator: z.number().int().nonnegative().max(1_000_000_000), completion_rate: z.number().finite().min(0).max(1).optional(), confidence: z.enum(["low", "medium", "high"]), issue_counts: SafetyIssueCounts, provenance: z.enum(["fixture", "not_proven", "protected_verified"]), metadata_digest: Digest }).strict().superRefine((value, context) => { if (new Set(value.requested_operations).size !== value.requested_operations.length) context.addIssue({ code: z.ZodIssueCode.custom, message: "requested operations must be unique" }); if (new Set(value.requested_scopes).size !== value.requested_scopes.length) context.addIssue({ code: z.ZodIssueCode.custom, message: "requested scopes must be unique" }); if (new Set(value.input_types).size !== value.input_types.length) context.addIssue({ code: z.ZodIssueCode.custom, message: "input types must be unique" }); if (value.completion_numerator > value.completion_denominator) context.addIssue({ code: z.ZodIssueCode.custom, message: "completion numerator cannot exceed denominator" }); const expected = value.completion_denominator === 0 ? undefined : value.completion_numerator / value.completion_denominator; if (value.completion_denominator === 0 && value.completion_rate !== undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "completion rate must be absent when denominator is zero" }); if (expected !== undefined && (value.completion_rate === undefined || Math.abs(value.completion_rate - expected) > 1e-9)) context.addIssue({ code: z.ZodIssueCode.custom, message: "completion rate must be derived from numerator and denominator" }); });
export type SkillSafetyMetadata = z.infer<typeof SkillSafetyMetadata>;
export function safetyMetadataDigest(value: Omit<SkillSafetyMetadata, "metadata_digest">): string { return `sha256:${createHash("sha256").update(canonicalJson(value), "utf8").digest("hex")}`; }

export const SkillReport = z.object({ report_id: ReportId, skill_id: SkillId, version_id: VersionId, package_digest: Digest, reporter_user_id: UserId, category: z.enum(["security", "privacy", "malware", "quality", "policy"]), report_digest: Digest, created_at: z.string().datetime({ offset: true }) }).strict();
export type SkillReport = z.infer<typeof SkillReport>;
export function skillReportDigest(value: Omit<SkillReport, "report_digest">): string { return `sha256:${createHash("sha256").update(canonicalJson(value), "utf8").digest("hex")}`; }
export const ModerationDecision = z.object({ moderation_id: ModerationId, skill_id: SkillId, version_id: VersionId, package_digest: Digest, status: z.enum(["approved", "rejected", "needs_review"]), moderator_kind: z.enum(["self_attested", "protected_moderator"]), verifier_id: NonBlank(128).optional(), report_ids: z.array(ReportId).max(100), revision: z.number().int().positive(), decided_at: z.string().datetime({ offset: true }) }).strict().superRefine((value, context) => { if (value.status === "approved" && (value.moderator_kind !== "protected_moderator" || value.verifier_id === undefined)) context.addIssue({ code: z.ZodIssueCode.custom, message: "approval requires protected moderator" }); });
export type ModerationDecision = z.infer<typeof ModerationDecision>;
export const SkillControlAction = z.object({ control_id: ControlId, skill_id: SkillId, version_id: VersionId, package_digest: Digest, action: z.enum(["revoked", "reinstated", "disabled", "enabled"]), owner_user_id: UserId, policy_epoch: z.number().int().positive(), revision: z.number().int().positive(), reason_code: z.string().regex(/^[A-Z0-9_]{3,64}$/), occurred_at: z.string().datetime({ offset: true }) }).strict();
export type SkillControlAction = z.infer<typeof SkillControlAction>;
export const SkillRollbackRequest = z.object({ rollback_id: RollbackId, skill_id: SkillId, publisher_id: PublisherId, owner_user_id: UserId, policy_epoch: z.number().int().positive(), from_version: z.number().int().positive(), from_package_digest: Digest, target_version: z.number().int().positive(), target_package_digest: Digest, explicit_confirmation: z.literal(true), requested_at: z.string().datetime({ offset: true }) }).strict().superRefine((value, context) => { if (value.target_version >= value.from_version) context.addIssue({ code: z.ZodIssueCode.custom, message: "rollback target must be older" }); });
export type SkillRollbackRequest = z.infer<typeof SkillRollbackRequest>;
