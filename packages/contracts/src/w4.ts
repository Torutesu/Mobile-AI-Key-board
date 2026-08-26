import { z } from "zod";
import { DeviceId, SessionId, UserId } from "./w3.js";
import { GrantId } from "./w4_ids.js";

export const ConnectorProvider = z.enum(["google_calendar", "notion", "maps"]);
export type ConnectorProvider = z.infer<typeof ConnectorProvider>;
export const ReadOnlyOperation = z.enum(["calendar.availability.read", "notion.pages.search", "maps.places.search"]);
export type ReadOnlyOperation = z.infer<typeof ReadOnlyOperation>;
export const OAuthProvider = ConnectorProvider;
export const OAuthCodeChallengeMethod = z.literal("S256");
export const Scope = z.enum(["calendar.availability.read", "notion.pages.search", "maps.places.search"]);
export type Scope = z.infer<typeof Scope>;
export const OAuthState = z.object({
  state: z.string().regex(/^oauth_[A-Za-z0-9_-]{32,128}$/), nonce: z.string().regex(/^[A-Za-z0-9_-]{32,128}$/),
  provider: OAuthProvider, user_id: UserId, device_id: DeviceId, session_id: SessionId,
  code_challenge: z.string().regex(/^[A-Za-z0-9_-]{43}$/), code_challenge_method: OAuthCodeChallengeMethod,
  requested_scopes: z.array(Scope).min(1).max(3), redirect_uri: z.string().url().max(2_048), expires_at: z.string().datetime({ offset: true })
}).strict();
export type OAuthState = z.infer<typeof OAuthState>;
export const OAuthStartRequest = z.object({ provider: OAuthProvider, requested_scopes: z.array(Scope).min(1).max(3), redirect_uri: z.string().url().max(2_048), code_challenge: z.string().regex(/^[A-Za-z0-9_-]{43}$/), code_challenge_method: OAuthCodeChallengeMethod }).strict();
export type OAuthStartRequest = z.infer<typeof OAuthStartRequest>;
export const OAuthCallbackRequest = z.object({ state: z.string().regex(/^oauth_[A-Za-z0-9_-]{32,128}$/), nonce: z.string().regex(/^[A-Za-z0-9_-]{32,128}$/), code: z.string().min(8).max(4_096), code_verifier: z.string().min(43).max(128) }).strict();
export type OAuthCallbackRequest = z.infer<typeof OAuthCallbackRequest>;
export const GrantStatus = z.enum(["active", "reconnect_required", "disconnected", "revoked"]);
export type GrantStatus = z.infer<typeof GrantStatus>;
export const CredentialRef = z.string().regex(/^cred_[A-Za-z0-9_-]{16,128}$/);
export type CredentialRef = z.infer<typeof CredentialRef>;
export const ConnectionGrant = z.object({
  grant_id: GrantId, user_id: UserId, device_id: DeviceId, provider: ConnectorProvider,
  scopes: z.array(Scope).min(1).max(3), status: GrantStatus, credential_ref: CredentialRef,
  created_at: z.string().datetime({ offset: true }), updated_at: z.string().datetime({ offset: true }),
  revoked_at: z.string().datetime({ offset: true }).optional()
}).strict().superRefine((value, context) => {
  if (value.status === "revoked" && value.revoked_at === undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "revoked grant requires revoked_at" });
  if (value.status !== "revoked" && value.revoked_at !== undefined) context.addIssue({ code: z.ZodIssueCode.custom, message: "non-revoked grant cannot carry revoked_at" });
});
export type ConnectionGrant = z.infer<typeof ConnectionGrant>;
export const GrantConsentRequest = z.object({ provider: ConnectorProvider, requested_scopes: z.array(Scope).min(1).max(3), explicit_incremental_consent: z.boolean() }).strict();
export type GrantConsentRequest = z.infer<typeof GrantConsentRequest>;
export const GrantRebindRequest = z.object({ grant_id: GrantId, new_device_id: DeviceId }).strict();
export const GrantLifecycleRequest = z.object({ grant_id: GrantId, reason: z.enum(["user_disconnect", "security_event", "provider_revoke"]) }).strict();

