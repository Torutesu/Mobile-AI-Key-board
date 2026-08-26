# Keyboard Shortcut Platform: Product Requirements

## 1. Document status

- Status: implementation-ready product requirement baseline
- Scope: iOS host app + keyboard extension, Android host app + IME, shared contracts, and the minimum backend interfaces needed for cross-device Skill metadata
- Reference horizon: public Acti product surfaces plus 20 user-supplied 1170 x 2532 screenshots inspected on 2026-08-26
- Product boundary: ordinary typing remains the primary product. Shortcuts add an explicit action layer; they never silently observe or execute from normal typing.
- Current implementation boundary: the repository has private Skill/binding fixtures and one fixed AI command entry, but it does not yet have persisted user-configurable physical key bindings, host-to-keyboard runtime sync, or a long-press activation router.

## 2. Product decision

Build shortcuts as a first-class platform primitive with an Acti-parity physical-key presentation.

The user installs a Skill, assigns one available QWERTY letter, and publishes a `TriggerKeyBinding` from the host app. The keyboard receives a sanitized immutable `ShortcutSnapshot`. A normal tap on that key always types the character; a deliberate long press activates the assigned Skill. The keyboard may also provide Command and a palette as accessible/discoverable fallbacks, but neither replaces physical letter-key assignment. Activation creates a `ShortcutActivation` bound to the exact Skill version, key binding, snapshot generation, and current editor context, then enters Capture Review -> Preview -> Apply/Confirm.

This preserves Acti-class speed while avoiding three weaknesses visible in the reference category:

1. a normal tap must retain the ordinary character meaning and timing of every bound key;
2. sensitive text must not be transmitted merely because a shortcut is visible or touched;
3. network or connected-account Skills must not run before the user sees the exact inputs, services, and effects.

## 3. Goals and non-goals

### 3.1 Goals

- A nontechnical user can create or install a Skill and place it on the keyboard without code.
- A shortcut is available in any compatible text field after configuration, without reopening the host app.
- Assigned keys are discoverable, work with one hand and assistive technology, and do not degrade ordinary typing.
- Every activation is bound to one immutable Skill version/digest and one editor session.
- The user reviews the exact source data before any network request or external action.
- R0/R1 local text actions can complete entirely inside the keyboard process.
- R2/R3 connected actions use explicit permission, confirmation, and receipt flows.
- Configuration survives process death, restart, and ordinary app/keyboard switching after physical-device qualification.

### 3.2 Non-goals for the first release

- Replacing Japanese conversion, autocorrect, prediction, dictation, or emoji infrastructure.
- Running Skills from passive analysis of every keystroke.
- Executing arbitrary downloaded code, JavaScript, shell commands, or unsigned plugins.
- Background execution after the keyboard is dismissed.
- Claiming support in secure fields, phone-pad fields, or apps that prohibit third-party keyboards.
- Unmoderated public marketplace publishing. The catalog and public/private information architecture are required for parity, but public submission remains gated by signing, moderation, reporting, revocation, and rollback.
- Multi-step autonomous agents that can widen tools, scopes, recipients, or effects at runtime.

## 4. Reference findings and design response

The complete screenshot-to-screen/state/acceptance mapping is maintained in `docs/21-acti-screenshot-parity.md`. If a summary in this document conflicts with an interaction clearly established by the supplied screenshots, document 21 and the physical-key requirements below take precedence.

### 4.1 Observed reference behavior

Acti publicly describes:

- an Acti Bar that is pressed for typing and held to invoke an action;
- the sequence Type -> Hold -> Preview -> Apply;
- a Skill Builder that converts plain-language intent into prompt, tools, and output;
- binding a Skill to a key for one-tap access;
- private or public Skill distribution through a Skill Hub;
- connected tools and APIs that return text, links, or actions into the active field.

Public feedback is still sparse and partly promotional. The highest-signal concerns found were slower tap typing than the default keyboard, visual noise when letter keys become Skill keys, friction when switching keyboards, and the privacy/trust cost of full keyboard/network access. These are directional signals, not statistically representative findings.

### 4.2 Product response

