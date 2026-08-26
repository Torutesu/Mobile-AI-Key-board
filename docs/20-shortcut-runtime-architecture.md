# Shortcut Runtime Architecture and Implementation Plan

## 1. Architecture outcome

This architecture implements the screenshot-derived product contract in `docs/21-acti-screenshot-parity.md`; in particular, physical letter-key assignment and tap-to-type/long-press-to-invoke are mandatory, while a rail/palette is only a fallback presentation.

The shortcut platform is a four-part system:

1. `Skill Contract`: immutable executable definition already established in W6.
2. `Shortcut Registry`: user-owned Skill/version binding, physical trigger key, and optional palette order.
3. `Shortcut Snapshot`: sanitized, immutable local projection consumed by the keyboard.
4. `Activation Runtime`: editor-bound state machine that reuses Capture Review, Trust Preview, execution, Result Preview, receipt, Apply, and Undo.

The host app owns mutation and synchronization. The keyboard is a low-latency reader and activation surface. Backend services may synchronize account metadata and execute connected Skills, but they never sit on the ordinary keystroke path.

## 2. Current-to-target gap

### 2.1 Reusable current foundations

- Shared `SkillDefinition`, `SkillVersion`, and `SkillBinding` contracts already bind exact version/digest, trigger, accessibility metadata, owner, and device.
- Shared W2 contracts already enforce disclosure, source opt-in, bounded capture, fingerprints, result revision, apply method, and Undo.
- W4/W5 already define exact scopes, provenance, connection epochs, confirmed writes, idempotency, reconciliation, and typed receipts.
- iOS and Android already have a fixed Command entry and local polite-rewrite workflow.
- Native host apps already have fixture Skill Builder and keyboard settings surfaces.

### 2.2 Missing foundation

- No platform-neutral trigger-key/layout contract.
- W6 `trigger.kind=shortcut` models an activation alias, not a physical key or long-press policy.
- Native host binding fixtures are not canonical projections of the shared W6 contract.
- iOS has no configured App Group entitlement/runtime store.
- Android host settings are not persisted or consumed by the IME.
- No versioned snapshot, atomic publication, last-known-good fallback, or tombstone.
- No bound-key presentation, long-press recognizer, or Skill palette in the keyboard.
- No activation router from a shortcut to the existing capture/execution state machines.
- No physical-device performance, lifecycle, permission, or third-party app qualification.

## 3. Trust boundaries

### TB1: Active editor

Untrusted content source. Text from `UITextDocumentProxy` or `InputConnection` is data, never instructions or authority. The editor can change at any time.

### TB2: Keyboard process

Latency-sensitive and highly privileged with respect to visible typing context. It holds only bounded ephemeral capture and a sanitized shortcut snapshot. It has no long-lived OAuth tokens, provider credentials, raw Skill fixtures, or arbitrary code.

### TB3: Host app

Canonical device-local configuration writer. It authenticates the user, manages Skills/connections, validates layouts, writes snapshots, displays detailed permissions, and performs host-mediated handoffs.

### TB4: Shared local storage

Carries versioned, content-free configuration only. It is not a credential vault, receipt store, or captured-content cache.

### TB5: Backend and providers

Execute only an authenticated, digest-bound plan with exact scopes and idempotency. Provider output is tainted data and cannot alter tools, risk, recipients, confirmation, or retention.

## 4. Canonical contracts

Add a new shared module `packages/contracts/src/shortcuts.ts`. JSON field names below are normative.

### 4.1 Shortcut presentation

```ts
type ShortcutPresentation = {
  icon_kind: "system" | "text";
  icon_value: string;              // allowlisted identifier or 1-3 grapheme abbreviation
  short_label: string;             // 1..24 graphemes
  accessibility_label: string;     // 2..80 nonblank chars
  accessibility_hint: string;      // 1..160 chars
  tint_token: "neutral" | "accent" | "read" | "write";
};
```

Rules:

- No remote image URL, HTML, SVG, binary payload, arbitrary color, or executable asset.
- `write` tint is advisory only; risk and confirmation derive from the bound Skill.
- Native apps map cross-platform semantic icon IDs to SF Symbols/Material icons using checked allowlists.

### 4.2 Shortcut binding

