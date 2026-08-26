# Quality, Acceptance, and Release Plan

## 1. Definition of done

A feature is done only when:

- the user-visible happy path and named failure paths work;
- accessibility semantics are present;
- privacy disclosure and risk policy are correct;
- shared contracts and migrations are versioned;
- unit, integration, UI, and adversarial tests cover the change;
- telemetry is content-free and useful;
- physical-device behavior is verified where OS integration matters;
- documentation and support recovery steps are updated.

## 2. Quality budgets

### Keyboard

- Cold start p50 <= 250 ms, p95 <= 400 ms on supported baseline devices.
- Warm open p95 <= 150 ms.
- Local key-to-commit p95 <= 50 ms.
- No network call during normal typing.
- Crash-free keyboard sessions >= 99.8% in beta and >= 99.95% before broad release.
- Memory remains within extension/IME limits with graceful degradation.

### AI and tools

- Disclosure response p95 <= 500 ms.
- First visible planning progress p95 <= 1.5 s.
- Text-only result p95 <= 5 s.
- Read-only connector completion p95 <= 4 s excluding provider incidents.
- Confirmed write settlement p95 <= 6 s, otherwise show typed pending/unknown state.
- Deterministic supported action completion >= 95% excluding revoked connections and provider outages.

### Product quality

- Protected-entity preservation >= 98% on launch corpus.
- Japanese relative-date resolution >= 99% for supported patterns, with absolute-date preview always shown.
- No invitee or recipient inferred into a write in MVP.
- 100% external writes have valid confirmation and receipt.

## 3. Test pyramid

### Unit

- keyboard layout and state reducers;
- Japanese date/time parsing;
- disclosure construction and local redaction;
- canonical JSON and digest generation;
- risk classification and confirmation rules;
- tool schema validation and error mapping;
- entity locking and rewrite diffs.

### Contract

- generated Swift/Kotlin/TypeScript clients match JSON Schema/OpenAPI;
- old mobile client against new backend compatibility;
- unknown fields and enum drift fail closed where security relevant;
- Skill version and tool adapter compatibility.

### Integration

- auth/session/device revocation;
- OAuth connect, expire, rebind, disconnect;
- planning -> confirmation -> execution -> receipt;
- retries, duplicate idempotency keys, partial failure, unknown outcome;
- deletion and retention jobs.

### Mobile UI

- onboarding from clean install;
- keyboard enable and Full Access states;
- typing in supported layouts and orientations;
- selection lost, field changed, offline, quota, auth expiry;
- VoiceOver/TalkBack navigation;
- dynamic type, reduced motion, high contrast, large targets.

### Adversarial

- prompt injection in selected text, Notion title/body, map result, and provider errors;
- secret patterns in input and output;
- cross-user/tenant IDs;
- plan mutation after review;
- stale confirmation after connection rebind;
- tool output attempting to invoke another tool;
- malicious community Skill version.

## 4. Physical device matrix

The executable matrix is maintained in [`docs/release-e2e-matrix.json`](release-e2e-matrix.json). Its checked-in baseline is intentionally `not_proven`; every `passed` row must be bound to a protected runner, real device, real app, candidate source, and artifact digest. The performance record and metric contract are in [`docs/release-performance-evidence.json`](release-performance-evidence.json) and [`docs/schemas/release-performance-evidence.schema.json`](schemas/release-performance-evidence.schema.json). Local fixture, simulator, JVM, and self-attested runs cannot satisfy either record.

Minimum beta matrix:

- iPhone baseline device on iOS 17.
- Current iPhone on current iOS.
- Small-screen iPhone.
- iPad portrait and landscape, even if public support is deferred.
- Android 11 baseline phone.
- Current Pixel.
- Current Samsung Galaxy.
- One low-memory Android device.

Apps/fields:

- Messages/LINE-like chat, Gmail/Mail, Slack, Notes, Safari/Chrome, Notion.
- Secure password and one-time-code fields.
- Phone number field.
- App that rejects iOS custom keyboards.
- WebView and custom editor with incomplete context support.

## 5. Acceptance scenarios

### A1: Ordinary typing isolation

Given no Skill is invoked, type a telemetry canary across supported apps. Network capture, backend logs, analytics, and crash reports contain none of it. Keyboard remains usable offline.

### A2: Explicit text transformation

Given selected Japanese text with names, date, number, and URL, invoke polite rewrite. Disclosure lists selection and model destination. Preview preserves locked entities. Apply replaces only the unchanged selection and supports undo.

### A3: Calendar confirmation binding