| Reference pattern | Foundation decision | Beyond-parity decision |
| --- | --- | --- |
| Hold a central bar to act | Keep the existing fixed Command entry as a universal fallback | Preserve Capture/Preview and provide an accessible non-hold alternative |
| Bind Skills to letter keys | Persist an exact `trigger_key` independently from Skill identity | Tap types; long press invokes; subtle underline is presentation only |
| Preview before apply | Reuse Capture Review and Result Preview | Show data, services, scopes, effect, cost, and Skill version in one Trust Preview |
| Networked action from keyboard | Permit only after explicit activation and source review | Host-mediated execution is the default for sensitive/connected actions |
| Skill community | Keep private Skills and curated packs first | Add signed packages, publisher verification, safety metadata, and rollback before public distribution |

## 5. Primary users and jobs

### 5.1 Mobile operator

Uses messaging, mail, browser, calendar, notes, and work apps. Wants to complete small tasks without context switching.

Jobs:

- rewrite or translate selected text;
- create and paste a meeting link;
- search a connected knowledge source and paste a source-linked answer;
- reuse a personal workflow with predictable inputs and output;
- know what will be sent and what will change before approval.

### 5.2 Skill creator

Wants to describe a repeatable workflow, test it, pin a version, and make it reachable from the keyboard.

Jobs:

- define purpose, inputs, tools, output, retention, and fixtures;
- choose an icon and short accessible label;
- assign, reorder, disable, upgrade, or remove a shortcut;
- inspect usage, failures, permissions, and version changes.

## 6. Core user journeys

### J1: Create and assign a private Skill

1. User opens Skill Builder in the host app.
2. User describes the desired outcome.
3. Builder produces a typed draft and names every requested input, tool, scope, effect, output, and retention rule.
4. Static and fixture tests pass.
5. User reviews and deploys immutable private version `vN`.
6. `Add To My Keyboard` opens the trigger-key sheet using the real QWERTY geometry.
7. Occupied/reserved/ineligible keys are disabled and identify the conflicting Skill; the user selects one available letter and confirms `Add`.
8. Host publishes a new `ShortcutSnapshot` atomically.
9. Keyboard loads the new snapshot, marks the assigned key with a subtle accent, and lists the Skill under `Skill Keys` without requiring account credentials in the keyboard process.

Acceptance: a new shortcut becomes visible within 2 seconds while the keyboard remains alive, and on the next keyboard open after process death.

### J2: Run a local text shortcut

1. User selects text or places the cursor in a compatible field.
2. User long-presses the assigned letter; releasing before the threshold remains ordinary typing.
3. Keyboard opens Capture Review with only sources declared by that Skill.
4. User acknowledges the capture.
5. Local execution produces an editable Result Preview.
6. User applies or copies the result.
7. Apply is rejected if the field fingerprint or selection changed.
8. A bounded one-shot Undo is offered.

Acceptance: no network API is reachable in this path; the output cannot be applied without a matching editor/revision binding.

### J3: Run a connected read shortcut

1. User long-presses the assigned letter for `空き時間` or activates the equivalent accessible action.
2. Trust Preview shows selected/surrounding input, Calendar account, exact read scopes, expected output, and no-write effect.
3. If the connection is missing or expired, the keyboard offers `アプリで接続` and preserves a content-free pending intent only.
4. User explicitly runs the Skill.
5. The result includes source and freshness metadata.
6. User inserts or copies it.

Acceptance: the Skill cannot widen scopes; provider content cannot add tools or authority; failed/partial/unknown remain distinct.

### J4: Run a connected write shortcut

1. User long-presses the assigned letter for `予定を作成` or activates the equivalent accessible action.
2. Keyboard gathers only declared sources and opens an exact action review.
3. Review names the account, resource, date/time/time zone, effect, invitation behavior, cost, and Undo availability.
4. User confirms a canonical digest.
5. Execution returns a receipt with succeeded/failed/partial/unknown.
6. Unknown cannot be blindly retried; reconciliation is required.

Acceptance: no external effect occurs before digest-bound confirmation; execution is owner/device/grant/epoch/idempotency bound.

### J5: Manage Skill Keys

