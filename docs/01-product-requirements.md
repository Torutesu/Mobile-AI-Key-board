# Product Requirements

## 1. Requirement language

`MUST` is release-blocking. `SHOULD` is expected unless a documented trade-off is accepted. `MAY` is optional.

## 2. Capability map

| Area | Parity requirement | Beyond-parity requirement |
|---|---|---|
| Typing | Full keyboard, autocorrect, languages, symbols, clipboard | Stable latency budget, one-handed mode, per-language tuning |
| Invocation | Hold action control or invoke bound Skill | Local intent suggestions without transmitting text |
| Context | Typed intent, selection, explicit clipboard | Field-aware bounded context with visible disclosure |
| AI | Generate, rewrite, translate, summarize | Entity preservation and evidence-aware outputs |
| Tools | OAuth connectors and tool calls | Risk policy, dry-run, receipts, undo |
| Skills | Create, edit, bind, clone | Typed schemas, test cases, versioning, approvals |
| Community | Discover and install Skills | Verified publishers and safety metadata |
| Trust | Privacy explanation and explicit trigger | Exact data/tool/side-effect preview |

## 3. Functional requirements

### 3.1 Keyboard foundation

- `KB-001` The keyboard MUST insert, delete, capitalize, change layout, move between supported input modes, and expose the OS-required keyboard switch control.
- `KB-002` Normal keystrokes MUST be handled locally and MUST NOT depend on authentication, network availability, quota, or backend health.
- `KB-003` Password, one-time-code, phone-pad, and declared sensitive fields MUST disable AI capture and MUST show a concise explanation when appropriate.
- `KB-004` The keyboard MUST preserve the active text field and cursor when opening and closing its action surface.
- `KB-005` The initial supported typing modes are Japanese, English, numbers, symbols, emoji, and explicit clipboard paste. Japanese conversion MAY initially rely on an adopted, license-compatible engine rather than a new engine.
- `KB-006` Users MUST be able to adjust height, handedness, haptics, sound, key label weight, and action-control placement.
- `KB-007` The keyboard MUST remain usable offline for ordinary typing.

### 3.2 Invocation and input capture

- `IN-001` A long press on the action control MUST enter Command mode; an ordinary tap MUST retain its normal typing meaning.
- `IN-002` Users MUST be able to invoke a bound Skill directly from a visible shortcut surface without writing a prompt.
- `IN-003` Every run MUST declare its input sources: command, selected text, surrounding text, clipboard, current date/time, locale, or location.
- `IN-004` Clipboard, location, and surrounding text MUST be opt-in per run unless a user has explicitly saved a narrowly scoped default for that Skill.
- `IN-005` The keyboard MUST show the exact text or a locally generated redacted preview before network transmission.
- `IN-006` Context capture MUST have hard character and token limits. Default surrounding-text limit: 1,000 characters before and 500 after the cursor.
- `IN-007` If the host app does not expose selected or surrounding text, the UI MUST fall back to typed command or clipboard and explain the limitation.

### 3.3 Planning and text results

- `AI-001` Every request MUST produce a typed plan before tools execute.
- `AI-002` Text-only plans MAY execute after one explicit invocation if they do not access external private data.
- `AI-003` Generated results MUST provide Preview, Apply, Edit, Regenerate, Copy, and Cancel where the platform permits.
- `AI-004` Rewrite and translation Skills MUST protect detected names, numbers, dates, URLs, email addresses, handles, product names, and user-locked spans.
- `AI-005` Outputs containing unsupported factual claims MUST state their source or uncertainty when the Skill is configured for factual retrieval.
- `AI-006` Cancellation MUST stop visible streaming and prevent any not-yet-started tool operation.
- `AI-007` The model MUST never be treated as the final authority for permissions, risk class, tool arguments, or whether confirmation can be skipped.

### 3.4 Connected tools and actions

