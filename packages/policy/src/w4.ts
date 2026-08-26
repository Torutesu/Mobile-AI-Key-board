import { ConnectionGrant, ConnectorResult, ConnectorProvider, ReadOnlyAuthority, ReadOnlyOperation, ReadOnlyQuery } from "@mobile-ai-keyboard/contracts";
import type { ConnectionGrant as ConnectionGrantData, ReadOnlyOperation as ReadOnlyOperationData, ReadOnlyQuery as ReadOnlyQueryData, UserId } from "@mobile-ai-keyboard/contracts";
import { PolicyViolation } from "./index.js";

const authorities: Record<ReadOnlyOperationData, { provider: "google_calendar" | "notion" | "maps"; scope: ReadOnlyOperationData }> = {
  "calendar.availability.read": { provider: "google_calendar", scope: "calendar.availability.read" },
  "notion.pages.search": { provider: "notion", scope: "notion.pages.search" },
  "maps.places.search": { provider: "maps", scope: "maps.places.search" }
};
export function readOnlyAuthority(operation: ReadOnlyOperationData): ReadOnlyAuthority { const entry = authorities[operation]; return ReadOnlyAuthority.parse({ operation, provider: entry.provider, required_scopes: [entry.scope], risk_class: "R2", side_effect: "none", write_capability: false }); }
export function validateReadOnlyQuery(value: unknown): ReadOnlyQueryData { const parsed = ReadOnlyQuery.safeParse(value); if (!parsed.success) throw new PolicyViolation("Read-only query contract is invalid", { code: "INVALID_READ_ONLY_QUERY" }); return parsed.data; }
export function assertReadOnlyQuery(value: unknown, grant: ConnectionGrantData, expectedUserId?: UserId): ReadOnlyQueryData {
  const query = validateReadOnlyQuery(value); const authority = readOnlyAuthority(query.operation);
  if (query.grant_id !== grant.grant_id) throw new PolicyViolation("Query grant does not match supplied grant", { code: "GRANT_OWNER_MISMATCH" });
  if (grant.status !== "active") throw new PolicyViolation("Connection grant is not active", { code: "GRANT_NOT_ACTIVE" });
  if (expectedUserId !== undefined && grant.user_id !== expectedUserId) throw new PolicyViolation("Connection grant owner mismatch", { code: "GRANT_OWNER_MISMATCH" });
  const requiredScope = authority.required_scopes[0];
  if (requiredScope === undefined || grant.provider !== authority.provider || !grant.scopes.includes(requiredScope)) throw new PolicyViolation("Grant does not have the exact read-only authority", { code: "SCOPE_MISSING" });
  return query;
}
export function assertReadOnlyOperation(operation: string): ReadOnlyAuthority { if (!ReadOnlyOperation.safeParse(operation).success) throw new PolicyViolation("Operation is outside the read-only authority ceiling", { code: "WRITE_OPERATION_REJECTED", operation }); return readOnlyAuthority(operation as ReadOnlyOperationData); }
export function assertConnectorResult(value: unknown): ConnectorResult { const parsed = ConnectorResult.safeParse(value); if (!parsed.success) throw new PolicyViolation("Connector result is not source-bound", { code: "INVALID_PROVENANCE" }); assertProviderContentCannotAuthorize(parsed.data); return parsed.data; }
export function assertResultBoundToQuery(value: unknown, queryValue: unknown): ConnectorResult {
  const result = assertConnectorResult(value); const query = validateReadOnlyQuery(queryValue); const expectedProvider = readOnlyAuthority(query.operation).provider;
  const sources = result.kind === "calendar_availability" ? result.sources : result.kind === "notion_search" ? result.pages.flatMap((page) => [page.source, page.title.provenance]) : result.places.flatMap((place) => [place.source, place.name.provenance, ...(place.address ? [place.address.provenance] : [])]);
  if (sources.some((source) => source.provider !== expectedProvider || source.grant_id !== query.grant_id)) throw new PolicyViolation("Connector result provenance is not bound to the requested grant", { code: "PROVENANCE_GRANT_MISMATCH" });
  return result;
}

/** Provider text is data only. It cannot carry operations, scope, risk, or tool authority. */
export function assertProviderContentCannotAuthorize(value: unknown): void {
  const visit = (candidate: unknown): void => {
    if (!candidate || typeof candidate !== "object") return;
    if (Array.isArray(candidate)) { for (const item of candidate) visit(item); return; }
    const record = candidate as Record<string, unknown>;
    const provenance = record.provenance as Record<string, unknown> | undefined;
    if (provenance?.taint === "untrusted_provider_content" && ["operation", "tools", "scopes", "risk_class", "write_capability", "authorization"].some((key) => key in record)) throw new PolicyViolation("Untrusted provider content cannot authorize tools or plans", { code: "PROVIDER_TAINT_ESCALATION" });
    for (const child of Object.values(record)) visit(child);
  };
  visit(value);
}
