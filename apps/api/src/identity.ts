import type { DeviceChallenge, DeviceRecord, DeviceRegistrationRequest, PlanVersionBinding, ReceiptEvent, SessionTokenResponse, UserId } from "@mobile-ai-keyboard/contracts";
import { AccountDeletionStateMachine, AppendOnlyAuditStore, AppendOnlyReceiptStore, DeviceRegistry, PlanBindingStore, RetentionStore, SessionManager, W3Error, type Clock, type DeviceProofVerifier } from "@mobile-ai-keyboard/skill-runtime";

/**
 * Provider-neutral W3 identity boundary. It deliberately accepts an injected
 * proof verifier and in-memory stores; no IdP, durable DB, KMS, or production
 * token verification is implied by this class.
 */
export class IdentityService {
  readonly devices: DeviceRegistry;
  readonly sessions: SessionManager;
  readonly bindings = new PlanBindingStore();
  readonly receipts = new AppendOnlyReceiptStore();
  readonly audits = new AppendOnlyAuditStore();
  readonly retention: RetentionStore;
  private readonly deletions = new Map<UserId, AccountDeletionStateMachine>();
  constructor(verifyProof: DeviceProofVerifier = () => false, private readonly clock?: Clock) {
    this.devices = new DeviceRegistry(clock, verifyProof); this.sessions = new SessionManager(this.devices, clock); this.retention = new RetentionStore(clock);
  }
  issueDeviceChallenge(userId: UserId): DeviceChallenge { return this.devices.issueChallenge(userId); }
  registerDevice(userId: UserId, request: DeviceRegistrationRequest): DeviceRecord { return this.devices.register(request, userId); }
  issueSession(userId: UserId, deviceId: string): SessionTokenResponse { return this.sessions.issue(userId, deviceId); }
  rotateSession(familyId: string, accessToken: string, userId: UserId): SessionTokenResponse { return this.sessions.rotate(familyId, accessToken, userId); }
  authenticate(accessToken: string, userId?: UserId) { return this.sessions.authenticate(accessToken, userId); }
  revokeDevice(userId: UserId, deviceId: string): void { this.sessions.revokeDevice(deviceId, userId); this.devices.revoke(deviceId, userId); }
  requestDeletion(userId: UserId) { const machine = this.deletion(userId); const record = machine.transition("requested"); this.sessions.revokeUser(userId); this.devices.revokeAll(userId); return record; }
  bindPlan(binding: PlanVersionBinding): PlanVersionBinding { return this.bindings.bind(binding); }
  assertRunOwner(runId: string, userId: UserId, deviceId: string): PlanVersionBinding { return this.bindings.get(runId, userId, deviceId); }
  appendReceipt(event: ReceiptEvent): ReceiptEvent {
    const binding = this.bindings.get(event.run_id, event.user_id, event.device_id);
    if (binding.plan_digest !== event.plan_digest) throw new W3Error("BINDING_CONFLICT", "Receipt plan digest does not match immutable run binding");
    return this.receipts.append(event);
  }
  deletion(userId: UserId): AccountDeletionStateMachine { const existing = this.deletions.get(userId); if (existing) return existing; const machine = new AccountDeletionStateMachine(userId, this.clock); this.deletions.set(userId, machine); return machine; }
}