- `AC-001` OAuth connections MUST be created in the companion app or an OS-secured authorization session, never inside an untrusted embedded page.
- `AC-002` Tokens MUST remain server-side or in OS secure storage and MUST NOT be exposed to the keyboard extension or model.
- `AC-003` The execution engine MUST validate every planned tool call against a server-owned schema, user identity, connection, allowed scopes, and risk policy.
- `AC-004` Read-only actions MUST be visually distinct from writes.
- `AC-005` Write actions MUST show target, payload summary, side effects, reversibility, and confirmation requirement.
- `AC-006` The MVP MUST prohibit delete, payment, credential, permission-change, bulk-send, and irreversible account actions.
- `AC-007` Every write MUST use an idempotency key and produce an immutable action receipt.
- `AC-008` A partial multi-tool failure MUST identify completed, failed, and not-started steps. It MUST NOT claim all-or-nothing success unless transactional semantics are proven.
- `AC-009` Retrying a completed request MUST not duplicate external side effects.

### 3.5 Skills

- `SK-001` A Skill MUST have a name, description, version, owner, trigger, input schema, output schema, allowed tools, risk ceiling, confirmation policy, retention policy, and test examples.
- `SK-002` Skill Builder MUST generate a draft Skill, not deploy it immediately.
- `SK-003` A draft MUST pass schema validation, policy validation, static prompt-injection checks, and at least one user-visible test before activation.
- `SK-004` Binding a Skill to a key MUST detect conflicts with typing, accessibility, and existing bindings.
- `SK-005` Updating a Skill MUST create a new immutable version and MUST NOT silently change installed copies.
- `SK-006` Community Skills MUST display publisher, requested connectors/scopes, data inputs, risk class, version, last review date, installs, completion rate, and reported issues.
- `SK-007` Public publishing remains disabled until moderation, reporting, revocation, signature, and version rollback are implemented.

### 3.6 Companion app

- `APP-001` The app MUST guide users through install, keyboard enablement, Full Access explanation, safe test field, account creation, and first successful Skill.
- `APP-002` The app MUST show keyboard status, network access status, enabled languages, connected tools, usage, Skills, receipts, privacy controls, and support.
- `APP-003` Users MUST be able to disconnect a tool, revoke all sessions, export their data, and delete their account.
- `APP-004` Account deletion MUST revoke server sessions and tool authorizations where supported and provide an honest completion state.
- `APP-005` The app MUST provide a local sandbox that demonstrates capture, preview, apply, and receipt behavior without requiring another app.

## 4. Initial connector scope

Release 1 connectors:

- Google Calendar: availability read, event draft/create after confirmation.
- Google Meet: create meeting details as part of a confirmed calendar event.
- Notion: search authorized pages and return title plus link; no page mutation initially.
- Maps: place search and map link generation using public or user-authorized location.

Deferred:

- Gmail and Slack writes, because recipient and representational-communication risks require stronger confirmation and audit UX.
- LINE account integration; initial LINE support is insertion into its active text field only.

## 5. Risk classes

| Class | Meaning | Examples | Confirmation |
|---|---|---|---|
| R0 | Local-only | keyboard settings, local snippet | none |
| R1 | Text processing | rewrite, translate selected text | invocation plus data preview |
| R2 | External read | calendar availability, Notion search | first use and scope change |
| R3 | Reversible draft/write | create uninvited calendar draft | explicit per execution |
| R4 | External communication | invite guests, send email/message, publish | explicit enhanced confirmation; post-MVP |
| R5 | Destructive/high stakes | delete, payment, credentials, permissions | prohibited in keyboard MVP |

## 6. Analytics events

Allowed event fields are enumerated; arbitrary payloads are prohibited.

- `keyboard_opened`: platform, version, locale, cold/warm.
- `command_started`: Skill ID/version, declared input-source types, risk class.
- `plan_reviewed`: plan type, accepted/edited/cancelled, latency bucket.
- `execution_finished`: tool identifiers, success class, latency bucket, retry count.
- `result_applied`: insertion/replacement/copy, character-count bucket.

Never record command text, selected text, clipboard contents, surrounding text, output text, OAuth data, recipient, document title, URL query, coordinates, or tool payloads.

## 7. Core product invariants

- The keyboard never becomes unusable because AI is unavailable.
- Invocation is not execution for an external write.
- Previewed side effects equal executed side effects.
- The model cannot widen tool scope.
- External content cannot grant authority.
- Success is reported only after provider acknowledgement.
- The active field changes only after explicit Apply, except normal typing.