export const ReadOnlyAuthority = z.object({ operation: ReadOnlyOperation, provider: ConnectorProvider, required_scopes: z.array(Scope).min(1).max(1), risk_class: z.literal("R2"), side_effect: z.literal("none"), write_capability: z.literal(false) }).strict();
export type ReadOnlyAuthority = z.infer<typeof ReadOnlyAuthority>;
export const CalendarAvailabilityQuery = z.object({ provider: z.literal("google_calendar"), operation: z.literal("calendar.availability.read"), grant_id: GrantId, start: z.string().datetime({ offset: true }), end: z.string().datetime({ offset: true }), timezone: z.string().min(1).max(64), page_size: z.number().int().positive().max(20).default(20), page_token: z.string().max(512).optional() }).strict();
export const NotionSearchQuery = z.object({ provider: z.literal("notion"), operation: z.literal("notion.pages.search"), grant_id: GrantId, query: z.string().min(1).max(200), page_size: z.number().int().positive().max(20).default(20), page_token: z.string().max(512).optional() }).strict();
export const MapsSearchQuery = z.object({ provider: z.literal("maps"), operation: z.literal("maps.places.search"), grant_id: GrantId, query: z.string().min(1).max(200), near: z.object({ latitude: z.number().min(-90).max(90), longitude: z.number().min(-180).max(180) }).strict().optional(), page_size: z.number().int().positive().max(20).default(10), page_token: z.string().max(512).optional() }).strict();
export const ReadOnlyQuery = z.discriminatedUnion("operation", [CalendarAvailabilityQuery, NotionSearchQuery, MapsSearchQuery]).superRefine((value, context) => {
  if (value.operation === "calendar.availability.read" && Date.parse(value.end) <= Date.parse(value.start)) context.addIssue({ code: z.ZodIssueCode.custom, message: "calendar availability end must be after start" });
});
export type ReadOnlyQuery = z.infer<typeof ReadOnlyQuery>;

export const SourceProvenance = z.object({ provider: ConnectorProvider, grant_id: GrantId, source_ref: z.string().min(1).max(512), fetched_at: z.string().datetime({ offset: true }), freshness_expires_at: z.string().datetime({ offset: true }), taint: z.literal("untrusted_provider_content") }).strict().superRefine((value, context) => {
  if (Date.parse(value.freshness_expires_at) < Date.parse(value.fetched_at)) context.addIssue({ code: z.ZodIssueCode.custom, message: "freshness expiry cannot precede fetch time" });
});
export type SourceProvenance = z.infer<typeof SourceProvenance>;
export const ProviderText = z.object({ text: z.string().max(10_000), provenance: SourceProvenance }).strict();
export const CalendarAvailabilityResult = z.object({ kind: z.literal("calendar_availability"), slots: z.array(z.object({ start: z.string().datetime({ offset: true }), end: z.string().datetime({ offset: true }), available: z.boolean() }).strict()).max(50), next_page_token: z.string().max(512).optional(), sources: z.array(SourceProvenance).max(50) }).strict();
export const NotionSearchResult = z.object({ kind: z.literal("notion_search"), pages: z.array(z.object({ title: ProviderText, url: z.string().url().max(2_048), source: SourceProvenance }).strict()).max(50), next_page_token: z.string().max(512).optional() }).strict();
export const MapsSearchResult = z.object({ kind: z.literal("maps_search"), places: z.array(z.object({ name: ProviderText, address: ProviderText.optional(), map_url: z.string().url().max(2_048), source: SourceProvenance }).strict()).max(20), next_page_token: z.string().max(512).optional() }).strict();
export const ConnectorResult = z.discriminatedUnion("kind", [CalendarAvailabilityResult, NotionSearchResult, MapsSearchResult]);
export type ConnectorResult = z.infer<typeof ConnectorResult>;

export const ConnectorFailure = z.object({ provider: ConnectorProvider, operation: ReadOnlyOperation, kind: z.enum(["auth_required", "scope_missing", "rate_limited", "invalid_request", "timeout", "provider_error", "unknown"]), retryable: z.boolean(), safe_code: z.string().regex(/^[A-Z0-9_]{3,64}$/), content_taint: z.literal("untrusted_provider_content").optional() }).strict();
export type ConnectorFailure = z.infer<typeof ConnectorFailure>;
export const ConnectorOutcome = z.discriminatedUnion("status", [z.object({ status: z.literal("succeeded"), result: ConnectorResult, receipt_status: z.literal("succeeded") }).strict(), z.object({ status: z.literal("partial"), result: ConnectorResult, failure: ConnectorFailure, receipt_status: z.literal("partial") }).strict(), z.object({ status: z.literal("failed"), failure: ConnectorFailure, receipt_status: z.literal("failed") }).strict(), z.object({ status: z.literal("unknown"), failure: ConnectorFailure, receipt_status: z.literal("unknown") }).strict()]);
export type ConnectorOutcome = z.infer<typeof ConnectorOutcome>;

export const EncryptedCredentialEnvelope = z.object({ credential_ref: CredentialRef, ciphertext: z.string().min(16).max(16_384), key_version: z.string().min(1).max(128), algorithm: z.enum(["AES-256-GCM", "provider-kms-envelope"]), expires_at: z.string().datetime({ offset: true }).optional() }).strict();
export type EncryptedCredentialEnvelope = z.infer<typeof EncryptedCredentialEnvelope>;
