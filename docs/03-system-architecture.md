# System Architecture

## 1. Architecture goals

- Normal typing has no backend dependency.
- Keyboard extensions contain no provider secrets or durable OAuth credentials.
- Plans are untrusted until validated by deterministic policy.
- Confirmed actions are bound to an immutable plan digest.
- Mobile, backend, and tests share versioned schemas.
- Providers can be replaced without changing the Skill contract.

## 2. Repository layout

```text
apps/
  ios/                    Swift app + keyboard extension
  android/                Kotlin app + IME service
  api/                    authenticated control and execution API
  worker/                 queued tool execution and reconciliation
packages/
  contracts/              JSON Schema/OpenAPI and generated clients
  skill-runtime/          Skill validation and deterministic planning
  policy/                 risk classification and confirmation rules
  tool-adapters/          provider-neutral tool interfaces
  test-vectors/           shared fixtures and adversarial cases
docs/
infra/
```

Native apps are intentional. A cross-platform UI layer MAY be used in non-keyboard companion screens later, but keyboard/IME code remains native because lifecycle, latency, accessibility, and OS APIs are product-critical.

## 3. Mobile components

### iOS

- `HostApp`: onboarding, auth, settings, Skills, OAuth, receipts.
- `KeyboardExtension`: local typing, invocation UI, bounded context capture, preview/apply.
- `SharedCore`: Codable contracts, crypto helpers, redaction, local settings.
- `App Group`: encrypted or data-protected shared settings, session handle, Skill manifests, pending receipts. Never raw OAuth tokens.
- `Keychain`: host-app credentials and device keys with the narrowest access group.

The keyboard extension uses `UITextDocumentProxy` and treats all context as optional and staleable. It cannot assume access to the entire field, selection, app identity, clipboard, microphone, or network.

### Android

- `MainActivity`: onboarding, auth, connections, Skills, receipts.
- `KeyboardImeService`: local typing and action UI.
- `InputConnectionAdapter`: bounded read, selection, composing text, and safe commit/replace.
- `EncryptedDataStore/Keystore`: settings and device credentials.
- `WorkManager`: receipt reconciliation and noninteractive sync, never autonomous user actions.

Sensitive input variations disable context reads and network actions before UI rendering.

## 4. Backend services

### API gateway

- Verifies access token, device/session status, request schema, replay protection, and rate limit.
- Assigns request ID and structured audit metadata.
- Rejects arbitrary model/tool payloads from clients.

### Planning service

- Resolves Skill version.
- Normalizes locale/timezone and declared input sources.
- Uses deterministic parsers first.
- Calls an LLM only for approved planning or generation tasks.
- Emits a typed `ActionPlan`, never executable provider credentials.

### Policy engine

- Recomputes risk class server-side.
- Compares requested tools to Skill allowlist and user-granted connections.
- Redacts or blocks prohibited data.
- Decides confirmation type and expiry.
- Produces a canonical plan digest.

### Execution worker

- Accepts only a confirmed, unexpired plan digest.
- Retrieves connection tokens from the credential broker.
- Executes typed tool adapters with idempotency keys.
- Writes per-step receipts and reconciles uncertain provider outcomes.

### Credential broker

- Stores encrypted OAuth refresh/access material separately from application content.
- Enforces tenant, user, provider, connection, scope, and tool-operation binding.
- Supports disconnect, revoke, rotation, and breach response.

### Receipt service

- Records intent-independent metadata: action type, target provider, result identifiers, timestamps, status, reversibility, and safe display summary.
- Stores sensitive provider output only when required and under a shorter retention class.

## 5. Execution sequence

1. Client creates a run with Skill version and declared input-source metadata.
2. Server returns a disclosure manifest.
3. Client displays exact data locally and confirms transmission.
4. Client submits bounded inputs.
5. Planner produces a typed plan.
6. Policy engine validates and signs the canonical plan digest.
7. Client displays plan and required confirmation.
8. Client confirms the exact digest.
9. Worker executes with idempotency key.
10. Receipt settles as succeeded, partial, failed, or unknown.
11. Client applies generated text only if the target field snapshot remains compatible.

The API MUST reject confirmation of a plan that differs by one byte after canonicalization.

## 6. Tool adapter contract

Each adapter declares:

- operation identifier and semantic version;
- JSON input/output schema;
- required OAuth scopes;
- risk class and reversibility;
- idempotency support;
- dry-run capability;
- timeout and retry policy;
- provider error mapping;
- receipt projection and sensitive fields;
- reconciliation method for unknown outcomes.

Initial operations:

- `calendar.availability.read`
- `calendar.event.create_private`
- `calendar.event.delete_own` only as an explicit undo endpoint, not a general Skill tool
- `notion.pages.search`
- `maps.places.search`
- `maps.link.build`

## 7. Model boundary

The model may:

- classify a permitted user intent;
- fill typed draft fields;
- generate or transform text;
- rank already retrieved results;
- ask for missing information.

The model may not:

- choose OAuth scopes;
- access credentials;
- invent tool names or arguments outside schema;
- lower risk class or confirmation requirements;
- declare an action successful;
- authorize retries;
- decide retention;
- treat retrieved text as system instructions.

## 8. Offline and degraded modes

- Ordinary typing and local snippets remain available.
- Network-bound controls show offline state before capture.
- Draft commands MAY be retained locally with explicit user choice, encrypted, and auto-expire after 24 hours.
- No external write is queued for later silent execution.
- If execution outcome is unknown, retry is blocked until provider reconciliation completes or the user chooses a clearly described manual resolution.

## 9. Observability

Three separate streams:

- Product analytics: allowlisted, content-free events.
- Operational telemetry: latency, error class, provider, version, region, request ID.
- Security audit: auth, connection, plan digest, confirmation, tool operation, receipt status.

Logging helpers reject fields marked `content`, `secret`, `credential`, `token`, `selection`, `clipboard`, `prompt`, `output`, or provider payload. Production debug logging is off by default.
