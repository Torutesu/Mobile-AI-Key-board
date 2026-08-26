import { z } from "zod";

const opaque = (prefix: string) => z.string().regex(new RegExp(`^${prefix}_[A-Za-z0-9_-]{16,128}$`));
export const UserId = opaque("usr");
export type UserId = z.infer<typeof UserId>;
export const DeviceId = opaque("dev");
export type DeviceId = z.infer<typeof DeviceId>;
export const DeviceChallengeId = opaque("dch");
export type DeviceChallengeId = z.infer<typeof DeviceChallengeId>;
export const SessionFamilyId = opaque("sf");
export type SessionFamilyId = z.infer<typeof SessionFamilyId>;
export const SessionId = opaque("ses");
export type SessionId = z.infer<typeof SessionId>;
export const ReceiptId = opaque("rcpt");
export type ReceiptId = z.infer<typeof ReceiptId>;
export const AuditEventId = opaque("aud");
export type AuditEventId = z.infer<typeof AuditEventId>;

export const Base64Url = z.string().regex(/^[A-Za-z0-9_-]+$/).min(16).max(2_048);
export const Ed25519PublicKey = z.string().regex(/^[A-Za-z0-9_-]{43}$/);
export const Ed25519Signature = z.string().regex(/^[A-Za-z0-9_-]{86}$/);
export const KeyAlgorithm = z.literal("ed25519");
export const DevicePlatform = z.enum(["ios", "android"]);
export const DeviceStatus = z.enum(["active", "revoked"]);
const ReceiptStatus = z.enum(["pending", "executing", "succeeded", "partial", "failed", "unknown", "undo_pending", "undone", "undo_failed"]);

export const DeviceChallenge = z.object({
  challenge_id: DeviceChallengeId,
  nonce: Base64Url,
  user_id: UserId,
  expires_at: z.string().datetime({ offset: true })
}).strict();
export type DeviceChallenge = z.infer<typeof DeviceChallenge>;

export const DeviceRegistrationRequest = z.object({
  device_id: DeviceId,
  platform: DevicePlatform,
  public_key_algorithm: KeyAlgorithm,
  public_key: Ed25519PublicKey,
  challenge_id: DeviceChallengeId,
  challenge_nonce: Base64Url,
  proof_signature: Ed25519Signature,
  app_version: z.string().min(1).max(64)
}).strict();
export type DeviceRegistrationRequest = z.infer<typeof DeviceRegistrationRequest>;

export const DeviceRecord = z.object({
  device_id: DeviceId,
  user_id: UserId,
  platform: DevicePlatform,
  public_key_algorithm: KeyAlgorithm,
  public_key: Ed25519PublicKey,
  status: DeviceStatus,
  created_at: z.string().datetime({ offset: true }),
  revoked_at: z.string().datetime({ offset: true }).optional(),
  last_seen_at: z.string().datetime({ offset: true }).optional()
}).strict().superRefine((value, context) => {
  if (value.status === "active" && value.revoked_at !== undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "active device cannot have revoked_at" });
  if (value.status === "revoked" && value.revoked_at === undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "revoked device requires revoked_at" });
});
export type DeviceRecord = z.infer<typeof DeviceRecord>;

export const SessionStatus = z.enum(["active", "rotated", "revoked", "expired"]);
export type SessionStatus = z.infer<typeof SessionStatus>;
export const SessionIssueRequest = z.object({ device_id: DeviceId, challenge_id: DeviceChallengeId, challenge_nonce: Base64Url, proof_signature: Ed25519Signature }).strict();
export type SessionIssueRequest = z.infer<typeof SessionIssueRequest>;
export const SessionRecord = z.object({
  session_id: SessionId,
  family_id: SessionFamilyId,
  user_id: UserId,
  device_id: DeviceId,
  generation: z.number().int().positive(),
  token_hash: z.string().regex(/^[a-f0-9]{64}$/),
  status: SessionStatus,
  issued_at: z.string().datetime({ offset: true }),
  expires_at: z.string().datetime({ offset: true }),
  rotated_at: z.string().datetime({ offset: true }).optional(),
  revoked_at: z.string().datetime({ offset: true }).optional()
}).strict().superRefine((value, context) => {
  if (value.status === "active" && (value.rotated_at !== undefined || value.revoked_at !== undefined)) context.addIssue({ code: z.ZodIssueCode.custom, message: "active session cannot carry terminal timestamps" });
  if (value.status === "rotated" && value.rotated_at === undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "rotated session requires rotated_at" });
  if (value.status === "revoked" && value.revoked_at === undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "revoked session requires revoked_at" });
});
export type SessionRecord = z.infer<typeof SessionRecord>;
export const SessionTokenResponse = z.object({ session_id: SessionId, family_id: SessionFamilyId, access_token: z.string().min(32).max(4_096), expires_at: z.string().datetime({ offset: true }) }).strict();
export type SessionTokenResponse = z.infer<typeof SessionTokenResponse>;
export const SessionRevokeRequest = z.object({ family_id: SessionFamilyId, reason: z.enum(["user_request", "device_revoked", "security_event", "account_deletion"]) }).strict();

