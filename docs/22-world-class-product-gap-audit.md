# World-Class Product Gap Audit

Status: current-tree audit, 2026-08-27

Scope: iOS host/keyboard extension, Android host/IME, shared Skill runtime and release evidence

Evidence rule: source, unit, simulator, emulator, physical-device, signed-artifact, and production evidence are reported separately. A local pass is never upgraded into release qualification.

## Executive decision

The repository now contains a real A–Z Skill Key foundation rather than a visual prototype. A user can create/install an executable local Skill, assign any QWERTY letter, run a fixture, publish the assignment, long-press the bound letter, review the selected text, preview the result, Apply/Copy, and perform guarded Undo. A short tap keeps its ordinary letter meaning. Assignments can be reassigned, explicitly swapped/replaced on conflict, paused/resumed, and removed.

The supported physical trigger set is intentionally **A–Z only** for the first beta. Number, symbol, space, return, delete, globe, shift, microphone, hardware modifier, chord, and multi-key triggers are not assignable. Those keys have typing, accessibility, locale, or OS-reserved semantics and must not be opened until collision policy and physical-device input-loss evidence exist.

This is a strong beta foundation, not yet a world-leading keyboard. The largest remaining distance is no longer the key-assignment UI; it is ordinary typing quality, physical-device proof, connected Skill execution, and operational safety.

## Closed in the current implementation

- A–Z add, search, fixture gate, reassign, explicit Swap/Replace, pause/resume, and delete on iOS and Android.
- Tap-to-type and deliberate 450 ms long-press separation, including Android cancellation on movement, pointer changes, view detachment, editor/window transitions, and delayed-callback invalidation.
- Owner/session-bound, integrity-checked, generation-monotonic snapshots with last-known-good recovery.
- Android process-death recovery through a bounded durable owner lease; expiry, corruption, sign-out, revocation floor, and account switch fail closed.
- Visible-keyboard convergence for same-owner generation updates and initial empty-to-active transitions.
- Immutable Skill id/version/digest and exact binding revalidation before execution, Apply, Copy, and Undo.
- Android revalidates the exact editor/session/version authority again at Copy and Undo, refreshes its `InputConnection` on every visible input-view attachment, and automatically destroys result/Undo state when the activation TTL expires.
- Selection revision locks include bounded before/after context, preventing duplicate-text Apply/Undo from targeting another occurrence.
- Password, OTP, phone pad, number pad, decimal pad, and unsupported field transitions clear ephemeral state and suppress Skill actions while preserving ordinary typing.
- Dismissal, editor change, window hide, process teardown, and stale activation expiry clear capture/result/action state.
- iOS cancel, editor change, secure transition, dismissal, and snapshot invalidation also resign and erase the custom command/result editors; captured text is not left in detached `UITextView` buffers.
- iOS refuses to publish or present a successful Skill Key assignment when the shared App Group container is unavailable. The Host fallback remains a recovery/test store, not executable keyboard authority, and onboarding requires fresh Full Access plus App Group availability.
- Content-free snapshot boundary: prompt, editor text, result, token, credential, and receipt are not persisted in the Skill Key snapshot.
- Native owner/session/exact-version circuit breakers on both platforms: three consecutive executor failures within ten minutes suppress only that Skill version and decoration; ordinary typing remains available, corruption fails Skill execution closed, and success clears the failure window.
- Android onboarding now requires enabled + currently selected IME + a content-free activation probe from this exact `InputMethodService` + nonblank test input, preventing another keyboard from completing setup.
- iOS onboarding refreshes on foreground return, expires capability observations after five minutes, and discloses the actual App Group metadata categories instead of understating them.
- A visible non-hold Skill palette on both keyboards routes each item through the same exact-version Capture Review path as its bound key; iOS moves accessibility focus on review transitions and Android emits content-free mode announcements.
- Android ordinary-input hardening now respects sound/haptic-off configuration, uses locale-stable letter mapping, invalidates stale review authority on IME view recreation, and reports delete/return mutation failure.
- Android now consumes persisted theme, key-size, and left/right one-handed layout settings in the real IME; rejected character insertion no longer consumes one-shot Shift, and empty-field backspace is a successful no-op rather than an error.
- Protected evidence schemas now bind the exact seven-app/device-class matrix, metric units and fixed pass thresholds, candidate artifact, and signed iOS archive/Android AAB inspections. Every passed E2E run, performance report, archive report, and AAB report requires a fresh Ed25519 signature over the complete canonical evidence from an out-of-band trusted verifier key; fake app lists, arbitrary coverage labels, boolean self-attestation, untrusted/expired/forged signatures, and over-budget measurements cannot self-report `passed`.