```ts
type ShortcutBindingV1 = {
  schema_version: 1;
  binding_id: `bind_${string}`;
  user_id: `usr_${string}`;
  device_id: `dev_${string}`;
  skill_id: `skill_${string}`;
  version_id: `sv_${string}`;
  skill_version: number;
  skill_digest: `sha256:${string}`;
  trigger_key: {
    layout_id: "latin_qwerty_v1";
    key_code: `Key${Uppercase<string>}`; // v1 validator accepts KeyA..KeyZ only
    display_label: string;              // derived A..Z; never trusted as identity
    activation_gesture: "long_press";
  };
  presentation: ShortcutPresentation;
  enabled: boolean;
  local_eligibility: "local" | "connected_read" | "confirmed_write";
  required_connection_ids: string[]; // opaque IDs only, max 5
  created_at: string;
  updated_at: string;
};
```

This extends the current W6 binding concept. The existing `trigger` remains part of the Skill definition for command/phrase semantics. `trigger_key` is device/layout presentation and activation state, not Skill authority. Key identity is a stable semantic code rather than a localized glyph or screen coordinate.

### 4.3 Layout

```ts
type ShortcutLayoutV1 = {
  schema_version: 1;
  layout_id: `layout_${string}`;
  user_id: `usr_${string}`;
  device_id: `dev_${string}`;
  revision: number;
  key_binding_ids: string[];      // unique, max 26; each points to one distinct trigger_key
  palette_binding_ids: string[];  // ordered, unique subset, max 32
  long_press_duration_ms: 450;
  cancellation_distance: number; // native units, fixed by policy: 10 pt iOS / 12 dp Android
  command_position: "leading";
  overflow_enabled: true;
  updated_at: string;
};
```

Rules:

- Command is permanent and is not represented as a removable binding.
- Active binding IDs and active `(layout_id, key_code)` pairs are unique and owner/device bound.
- Disabled or missing bindings cannot appear as executable key or palette items.
- Long-press timing and cancellation policy are validated constants in v1; remote configuration cannot make normal typing harder or accidental execution easier.
- Palette order is presentation only and cannot change the physical key binding.

### 4.4 Sanitized Skill projection

```ts
type ShortcutSkillProjectionV1 = {
  skill_id: string;
  version_id: string;
  skill_version: number;
  skill_digest: string;
  name: string;
  description: string;
  input_sources: Array<"command" | "selection" | "surrounding_text" | "clipboard" | "current_datetime" | "locale" | "location">;
  output_type: "insert_text" | "replace_selection" | "copy" | "json";
  risk_ceiling: "R0" | "R1" | "R2" | "R3";
  confirmation: "none" | "policy_required";
  retention: "none" | "transient_content" | "receipt_metadata";
  tool_summaries: Array<{
    operation: string;
    required_scopes: string[];
    side_effect: "none" | "creates_private_event" | "updates_private_resource";
  }>;
  execution_route: "keyboard_local" | "keyboard_network" | "host_handoff";
};
```

Excluded fields include full instruction/prompt, visible fixtures, provider credentials, tokens, recipients, past input/output, receipt details, email/display name, and raw OAuth metadata.

### 4.5 Snapshot

```ts
type ShortcutSnapshotV1 = {
  schema_version: 1;
  snapshot_id: `ss_${string}`;
  generation: number;
  user_subject_hash: `sha256:${string}` | null;
  device_id: string;
  layout: ShortcutLayoutV1;
  bindings: ShortcutBindingV1[];
  skills: ShortcutSkillProjectionV1[];
  connection_states: Array<{
    connection_id: string;
    state: "active" | "expired" | "revoked" | "missing";
    epoch: number;
  }>;
  policy_epoch: number;
  created_at: string;
  expires_at: string | null;
  tombstone_reason: "signed_out" | "account_deleted" | "device_revoked" | null;
  content_digest: `sha256:${string}`;
};
```

Normative limits:

- encoded canonical JSON <= 256 KiB;
- bindings <= 32, active layout IDs <= 12, tools per Skill <= 16;
- strings use repository-wide bounds and reject control characters;
- `content_digest` covers the object excluding `content_digest` itself;
- generation is strictly monotonic per device;
- tombstone contains no private/connected bindings and preserves only allowed ordinary keyboard preferences outside this schema.

### 4.6 Activation

```ts
type ShortcutActivationV1 = {
  schema_version: 1;
  activation_id: `act_${string}`;
  binding_id: string;
  skill_id: string;
  version_id: string;
  skill_digest: string;
  snapshot_generation: number;
  device_id: string;
  editor_session_id: string;       // process-local opaque value
  field_safety: "safe" | "sensitive" | "unsupported";
  requested_at: string;
  expires_at: string;              // default 2 minutes
};
```