1. User opens the Keyboard tab or `Keyboard Settings -> Skill Keys` in the host app.
2. User sees a keyboard preview plus a list such as `H — 画面翻訳` and `M — Mag 7`, then reassigns, disables, or removes a binding.
3. Conflicts, unavailable Skills, revoked connections, and required upgrades are visible before save.
4. Save publishes all key bindings as one new snapshot generation; two active Skills can never own the same physical key.

Acceptance: partial writes never produce a mixed old/new layout; rollback can restore the last valid generation.

## 7. Interaction model

### 7.1 Keyboard surfaces

The keyboard has four action surfaces:

1. `Command`: permanent entry to a natural-language command flow. This is never removable.
2. `Skill Keys`: user-selected QWERTY letters whose tap behavior is unchanged and whose long press invokes the assigned Skill.
3. `Skill list/palette`: searchable, name-first fallback for discovery, accessibility, unassigned Skills, and compact layouts.
4. `Candidate/action rail`: optional result/candidate surface; it is not the canonical binding mechanism.

Default behavior:

- supported assignable keys are locale/layout specific; the first English implementation uses `A-Z` and publishes the exact layout ID;
- tap commits the ordinary character with no wait for the long-press timeout;
- long press arms after 450 ms by default, is cancelled by movement beyond 10 pt/12 dp, field change, pointer cancellation, multi-touch ambiguity, or key release before the threshold;
- the Skill begins only once per pointer sequence and must not also commit the letter;
- Shift/caps changes the typed character label, not the binding identity; `H` and `h` are one physical binding;
- delete, shift, space, return, globe/language, emoji, symbols, dictation, and system-reserved keys are never assignable in v1.

### 7.2 Shortcut states

Each shortcut renders exactly one of:

- `ready`: executable under the current field and local configuration;
- `review_required`: ready but data/effect review is required;
- `connection_required`: host app handoff needed;
- `full_access_required`: iOS network/shared-write capability is unavailable;
- `unsupported_field`: secure/password/OTP/payment/phone-pad/blocked editor;
- `upgrade_required`: bound version revoked or incompatible;
- `offline`: network execution unavailable; local Skills remain usable;
- `quota_blocked`: limit reached before execution;
- `disabled`: visible only in management UI;
- `loading`: snapshot is being validated; Command and typing remain available.

### 7.3 Gestures

- Tap an assigned letter: type normally and never execute a Skill.
- Long press an assigned letter: open Capture/Trust Preview; never perform a network/external effect immediately.
- Long press an unassigned letter: preserve the platform keyboard's existing alternate-character behavior where supported.
- Accessible Skill list action: invokes the same activation path without requiring a hold.
- Tap Command: open natural-language command entry.
- Accessible alternative: every hold/long-press action has a visible button or accessibility custom action.
- Haptics: light on opening review; success only after local apply or confirmed external success; warning on stale/blocked state.

### 7.4 Visual and accessibility constraints

- Never change tap meaning or hit target of alphabet keys. A bound key may use the screenshot-derived 2 pt accent underline/glow, but color cannot be the only indication.
- Minimum touch target: 44 x 44 pt on iOS, 48 x 48 dp on Android.
- Management surfaces show both the physical letter and full Skill name; assistive labels announce `H、画面翻訳、長押しで実行`.
- VoiceOver/TalkBack announces: name, state, risk/effect summary, and action hint.
- Reordering exposes Move before/after actions in addition to drag.
- Dynamic Type / font scale may reduce visible slots but must not truncate the only accessible name.
- Color is never the sole indicator of state.

## 8. Functional requirements

Priority meanings: P0 is required for internal dogfood; P1 for Acti-class beta; P2 for beyond-parity expansion.

### 8.1 Definition and binding

