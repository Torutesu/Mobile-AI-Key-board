import { createHash, randomBytes, randomUUID } from "node:crypto";
import { AccountDeletionRecord, type AccountDeletionRecord as AccountDeletionRecordData, AuditEvent, type AuditEvent as AuditEventData, DeviceChallenge, type DeviceChallenge as DeviceChallengeData, DeviceRecord, type DeviceRecord as DeviceRecordData, DeviceRegistrationRequest, type DeviceRegistrationRequest as DeviceRegistrationRequestData, DeviceId, type PlanVersionBinding, PlanVersionBinding as PlanVersionBindingSchema, ReceiptEvent, type ReceiptEvent as ReceiptEventData, RetentionRule, type RetentionRule as RetentionRuleData, SessionRecord, type SessionRecord as SessionRecordData, SessionTokenResponse, type SessionTokenResponse as SessionTokenResponseData, UserId, type UserId as UserIdData } from "@mobile-ai-keyboard/contracts";
import { canonicalJson } from "@mobile-ai-keyboard/contracts";

export type W3ErrorCode = "INVALID_CONTRACT" | "CHALLENGE_NOT_FOUND" | "CHALLENGE_EXPIRED" | "PROOF_REJECTED" | "DEVICE_EXISTS" | "DEVICE_NOT_FOUND" | "DEVICE_REVOKED" | "SESSION_NOT_FOUND" | "SESSION_REVOKED" | "SESSION_EXPIRED" | "SESSION_REPLAY" | "SESSION_OWNER_MISMATCH" | "BINDING_CONFLICT" | "RUN_NOT_FOUND" | "RECEIPT_APPEND_CONFLICT" | "AUDIT_APPEND_CONFLICT" | "INVALID_DELETION_TRANSITION" | "RETENTION_NOT_FOUND" | "RETENTION_CONFLICT";
export class W3Error extends Error { constructor(readonly code: W3ErrorCode, message: string) { super(message); this.name = "W3Error"; } }
export type Clock = () => Date;
const utcNow: Clock = () => new Date();
const opaqueId = (prefix: string): string => `${prefix}_${randomUUID().replaceAll("-", "")}`;
const tokenHash = (token: string): string => createHash("sha256").update(token, "utf8").digest("hex");
const secureToken = (): string => randomBytes(32).toString("base64url");
const asIso = (date: Date): string => date.toISOString();
const clone = <T>(value: T): T => structuredClone(value);

export function deviceProofPayload(request: DeviceRegistrationRequestData, challenge: DeviceChallengeData): string {
  return canonicalJson({ challenge_id: challenge.challenge_id, challenge_nonce: challenge.nonce, user_id: challenge.user_id, device_id: request.device_id, platform: request.platform, public_key_algorithm: request.public_key_algorithm, public_key: request.public_key, app_version: request.app_version });
}
export type DeviceProofVerifier = (canonicalPayload: string, proofSignature: string, publicKey: string) => boolean;
export class DeviceRegistry {
  private readonly challenges = new Map<string, DeviceChallengeData>();
  private readonly devices = new Map<string, DeviceRecordData>();
  constructor(private readonly clock: Clock = utcNow, private readonly verifyProof: DeviceProofVerifier = () => false) {}
  issueChallenge(userId: UserIdData, ttlMs = 5 * 60_000): DeviceChallengeData {
    const now = this.clock(); const challenge = DeviceChallenge.parse({ challenge_id: opaqueId("dch"), nonce: randomBytes(32).toString("base64url"), user_id: userId, expires_at: asIso(new Date(now.getTime() + ttlMs)) });
    this.challenges.set(challenge.challenge_id, challenge); return challenge;
  }
  register(request: unknown, expectedUserId: UserIdData): DeviceRecordData {
    const parsed = DeviceRegistrationRequest.safeParse(request); if (!parsed.success) throw new W3Error("INVALID_CONTRACT", "Device registration contract is invalid");
    const challenge = this.challenges.get(parsed.data.challenge_id); if (!challenge) throw new W3Error("CHALLENGE_NOT_FOUND", "Device challenge was not found");
    if (challenge.user_id !== expectedUserId || challenge.nonce !== parsed.data.challenge_nonce) throw new W3Error("PROOF_REJECTED", "Device challenge does not belong to this user");
    if (Date.parse(challenge.expires_at) <= this.clock().getTime()) throw new W3Error("CHALLENGE_EXPIRED", "Device challenge has expired");
    if (!this.verifyProof(deviceProofPayload(parsed.data, challenge), parsed.data.proof_signature, parsed.data.public_key)) throw new W3Error("PROOF_REJECTED", "Device proof signature was rejected");
    if (this.devices.has(parsed.data.device_id)) throw new W3Error("DEVICE_EXISTS", "Device ID is already registered");
    const now = asIso(this.clock()); const record = DeviceRecord.parse({ device_id: parsed.data.device_id, user_id: expectedUserId, platform: parsed.data.platform, public_key_algorithm: parsed.data.public_key_algorithm, public_key: parsed.data.public_key, status: "active", created_at: now });
    this.devices.set(record.device_id, clone(record)); this.challenges.delete(challenge.challenge_id); return clone(record);
  }
  get(deviceId: string): DeviceRecordData { const record = this.devices.get(deviceId); if (!record) throw new W3Error("DEVICE_NOT_FOUND", "Device was not found"); return clone(record); }
  assertActive(deviceId: string, userId: UserIdData): DeviceRecordData { const record = this.get(deviceId); if (record.user_id !== userId) throw new W3Error("DEVICE_NOT_FOUND", "Device was not found"); if (record.status !== "active") throw new W3Error("DEVICE_REVOKED", "Device is revoked"); return record; }
  revoke(deviceId: string, userId: UserIdData): DeviceRecordData { const record = this.assertActive(deviceId, userId); const revoked = DeviceRecord.parse({ ...record, status: "revoked", revoked_at: asIso(this.clock()) }); this.devices.set(deviceId, clone(revoked)); return clone(revoked); }
  revokeAll(userId: UserIdData): void { for (const record of this.devices.values()) if (record.user_id === userId && record.status === "active") this.revoke(record.device_id, userId); }
}

