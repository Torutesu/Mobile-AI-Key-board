# Acti Screenshot Parity Specification

## 1. Purpose and evidence boundary

This document converts the 20 user-supplied Acti screenshots into implementation and acceptance requirements for this repository. The images are visual/interaction references, not embedded product assets and not evidence that every depicted service is operational.

- Reference capture: 20 iPhone screenshots, 1170 x 2532 px, supplied 2026-08-26.
- Target: native iOS host app + keyboard extension and Android host app + IME with equivalent behavior.
- P0 parity means the workflow is real, persisted, and executable. A static screen, fixture-only action, or navigation dead end does not pass.
- Connected provider, public marketplace, analytics, and account claims remain `not_proven` until backed by live services and required release/security evidence.
- Product copy, icons, avatars, Skill names, and branding must be original or properly licensed. Layout and interaction may closely follow the reference.

## 2. Confirmed product model

The screenshots establish this system:

`Discover or build Skill -> choose Public/Private -> configure tools -> build/version -> Add To My Keyboard -> assign available letter -> publish snapshot -> long-press that letter in the keyboard -> review inputs/effects -> execute -> insert/copy/apply`

Normal key taps remain normal typing. The Skill binding is a long-press layer on top of a physical letter key. The app also exposes a keyboard preview and `Skill Keys` list so the hidden gesture is discoverable.

## 3. Screen inventory and required states

| Ref | Screen/state | Required behavior | Priority |
| --- | --- | --- | --- |
| 01 | Assign Trigger Key sheet | Real QWERTY geometry; available, occupied, reserved, selected states; Add disabled until valid; Cancel is lossless | P0 |
| 02 | My Skills | Private/Public tabs; ownership label; active/disabled/error states; open details | P0 |
| 03 | Type-choice transition | Motion can be simplified, but reduced-motion state and deterministic destination are required | P2 |
| 04-05 | Profile/settings home | Profile header; Creator, My Skills, Account, Connected Tools, Keyboard Settings, Community, About; persistent nav | P1 |
| 06-07 | Keyboard Settings | Language, size/position, label weight, caps display, preview, haptics, sounds, correction, prediction, gestures | P1, with unsupported settings labelled |
| 08/17 | Choose Skill Type | Public/Private choice; drag interaction plus tap/accessibility alternatives; explanation of distribution/privacy | P1 |
| 09 | Connected Tools | Active connections; provider catalog; exact scopes/permissions; connect/reconnect/disconnect | P1 |
| 10 | Public Skill Detail | Skill metadata, creator, adds, overview/input token, update history, Add To My Keyboard CTA | P1 |
| 11 | About | Terms, EULA, privacy, OSS licenses, app version; working links | P1 |
| 12 | Account Information | Identity, sign-in method, masked email, member since, linked accounts, account options, logout | P1 |
| 13/18/19 | Skill Builder | Intent input; Apps/APIs/Agents tabs; expandable operations; selection; Build; validation/review | P0 private, P1 connected/public |
| 14 | Creator Center | Skill adds, published Skill count, followers, weekly/monthly/total ranking; source/freshness/empty states | P2 |
| 15-16 | Skills catalog/search | Featured/Latest, search, result/empty/error/offline/pagination; cards open detail | P1 |
| 20 | Keyboard home / Skill Keys | Keyboard preview with bound-key indicators; key-to-Skill list; edit/add; persistent nav | P0 |

## 4. Navigation and information architecture

The host app has four persistent destinations:

1. `Keyboard`: keyboard preview, Skill Keys, keyboard enablement/status.
2. `Skills`: catalog, search, Featured/Latest, Skill detail.
3. `Profile`: profile, My Skills, Creator, account/tools/settings/support.
4. `Create`: modal entry into Public/Private choice and Skill Builder.

Rules:

- The selected destination uses a filled high-contrast container and label for accessibility; icon-only is permitted only when an accessible name is present.
- `Create` is a separate circular action and must not erase the previous tab state on cancellation.
- Deep links from keyboard, account reconnect, public Skill, and notification restore a typed destination, not an arbitrary URL screen.
- Back/cancel is predictable. Unsaved builder or assignment changes require discard confirmation only when data exists.
- Every loading state has skeleton/progress, every list has empty/offline/error/retry states, and fixed bottom CTAs respect keyboard/safe-area insets.

## 5. P0 end-to-end acceptance journey