| ID | Priority | Requirement | Acceptance |
| --- | --- | --- | --- |
| KS-001 | P0 | A binding references an immutable Skill version and digest. | Any version/digest mismatch fails closed and the shortcut cannot run. |
| KS-002 | P0 | Binding identity is separate from presentation slot. | Reordering does not change `binding_id` or Skill version. |
| KS-003 | P0 | The host app is the sole layout writer. | Extension/IME cannot mutate canonical layout or silently upgrade a version. |
| KS-004 | P0 | User can add, remove, enable, disable, and reorder bindings. | Saved operations survive process death and reload in the keyboard. |
| KS-005 | P0 | Duplicate active positions and duplicate activation aliases are rejected. | Save shows a conflict and does not publish a partial snapshot. |
| KS-006 | P1 | User can choose icon, short label, and accessible label from allowlisted presentation values. | Invalid asset identifiers or blank labels are rejected. |
| KS-007 | P1 | A revoked or incompatible Skill enters `upgrade_required`; it never silently upgrades. | Explicit review installs a new exact version/digest. |
| KS-008 | P1 | Per-device layout is supported; account default may seed a new device. | One device's local order does not unexpectedly overwrite another. |

### 8.2 Snapshot and sync

| ID | Priority | Requirement | Acceptance |
| --- | --- | --- | --- |
| KS-020 | P0 | Host publishes one immutable, canonical snapshot containing sanitized bindings and layout. | Reader sees either generation N or N+1, never a mixed generation. |
| KS-021 | P0 | Snapshot is schema-versioned, generation-monotonic, digest-bound, and size-bounded. | Invalid schema/digest/generation/size falls back to last-known-good. |
| KS-022 | P0 | Keyboard startup reads locally with no mandatory network call. | Cold keyboard render succeeds offline with last-known-good configuration. |
| KS-023 | P0 | Credentials, tokens, raw test fixtures, prompts, receipt content, and account PII are excluded. | Automated snapshot scan rejects prohibited fields and values. |
| KS-024 | P0 | Keyboard refresh is notification-assisted and foreground/open validated. | Lost notification still converges on next open or foreground. |
| KS-025 | P1 | Host can roll back to the previous valid generation. | Corrupt/current generation is quarantined and prior layout loads. |
| KS-026 | P1 | Account deletion and sign-out publish a sanitized tombstone snapshot. | Private/connected bindings disappear; ordinary preferences remain per policy. |

### 8.3 Activation and execution

| ID | Priority | Requirement | Acceptance |
| --- | --- | --- | --- |
| KS-040 | P0 | Activation captures binding ID, exact Skill version/digest, snapshot generation, editor session, and activation time. | Changed generation/version/editor invalidates apply or external confirmation. |
| KS-041 | P0 | Tap opens review; it does not silently transmit text or invoke a tool. | Network spy records zero requests before explicit acknowledgement/run. |
| KS-042 | P0 | Only sources declared by the Skill are offered, defaulting off except explicit selection initiated by the user. | Undeclared source access is rejected by policy and native adapter. |
| KS-043 | P0 | Secure/password/OTP/payment-card inputs suppress all AI/Skill capture and execution. | Keyboard exposes ordinary safe input only; buffers and pending activation are cleared. |
| KS-044 | P0 | Local R0/R1 Skills use the existing revision-safe Preview/Apply/Undo path. | Entity preservation, stale-field, result revision, and undo tests pass. |
| KS-045 | P1 | R2/R3 execution uses exact tool/scope/effect contracts and risk-based confirmation. | Authority widening or digest mismatch fails before provider invocation. |
| KS-046 | P1 | If host handoff is required, only an opaque, expiring pending intent crosses the boundary. | Source/output content is not placed in a URL or OS notification. |
| KS-047 | P1 | All outcomes are succeeded, partial, failed, unknown, or cancelled. | Unknown cannot be displayed as success or retried without reconciliation policy. |
| KS-048 | P1 | Every provider effect produces a content-free durable receipt. | Receipt binds run, Skill, plan, owner, device, provider operation, and outcome. |

### 8.4 Reliability and typing protection

