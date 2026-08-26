# Implementation Status

## Milestone boundary

This checkpoint implements the W0/W1 local-first foundation, W2 local text-action vertical slice, W3 provider-neutral identity/receipt lifecycle, W4 read-only connection contracts plus native fixtures, the W5 single confirmed-write fixture, the W6 private Skill/binding/quota fixture, the W7 parity/launch qualification foundation, and the W8 beyond-parity trust foundation. It deliberately does not connect a remote LLM, external identity provider, live OAuth account, durable database, credential vault, external provider adapter, crash collector, protected release runner, publisher verifier, moderation service, public marketplace, or store backend.

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
- Challenge-bound Ed25519 device-registration contracts, token-hash-only rotating session families, stale-token replay revocation, and user/device/session ownership checks.
- Immutable owner-bound plan versions, append-only receipt identity/sequence checks, content-free audit schemas, retention/legal-hold scheduling, and explicit account-deletion transitions.
- Provider-neutral API composition and content-free worker receipt projection; all backing stores remain in-memory fixtures.
- One-time OAuth state with nonce, expiry, S256 PKCE, structured-clone isolation, replay consumption, exact read-only scope allowlists, incremental consent, owner-bound rebind/disconnect/revoke, and implicit cross-device rebind rejection.
- Calendar availability, Notion page search, and Maps place search contracts with page-size limits, ordered time windows, source/grant provenance, freshness chronology, untrusted-provider taint, and succeeded/partial/failed/unknown outcomes.
- Provider content cannot add operation, scope, risk, write capability, tools, or authorization; both succeeded and partial results pass the same provenance and taint checks.
- `calendar.event.create_private` is the only W5 create authority: R3, explicit per-run confirmation, empty attendees, `send_updates=none`, exact write scope, canonical digest, plan/owner/device/grant/connection-epoch expiry binding, and content-free receipts.
- W5 runtime fixtures deduplicate concurrent/retried execution, reject idempotency collisions and confirmation replay, persist an executor-generated operation key for unknown outcomes, require exact-key reconciliation, and expose only bounded exact-resource `calendar.event.delete_own` Undo.
- W6 typed Skill definitions bind trigger, inputs, exact operation/scope/effect tools, risk, confirmation, output, retention, and visible fixtures into canonical digests; static checks reject duplicate inputs/sources, unsupported authority, and prompt-injection markers.
- W6 lifecycle fixtures require current-revision fixture results before private publishing, preserve immutable versions, pin device bindings to an exact version/digest, require explicit upgrades, reject typing/accessibility conflicts, keep sharing private and revocable, and account for run/input/output/cost quota reservations.
- W7 release candidates bind source SHA, artifact/privacy digests, schema, release epoch, owner, and a unique complete test-run set. Qualification rejects mock, fixture, simulator, self-attested, stale, future-dated, untrusted, incomplete, or candidate-mismatched evidence.
- W7 fixed release-quality policy requires all documented performance/crash metrics for both iOS and Android; caller-relaxed diagnostic budgets cannot qualify a beta or broad release.
- W7 kill switches are exact-target, owner/epoch-bound, monotonically revised, and unable to disable ordinary typing. Incident records are append-only and content-free.
- W7 forward migration requires exact-candidate protected qualification and fixed-policy quality decisions; migration and rollback are environment/candidate bound and idempotent.
- W8 publisher identities, signed Skill packages, protected-verifier evidence, immutable team policies, local contextual suggestions, safety metadata, reports, moderation, control actions, and rollback requests are exact owner/version/package/epoch bound.
- W8 completion rates are derived from bounded integer counts, zero attempts have no rate, low samples remain low confidence, review evidence expires, and public issue metadata is content-free and categorized.
- W8 suggestions contain typed/opaque local metadata only, have no network or execution authority, and cannot insert text, call tools, install a Skill, or widen connector access.
- Team policy install, upgrade, revocation, and rollback are explicit and fail closed on digest, owner, team, version, epoch, scope, risk, confirmation, chronology, or evidence mismatch. R4 remains disabled pending a separate review.
- Trigger-key contracts cover A-Z physical keys, immutable Skill version/digest pins, content-free presentation projections, exact-device layouts, canonical tamper-evident snapshots, generation/replay checks, duplicate/reserved-key conflicts, and activation bindings. The pure gesture runtime preserves short-tap character commit and emits one activation only after the hold threshold.

### iOS