Activation never contains captured text. Capture belongs to the existing W2 disclosure/capture contract and is bound later by digest/fingerprint.

## 5. Validation invariants

Implement in `packages/policy/src/shortcuts.ts`:

- `validateShortcutBinding(binding, version, owner)` checks owner/device/version/digest and derived eligibility.
- `validateShortcutLayout(layout, bindings, owner)` checks key and palette references, physical-key uniqueness, assignable-key allowlist, timing constants, maximums, enabled state, and no missing references.
- `validateShortcutSnapshot(snapshot, lastGeneration, device)` checks schema, size, canonical digest, monotonic generation, referential integrity, projection/Skill equality, connection state bounds, chronology, and tombstone rules.
- `validateShortcutActivation(activation, snapshot, editor, now)` checks exact binding/Skill/version/digest/generation/device/editor/safety/expiry.
- Risk, confirmation, tools, scopes, and execution route are recomputed from the immutable Skill definition by the trusted host/backend; callers cannot downgrade them.
- A projection can narrow capability but cannot widen the full Skill definition.
- Unknown fields fail closed.
- Invalid snapshot publication does not replace last-known-good.

## 6. State machines

### 6.1 Host configuration

`idle -> editing -> validating -> publishing -> published`

Failure branches:

- `validating -> conflict`
- `publishing -> publish_failed`
- `published -> rollback_pending -> published`
- any authenticated state -> tombstone_pending -> tombstoned`

Only `published` or `tombstoned` creates a new generation.

### 6.2 Keyboard snapshot

`unloaded -> loading -> ready`

Failure branches:

- `loading -> last_known_good`
- `loading -> command_only`
- `ready -> refreshing -> ready`
- `refreshing -> last_known_good`
- `ready -> tombstoned -> command_only`

Ordinary typing is independent from this machine.

### 6.3 Activation

`idle -> selected -> eligibility_check -> capture_review -> acknowledged -> plan_review -> executing -> result_preview -> applied`

Additional terminal/intermediate states:

- `eligibility_check -> blocked`
- `eligibility_check -> host_handoff`
- `capture_review -> cancelled`
- `plan_review -> confirmation_required -> executing`
- `executing -> partial | failed | unknown`
- `result_preview -> copied | cancelled`
- `applied -> undo_available -> undone | undo_expired | undo_rejected`

Any editor change, secure transition, snapshot generation change, version revocation, or timeout transitions to `invalidated` and clears content.

## 7. iOS design

### 7.1 Entitlements and capability modes

Configure the containing app and keyboard extension with a registered App Group, for example `group.com.torutesu.mobileaikeyboard`, in release-specific provisioning.

Two operating modes are required:

- `Standard access`: ordinary typing and keyboard-owned/local bundled actions only. The extension may read permitted shared configuration under current platform behavior but must not assume network or shared-container writes.
- `Full Access`: allows shared-container write/network capabilities subject to user permission and App Store rules. It is required only for routes that genuinely need those capabilities.

The runtime checks `hasFullAccess` and derives shortcut eligibility. The product must not claim Full Access is required for ordinary typing.

### 7.2 Storage

Host writer:

1. construct and validate complete snapshot;
2. encode canonical JSON;
3. write `shortcut-snapshot.<generation>.tmp` with complete file protection appropriate for use while the device is unlocked;
4. fsync/close and atomically replace `shortcut-snapshot.current.json`;
5. preserve one prior valid generation as `shortcut-snapshot.previous.json`;
6. update minimal `UserDefaults(suiteName:)` metadata: generation and digest;
7. issue a Darwin notification as a refresh hint.

Extension reader:

1. compare cached generation when keyboard appears or the hint arrives;
2. read at most 256 KiB off the key handling path;
3. validate schema/digest/generation/references;
4. swap one immutable in-memory value on the main thread;
5. retain last-known-good if validation fails.

Do not use shared storage for OAuth tokens or captured content. Credentials remain in a host/backend-controlled credential store. If shared Keychain access is later needed, define it as a separate, reviewed capability; it is not part of this shortcut snapshot.

### 7.3 Execution routing

- `keyboard_local`: local deterministic/qualified R0/R1 executors only.
- `keyboard_network`: deferred until Full Access, network privacy, memory, cancellation, and App Review qualification are proven.
- `host_handoff`: default for connected reads/writes. Persist only an opaque activation nonce with no source text; open the host app through an allowed user-initiated route. The host revalidates Skill/version/connection and gathers any additional protected data there.

Because iOS may replace a custom keyboard in secure fields, phone-pad fields can use the system keyboard, and host apps can disallow third-party keyboards, these are explicit unsupported surfaces rather than errors in the product.

### 7.4 Native interfaces

Add to `MobileAIKeyboardCore`:

```swift
public protocol ShortcutSnapshotReading {
    func loadLastKnownGood() async throws -> ShortcutSnapshot
    func refresh(after generation: Int) async throws -> ShortcutSnapshot?
}