| ID | Priority | Requirement | Acceptance |
| --- | --- | --- | --- |
| KS-060 | P0 | Shortcut subsystem failure cannot block ordinary typing, delete, shift, space, return, or keyboard switching. | Fault-injection disables Skill activation/decoration and preserves normal input. |
| KS-061 | P0 | No synchronous disk or network I/O occurs on the key tap/commit path. | Instrumented P95 overhead for ordinary key handling is <= 2 ms versus Skill-Keys-disabled baseline. |
| KS-062 | P0 | Snapshot parsing occurs off the ordinary key path and is cached in memory. | Large-valid snapshot does not cause dropped key events during refresh. |
| KS-063 | P0 | Pending activation and captured content are cleared on editor change, secure transition, keyboard dismissal, timeout, or process death. | Lifecycle tests observe no stale content restoration. |
| KS-064 | P1 | Rail first meaningful render is <= 100 ms warm and <= 250 ms cold from keyboard view creation on target devices. | Physical-device trace meets P95 budget. |
| KS-065 | P1 | Shortcut tap-to-review is <= 100 ms for local metadata and shows progress after 150 ms for heavier preparation. | Physical-device UI trace meets P95 budget. |
| KS-066 | P1 | Crashes, corruption, and repeated execution failures trip a Skill-activation-only kill switch. | Ordinary typing remains active and a recoverable error is shown. |

### 8.5 Privacy, permissions, and trust

| ID | Priority | Requirement | Acceptance |
| --- | --- | --- | --- |
| KS-080 | P0 | Normal keystrokes are never telemetry, snapshot, receipt, or diagnostic fields. | Static allowlists and traffic capture prove content-free telemetry. |
| KS-081 | P0 | Review enumerates data classes and character counts before transmission. | User can cancel without any content leaving the device. |
| KS-082 | P0 | iOS without Full Access remains a useful local keyboard with local Skills; unavailable connected Skills explain why. | No coercive blanket prompt; local route remains usable. |
| KS-083 | P0 | Android password fields suppress capture, candidate content, previews, logging, and storage. | Password-field adversarial test observes no content outside target editor. |
| KS-084 | P1 | Connected scopes are granted incrementally per tool/Skill and can be revoked in the host. | Revocation invalidates cached eligibility on next snapshot refresh. |
| KS-085 | P1 | Clipboard and location are opt-in runtime sources, never implicit ambient context. | Trigger without source acknowledgement cannot read either source. |
| KS-086 | P1 | Every shortcut detail screen shows local/network classification, inputs, tools, risk, retention, and version. | Information matches the bound Skill contract digest. |

## 9. Information architecture in the host app

Add a top-level `Keyboard` area with:

- `Keyboard / Skill Keys`: keyboard preview, key-to-Skill list, add/reassign/remove, disabled section, and live keyboard status.
- `All Skills`: private Skills and curated packs with eligibility and connection badges.
- `Shortcut detail`: presentation, exact version, data sources, tools, scope, risk, retention, quota, test status, last update, disable/remove/upgrade.
- `Keyboard access`: iOS Full Access explanation or Android IME enablement status with local-versus-network capability matrix.
- `Privacy`: normal typing guarantee, per-Skill data flow, connection revocation, receipts, retention, deletion.

The Skill Builder's deploy success screen must offer `Add To My Keyboard`; deployment and assignment remain separate actions so a Skill can exist without occupying a physical key.

## 10. Empty, error, and recovery states

- No shortcuts: show Command plus `ショートカットを追加` in the host; keyboard overflow opens a short explanation, not a dead end.
- Snapshot corrupt: load last-known-good and mark configuration repair needed in host.
- No last-known-good: show Command only; never block typing.
- Account signed out: local bundled Skills may remain if policy allows; owner-bound/private/connected Skills are removed.
- Skill revoked: retain its position as disabled for one generation so the user sees why it disappeared, then allow removal/upgrade.
- Connection expired: shortcut opens a no-content handoff to reconnect.
- Network offline: local shortcuts remain enabled; connected shortcuts show offline before capture.
- Quota exceeded: show reset time/cost class in host; never capture content that cannot be processed.
- Host app missing/unavailable: keyboard continues with last-known-good local configuration and Command fallback.

## 11. Success metrics

All metrics are content-free and opt-in/region-appropriate.

### Product

- shortcut assignment completion rate;
- time from private Skill deploy to first successful keyboard run;
- shortcut activation -> preview completion rate;
- preview -> apply/copy/confirm rate by risk class;
- shortcut reorder/remove/disable rate;
- connection-required handoff completion rate.