### 5.1 Install and assign

1. User opens a private or eligible public Skill detail.
2. `Add To My Keyboard` validates immutable Skill version/digest, device, compatibility, required connection, and quota.
3. Trigger sheet displays `A-Z` for `latin_qwerty_v1`.
4. Occupied keys are disabled and expose `Assigned to <Skill>`; reserved/unsupported keys explain why.
5. Selecting an available key updates the highlight and enables Add.
6. Add publishes one atomic snapshot generation. A partial assignment is impossible.
7. Success returns to Keyboard/My Skills and shows both `H` and the full Skill name.
8. The live keyboard refreshes within 2 seconds or on its next open after process death.

### 5.2 Invoke from the real keyboard

1. Touch and release before 450 ms: commit the ordinary character immediately; never invoke.
2. Hold to 450 ms within the movement threshold: provide one haptic cue, do not commit the character, create exactly one activation.
3. Movement beyond 10 pt iOS / 12 dp Android, editor change, multi-touch ambiguity, pointer cancel, secure field, or keyboard dismissal cancels activation.
4. Capture Review shows only Skill-declared sources. No network request occurs merely from key down/hold.
5. Local text Skill produces editable Result Preview; Apply is editor/revision bound and Undo is bounded.
6. Connected write shows account, scopes, recipients/resource, exact effect, cost, version, and canonical confirmation digest before execution.
7. Failed, partial, unknown, stale, offline, revoked, quota, and unsupported outcomes are distinct.

### 5.3 Reassign and remove

- Reassign is transactional: the old key remains active until the new snapshot is valid and published.
- Selecting an occupied key offers explicit swap/reassign; it never silently evicts another Skill.
- Remove deletes only the device binding, not the Skill/version.
- Sign-out, account deletion, or device revocation publishes a tombstone and removes private/connected Skill Keys while preserving ordinary typing.

## 6. Functional requirements

### 6.1 Skill catalog and detail

| ID | Requirement |
| --- | --- |
| ACTI-CAT-001 | Featured/Latest selection is URL/state-restorable and has loading, empty, error, offline, retry, and pagination states. |
| ACTI-CAT-002 | Search debounces locally, cancels stale requests, preserves query on detail return, and announces result count. |
| ACTI-CAT-003 | A card shows Skill name, icon, add count, publisher identity, and publisher Skill count without inventing live metrics. |
| ACTI-CAT-004 | Detail binds name, version, digest, visibility, publisher, safety metadata, overview, declared inputs/tools/output/retention, update history, and install eligibility. |
| ACTI-CAT-005 | `Add To My Keyboard` cannot bypass signature/publisher/version/connection/platform policy. |

### 6.2 My Skills and publishing

| ID | Requirement |
| --- | --- |
| ACTI-MYS-001 | Private and Public tabs use server/authoritative visibility, not only presentation state. |
| ACTI-MYS-002 | Each row shows active, disabled, upgrade required, connection required, revoked, build failed, or moderation state. |
| ACTI-MYS-003 | Editing creates a draft/new immutable version; an installed binding never silently changes digest. |
| ACTI-MYS-004 | Public submission requires signing, moderation, report/revoke/rollback, policy review, and publisher identity. Until implemented it is visibly unavailable or `not_proven`. |

### 6.3 Trigger-key assignment

| ID | Requirement |
| --- | --- |
| ACTI-KEY-001 | Canonical identity is `(layout_id, key_code)`, not screen position, glyph, locale case, or Unicode character. |
| ACTI-KEY-002 | One active device layout has at most one binding per assignable key and one physical key per binding. |
| ACTI-KEY-003 | The picker derives availability from the same validated snapshot that will be published. |
| ACTI-KEY-004 | Add is disabled for no selection, occupied/reserved/unsupported keys, invalid Skill state, stale revision, or publication in progress. |
| ACTI-KEY-005 | Assignment is owner/device/version/digest bound and survives host/keyboard process death and restart. |
| ACTI-KEY-006 | Tap-to-type latency and output are identical within defined budgets with 0, 2, 12, and 26 bindings. |
| ACTI-KEY-007 | Long press fires once, suppresses that pointer sequence's character commit, and enters the same reviewed activation state machine as Command/palette. |
| ACTI-KEY-008 | VoiceOver/TalkBack can enumerate and invoke every Skill without long press; switch control and system keyboard switching remain reachable. |