- SwiftUI host app and custom keyboard extension build graph.
- Explicit typing, command, capture review, planning, result review, action review, execution, receipt, locked, and error states.
- Disclosure acknowledgement and stale-field fingerprint checks before Apply.
- Secure/password/OTP/payment-card field lockout.
- Local polite-rewrite fixture with protected entity preservation.
- Content-free telemetry allowlist and accessibility-labelled controls.
- Visible and long-press Command entry, per-run selection/surrounding source controls, exact and locally redacted Capture Review, explicit acknowledgement, editable/regenerable Result Preview, copy/cancel, stale-safe Apply, and one-shot Undo.
- SHA-256 field fingerprints and editor/document boundary invalidation; command 500, selection 4,000, surrounding 1,000 + 500, result 10,000 character limits.
- Host Account, Devices, Activity, and Privacy fixture surfaces with session expiry/revocation, partial/failed receipts, retention choices, deletion progress, Dynamic Type, and accessibility labels.
- Connections and source-linked Results fixture UI for Calendar, Notion, and Maps with exact scopes, guarded lifecycle transitions, query-preserving pagination, reconnect/rebind/disconnect, freshness/partial warnings, and SHA-256 plan digests.
- Calendar write fixture UI with separate capability enablement, draft/edit invalidation, data/service/effect review, canonical SHA-256 confirmation, execution expiry/owner/epoch recheck, succeeded/failed/partial/unknown receipts, reconciliation-only unknown recovery, and one-shot exact-resource Undo.
- Private Skill Builder fixture UI with desired-outcome intake, explicit missing fields, typed manifest/schema review, allowlisted SF Symbols, static/policy validation, visible fixture results, quota/cost disclosure, digest confirmation, immutable private versions, exact binding pins, explicit upgrades, and private share/revoke.
- Versioned keyboard customization and Japanese workflow-pack fixture models, qualification-budget surfaces, source-declared privacy manifests, and launch-readiness copy that distinguishes source presence from archive/runtime verification. Extension runtime settings sync and persistence remain `not_proven`.
- Local contextual-suggestion, Trust Preview, team-policy, and R4-denial fixture screens. They expose provenance, immutable digests, derived completion confidence, typed issue counts, explicit upgrade/revoke state, and `not_proven` boundaries without claiming publisher/package verification.
- Skill Keys management with QWERTY preview, search, A-Z add/reassign/remove, occupied-key selection, explicit Swap/Replace, save-before-test local fixture preview, success confirmation, version/digest-bound content-free App Group snapshots, last-known-good fallback, bound-key accessibility actions, tap-to-type preservation, 450 ms long-press activation, and routing into the existing Capture Review/Result Preview flow. Skill Keys sharing requests Full Access while ordinary typing remains available without it.
- P0 input-safety hardening keeps bundled local transforms selection-only on both platforms, blocks empty selection instead of treating a Skill label as editor content, exposes Android Skill execution through an accessibility long-click while ordinary accessibility click still types, and refreshes iOS secure/content-type traits at extension appearance and editor-change boundaries. Physical VoiceOver/TalkBack and third-party editor qualification remain `not_proven`.

### Android

- Compose host app and InputMethodService keyboard foundation.
- Local state, field-safety, rewrite, entity-preservation, fingerprint, and telemetry core.
- Ordinary text entry and explicit command-mode transition without network access.
- Capture Review, local-only acknowledgement gate, editable/regenerable Result Preview, copy/cancel, stale-safe insertion or selection replacement, and one-shot Undo.
- Bounded `InputConnection` reads, active-selection protection, exact applied-suffix verification before Undo, source/result limits, and editor-boundary state destruction.
- Host Account, Devices, Activity, and Privacy fixture surfaces with confirmed device revoke, session states, content-free receipt details, retention choices, deletion progress, scrolling, and accessibility semantics.
- Connections and source-linked Results fixture UI for Calendar, Notion, and Maps with exact scopes, guarded connection/pagination/result-selection reducers, disconnect cleanup, typed failed/partial receipts, and SHA-256 plan digests.
- Calendar write fixture UI with active-session and connected-Calendar gates, separately enabled exact write capability, digest-bound owner/epoch/version/expiry, honest step projection, unknown blind-retry prevention, reconciliation, and bounded one-shot Undo.
- Private Skill Builder fixture UI with bounded strict JSON parsing, typed local-only authority, injection/binding checks, visible fixture tests, quota accounting, owner/session-bound digests, immutable private versions, explicit upgrades, private share/revoke, and Material icons.
- Versioned keyboard customization and Japanese workflow-pack fixture models plus qualification-budget surfaces. Session/revocation boundaries preserve ordinary preferences while account deletion resets them; the configuration is IME-consumable as a typed model, but Host-to-IME runtime sync and persistence remain `not_proven`.
- Local contextual-suggestion and Trust Preview fixtures with secure-input suppression, content-free typed metadata, exact team-policy checks, explicit install/upgrade/revoke actions, and a permanently disabled R4 boundary. Public catalog and runtime synchronization remain `not_proven`.
- Skill Keys management with QWERTY preview, search, A-Z add/reassign/remove, occupied-key selection, explicit Swap/Replace, save-before-test local fixture preview, deterministic binding order, content-free active/last-known-good `SharedPreferences` snapshots, generation/digest validation, bound-key semantics, movement-cancelled 450 ms long press, preserved short-tap typing, and routing into the existing Review/apply workflow.

## Verified in this checkpoint