### Quality and trust

- ordinary key latency delta with Skill Keys enabled;
- bound-key decoration and snapshot cold/warm render latency;
- stale-apply rejection rate;
- unknown/partial outcome rate;
- crash-free keyboard sessions;
- fallback-to-Command/last-known-good rate;
- Full Access explanation view -> user decision, without treating denial as failure;
- privacy cancellation rate before transmission.

No metric may include command text, selected/surrounding text, output, clipboard data, field labels, app content, contact identifiers, or connected resource names.

## 12. Release acceptance

Acti-class shortcut parity is achieved only when all of the following are proven on physical iPhone and Android devices:

1. create/deploy/assign/reorder/disable/remove/upgrade private Skills;
2. host-to-keyboard snapshot sync across warm process, cold process, restart, and lost notification;
3. local shortcut Capture Review -> Preview -> Apply -> Undo in representative messaging, mail, browser, notes, and document editors;
4. secure/password/OTP/payment/unsupported-field suppression;
5. no regression against ordinary typing latency, dropped keys, crash, memory, rotation, and keyboard switching budgets;
6. no network before explicit activation and acknowledgement;
7. connected read and one confirmed write with exact scopes, receipts, unknown reconciliation, revocation, and expiry;
8. accessibility at supported text/font scales and one-handed layouts;
9. signed release artifact, privacy manifest/data-safety declaration, and exact-candidate traffic evidence;
10. all absent external/device/provider evidence remains explicitly `not_proven`.

## 13. Research source map

### Primary product sources

- [Acti homepage](https://openacti.com/): Acti Bar positioning, shortcut/Skill imagery, connected tools/APIs, and the programmable-keyboard thesis.
- [What is the Acti Bar?](https://openacti.com/acti-bar/): Type -> Hold -> Preview -> Apply workflow and the claim that the bar is the persistent action control.
- [What is Skill Builder?](https://openacti.com/acti-skill-builder/): plain-language Skill creation and explicit key binding.
- [What is the Skill Hub?](https://openacti.com/acti-skill-hub/): private/public distribution and marketplace model.
- [Acti Privacy Policy](https://openacti.com/privacy/): explicit Skill invocation, configured input sources, connected-tool permissions, and network access claims.
- [Apple App Store listing](https://apps.apple.com/us/app/acti-agentic-keyboard/id6745523677): current iOS distribution and public positioning.
- [Google Play listing](https://play.google.com/store/apps/details?id=ltd.xyzer.app.bongocat): current Android distribution and public positioning.

### Platform sources

- [Apple: Configuring open access for a custom keyboard](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard): default sandbox, Full Access, shared-container/network capabilities, and keyboard data responsibilities.
- [Apple: Configuring a custom keyboard interface](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface): secure fields, phone-pad fields, and apps that disallow third-party keyboards.
- [Apple: Configuring app groups](https://developer.apple.com/documentation/xcode/configuring-app-groups): host/extension shared-container configuration.
- [Android: Create an input method](https://developer.android.com/develop/ui/views/touch-and-input/creating-input-method): IME lifecycle, `InputConnection`, input types, and password handling.
- [Android: DataStore](https://developer.android.com/topic/libraries/architecture/datastore): immutable transactional storage and multi-process requirements.

### Public feedback searched

- Acti's public subreddit, launch/community discussions, App Store, Google Play, Product Hunt coverage, and recent reviews were searched for shortcut, typing, permission, privacy, reliability, and workflow issues.
- Signal was weak because the product was recently launched and many posts were authored by or closely associated with its team. The reported latency, visual-noise, switching, and privacy concerns therefore informed risk prioritization but are not treated as prevalence estimates.

### Evidence separation

- Statements in section 4.1 are observations from the cited product/public sources.
- The physical-key binding model, optional palette, host-writer model, sanitized snapshot, host-mediated routing, performance budgets, and all requirements are design decisions for this repository informed by the supplied screenshots.
- Claims about current repository implementation are based on the checked-in source and `docs/08-implementation-status.md`, not on Acti's behavior.