## P0 — required before an external beta claim

### 1. Physical-device qualification

Run the exact-candidate matrix on current iPhone and Android hardware across Messages/chat, Mail, Safari/Chrome, Notes/docs, search fields, multiline editors, duplicate selections, password/OTP/payment/phone fields, keyboard switching, rotation, background/foreground, low-memory process death, and account switch. Record candidate digest, OS/device/app version, protected runner identity, and content-free results.

Exit: zero ordinary-tap drops or false long-press executions within the fixed budget; no stale Apply/Copy/Undo after any boundary; A–Z assignments survive only the authorized owner session.

### 2. Signed distribution artifacts

Produce and independently inspect a signed iOS archive and Android AAB. Bind host/extension App Group entitlements, Full Access declaration, privacy manifests, bundle/package identity, signing identity, and artifact SHA-256 to the source commit. Simulator builds and debug APKs do not satisfy this gate.

### 3. Ordinary typing quality

The reference product exposes language, size/position, label weight, sound/haptics, capitalization, correction, prediction, slide typing, number gestures, and key preview controls. This repository still lacks production-grade Japanese composition/conversion, candidate selection, autocorrect, prediction, dictionary/licensing, emoji/dictation parity, and broad locale layouts.

Exit: either ship an explicitly English-only beta with narrow store claims, or qualify a real Japanese IME pipeline. Do not market the current deterministic keyboard shell as a system-keyboard replacement.

### 4. Native activation-only kill switch and failure containment — implemented locally, physical fault injection pending

The durable owner/epoch/version-bound circuit breaker and executor/persistence corruption tests are now implemented on both keyboard processes. Remaining exit work is protected physical fault injection for snapshot read, render, callback, process death, and memory pressure while proving A–Z taps, space, delete, return, shift, and keyboard switch remain usable.

### 5. Connected Skills and host handoff

Calendar, Gmail, Notion, Slack, Meet, and similar screenshots imply more than local text rewrite. Current R2/R3 models and fixtures do not constitute live OAuth, credential custody, provider execution, reconciliation, receipt, or revocation. Implement a signed host-handoff capability with exact inputs/tools/scopes/effect/cost preview, explicit confirmation, idempotency, unknown-outcome reconciliation, and exact-resource Undo where possible.

Exit: no network request before acknowledgement/confirmation; a traffic capture proves the boundary; provider-side state and receipts are independently verified.

### 6. Accessibility and one-handed operation

Qualify VoiceOver and TalkBack, Switch Control, Dynamic Type/font scale, reduced motion, high contrast, one-handed reach, and non-hold fallback actions. Announcements must include key, Skill, enabled/revoked/upgrade-required state, input source, risk/effect, and the available action without exposing editor content.

## P1 — required to beat the reference category

### Skill platform

- Signed Skill packages, verified publisher identity, moderation/reporting, rollback, revocation propagation, and immutable version history.
- Private/team/public visibility with clear trust differences; no public marketplace until the safety supply chain is real.
- Builder schema for typed inputs, output contract, tools, retention, fixtures, cost ceiling, timeout, and failure policy.
- Explicit upgrade-required state when installed version/digest/executor compatibility changes.
- Search and grouping within the implemented visible overflow palette; physical VoiceOver/TalkBack and Switch Control operation remains `not_proven`.
- Authenticated cross-device metadata sync with conflict resolution and tombstones; never sync editor content or credentials through the shortcut snapshot.