export class SessionManager {
  private readonly sessions = new Map<string, SessionRecordData>();
  private readonly currentByFamily = new Map<string, string>();
  constructor(private readonly devices: DeviceRegistry, private readonly clock: Clock = utcNow, private readonly ttlMs = 30 * 60_000) {}
  issue(userId: UserIdData, deviceId: string): SessionTokenResponseData {
    this.devices.assertActive(deviceId, userId); const now = this.clock(); const raw = secureToken(); const familyId = opaqueId("sf"); const sessionId = opaqueId("ses");
    const record = SessionRecord.parse({ session_id: sessionId, family_id: familyId, user_id: userId, device_id: deviceId, generation: 1, token_hash: tokenHash(raw), status: "active", issued_at: asIso(now), expires_at: asIso(new Date(now.getTime() + this.ttlMs)) });
    this.sessions.set(sessionId, clone(record)); this.currentByFamily.set(familyId, sessionId); return SessionTokenResponse.parse({ session_id: sessionId, family_id: familyId, access_token: raw, expires_at: record.expires_at });
  }
  authenticate(rawToken: string, expectedUserId?: UserIdData): SessionRecordData {
    const hash = tokenHash(rawToken); const record = [...this.sessions.values()].find((candidate) => candidate.token_hash === hash);
    if (!record) throw new W3Error("SESSION_NOT_FOUND", "Session was not found");
    if (expectedUserId !== undefined && record.user_id !== expectedUserId) throw new W3Error("SESSION_OWNER_MISMATCH", "Session does not belong to this user");
    if (Date.parse(record.expires_at) <= this.clock().getTime()) { this.sessions.set(record.session_id, SessionRecord.parse({ ...record, status: "expired" })); throw new W3Error("SESSION_EXPIRED", "Session has expired"); }
    if (record.status !== "active" || this.currentByFamily.get(record.family_id) !== record.session_id) throw new W3Error(record.status === "revoked" ? "SESSION_REVOKED" : "SESSION_REPLAY", "Session is no longer current");
    return clone(record);
  }
  rotate(familyId: string, rawToken: string, expectedUserId?: UserIdData): SessionTokenResponseData {
    const currentId = this.currentByFamily.get(familyId); if (!currentId) throw new W3Error("SESSION_NOT_FOUND", "Session family was not found");
    const current = this.sessions.get(currentId); if (!current) throw new W3Error("SESSION_NOT_FOUND", "Session was not found");
    if (expectedUserId !== undefined && current.user_id !== expectedUserId) throw new W3Error("SESSION_OWNER_MISMATCH", "Session family does not belong to this user");
    if (current.token_hash !== tokenHash(rawToken) || current.status !== "active") { this.revokeFamilyInternal(familyId); throw new W3Error("SESSION_REPLAY", "A stale session token was replayed"); }
    if (Date.parse(current.expires_at) <= this.clock().getTime()) { this.revokeFamilyInternal(familyId); throw new W3Error("SESSION_EXPIRED", "Session has expired"); }
    const now = this.clock(); const raw = secureToken(); const next = SessionRecord.parse({ ...current, session_id: opaqueId("ses"), generation: current.generation + 1, token_hash: tokenHash(raw), status: "active", issued_at: asIso(now), expires_at: asIso(new Date(now.getTime() + this.ttlMs)), rotated_at: undefined, revoked_at: undefined });
    this.sessions.set(current.session_id, clone(SessionRecord.parse({ ...current, status: "rotated", rotated_at: asIso(now) }))); this.sessions.set(next.session_id, clone(next)); this.currentByFamily.set(familyId, next.session_id); return SessionTokenResponse.parse({ session_id: next.session_id, family_id: familyId, access_token: raw, expires_at: next.expires_at });
  }
  revokeFamily(familyId: string, expectedUserId?: UserIdData): void { const currentId = this.currentByFamily.get(familyId); if (!currentId) throw new W3Error("SESSION_NOT_FOUND", "Session family was not found"); const current = this.sessions.get(currentId); if (expectedUserId !== undefined && current?.user_id !== expectedUserId) throw new W3Error("SESSION_OWNER_MISMATCH", "Session family does not belong to this user"); this.revokeFamilyInternal(familyId); }
  revokeUser(userId: UserIdData): void { for (const record of this.sessions.values()) if (record.user_id === userId && record.status === "active") this.revokeFamilyInternal(record.family_id); }
  revokeDevice(deviceId: string, userId: UserIdData): void { const device = this.devices.get(deviceId); if (device.user_id !== userId) throw new W3Error("DEVICE_NOT_FOUND", "Device was not found"); for (const record of this.sessions.values()) if (record.device_id === deviceId && record.user_id === userId && record.status === "active") this.revokeFamilyInternal(record.family_id); }
  private revokeFamilyInternal(familyId: string): void { const currentId = this.currentByFamily.get(familyId); if (!currentId) return; const current = this.sessions.get(currentId); if (current) this.sessions.set(currentId, SessionRecord.parse({ ...current, status: "revoked", revoked_at: asIso(this.clock()) })); this.currentByFamily.delete(familyId); }
}