public protocol ShortcutSnapshotPublishing {
    func publish(_ snapshot: ShortcutSnapshot) async throws
    func publishTombstone(reason: ShortcutTombstoneReason) async throws
}

public protocol ShortcutActivationRouting {
    func route(_ activation: ShortcutActivation, skill: ShortcutSkillProjection) -> ShortcutExecutionRoute
}
```

The extension receives only `ShortcutSnapshotReading` and `ShortcutActivationRouting`.

## 8. Android design

### 8.1 Process model

Keep host and IME compatible with both same-process and `android:process` separation. Use one repository abstraction per process. If the IME is placed in a separate process, both sides must use `MultiProcessDataStore`; never mix single-process and multi-process DataStore for the same file.

### 8.2 Storage

Use a typed, immutable Proto DataStore snapshot or bounded JSON serializer behind:

```kotlin
interface ShortcutSnapshotRepository {
    val snapshots: Flow<ShortcutSnapshot>
    suspend fun publish(snapshot: ShortcutSnapshot)
    suspend fun publishTombstone(reason: ShortcutTombstoneReason)
    suspend fun lastKnownGood(): ShortcutSnapshot
}
```

Rules:

- one DataStore instance per file per process;
- serialized transactional update with strictly increasing generation;
- validated immutable value types;
- corruption handler restores empty/last-known-good command-only configuration and emits content-free repair telemetry;
- IME collects the Flow in a service-owned coroutine scope and swaps an in-memory snapshot;
- no DataStore read/write occurs during ordinary key commit;
- tokens use Android Keystore-backed storage outside DataStore; captured content is never persisted.

### 8.3 Field safety

On every `onStartInput` and `onStartInputView`:

- reset activation/capture/result/Undo state;
- derive a new opaque editor session ID;
- inspect `EditorInfo.inputType`, variation, class, flags, and private IME options;
- suppress shortcuts and candidates for password and other sensitive classes;
- handle `TYPE_NULL` as unsupported for complex replacement;
- never store or display passwords in candidate/preview UI.

### 8.4 Execution routing

- Local R0/R1 runs inside the IME through an allowlisted executor.
- Networked R2/R3 may run through a bound app service only after separate lifecycle/security review, or use an explicit host Activity handoff.
- A service route must accept only an authenticated activation/plan digest and bounded explicit capture after acknowledgement; it cannot receive ambient keystroke streams.
- Process death yields cancelled/unknown according to whether a provider call may have crossed the effect boundary; it never assumes success.

## 9. Backend interfaces

The first local foundation does not require backend sync. When account sync is added, use these boundaries:

### 9.1 Layout sync

- `GET /v1/devices/{device_id}/shortcut-layout`
- `PUT /v1/devices/{device_id}/shortcut-layout` with `If-Match: revision`
- server validates owner/device/binding/version and returns a canonical revision/digest;
- conflicts are explicit `409 layout_revision_conflict`; last-write-wins is forbidden.

### 9.2 Execution

- `POST /v1/shortcut-activations/{activation_id}/plan`
- `POST /v1/runs` using existing immutable plan/disclosure contracts;
- `POST /v1/runs/{run_id}/confirm` for risk-required actions;
- `GET /v1/runs/{run_id}/receipt` for reconciliation/result metadata.

Requests bind user, device, session family, Skill/version/digest, snapshot generation, disclosure/capture digest, plan digest, connection/grant epoch, idempotency key, and expiry. The server recomputes capability from authoritative definitions.

## 10. Security requirements

- No dynamic code loading or arbitrary URL execution from a Skill package.
- No shortcut/presentation field is interpolated into a prompt or tool call without typed encoding.
- Snapshot digest uses canonical serialization shared by TypeScript, Swift, and Kotlin golden vectors.
- Signed package/publisher verification is required before public or remote curated Skills; local private Skills remain owner/version bound.
- Host-mediated deep link contains only opaque nonce, route kind, and expiry. No selected text, command, output, connection name, email, or provider resource in URLs.
- Activation nonce is one-time, device-bound, expires in 2 minutes, and is consumed on handoff.
- Captured content is zeroized/released on all terminal and lifecycle invalidation paths as far as managed runtimes permit.
- Logs/analytics allow only opaque IDs, enum states, counts, durations, digests, and error codes.
- Snapshot and activation parsers reject duplicate keys, unknown fields, overlong strings, invalid Unicode/control characters, excessive arrays, digest mismatch, future chronology, and integer overflow.
- A shortcut cannot disable ordinary typing or the keyboard switch control.
- Touch-down on a bound key must not synchronously read disk, call network, or defer the ordinary tap commit while waiting for long press.
- Long press fires at most once, never also commits the character, and is invalidated on editor/session/layout generation change.

## 11. Performance and resource budgets

Budgets must be measured on minimum-supported physical devices and compared with Skill Keys disabled.

| Metric | P95 target | Hard failure |
| --- | ---: | ---: |
| Additional ordinary key handling CPU time | <= 2 ms | > 5 ms |
| Warm bound-key decoration render | <= 100 ms | > 200 ms |
| Cold bound-key decoration render | <= 250 ms | > 500 ms |
| Long-press threshold to local review | <= 100 ms | > 250 ms |
| False Skill activations during 10,000 ordinary taps | 0 | any |
| Snapshot parse + validate, 256 KiB | <= 50 ms off key path | > 150 ms |
| Keyboard-process memory increase from shortcut foundation | <= 8 MiB | > 16 MiB |
| Snapshot refresh dropped ordinary key events | 0 | any |
| Duplicate external execution from repeat tap/retry | 0 | any |

Do not optimize by weakening validation, persisting capture, or moving network work onto the key path.

## 12. Test strategy

### 12.1 Shared unit and property tests

- canonical digest golden vectors across TS/Swift/Kotlin;
- malformed/duplicate/unknown/oversized snapshot rejection;
- generation rollback, device/owner confusion, missing references, duplicate physical keys, invalid/reserved keys;
- Skill version/digest mismatch and silent-upgrade rejection;
- projection capability widening rejection;
- tombstone erasure rules;
- activation editor/generation/version/expiry confusion;
- secure-field policy;
- telemetry content allowlist.

### 12.2 Native unit tests

- snapshot repository atomic publish/read/rollback/corruption;
- notification missed, repeated, reordered, or stale;
- local eligibility derivation for access/network/connection/quota/revocation;
- QWERTY key-code/glyph mapping, Shift/caps invariance, bound-key indicator, and palette order;
- tap types immediately; short hold types; threshold hold invokes once; movement/multi-touch/cancel/editor-change never invokes;
- accessibility names, hints, custom reorder actions, font scaling;
- editor change clears capture, preview, pending handoff, and Undo;
- ordinary typing remains functional under every shortcut failure.

### 12.3 Integration tests

- host creates binding -> publishes generation -> live keyboard refreshes;
- cold keyboard reads last-known-good offline;
- sign-out/account deletion/device revoke tombstones configuration;
- local shortcut full path with stale mutation and Undo;
- connected read with expired/revoked connection;
- confirmed write with duplicate tap, timeout, partial, unknown, reconciliation;
- process kill before request, during request, after provider effect, and before receipt persistence;
- no request before explicit acknowledgement using an instrumented network boundary.

### 12.4 Physical-device matrix

iOS:

- minimum supported iPhone, current small and large iPhone, supported iPad if launch-scoped;
- standard access and Full Access;
- Messages, Mail, Safari, Notes, a document editor, and one app that blocks third-party keyboards;
- secure, phone-pad, one-time-code, rotation, memory pressure, keyboard switching, device restart.

Android:

- minimum API low-memory device, current Pixel-class device, one Samsung-class device;
- messaging, mail, browser, notes, document editor, password manager field;
- process death, service recreation, rotation, locale change, font scale, IME switching, restart.

## 13. Implementation work packages

### W9A: Shared shortcut contracts and policy

Deliver:

- contracts, canonical digests, limits, policy validators, activation state machine;
- migrations/adapters from existing W6 `SkillBinding`;
- adversarial and cross-language golden tests.

Exit:

- shared checks pass;
- no native fixture invents a conflicting schema;
- all capability widening and ownership/version confusion cases fail closed.

### W9B: Native snapshot stores

Deliver:

- iOS App Group provisioning/configuration, host publisher, extension reader, last-known-good;
- Android DataStore repository, host publisher, IME collector, corruption recovery;
- tombstone and migration behavior.

Exit:

- warm/cold/process-death/restart sync passes on physical devices;
- credentials and content are absent from snapshots;
- corrupt publication never blocks typing.

### W9C: Host Skill Keys manager

Deliver:

- keyboard preview and Skill Keys list; `Add To My Keyboard`; QWERTY trigger-key sheet; occupied/reserved/unsupported states; conflict/reassign; disable/remove; detail; upgrade; connection/access states;
- deploy-success and public Skill detail `Add To My Keyboard` paths;
- transactional validation/publish and rollback.

Exit:

- nontechnical test users complete create/install -> choose available letter -> verify on keyboard -> reassign/remove without developer assistance;
- accessibility and localization checks pass.

### W9D: Physical Skill Keys and palette

Deliver:

- tap-to-type/long-press-to-invoke recognizer, subtle assigned-key underline, permanent Command, searchable palette, state badges, and accessible direct activation;
- failure isolation from ordinary typing;
- content-free metrics and performance traces.

Exit:

- ordinary typing budgets and zero false activation pass with 0/2/12/26 physical bindings and 32 palette items;
- shortcut states are accurate offline, signed-out, revoked, expired, and unsupported.

### W9E: Activation router and local execution

Deliver:

- exact activation binding;
- shortcut -> existing Capture Review/Result Preview/Apply/Undo path;
- local R1 executor registry;
- lifecycle invalidation and network-before-ack tests.

Exit:

- selected/surrounding local workflows pass representative third-party apps;
- no silent transmission or stale apply is observed.

### W9F: Connected execution and qualification

Deliver:

- content-free host handoff;
- one production read-only Skill and one separately confirmed write;
- receipts, unknown reconciliation, revocation, kill switch;
- store/privacy declarations and exact-candidate evidence.

Exit:

- external provider/device/security/release gates pass;
- all unsupported surfaces and remaining evidence gaps are accurately documented.

## 14. Code ownership map

| Area | Target path |
| --- | --- |
| Shared contracts | `packages/contracts/src/shortcuts.ts` |
| Shared policy | `packages/policy/src/shortcuts.ts` |
| Shared runtime | `packages/skill-runtime/src/shortcuts.ts` |
| Shared tests | corresponding package test directories |
| iOS models/repository | `apps/ios/Sources/MobileAIKeyboardCore/` |
| iOS host management UI | `apps/ios/MobileAIKeyboardHost/` |
| iOS Skill Keys/runtime | `apps/ios/MobileAIKeyboardExtension/` |
| iOS entitlements/project | `apps/ios/*.entitlements`, `apps/ios/project.yml` |
| Android models/repository | `apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/core/` |
| Android host management UI | Android host Compose packages |
| Android Skill Keys/runtime | `apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/ime/` |

## 15. Migration sequence from current fixtures

1. Add new shared contracts without changing current fixed Command flow.
2. Create adapters that convert current private Skill versions to canonical `ShortcutBindingV1`; reject fixture digests that are not valid production digests.
3. Replace iOS `InstalledSkillBinding` and Android `InstalledSkillBinding` as authorities with native projections of the shared schema.
4. Implement snapshot stores and prove Command-only fallback before adding bound-key UI.
5. Render assigned-key indicators without execution, then prove tap behavior and latency are unchanged.
6. Route one bundled local polite-rewrite Skill through the canonical activation machine.
7. Add host QWERTY assignment/conflict/reassignment/remove and live refresh.
8. Add additional local Skills.
9. Add connected read, then separately confirmed write.
10. Delete legacy fixture binding paths only after migration/rollback tests and one release cycle.

## 16. Definition of done

The foundation is complete when the repository contains one canonical shortcut schema across shared/iOS/Android code, the host app can transactionally publish a user-defined layout, both native keyboards can consume it without slowing ordinary typing, one local Skill completes the full reviewed workflow, permission/sensitive/lifecycle failures fail closed, and physical-device evidence binds all claims to the exact signed candidate.

Until then, `custom keyboard shortcuts`, `host-to-keyboard sync`, `persistence across restart`, and `Acti-class key binding parity` must remain `not_proven` in product claims.

## 17. Platform references

- [Apple custom keyboard open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)
- [Apple custom keyboard interface constraints](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface)
- [Apple App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [Apple shared data overview](https://developer.apple.com/documentation/technologyoverviews/shared-data)
- [Android input method guide](https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method)
- [Android InputMethodService reference](https://developer.android.com/reference/android/inputmethodservice/InputMethodService)
- [Android DataStore and multi-process guidance](https://developer.android.com/topic/libraries/architecture/datastore)
