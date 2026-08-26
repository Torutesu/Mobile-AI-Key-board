# UX Workflows and Screen States

## 1. Information architecture

### Keyboard surfaces

- Typing: keys, candidate row, action control, language switch, delete, return.
- Command: compact prompt field, input-source chips, Skill shortcuts, cancel.
- Trust Preview: data leaving device, tools, targets, proposed side effects.
- Result Preview: generated text or action plan, edit/regenerate/apply.
- Execution: per-step progress and cancellation where safe.
- Receipt: outcome, inserted result, external resource link, undo where supported.

### Companion app tabs

1. Home: readiness, quick test, recent receipts, suggested next setup.
2. Skills: installed, personal, drafts, bindings.
3. Connections: services, scopes, account label, status, disconnect.
4. Activity: searchable local/server receipts with retention controls.
5. Settings: keyboard, languages, privacy, security, account, support.

## 2. Keyboard state machine

| State | Entry | Primary actions | Exit |
|---|---|---|---|
| `typing` | text field focused | type, switch mode, invoke | command or dismiss |
| `command` | hold action control or choose Skill | enter intent, choose input sources | review or cancel |
| `capture_review` | run requested | inspect/redact data and permissions | plan or cancel |
| `planning` | disclosure accepted | wait, cancel | result/action review or error |
| `result_review` | text result ready | edit, regenerate, apply, copy | typing or command |
| `action_review` | external plan ready | inspect steps, confirm, edit inputs | executing or cancel |
| `executing` | confirmed | watch steps, safe cancel | receipt or error |
| `receipt` | run settled | apply result, open resource, undo | typing |
| `error` | recoverable/nonrecoverable failure | retry safe steps, reconnect, copy details | prior safe state |
| `locked` | sensitive/unsupported field | normal safe typing or switch keyboard | typing/dismiss |

State restoration rules:

- Rotating the device or backgrounding for <= 60 seconds SHOULD preserve an unconfirmed draft locally.
- Confirmations expire after 60 seconds or any target/payload change.
- A field/app identity change invalidates captured context and pending Apply operations.
- External writes continue server-side after provider acceptance; the receipt reconciles on return.

## 3. Onboarding workflow

### Step 1: Value before permission

Show one concrete Japanese workflow: receive a scheduling message, check availability, create a draft, insert a reply. Do not ask for Full Access on the first screen.

Health criterion: user can explain the outcome without knowing the term “agentic keyboard.”

### Step 2: Local sandbox

Let the user type and run a local rewrite in the companion app. Demonstrate Preview and Apply without keyboard permission or account creation.

### Step 3: Add keyboard

Provide OS-specific instructions, deep links where permitted, and a live readiness check. Never fake successful enablement.

### Step 4: Explain Full Access

Before asking:

- Normal typing stays local.
- AI runs transmit only explicitly reviewed inputs.
- Secure fields disable AI.
- Full Access is required by iOS for networking and shared app state.
- The user can turn it off at any time; ordinary typing remains available where possible.

### Step 5: First in-context success

Open a safe test field, ask the user to switch keyboards, type a short sentence, hold the action control, select “丁寧に”, preview, and apply.

### Step 6: Optional connection

Only after text-only success, offer Calendar connection with a clear scope explanation. Account creation is delayed until sync or a connector requires it.

## 4. Golden workflow A: Rewrite in LINE

User goal: make an existing Japanese message concise and polite.

1. User selects or places cursor after text.
2. Holds action control and chooses `丁寧に短く`.
3. Capture Review shows selected/surrounding characters and states `AI provider only; no external tools`.
4. Result Preview highlights entity changes. Changed names, dates, numbers, and URLs are warnings.
5. User edits or applies.
6. Original range is replaced only if still unchanged; otherwise insert at cursor or ask user to reselect.

Acceptance:

- No message is sent.
- Original text can be restored with Undo.
- Protected entities are preserved or explicitly approved.

## 5. Golden workflow B: Schedule from a conversation

User goal: respond to “来週火曜の15時どうですか？” without switching apps.

1. User explicitly selects/copies the proposal and invokes `日程調整`.
2. Local parser identifies locale, timezone, relative date, proposed duration, and missing participants.
3. Trust Preview shows Calendar read scope, selected text, resolved date, and no writes yet.
4. Calendar availability is read.
5. Action Review displays:
   - resolved date/time/timezone;
   - conflict status;
   - event title placeholder;
   - attendees: none by default;
   - external effect: create private event draft;
   - chat output: proposed reply.
6. User changes duration/title if needed and confirms.
7. Server creates event with idempotency key.
8. Receipt shows provider event ID/link and whether undo is available.
9. Reply text is inserted only after Apply.

Ambiguity rules:

- Relative dates always show the resolved absolute date.
- Missing timezone uses device timezone and displays it.
- No attendee is inferred from conversation text in MVP.
- Conflicts never trigger automatic rescheduling.

## 6. Golden workflow C: Find and share a Notion document

1. User invokes `Notion検索` and types a query.
2. Trust Preview shows query and authorized workspace/account label.
3. Results show title, breadcrumb, last edited time, and a short safe snippet.
4. User selects one result.
5. Keyboard inserts title plus canonical URL.

No model is required for exact search. AI ranking is optional and MUST not invent documents.

## 7. Skill Builder workflow

1. User describes a desired outcome in the companion app.
2. Builder asks only for missing input/output/tool information.
3. A structured draft is shown as plain language plus an advanced schema view.
4. User connects required tools separately.
5. Test mode runs with fixtures or read-only data; writes use dry-run.
6. Validation explains blocked permissions or unsafe steps.
7. User names, icons, and binds the Skill.
8. Deployment creates version 1 and records its contract digest.

The Builder never equates a successful LLM response with a valid or safe Skill.

## 8. Error and recovery language

Errors answer four questions:

1. What finished?
2. What did not finish?
3. Did anything change externally?
4. What is the safest next action?

Examples:

- `予定は作成されていません。Google Calendarの接続が切れています。再接続後に同じ確認画面へ戻れます。`
- `予定は作成されましたが、返信文を入力欄へ挿入できませんでした。予定を開く / 返信文をコピー。`
- `入力欄の内容が変更されたため、自動置換を止めました。結果をコピーするか、もう一度範囲を選択してください。`

Avoid “Something went wrong” when a typed recovery state is known.

## 9. Accessibility

- Touch targets MUST be at least 44x44 pt on iOS and 48x48 dp on Android.
- All controls MUST expose accessible names, values, state, and order.
- Long press MUST have an equivalent visible button and assistive-technology action.
- Haptics and color MUST NOT be the only indicators of risk or completion.
- Dynamic Type/font scaling MUST work in the companion app; keyboard critical labels MUST remain legible at supported accessibility sizes.
- Motion MUST respect reduced-motion preferences.
- Streaming output MUST not continuously steal screen-reader focus.
- Risk and confirmation copy MUST be available in Japanese and English at launch.