Given a relative-date proposal, plan resolves and displays absolute date/time/timezone. Mutating title, time, or attendees invalidates the old digest. Only the newly confirmed digest executes.

### A4: Duplicate prevention

After provider success but before client response, retry the same idempotency key. Exactly one event exists and the same receipt is returned.

### A5: Unknown outcome

Simulate provider timeout after accepting a create request. UI reports unknown, blocks blind retry, reconciles by provider lookup, and resolves to succeeded or safe manual action.

### A6: Prompt injection

Selected content asks the agent to ignore rules and email private documents. A read/transform Skill does not gain a mail tool, scope, recipient, or write step.

### A7: Revocation

Disconnect Calendar after plan review and before confirmation. Confirmation fails closed because the connection epoch changed; no action occurs.

### A8: Secure field

Focus password and OTP fields. AI controls and capture are disabled; no content is retained, suggested, logged, or transmitted.

## 6. Release stages

### Stage 0: Internal feasibility

- Native keyboard/IME lifecycle.
- Local typing and state machine.
- No production OAuth or writes.
- Physical-device evidence for platform constraints.

### Stage 1: Private text beta

- Rewrite, translate, summarize, snippets.
- Command, disclosure, preview, apply.
- No connected tools.
- Invite-only with telemetry canaries.

### Stage 2: Read-only connected beta

- Calendar availability, Notion search, Maps search.
- OAuth broker and receipt infrastructure.
- Connector reliability and prompt-injection audit.

### Stage 3: Confirmed-write beta

- Private calendar event creation.
- Exact digest confirmation, idempotency, reconciliation, undo.
- External security review.

### Stage 4: Parity release

- Skill Builder, bindings, private sharing, quota controls.
- Japanese/English workflows and customization.
- Store review readiness and support operations.

### Stage 5: Beyond parity

- Trust Preview refinements, team policies, verified Skill catalog.
- Risk-class R4 communication actions only after separate approval and evidence.

## 7. Promotion gates

The deterministic source/evidence gate is `pnpm release:readiness`. CI invokes `pnpm release:readiness -- --static-only --report <path>` to validate source declarations, privacy/entitlement consistency, fixture disclosure markers, required commands, and evidence schemas while preserving `not_proven` for missing protected runs. A release invocation without `--static-only` fails closed until the real-device matrix and protected performance evidence are complete. The required command/artifact contract is [`docs/release-evidence-manifest.json`](release-evidence-manifest.json).

`pnpm benchmark:performance` runs the content-free deterministic diagnostic in [`scripts/performance-benchmark.mjs`](../scripts/performance-benchmark.mjs). It checks key-to-commit p50/p95 (35/50 ms), cold/warm keyboard open p95 (400/150 ms), long-press false activation (0.1%), and ordinary tap drop (0.1%) for both platforms. It is intended to catch contract regressions locally; its fixture result is never a physical-device or production performance proof, and the readiness gate keeps that evidence `not_proven`.

The TypeScript-authoritative shortcut snapshot/binding vectors are in [`fixtures/shortcut-golden-vectors.json`](../fixtures/shortcut-golden-vectors.json). `pnpm shortcuts:vectors:check` regenerates the vectors in memory and byte-compares them, then validates schema version, QWERTY key normalization, canonical snapshot digest, duplicate physical-key conflict, and local-route authority. `pnpm shortcuts:vectors:native-check` is a separate fail-closed source gate: both Swift and Kotlin unit suites must directly load this fixture and assert a valid vector, a physical-key conflict, the digest field, and the rejection fields. The fixture status is `not_proven` until that wiring is present, then becomes `native_unit_consumers`; the latter proves only native unit-consumer coverage, never cross-process runtime interoperability, physical-device behavior, or a release qualification.

Each candidate must bind:

- source commit and clean tree;
- generated mobile/backend artifacts and digests;
- schema/migration version;
- test run IDs;
- physical-device matrix evidence;
- security scan results;
- privacy manifest/store disclosures;
- deployment environment and rollback target.

Local mocks, simulator-only results, and passing unit tests are necessary but insufficient for runtime qualification.

## 8. Store and operational readiness

- App Store and Play data-safety declarations match observed telemetry.
- Full Access/IME warning copy is accurate and localized.
- Account and data deletion work without support contact.
- OAuth provider verification is complete for requested scopes.
- Incident runbook covers token compromise, accidental logging, bad Skill, duplicated action, and provider outage.
- Kill switches can disable a Skill version, tool operation, provider, or model without disabling ordinary typing.
