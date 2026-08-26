import { createHash, randomBytes, randomUUID } from "node:crypto";
import { ConnectionGrant, type ConnectionGrant as ConnectionGrantData, ConnectorOutcome, type ConnectorOutcome as ConnectorOutcomeData, CredentialRef, EncryptedCredentialEnvelope, GrantConsentRequest, OAuthCallbackRequest, OAuthStartRequest, OAuthState, type OAuthState as OAuthStateData, ReadOnlyQuery, type ReadOnlyQuery as ReadOnlyQueryData, Scope, type UserId, type DeviceId, type SessionId } from "@mobile-ai-keyboard/contracts";
import type { ConnectorFailure } from "@mobile-ai-keyboard/contracts";
import { assertConnectorResult, assertReadOnlyQuery, PolicyViolation } from "@mobile-ai-keyboard/policy";
import { type Clock } from "./w3.js";

export type W4ErrorCode = "INVALID_CONTRACT" | "OAUTH_STATE_NOT_FOUND" | "OAUTH_STATE_REPLAY" | "OAUTH_STATE_EXPIRED" | "PKCE_MISMATCH" | "SCOPE_WIDENING" | "GRANT_NOT_FOUND" | "GRANT_OWNER_MISMATCH" | "GRANT_NOT_ACTIVE" | "GRANT_REVOKED" | "REBIND_OWNER_MISMATCH" | "CREDENTIAL_STORE_UNAVAILABLE" | "PAGINATION_LIMIT" | "CONNECTOR_FAILURE" | "CONNECTOR_UNKNOWN";
export class W4Error extends Error { constructor(readonly code: W4ErrorCode, message: string) { super(message); this.name = "W4Error"; } }
const nowDefault: Clock = () => new Date();
const opaque = (prefix: string): string => `${prefix}_${randomUUID().replaceAll("-", "")}`;
const base64url = (bytes: Buffer): string => bytes.toString("base64url");
const sha256url = (value: string): string => base64url(createHash("sha256").update(value, "utf8").digest());

export type OAuthCompleted = OAuthStateData & { authorization_code: string };
export class OAuthStateManager {
  private readonly states = new Map<string, OAuthStateData>();
  constructor(private readonly clock: Clock = nowDefault, private readonly ttlMs = 10 * 60_000) {}
  start(userId: UserId, deviceId: DeviceId, sessionId: SessionId, request: unknown): OAuthStateData {
    const parsed = OAuthStartRequest.safeParse(request); if (!parsed.success) throw new W4Error("INVALID_CONTRACT", "OAuth start contract is invalid");
    const now = this.clock(); const state = OAuthState.parse({ state: opaque("oauth"), nonce: base64url(randomBytes(32)), provider: parsed.data.provider, user_id: userId, device_id: deviceId, session_id: sessionId, code_challenge: parsed.data.code_challenge, code_challenge_method: parsed.data.code_challenge_method, requested_scopes: parsed.data.requested_scopes, redirect_uri: parsed.data.redirect_uri, expires_at: new Date(now.getTime() + this.ttlMs).toISOString() });
    this.states.set(state.state, structuredClone(state)); return structuredClone(state);
  }
  complete(callback: unknown): OAuthCompleted {
    const parsed = OAuthCallbackRequest.safeParse(callback); if (!parsed.success) throw new W4Error("INVALID_CONTRACT", "OAuth callback contract is invalid");
    const state = this.states.get(parsed.data.state); if (!state) throw new W4Error("OAUTH_STATE_NOT_FOUND", "OAuth state was not found");
    this.states.delete(state.state);
    if (Date.parse(state.expires_at) <= this.clock().getTime()) throw new W4Error("OAUTH_STATE_EXPIRED", "OAuth state has expired");
    if (parsed.data.nonce !== state.nonce) throw new W4Error("OAUTH_STATE_REPLAY", "OAuth nonce does not match state");
    if (sha256url(parsed.data.code_verifier) !== state.code_challenge) throw new W4Error("PKCE_MISMATCH", "OAuth PKCE verifier does not match state");
    return { ...state, authorization_code: parsed.data.code };
  }
}