### 6.4 Builder

| ID | Requirement |
| --- | --- |
| ACTI-BLD-001 | Intent textarea is bounded, saved as draft, and treated as untrusted user data. |
| ACTI-BLD-002 | Apps/APIs/Agents tabs list allowlisted capabilities and exact operations; choosing an app never grants every operation automatically. |
| ACTI-BLD-003 | Build produces a typed draft with inputs, operations/scopes/effects, risk, confirmation, output, retention, fixtures, limits, estimated cost, and version. |
| ACTI-BLD-004 | Private build requires static validation and fixture test before deploy. Public build additionally requires the publishing gates above. |
| ACTI-BLD-005 | Agent/tool output cannot widen requested capabilities; authority is recomputed from selected allowlisted operations. |
| ACTI-BLD-006 | Builder failure retains the draft and selected tools, shows typed issues, and never creates a partial published version. |

### 6.5 Connected Tools

| ID | Requirement |
| --- | --- |
| ACTI-CON-001 | Provider rows show verified provider identity, supported operations, exact scopes, privacy route, and connection state. |
| ACTI-CON-002 | OAuth uses state, nonce, PKCE, exact redirect validation, incremental scopes, owner/device binding, replay protection, and encrypted credential custody outside keyboard storage. |
| ACTI-CON-003 | Connect, reconnect/rebind, disconnect, revoke, expired, partial, and provider-down states are distinct. |
| ACTI-CON-004 | Keyboard snapshot contains only opaque connection ID/state/epoch; never tokens, email, account content, or raw provider metadata. |

### 6.6 Keyboard settings

Settings must be divided into actual capabilities rather than decorative switches:

- Keyboard: language/layout, size/position where platform architecture permits.
- Appearance: label weight, uppercase labels, character preview.
- Feedback: haptics intensity, sounds.
- Input assistance: auto-capitalization, period shortcut, autocorrection, backspace policy, predictive text, next-word suggestions.
- Gestures/keys: slide-to-type and swipe-up numbers.

Each setting declares `supported`, `unsupported_on_platform`, or `planned`. A displayed switch must change persisted runtime behavior. Unsupported platform-native behavior is disabled with explanation, not simulated. Settings sync must never carry typed content and must not block the key path.

### 6.7 Account, legal, creator, community

- Account data comes from authenticated state; email is masked by default; logout publishes the keyboard tombstone before clearing the session.
- Terms, EULA, privacy, and OSS screens use bundled/versioned documents or verified HTTPS links and expose effective date/version.
- Creator metrics declare source, time range, freshness, and zero/empty state. Fixture rankings cannot appear as real analytics.
- Community is P2 and requires moderation/report/block/safety operations; a Discord link alone does not satisfy in-product community.

## 7. Visual specification

### 7.1 Tokens derived from the screenshots

These values are starting targets and must be calibrated by rendered comparison at the original 1170 x 2532 reference size and representative Android sizes.

| Token | Target |
| --- | --- |
| App background | cool blue-grey near `#F1F5FB`, no saturated wash |
| Surface | white/near-white, subtle cool shadow |
| Primary text | near-black `#05070A` |
| Secondary text | neutral grey near `#8C9096` |
| Accent | cyan/blue near `#119CF3`; green only for success/Active |
| Primary CTA | near-black fill, white label |
| Screen horizontal margin | ~60 px at 1170 reference (~20 pt) |
| Large card radius | ~60 px reference (~20 pt) |
| Capsule radius | full pill |
| Row height | ~170-220 px reference depending on content |
| Minimum native target | 44 pt iOS / 48 dp Android |
| Bound-key indicator | 2 pt cyan underline/glow; no letter recolor |

### 7.2 Typography and layout

- Use the product's native tokenized font stack; match the geometric rounded appearance without redistributing proprietary fonts.
- Page titles are strong, mostly centered in detail/settings screens and leading in catalog/home screens.
- Cards use large whitespace, one dominant label, muted metadata, and clear chevrons/actions.
- Bottom navigation and fixed CTA are translucent/solid floating surfaces above the safe area; scrolling content must remain reachable behind neither.
- Support Dynamic Type/font scale, Japanese line breaking, RTL where applicable, dark mode before public release, and reduced motion.

### 7.3 Motion

