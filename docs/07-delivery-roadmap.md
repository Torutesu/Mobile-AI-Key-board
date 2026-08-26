# Delivery Roadmap

## 1. Delivery principle

Reach behavioral parity in vertical slices, not by building a wide catalog of disconnected screens. Every slice includes keyboard interaction, backend contract, privacy disclosure, failure handling, tests, and physical-device proof.

## 2. Workstreams

### W0: Foundations

- Monorepo, build tooling, CI, schema generation, environment separation.
- Architecture decision records and dependency/license policy.
- Test accounts, provider sandboxes, secret management, baseline observability.

Exit: empty signed iOS/Android apps and API deploy reproducibly from a bound commit.

### W1: Native typing foundation

- iOS extension and Android IME lifecycle.
- English/Japanese layout strategy, composition, candidates, symbols, switch key.
- Local settings, haptics, sizing, orientation, accessibility.
- Sensitive-field suppression and offline behavior.

Exit: the product can be used as a stable ordinary keyboard for an internal daily-driver test without any AI.

### W2: Text action vertical slice

- Hold-to-command gesture and accessible alternative.
- Input source chips, local redaction, disclosure acknowledgement.
- Streaming planner/result, preview/edit/apply/undo.
- Rewrite, shorten, translate with entity preservation.

Exit: private beta users complete text workflows in real third-party apps with zero silent transmission.

### W3: Identity, devices, and receipts

- Sign-in, device keys, session rotation/revocation.
- Run state machine, immutable plan versions, audit metadata.
- Activity UI and deletion/retention controls.

Exit: every run has an authenticated lifecycle and user-readable outcome.

### W4: Read-only connections

- OAuth credential broker.
- Calendar availability, Notion search, Maps search.
- Incremental scopes, reconnect/rebind/disconnect.
- Prompt-injection and data-minimization qualification.

Exit: read-only results are reliable, source-linked, and cannot widen authority.

### W5: Confirmed writes

- Risk policy and plan digest confirmation.
- Calendar private-event creation.
- Idempotency, partial/unknown states, reconciliation, undo.
- External security assessment.

Exit: one production external-write workflow meets all security and reliability gates.

### W6: Skills and bindings

- Typed Skill schema, Builder draft conversation, validation, fixtures.
- Versioning, deployment, binding conflict checks, private sharing.
- Usage quota and cost controls.

Exit: a nondeveloper can safely create and reuse a private Skill without code.

### W7: Parity and launch

- Onboarding polish, keyboard customization, Japanese workflow packs.
- Store assets, privacy/data-safety declarations, support and incident runbooks.
- Beta migration, rollback, performance and crash gates.

Exit: Acti-class core experience is publicly usable without relying on marketplace scale.

### W8: Beyond parity

- Verified Skill publisher/package contracts and immutable team policies, with fixture provenance kept visibly `not_proven` until protected external evidence exists.
- Local-only contextual suggestions that retain no captured/output content and carry no insertion, installation, connector, or execution authority.
- User-visible, digest-bound completion counts, derived rate/confidence, review freshness, typed issue counts, requested operations/scopes, and revocation state.
- Moderation, control, rollback, and explicit upgrade contracts bound to exact owner/team/version/package/epoch state.
- Additional R4 connectors only after the separate security, privacy, physical-device, provider, support, and release-evidence review in the W8 acceptance baseline.

Exit: the local/provider-neutral trust foundation passes adversarial shared and native tests, while every absent production verifier, marketplace, device, provider, and R4 gate remains explicitly `not_proven`. W8 fixture completion is not public-marketplace or R4 qualification.

### W9: Keyboard shortcut platform

- Canonical physical `A-Z` trigger-key bindings plus optional ordered palette layout, sanitized immutable snapshots, generation/digest validation, tombstones, and last-known-good rollback.
- iOS host-to-extension App Group publication and Android host-to-IME DataStore synchronization.
- Host `Add To My Keyboard` flow, QWERTY trigger-key picker, conflict/reassignment, disable/remove, explicit version upgrade, and connection/access state management.
- Tap-to-type/long-press-to-invoke keyboard semantics, subtle bound-key indicators, permanent Command/palette fallback, and accessible equivalent actions.
- Exact shortcut activation binding into Capture Review, Trust Preview, local execution, Result Preview, Apply, receipt, and Undo.
- One connected read and one separately confirmed write only after physical-device, permission, provider, security, and release-evidence gates.

Exit: a nondeveloper can deploy a private Skill, assign it to the keyboard, use it safely in representative third-party apps, and manage or revoke it across process death/restart without regressing ordinary typing. See `docs/19-keyboard-shortcut-product-requirements.md` and `docs/20-shortcut-runtime-architecture.md`.

## 3. Recommended implementation order

1. Android IME feasibility and iOS extension feasibility in parallel conceptually, but keep shared schemas platform-neutral.
2. Implement text-only Command -> Preview -> Apply on both platforms.
3. Prove ordinary keyboard stability before OAuth.
4. Add read-only Calendar/Notion before any external write.
5. Add exactly one confirmed write and qualify idempotency/reconciliation.
6. Build Skill Builder on the same typed contracts already proven manually.
7. Add catalog/community only after update safety and moderation exist.

## 4. Decisions required before coding

The following are deliberately unresolved and should become ADRs during W0:

- Adopted Japanese IME/conversion engine and license.
- Backend runtime and hosting provider.
- Primary database, queue, KMS, and OAuth broker implementation.
- Initial LLM providers and regional data-processing guarantees.
- Account requirement timing and anonymous-device migration.
- Whether iPad is launch-supported or beta-only.
- Exact receipt/content retention defaults by region.

These choices must preserve the product contracts in the other specifications.

## 5. First engineering milestone

Deliver a device-tested skeleton containing:

- iOS host app plus keyboard extension;
- Android app plus IME;
- local English typing and a documented Japanese input spike;
- action control with typing/command state transition;
- local-only polite rewrite fixture;
- sensitive-field suppression;
- performance instrumentation with content-free telemetry;
- CI builds and unit tests.

No network, account, LLM, OAuth, or tool execution is needed in this milestone. Its purpose is to retire the platform and typing risks before backend complexity begins.

## 6. Scope-control rules

- New connectors require a tool contract, risk class, scopes, failure model, receipt, and adversarial tests.
- New input sources require disclosure, local preview, size limit, retention rule, and secure-field behavior.
- New autonomous behavior is out of scope unless the charter is explicitly revised.
- Marketplace growth work cannot bypass Skill versioning, review, reporting, and kill switches.
- A launch date does not waive physical-device, privacy, or external-action gates.