const providerScopes: Record<ConnectionGrantData["provider"], readonly Scope[]> = { google_calendar: ["calendar.availability.read"], notion: ["notion.pages.search"], maps: ["maps.places.search"] };
export class GrantLifecycleManager {
  private readonly grants = new Map<string, ConnectionGrantData>();
  constructor(private readonly clock: Clock = nowDefault) {}
  connect(owner: { user_id: UserId; device_id: DeviceId }, request: unknown, credentialRef: string): ConnectionGrantData {
    const parsed = GrantConsentRequest.safeParse(request); if (!parsed.success) throw new W4Error("INVALID_CONTRACT", "Grant consent contract is invalid");
    const allowed = providerScopes[parsed.data.provider]; if (parsed.data.requested_scopes.some((scope) => !allowed.includes(scope))) throw new W4Error("SCOPE_WIDENING", "Requested scope is outside provider read-only ceiling");
    CredentialRef.parse(credentialRef);
    const existing = [...this.grants.values()].find((grant) => grant.user_id === owner.user_id && grant.provider === parsed.data.provider);
    const now = new Date(this.clock()).toISOString();
    if (existing) {
      if (existing.device_id !== owner.device_id) throw new W4Error("REBIND_OWNER_MISMATCH", "Existing grant requires explicit device rebind");
      if (existing.status === "active" && parsed.data.requested_scopes.some((scope) => !existing.scopes.includes(scope)) && !parsed.data.explicit_incremental_consent) throw new W4Error("SCOPE_WIDENING", "Incremental scope requires explicit consent");
      if (existing.user_id !== owner.user_id) throw new W4Error("GRANT_OWNER_MISMATCH", "Grant belongs to another user");
      const scopes = [...new Set([...existing.scopes, ...parsed.data.requested_scopes])]; const updated = ConnectionGrant.parse({ ...existing, device_id: owner.device_id, scopes, status: "active", credential_ref: credentialRef, updated_at: now, revoked_at: undefined }); this.grants.set(updated.grant_id, updated); return structuredClone(updated);
    }
    const grant = ConnectionGrant.parse({ grant_id: opaque("grant"), user_id: owner.user_id, device_id: owner.device_id, provider: parsed.data.provider, scopes: parsed.data.requested_scopes, status: "active", credential_ref: credentialRef, created_at: now, updated_at: now }); this.grants.set(grant.grant_id, grant); return structuredClone(grant);
  }
  get(grantId: string, owner: { user_id: UserId; device_id?: DeviceId }): ConnectionGrantData { const grant = this.grants.get(grantId); if (!grant) throw new W4Error("GRANT_NOT_FOUND", "Connection grant was not found"); if (grant.user_id !== owner.user_id || (owner.device_id !== undefined && grant.device_id !== owner.device_id)) throw new W4Error("GRANT_OWNER_MISMATCH", "Connection grant belongs to another owner"); return structuredClone(grant); }
  disconnect(grantId: string, owner: { user_id: UserId; device_id?: DeviceId }): ConnectionGrantData { const grant = this.get(grantId, owner); const updated = ConnectionGrant.parse({ ...grant, status: "disconnected", updated_at: new Date(this.clock()).toISOString() }); this.grants.set(grantId, updated); return structuredClone(updated); }
  revoke(grantId: string, owner: { user_id: UserId; device_id?: DeviceId }): ConnectionGrantData { const grant = this.get(grantId, owner); const updated = ConnectionGrant.parse({ ...grant, status: "revoked", revoked_at: new Date(this.clock()).toISOString(), updated_at: new Date(this.clock()).toISOString() }); this.grants.set(grantId, updated); return structuredClone(updated); }
  rebind(grantId: string, owner: { user_id: UserId; device_id: DeviceId }, newDeviceId: DeviceId): ConnectionGrantData { const grant = this.get(grantId, owner); if (grant.user_id !== owner.user_id) throw new W4Error("REBIND_OWNER_MISMATCH", "Grant cannot be rebound across users"); const updated = ConnectionGrant.parse({ ...grant, device_id: newDeviceId, updated_at: new Date(this.clock()).toISOString() }); this.grants.set(grantId, updated); return structuredClone(updated); }
}

export interface EncryptedCredentialStore { put(envelope: EncryptedCredentialEnvelope): Promise<void>; get(credentialRef: string): Promise<EncryptedCredentialEnvelope | undefined>; revoke(credentialRef: string): Promise<void>; }
export class NoopEncryptedCredentialStore implements EncryptedCredentialStore {
  async put(_envelope: EncryptedCredentialEnvelope): Promise<void> { throw new W4Error("CREDENTIAL_STORE_UNAVAILABLE", "No encrypted credential store is configured"); }
  async get(_credentialRef: string): Promise<EncryptedCredentialEnvelope | undefined> { throw new W4Error("CREDENTIAL_STORE_UNAVAILABLE", "No encrypted credential store is configured"); }
  async revoke(_credentialRef: string): Promise<void> { throw new W4Error("CREDENTIAL_STORE_UNAVAILABLE", "No encrypted credential store is configured"); }
}

export class PaginationGuard {
  private pages = 0; private items = 0;
  constructor(private readonly maxPages = 5, private readonly maxItems = 100) {}
  accept(pageItemCount: number, nextPageToken?: string): void { if (!Number.isInteger(pageItemCount) || pageItemCount < 0 || pageItemCount > 50) throw new W4Error("PAGINATION_LIMIT", "Connector page size is outside the hard bound"); this.pages += 1; this.items += pageItemCount; if (this.pages > this.maxPages || this.items > this.maxItems) throw new W4Error("PAGINATION_LIMIT", "Connector pagination budget was exceeded"); if (nextPageToken !== undefined && this.pages === this.maxPages) throw new W4Error("PAGINATION_LIMIT", "Connector returned more pages than allowed"); }
}

export function validateReadOnlyOutcome(value: unknown): ConnectorOutcomeData { const parsed = ConnectorOutcome.safeParse(value); if (!parsed.success) throw new W4Error("INVALID_CONTRACT", "Connector outcome is invalid"); if (parsed.data.status === "succeeded" || parsed.data.status === "partial") assertConnectorResult(parsed.data.result); return parsed.data; }
export function assertQueryForGrant(query: unknown, grant: ConnectionGrantData, userId: UserId): ReadOnlyQueryData { try { return assertReadOnlyQuery(query, grant, userId); } catch (error) { if (error instanceof PolicyViolation) throw new W4Error("CONNECTOR_FAILURE", error.message); throw error; } }
export function classifyConnectorError(error: unknown, provider: ConnectionGrantData["provider"], operation: ReadOnlyQueryData["operation"]): ConnectorOutcomeData { const unknown = error instanceof W4Error && error.code === "CONNECTOR_UNKNOWN"; const kind: ConnectorFailure["kind"] = unknown ? "unknown" : error instanceof W4Error && error.code === "PAGINATION_LIMIT" ? "invalid_request" : "provider_error"; const failure: ConnectorFailure = { provider, operation, kind, retryable: kind === "provider_error" || kind === "unknown", safe_code: kind === "unknown" ? "PROVIDER_OUTCOME_UNKNOWN" : "PROVIDER_ERROR", content_taint: "untrusted_provider_content" }; return unknown ? { status: "unknown", failure, receipt_status: "unknown" } : { status: "failed", failure, receipt_status: "failed" }; }