export class PlanBindingStore {
  private readonly bindings = new Map<string, PlanVersionBinding>();
  bind(binding: unknown): PlanVersionBinding {
    const parsed = PlanVersionBindingSchema.safeParse(binding); if (!parsed.success) throw new W3Error("INVALID_CONTRACT", "Plan binding contract is invalid");
    const existing = this.bindings.get(parsed.data.run_id); if (existing) { if (canonicalJson(existing) !== canonicalJson(parsed.data)) throw new W3Error("BINDING_CONFLICT", "Run is already bound to a different immutable plan or owner"); return clone(existing); }
    this.bindings.set(parsed.data.run_id, clone(parsed.data)); return clone(parsed.data);
  }
  get(runId: string, userId: UserIdData, deviceId: string): PlanVersionBinding { const binding = this.bindings.get(runId); if (!binding) throw new W3Error("RUN_NOT_FOUND", "Run binding was not found"); if (binding.user_id !== userId || binding.device_id !== deviceId) throw new W3Error("SESSION_OWNER_MISMATCH", "Run does not belong to authenticated owner"); return clone(binding); }
}

export class AppendOnlyReceiptStore {
  private readonly events = new Map<string, ReceiptEventData[]>();
  private readonly eventIds = new Set<string>();
  append(event: unknown): ReceiptEventData {
    const parsed = ReceiptEvent.safeParse(event); if (!parsed.success) throw new W3Error("INVALID_CONTRACT", "Receipt event contract is invalid"); const history = this.events.get(parsed.data.receipt_id) ?? []; const last = history.at(-1);
    if (this.eventIds.has(parsed.data.event_id)) throw new W3Error("RECEIPT_APPEND_CONFLICT", "Receipt event was replayed");
    if (last && (last.run_id !== parsed.data.run_id || last.user_id !== parsed.data.user_id || last.device_id !== parsed.data.device_id || last.plan_digest !== parsed.data.plan_digest || last.request_id !== parsed.data.request_id)) throw new W3Error("RECEIPT_APPEND_CONFLICT", "Receipt identity or immutable plan binding changed");
    if (last && parsed.data.sequence !== last.sequence + 1) throw new W3Error("RECEIPT_APPEND_CONFLICT", "Receipt sequence is not append-only");
    if (!last && parsed.data.sequence !== 1) throw new W3Error("RECEIPT_APPEND_CONFLICT", "Receipt must start at sequence 1");
    this.events.set(parsed.data.receipt_id, [...history, clone(parsed.data)]); this.eventIds.add(parsed.data.event_id); return clone(parsed.data);
  }
  list(receiptId: string): readonly ReceiptEventData[] { return clone(this.events.get(receiptId) ?? []); }
}