- Shared TypeScript build and unit tests.
- iOS Swift unit tests, XcodeGen project generation, destination-specific signed Simulator build, embedded-extension validation, host launch, and keyboard enablement in Settings.
- Android JVM unit tests, InputConnection adapter simulations, lint, and debug APK assembly.
- CI definitions for the same three lanes.
- W3 replay, owner mismatch, immutable binding, append-only receipt identity, clone-boundary, invalid deletion transition, retention expiry, and native reducer tests.
- W4 OAuth replay/PKCE, caller-mutation isolation, owner/grant/device confusion, explicit rebind, exact scope ceiling, provenance/freshness chronology, provider-taint escalation, pagination, invalid native state transitions, digest format, and typed failure tests.
- W5 digest tamper, attendee/invite injection, confirmation expiry/replay, cross-owner/grant/epoch/resource confusion, concurrent idempotency, unknown retry/reconciliation, delimiter-safe native canonicalization, session/disconnect cleanup, Undo expiry/double-use, and content-minimized receipt tests.
- W6 stale/tampered/incomplete fixture-result, schema/effect/scope, injection, duplicate input/source, immutable version, explicit-upgrade, typing/accessibility, private-share, quota/idempotency, owner/epoch, strict-JSON, and delimiter-escape tests.
- W7 candidate/evidence tamper, incomplete two-platform metrics, fixed-threshold, crash-rate, kill-switch authority, content-free incident, protected-evidence freshness, and migration/rollback binding tests.
- W8 publisher/package/evidence, team-policy, suggestion/telemetry, safety-metric, report/moderation, revocation/control, and rollback adversarial tests across shared, iOS, and Android reducers.
- Trigger-key schema/policy/gesture tests, iOS snapshot/store/validator tests, Android snapshot/conflict/tamper tests, iOS 18.6/26.4 Simulator builds, and Android unit/lint/debug APK assembly.
- Source-level iOS privacy manifests and current Android no-INTERNET boundary; archive/AAB privacy aggregation and physical-device traffic capture remain separate gates.

## Not yet qualified

- Physical iPhone and Android device lifecycle, memory pressure, rotation, process death, and keyboard switching.
- Custom-keyboard switching into the live W2 surface remains `not_proven`: the signed extension was enabled in Simulator Settings, but Simulator input-mode cycling did not select it.
- Physical-device Full Access behavior, App Group provisioning/signing, store checks, and release archives. Simulator builds prove configuration and compilation, not production entitlement provisioning.
- Stable Japanese composition, conversion, candidate selection, and dictionary licensing.
- Selection replacement and undo across representative third-party apps such as messaging, mail, browser, and document editors.
- Production identity verification, durable database/queue/ledger, KMS, secrets, deployment, monitoring, and incident recovery.
- External IdP issuer/audience/revocation checks, Secure Enclave/Android Keystore proof, production token verifier, multi-instance race safety, and provider-side deletion/backup expiry.
- Live LLM privacy behavior, streaming, redaction, provider retention, regional processing, and adversarial prompt qualification.
- Live OAuth authorization/redirect allowlisting/revocation, Google Calendar/Notion/Maps provider calls, KMS-backed credential envelopes, multi-instance replay safety, external writes, reconciliation, and receipts backed by real provider state.
- Real Calendar event creation/deletion, provider-side idempotency and lookup semantics, externally verified reconciliation/Undo, and the required independent security assessment for R3 write promotion.
- Durable transactional Skill storage, trusted test executors, signed Skill packages, external cost settlement, moderation/reporting/kill switches, public marketplace publication, and cross-device production binding synchronization.
- Protected publisher/package verification, hardware-backed publisher signing custody, real team administration, durable governance/revocation state, external moderation, public safety metrics, marketplace distribution, and separately qualified R4 connectors.
- Physical-device Host-to-extension/App Group and Host-to-IME persistence/runtime synchronization across process death or restart. The native local implementations and simulator/JVM checks exist, but device evidence remains `not_proven`.
- TypeScript, Swift, and Kotlin snapshot encoders intentionally validate their own native projections today. The checked-in fixture records `native_consumption_status: "not_proven"` until both native unit suites directly consume it; when the source gate observes both consumers it may report the narrower `"native_unit_consumers"` level. Neither status proves canonical byte parity, cross-process runtime interoperability, physical-device behavior, or a server-synchronized registry.
- Optional searchable overflow palette, authenticated cross-device shortcut synchronization, and production Skill catalog installation. Physical A-Z assignment, conflict management, tap/hold handling, and local Review routing are implemented foundations; Acti-class parity on representative third-party apps remains `not_proven` until device qualification.
- Exact-candidate protected CI identity, durable incident/kill-switch storage, real crash/performance collection, independently repeatable beta migration/rollback, and configured on-call/support/privacy endpoints.
- App Store/Play product identity, legal/privacy copy, signed archive/AAB inspection, store privacy aggregation, review submissions, approval, rollout, and rollback evidence.

These items remain `not_proven`; simulator, JVM, or local fixture success must not be presented as physical-device or production qualification.
