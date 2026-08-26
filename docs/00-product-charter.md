# Product Charter

Status: Baseline v0.1

Date: 2026-08-26

Owner: Product and engineering

## 1. Product thesis

Mobile work breaks at app boundaries. A user sees a request in LINE, Slack, Gmail, or a browser, then switches to search, calendar, maps, notes, or an AI app, reconstructs the context, performs an action, copies the result, and returns. The keyboard is already present at the moment intent becomes text, so it can become the smallest cross-app control surface for completing that loop.

The product is not a chatbot embedded in a keyboard. It is a user-controlled execution layer with five stages:

`Capture -> Plan -> Review -> Execute -> Apply`

## 2. Initial audience

Primary launch audience:

- Japanese and English bilingual iPhone and Android users.
- People who coordinate work from chat and email: founders, operators, sales, recruiting, consulting, and project leads.
- Users who repeatedly move between messaging, calendar, maps, documents, and meeting tools.

Secondary audience:

- Creators and power users who want reusable personal commands.
- Teams that want approved workflow templates with centrally controlled connectors.

## 3. Jobs to be done

### J1: Turn a conversation into a coordinated next step

When someone proposes a meeting, I want to extract the date and participants, check my calendar, prepare an event draft, and insert a natural reply without leaving the conversation.

### J2: Retrieve and share trusted information

When someone asks for a document, place, price, or schedule, I want to find the correct source and paste a compact answer or link into the active field.

### J3: Improve text in context

When I have already written something, I want to rewrite, shorten, translate, or adjust tone while preserving names, facts, URLs, and my intent.

### J4: Reuse a personal workflow

When I repeat a multi-step mobile task, I want to save it as a named Skill and invoke it consistently from the keyboard.

## 4. Product positioning

> 会話を文章で終わらせず、その場で安全に次の行動へ変える。

Category: AI-first mobile input and action layer.

Competitive distinction:

- Versus system writing tools: performs reviewed actions, not only text transformation.
- Versus standalone AI apps: preserves the active app and insertion point.
- Versus automation products: starts from conversational context and returns a human-readable result to the field.
- Versus Acti: prioritizes explicit data disclosure, risk-based execution, Japanese workflows, action receipts, and ordinary keyboard quality.

## 5. Success metrics

North-star metric:

- Weekly verified workflow completions per retained user.

Activation:

- Keyboard enabled and first successful text-only Skill within 10 minutes.
- First connected-tool workflow completed within 24 hours.

Quality:

- >= 95% successful execution for supported deterministic actions.
- >= 99.5% correct declaration of intended external side effects before confirmation.
- >= 98% of text transformations preserve protected entities.
- p95 keyboard cold-start <= 400 ms; p95 local key commit <= 50 ms.
- p95 first visible AI progress <= 1.5 s on a normal network.

Retention:

- >= 35% week-4 retention among users with two successful workflows in week 1.
- >= 3 verified workflow completions per weekly active user.

Trust:

- 100% of network-bound runs display the data disclosure before transmission.
- 0 silent external writes.
- 0 plaintext OAuth tokens, prompts, selected text, or tool results in analytics or ordinary logs.

## 6. Scope

Parity scope:

- Native iOS custom keyboard and Android IME.
- Companion app for onboarding, account, settings, connections, Skills, and history.
- Explicit long-press or dedicated action control.
- Typed intent, selected text, explicit clipboard input, and optional bounded surrounding text.
- Preview and apply for generated text.
- OAuth-backed read and write actions.
- Skill creation, editing, binding, cloning, and private sharing.
- Usage quotas and provider-cost controls.

Beyond-parity scope:

- Trust Preview describing data, tools, scopes, side effects, and reversibility.
- Japanese date, tone, honorific, and workflow handling.
- Deterministic execution whenever an LLM is unnecessary.
- Action receipts, partial-success handling, retry safety, and undo when supported.
- Team-approved Skill packages and policy controls after consumer validation.

## 7. Non-goals for the first public release

- Autonomous background execution.
- Sending messages, invites, posts, or payments without final confirmation.
- Deleting records through the keyboard.
- Password, one-time-code, banking, medical, or other secure-field processing.
- Reading entire conversations or screens through accessibility scraping.
- Rebuilding a world-class Japanese conversion engine from zero before workflow validation.
- A public Skill marketplace before private Skills are safe and reliable.
- Claims of working in every app or field.

## 8. Platform truth

On iOS, secure fields, phone-pad fields, and apps that reject keyboard extensions fall back to the system keyboard. The extension requires Full Access for networking and cannot directly use the microphone. Voice input therefore uses system-provided dictation where available or a deliberate handoff to the companion app.

On Android, the IME can receive surrounding or selected text through `InputConnection`, but password and sensitive input types must disable capture, suggestions, history, and network actions.

These limits are user-facing product states, not hidden implementation details.

## 9. Legal and benchmark boundary

Public benchmark behavior may inform requirements, but implementation must be independent. Do not copy Acti code, assets, brand language, screenshots, internal prompts, catalogs, or private behavior. Do not scrape authenticated surfaces or reverse engineer binaries. The result should reproduce the user job and then improve it, not impersonate the reference product.