export const PlanVersionBinding = z.object({
  binding_id: opaque("bind"), run_id: z.string().min(1), user_id: UserId, device_id: DeviceId,
  plan_id: z.string().min(1), plan_version: z.number().int().positive(), plan_digest: z.string().regex(/^sha256:[a-f0-9]{64}$/),
  policy_epoch: z.string().min(1).max(128), bound_at: z.string().datetime({ offset: true })
}).strict();
export type PlanVersionBinding = z.infer<typeof PlanVersionBinding>;

export const AuthenticatedRunOwner = z.object({ user_id: UserId, device_id: DeviceId, session_id: SessionId, session_family_id: SessionFamilyId }).strict();
export type AuthenticatedRunOwner = z.infer<typeof AuthenticatedRunOwner>;

export const ReceiptStepMetadata = z.object({ step_id: z.string().min(1).max(80), operation: z.string().regex(/^[a-z][a-z0-9_.-]{2,100}$/), status: z.enum(["pending", "executing", "succeeded", "failed", "not_started", "unknown"]), provider: z.string().min(1).max(80).optional(), provider_resource_ref: z.string().min(1).max(512).optional(), completed_at: z.string().datetime({ offset: true }).optional() }).strict();
export type ReceiptStepMetadata = z.infer<typeof ReceiptStepMetadata>;
export const ReceiptEvent = z.object({
  event_id: AuditEventId, receipt_id: ReceiptId, run_id: z.string().min(1), user_id: UserId, device_id: DeviceId,
  sequence: z.number().int().positive(), status: ReceiptStatus, step_metadata: z.array(ReceiptStepMetadata).max(50),
  plan_digest: z.string().regex(/^sha256:[a-f0-9]{64}$/), request_id: z.string().min(1).max(128), occurred_at: z.string().datetime({ offset: true })
}).strict();
export type ReceiptEvent = z.infer<typeof ReceiptEvent>;
export const AuditEvent = z.object({
  event_id: AuditEventId, actor_user_id: UserId, actor_device_id: DeviceId, actor_session_id: SessionId,
  action: z.enum(["device_registered", "device_revoked", "session_issued", "session_rotated", "session_revoked", "plan_bound", "run_created", "receipt_appended", "retention_applied", "deletion_requested", "deletion_completed"]),
  object_type: z.enum(["device", "session_family", "run", "plan", "receipt", "account"]), object_id: z.string().min(1).max(256),
  outcome: z.enum(["accepted", "rejected", "succeeded", "failed"]), request_id: z.string().min(1).max(128), occurred_at: z.string().datetime({ offset: true }),
  plan_digest: z.string().regex(/^sha256:[a-f0-9]{64}$/).optional()
}).strict();
export type AuditEvent = z.infer<typeof AuditEvent>;

export const RetentionClass = z.enum(["none", "transient_content", "receipt_metadata", "audit_metadata", "account_record"]);
export type RetentionClass = z.infer<typeof RetentionClass>;
export const RetentionRule = z.object({ record_type: z.enum(["content", "capture", "receipt", "audit", "account"]), retention_class: RetentionClass, max_age_seconds: z.number().int().nonnegative(), purge_strategy: z.enum(["immediate", "scheduled", "legal_hold"]) }).strict();
export type RetentionRule = z.infer<typeof RetentionRule>;
export const DeletionStatus = z.enum(["active", "requested", "grace_period", "deleting", "deleted", "failed"]);
export type DeletionStatus = z.infer<typeof DeletionStatus>;
export const AccountDeletionRecord = z.object({ user_id: UserId, status: DeletionStatus, requested_at: z.string().datetime({ offset: true }).optional(), grace_expires_at: z.string().datetime({ offset: true }).optional(), completed_at: z.string().datetime({ offset: true }).optional(), failure_code: z.string().min(1).max(80).optional() }).strict().superRefine((value, context) => {
  if (["requested", "grace_period", "deleting", "deleted", "failed"].includes(value.status) && value.requested_at === undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "deletion lifecycle requires requested_at" });
  if (value.status === "grace_period" && value.grace_expires_at === undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "grace period requires grace_expires_at" });
  if (value.status === "deleted" && value.completed_at === undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "deleted account requires completed_at" });
  if (value.status === "failed" && value.failure_code === undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "failed deletion requires failure_code" });
});
export type AccountDeletionRecord = z.infer<typeof AccountDeletionRecord>;