### Keyboard quality and personalization

- Measured adaptive long-press behavior, configurable within a safe range, without degrading tap latency.
- Size/position, one-handed mode, label weight, character preview, haptic/sound level, capitalization, correction, prediction, and number gestures backed by real runtime behavior rather than settings-only surfaces.
- Per-app compatibility diagnostics and a recovery screen that explains secure-field/OS limitations without asking for unnecessary access.
- Local-only clipboard input remains opt-in and off by default; clipboard changes must revoke pending actions.

### Reliability, privacy, and observability

- Content-free native telemetry allowlists tested against command, selection, output, clipboard, app, contact, resource, URL, and field-content denylist corpora.
- Crash/ANR/OOM and performance collection that binds exact build/device while never retaining editor content.
- SLOs for tap latency, cold/warm open, long-press false activation, Skill completion, snapshot convergence, crash-free sessions, and battery/memory overhead.
- Support/incident runbooks, on-call ownership, privacy requests, deletion verification, staged rollout, rollback rehearsal, and post-incident review.

## P2 — category leadership

- On-device model routing with energy/latency/quality budgets and a visible local-versus-cloud decision.
- Context packs that are explicitly selected, locally summarized, source-linked, and never passively monitor all typing.
- Enterprise policy for allowed Skills, connectors, data regions, retention, audit export, and managed revocation.
- Multi-device layouts, optional tablets/foldables/hardware keyboards, and conflict-safe user-defined gestures only after ordinary-input evidence exists.
- Creator analytics based on content-free attempts/success/failure/latency counters, with low-sample confidence and no dark-pattern ranking.
- A curated workflow library optimized for actual mobile jobs: reply, translate, summarize selection, structured capture, meeting coordination, knowledge lookup, and confirmed single-resource actions.

## Release truth table

| Claim | Current status |
| --- | --- |
| A–Z keys can be assigned and managed | Implemented; local builds/tests pass |
| Number/symbol/control keys can be assigned | Intentionally unsupported for beta; collision policy and zero-input-loss physical evidence required first |
| Tap types and long press invokes a local Skill | Implemented; simulator/emulator/source evidence, physical matrix `not_proven` |
| Assigned Skills have a visible non-hold action | Implemented on iOS/Android; physical VoiceOver/TalkBack and Switch Control `not_proven` |
| Repeated Skill failure is contained per exact version | Implemented and fault-tested locally; physical crash/memory-pressure evidence `not_proven` |
| Onboarding proves this Android IME was used | Implemented with selected-IME + content-free activation handshake; physical OEM matrix `not_proven` |
| Settings survive authorized Android process death | Implemented with integrity-bound lease; physical memory-pressure run `not_proven` |
| Secure/unsupported fields suppress Skill execution | Implemented and unit-tested; representative third-party-device proof `not_proven` |
| App Group unavailable can still create a working iOS key | Rejected in production; UI-test fallback is debug-only and explicitly non-qualifying |
| Stale Android result can Copy/Undo after expiry or editor reattachment | Rejected and automatically cleared locally; physical OEM lifecycle proof `not_proven` |
| Cross-platform canonical contracts | Native golden-vector consumers pass; full runtime wire interoperability `not_proven` |
| Connected tools perform real actions safely | `not_proven`; fixtures/contracts only |
| App Store / Play release ready | `not_proven`; signed archive/AAB and protected evidence missing |
| Japanese system-keyboard replacement quality | Not implemented |

## Next execution order

1. Run CI for the exact commit and preserve all three lane artifacts.
2. Stand up protected physical-device E2E, accessibility, failure-injection, and performance runners against the exact seven-app contract.
3. Produce signed archive/AAB inspection evidence using the checked-in fail-closed schemas.
4. Choose and state the beta language/input-quality boundary; current UI is an English QWERTY shell despite Japanese workflow labels.
5. Implement one connected read-only Skill end to end before expanding the connector catalog.
6. Consume every exposed keyboard setting in the real IME or remove the setting from beta UI.
7. Only after those gates, begin public marketplace and creator-growth work.
