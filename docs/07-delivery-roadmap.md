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

- Verified Skill publishers and team policies.
- Local-only contextual suggestions.
- User-visible completion-rate and safety metadata.
- Additional R4 connectors after separate review.

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
