import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { createHash, randomUUID } from "node:crypto";
import { canonicalJson, CreateRunRequest, type CreateRunRequest as CreateRunRequestData, type Disclosure } from "@mobile-ai-keyboard/contracts";
import { createDisclosure, newId, RunStateMachine } from "@mobile-ai-keyboard/skill-runtime";

export class ApiError extends Error { constructor(readonly statusCode: number, readonly code: string, message: string) { super(message); this.name = "ApiError"; } }
type Run = { id: string; owner: string; state: RunStateMachine; disclosure: Disclosure; expiresAt: string };
export class RunStore {
  private readonly runs = new Map<string, Run>();
  private readonly idempotency = new Map<string, { fingerprint: string; run: Run }>();
  create(owner: string, idempotencyKey: string, payload: CreateRunRequestData): Run {
    const fingerprint = createHash("sha256").update(canonicalJson(payload), "utf8").digest("hex");
    const idempotencyScope = `${owner}:${idempotencyKey}`;
    const previous = this.idempotency.get(idempotencyScope);
    if (previous) {
      if (previous.fingerprint !== fingerprint) throw new ApiError(409, "IDEMPOTENCY_CONFLICT", "Idempotency-Key was already used with a different payload");
      return previous.run;
    }
    const run: Run = { id: newId("run"), owner, state: new RunStateMachine(), disclosure: createDisclosure(payload.available_input_sources, [payload.skill.id]), expiresAt: new Date(Date.now() + 10 * 60_000).toISOString() };
    this.runs.set(run.id, run); this.idempotency.set(idempotencyScope, { fingerprint, run }); return run;
  }
  get(id: string, owner: string): Run { const run = this.runs.get(id); if (!run || run.owner !== owner) throw new ApiError(404, "RUN_NOT_FOUND", "Run was not found"); return run; }
}

async function body(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = []; let totalBytes = 0;
  for await (const chunk of request) {
    const bytes = Buffer.from(chunk); totalBytes += bytes.byteLength;
    if (totalBytes > 100_000) throw new ApiError(413, "PAYLOAD_TOO_LARGE", "Request body is too large");
    chunks.push(bytes);
  }
  if (chunks.length === 0) return undefined;
  try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch { throw new ApiError(400, "INVALID_JSON", "Request body is not valid JSON"); }
}
function json(response: ServerResponse, status: number, value: unknown, requestId: string): void { response.writeHead(status, { "content-type": "application/json", "x-request-id": requestId, "cache-control": "no-store" }); response.end(JSON.stringify({ request_id: requestId, ...value as object })); }
function auth(request: IncomingMessage): string {
  const header = request.headers.authorization;
  if (!header?.startsWith("Bearer ") || header.length < 10) {
    throw new ApiError(401, "UNAUTHENTICATED", "A valid access token is required");
  }

  // W0 uses an opaque, non-reversible principal so raw bearer credentials never
  // enter stores or logs. Production must replace this with signature, issuer,
  // audience, expiry, and revocation verification by the selected identity layer.
  return `unverified_token_sha256:${createHash("sha256").update(header.slice(7)).digest("hex")}`;
}

export function createApiHandler(store = new RunStore()) {
  return async (request: IncomingMessage, response: ServerResponse): Promise<void> => {
    const requestId = `req_${randomUUID()}`;
    try {
      const method = request.method ?? "GET"; const path = new URL(request.url ?? "/", "http://localhost").pathname;
      if (method === "GET" && path === "/healthz") return json(response, 200, { status: "ok" }, requestId);
      const owner = auth(request);
      if (method === "POST" && path === "/v1/runs") {
        const idempotencyHeader = request.headers["idempotency-key"];
        if (typeof idempotencyHeader !== "string" || idempotencyHeader.trim().length === 0 || idempotencyHeader.length > 200) throw new ApiError(400, "IDEMPOTENCY_KEY_REQUIRED", "Mutating requests require Idempotency-Key");
        const parsed = CreateRunRequest.safeParse(await body(request)); if (!parsed.success) throw new ApiError(400, "INVALID_REQUEST", "Request does not match the run contract");
        const run = store.create(owner, idempotencyHeader, parsed.data);
        return json(response, 201, { run_id: run.id, status: run.state.status, disclosure: run.disclosure, expires_at: run.expiresAt }, requestId);
      }
      const match = path.match(/^\/v1\/runs\/([^/]+)$/);
      if (method === "GET" && match?.[1]) { const run = store.get(match[1], owner); return json(response, 200, { run_id: run.id, status: run.state.status, expires_at: run.expiresAt }, requestId); }
      throw new ApiError(404, "NOT_FOUND", "Route was not found");
    } catch (error) {
      const e = error instanceof ApiError ? error : new ApiError(500, "INTERNAL_ERROR", "Internal server error");
      if (e.statusCode >= 500) console.error(JSON.stringify({ request_id: requestId, code: e.code }));
      json(response, e.statusCode, { status: "error", error: { code: e.code, message: e.message } }, requestId);
    }
  };
}

export function startServer(port = Number(process.env.PORT ?? 8787)) { const server = createServer(createApiHandler()); return server.listen(port, "127.0.0.1", () => console.log(`API listening on 127.0.0.1:${port}`)); }
if (import.meta.url === `file://${process.argv[1]}`) startServer();
