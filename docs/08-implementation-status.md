# Implementation Status

## Milestone boundary

This checkpoint implements the W0/W1 local-first foundation and the W2 local text-action vertical slice. It deliberately does not connect a remote LLM, identity provider, OAuth account, or external action adapter.

## Implemented

### Shared contracts and services

- Strict TypeScript workspace with project references and reproducible pnpm lockfile.
- Validated ActionPlan, disclosure, run, receipt, telemetry, and typed-error contracts.
- Canonical plan serialization and SHA-256 confirmation digest.
- R0-R5 policy classification, prohibited-operation checks, and server-side risk recomputation.
- Run lifecycle state machine, disclosure digest, relative-date parsing, and content-free telemetry types.
- Minimal HTTP API with payload bounds, no-store responses, opaque credential-derived principals, owner-bound reads, and idempotency-key enforcement.
- Worker confirmation check, digest binding, execution ledger, retry suppression, and partial-result receipts.
- Local-only R1 disclosure, capture, preview, plan, result revision, apply-method, and undo contracts with source-specific Unicode limits.
- Fail-closed policy for source opt-in, acknowledgement/capture/plan digests, network/tool contamination, stale result revisions, and inactive/expired undo capabilities.

### iOS

- SwiftUI host app and custom keyboard extension build graph.
- Explicit typing, command, capture review, planning, result review, action review, execution, receipt, locked, and error states.
- Disclosure acknowledgement and stale-field fingerprint checks before Apply.
- Secure/password/OTP/payment-card field lockout.
- Local polite-rewrite fixture with protected entity preservation.
- Content-free telemetry allowlist and accessibility-labelled controls.
- Visible and long-press Command entry, per-run selection/surrounding source controls, exact and locally redacted Capture Review, explicit acknowledgement, editable/regenerable Result Preview, copy/cancel, stale-safe Apply, and one-shot Undo.
- SHA-256 field fingerprints and editor/document boundary invalidation; command 500, selection 4,000, surrounding 1,000 + 500, result 10,000 character limits.

### Android

- Compose host app and InputMethodService keyboard foundation.
- Local state, field-safety, rewrite, entity-preservation, fingerprint, and telemetry core.
- Ordinary text entry and explicit command-mode transition without network access.
- Capture Review, local-only acknowledgement gate, editable/regenerable Result Preview, copy/cancel, stale-safe insertion or selection replacement, and one-shot Undo.
- Bounded `InputConnection` reads, active-selection protection, exact applied-suffix verification before Undo, source/result limits, and editor-boundary state destruction.

## Verified in this checkpoint

- Shared TypeScript build and unit tests.
- iOS Swift unit tests, XcodeGen project generation, destination-specific signed Simulator build, embedded-extension validation, host launch, and keyboard enablement in Settings.
- Android JVM unit tests, InputConnection adapter simulations, lint, and debug APK assembly.
- CI definitions for the same three lanes.

## Not yet qualified

- Physical iPhone and Android device lifecycle, memory pressure, rotation, process death, and keyboard switching.
- Custom-keyboard switching into the live W2 surface remains `not_proven`: the signed extension was enabled in Simulator Settings, but Simulator input-mode cycling did not select it.
- Full Access behavior, App Group provisioning, signing, notarization-equivalent store checks, and release archives.
- Stable Japanese composition, conversion, candidate selection, and dictionary licensing.
- Selection replacement and undo across representative third-party apps such as messaging, mail, browser, and document editors.
- Production identity verification, durable database/queue/ledger, KMS, secrets, deployment, monitoring, and incident recovery.
- Live LLM privacy behavior, streaming, redaction, provider retention, regional processing, and adversarial prompt qualification.
- OAuth connectors, external writes, reconciliation, and receipts backed by real provider state.

These items remain `not_proven`; simulator, JVM, or local fixture success must not be presented as physical-device or production qualification.