export class AppendOnlyAuditStore {
  private readonly events: AuditEventData[] = [];
  append(event: unknown): AuditEventData { const parsed = AuditEvent.safeParse(event); if (!parsed.success) throw new W3Error("INVALID_CONTRACT", "Audit event contract is invalid"); if (this.events.some((entry) => entry.event_id === parsed.data.event_id)) throw new W3Error("AUDIT_APPEND_CONFLICT", "Audit event was replayed"); this.events.push(clone(parsed.data)); return clone(parsed.data); }
  list(): readonly AuditEventData[] { return clone(this.events); }
}

const deletionTransitions: Record<AccountDeletionRecordData["status"], readonly AccountDeletionRecordData["status"][]> = { active: ["requested"], requested: ["grace_period", "deleting"], grace_period: ["deleting"], deleting: ["deleted", "failed"], deleted: [], failed: ["deleting"] };
export class AccountDeletionStateMachine {
  private record: AccountDeletionRecordData;
  constructor(userId: UserIdData, private readonly clock: Clock = utcNow) { this.record = AccountDeletionRecord.parse({ user_id: userId, status: "active" }); }
  get current(): AccountDeletionRecordData { return clone(this.record); }
  transition(next: AccountDeletionRecordData["status"], graceMs = 7 * 24 * 60 * 60_000, failureCode?: string): AccountDeletionRecordData {
    if (!deletionTransitions[this.record.status].includes(next)) throw new W3Error("INVALID_DELETION_TRANSITION", `Cannot transition deletion from ${this.record.status} to ${next}`);
    const now = asIso(this.clock()); const values: AccountDeletionRecordData = { user_id: this.record.user_id, status: next, requested_at: this.record.requested_at, grace_expires_at: this.record.grace_expires_at, completed_at: next === "deleted" ? now : this.record.completed_at, failure_code: next === "failed" ? failureCode ?? "unknown" : undefined };
    if (next === "requested") values.requested_at = now;
    if (next === "grace_period") values.grace_expires_at = asIso(new Date(this.clock().getTime() + graceMs));
    this.record = AccountDeletionRecord.parse(values); return clone(this.record);
  }
}

export type RetentionEntry = { id: string; rule: RetentionRuleData; expiresAt: number };
export class RetentionStore {
  private readonly entries = new Map<string, RetentionEntry>();
  constructor(private readonly clock: Clock = utcNow) {}
  schedule(id: string, rule: unknown): RetentionEntry { const parsed = RetentionRule.safeParse(rule); if (!parsed.success) throw new W3Error("INVALID_CONTRACT", "Retention rule contract is invalid"); if (this.entries.has(id)) throw new W3Error("RETENTION_CONFLICT", "Retention entry is already scheduled"); const entry = { id, rule: clone(parsed.data), expiresAt: this.clock().getTime() + parsed.data.max_age_seconds * 1_000 }; this.entries.set(id, clone(entry)); return clone(entry); }
  due(): readonly RetentionEntry[] { const now = this.clock().getTime(); return clone([...this.entries.values()].filter((entry) => entry.expiresAt <= now && entry.rule.purge_strategy !== "legal_hold")); }
  apply(id: string): void { if (!this.entries.has(id)) throw new W3Error("RETENTION_NOT_FOUND", "Retention entry was not found"); this.entries.delete(id); }
}