- Type chooser may use the reference pearl/orb drag, but tap buttons and accessibility actions are mandatory.
- Spring/morph motion must never delay navigation state, obscure text, or exceed reduced-motion preferences.
- Loading/transitional frames cannot become blank dead-end screens like references 03/17 if interaction fails.

## 8. Current repository gap assessment

| Capability | Current evidence | Required disposition |
| --- | --- | --- |
| Local Command -> review -> result -> apply/undo | Implemented native/shared foundation | Reuse as activation destination |
| Skill definition/version/digest/binding fixtures | Implemented shared/native fixtures | Adapt into canonical trigger-key snapshot |
| Keyboard Skill Keys | Implemented local iOS/Android foundation; device lifecycle not qualified | P0 device qualification remains |
| Trigger-key picker/conflict UI | Implemented A-Z add/reassign/remove, searchable Skills, occupied-key selection, explicit Swap/Replace, and save-before-test fixture preview | P0 interaction and Simulator visual QA implemented; physical-device accessibility/lifecycle QA continues |
| Host -> iOS extension persistence | App Group publisher/last-known-good reader configured; production provisioning not proven | P0, `not_proven` until device-qualified |
| Host -> Android IME persistence | Content-free active/last-known-good shared app preferences implemented | P0, process-death/device qualification remains `not_proven` |
| Skills catalog/search/detail | Not implemented as live product | P1 |
| My Skills private/public management | Partial private fixtures | P0 private; P1 public state |
| Builder | Fixture surface/contracts exist | Connect to persistence/version/deploy/assignment |
| Connected Tools | Provider-neutral contracts/fixtures | Live OAuth/provider remains `not_proven` |
| Keyboard settings | Partial fixture settings | Every visible control must reach runtime or be labelled unsupported |
| Account/About/Profile | Partial fixture surfaces | Restyle and bind to authenticated/legal state |
| Creator/community | Contract/fixture foundation only | P2; no live claims |

## 9. Implementation slices

1. `Parity contract`: canonical `TriggerKeyBinding`, layout, snapshot, validator, golden vectors, conflicts, tombstones.
2. `Native persistence`: iOS App Group publisher/reader and Android DataStore publisher/collector with last-known-good.
3. `Skill Keys management`: Keyboard tab, preview, list, trigger picker, add/reassign/remove, My Skills state.
4. `Keyboard runtime`: bound-key indicator; tap/hold gesture machine; accessible action; activation routing; fault isolation.
5. `Local vertical slice`: one bundled rewrite/translation Skill through capture/review/result/apply/undo in real third-party editors.
6. `Builder integration`: private build/version/test/deploy then immediate assignment.
7. `Catalog/detail`: curated signed catalog, search, detail, install/update/revoke; public submission remains gated.
8. `Connected tools`: live read-only provider first, then separately confirmed write after qualification.
9. `Settings/account/legal`: runtime-backed controls, auth state, legal documents, privacy disclosures.
10. `Creator/community`: only after authoritative analytics and moderation infrastructure exist.

## 10. Verification and definition of done

Visual verification:

- Render every implemented reference state at iPhone 1170 x 2532 equivalent plus minimum/large supported devices.
- Compare side-by-side for hierarchy, margins, typography, card radii, fixed CTA/nav, safe areas, keyboard overlap, empty/error states, and Japanese text.
- Run accessibility contrast, Dynamic Type/font scale, VoiceOver/TalkBack, reduced motion, and touch-target checks.

Behavioral verification:

- Shared contract/property/adversarial tests and cross-language canonical vectors pass.
- 10,000 normal taps over assigned/unassigned keys produce zero Skill activations and no dropped/duplicated characters.
- Short/threshold/long/moved/cancelled/multi-touch/editor-change gesture tests pass on physical iPhone and Android devices.
- Assignment and removal survive host/keyboard process death, reboot, locale/case changes, offline state, and snapshot corruption.
- No network occurs before explicit capture acknowledgement; connected writes remain digest-confirmed and receipt-bound.
- Representative Messages/Mail/browser/notes/document apps pass, while secure/blocked/phone-pad surfaces report honest limitations.

The screenshot-parity foundation is done only when a tester can discover or build a Skill, install it, choose an available letter, see it in Skill Keys, invoke it by long press in a third-party text field, review and apply the result, reassign/remove it, and repeat after process death/restart. Until physical-device evidence binds that journey to the exact signed candidate, `Acti-style letter shortcuts work` remains `not_proven`.
