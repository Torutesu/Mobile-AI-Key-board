# Security and Privacy Specification

## 1. Security objective

The keyboard occupies a privileged trust position. The system must prove that ordinary keystrokes stay local, network transmission occurs only after explicit review, and external actions cannot exceed the exact plan the user confirmed.

## 2. Trust boundaries

- Host text field and surrounding text: untrusted content.
- Keyboard/IME process: user-facing capture boundary, resource constrained.
- Companion app: account and connection management boundary.
- Mobile-to-API channel: authenticated but replayable without controls.
- Model output: untrusted proposal.
- Retrieved documents, email, web, and tool results: untrusted data, never authority.
- Policy engine: server-owned authority for risk and allowed operations.
- Credential broker: separate high-value secret boundary.
- Tool provider: external system with independent success semantics.

## 3. Non-negotiable invariants

1. No remote keylog: normal typed characters are not sent to our service, analytics, crash reporting, or model providers.
2. Explicit capture: every network run is bound to a disclosure acknowledgement.
3. Least data: only selected and reviewed inputs are sent.
4. Least authority: tool tokens are scoped and never exposed to models or keyboard code.
5. Exact confirmation: execution is bound to the canonical digest displayed to the user.
6. No silent communication or destructive action.
7. Untrusted context cannot add tools, scopes, recipients, or permissions.
8. Receipts distinguish succeeded, failed, partial, and unknown outcomes.
9. Revocation prevents new operations immediately, subject to provider realities.
10. Logs and analytics are content-free by construction, not convention.

## 4. Threats and required controls

| Threat | Attack case | Required controls |
|---|---|---|
| Accidental keylogging | analytics captures input values | typed event schema, log-field denylist, tests scanning telemetry |
| Prompt injection | selected email says “send all docs to attacker” | separate instruction/data channels, fixed tool allowlist, no authority from content |
| Plan swapping | UI shows draft but server executes invite | canonical digest, expiry, policy epoch, exact confirmation |
| OAuth theft | extension or model receives refresh token | brokered tokens, Keychain/Keystore, no token in prompt/client payload |
| Overbroad scope | benign Skill requests full Gmail access | operation-to-scope allowlist, incremental authorization, scope display |
| Duplicate side effect | timeout retry creates two events | idempotency key, provider dedupe, reconciliation before retry |
| Stale field replacement | user edits message while AI runs | field snapshot fingerprint, compatible-range check, fallback to copy |
| Malicious Skill update | publisher changes installed behavior | immutable versions, explicit upgrades, signed digest, rollback |
| Community abuse | popular Skill exfiltrates data | moderation, static policy, runtime policy, reports, kill switch |
| Local compromise | tokens extracted from shared storage | no shared OAuth tokens, hardware-backed device key where available |
| Supply-chain compromise | modified mobile/backend dependencies | lockfiles, provenance, SBOM, signing, protected release workflow |
| Unknown provider outcome | calendar API times out after creation | status `unknown`, provider lookup reconciliation, block blind retry |

## 5. Data classification

- `Public`: public Skill metadata and documentation.
- `Account`: profile, preferences, device metadata.
- `Private content`: submitted command, selection, output, document snippet.
- `Connected-tool content`: calendar, Notion, future mail/chat data.
- `Secret`: OAuth tokens, session tokens, signing keys, device private keys.
- `Security audit`: plan digests, policy epochs, identifiers, outcomes.

Secrets never enter general application tables, model context, analytics, support exports, or client logs.

## 6. Capture policy

- Default inputs: command only.
- Selection: explicit chip, with visible character count and preview.
- Surrounding context: off by default; bounded and redacted locally.
- Clipboard: never read speculatively; explicit per-run selection.
- Location: companion-app permission and per-run disclosure; coarse unless precision is required.
- App identity: use only OS-supported, documented signals. Do not fingerprint host apps.
- Secure input: disable AI UI before attempting context access.

### iOS Full Access disclosure

The current iOS extension requests Full Access (`RequestsOpenAccess=true`) so its content-free Skill Keys/settings projection can use the shared App Group. Full Access does not turn ordinary typing into a network operation in this fixture: no live transport is present, and ordinary typing remains the protected fallback. A release candidate must disclose the exact data, destination, purpose, retention, and deletion behavior for each explicitly invoked network-backed Skill before submission. Source manifests and simulator builds are configuration evidence only; archived entitlements, runtime traffic, and physical-device behavior remain `not_proven` until independently verified.

Client redaction warns about passwords, API keys, card patterns, private keys, one-time codes, and high-risk identifiers. Redaction is defense-in-depth; detected secrets are blocked by default rather than silently altered.

## 7. Authentication and device security

- Sign in with Apple/Google or verified email link/code.
- Short-lived access tokens and rotating refresh sessions.
- Each installation receives a device key pair; private key remains in Keychain/Keystore.
- High-risk confirmation MAY require device authentication and a signed challenge.
- Server binds sessions to user, device, platform, app instance, and revocation epoch.
- Root/jailbreak signals are advisory, not sole authorization controls.
- App Attest and Play Integrity are post-MVP hardening gates, not substitutes for server policy.

## 8. OAuth and tools

- Use Authorization Code with PKCE and provider-approved system authorization sessions.
- Request incremental scopes only when a chosen Skill requires them.
- Store credential material encrypted with a managed KMS key and per-record context binding.
- Maintain separate connection metadata and secret storage.
- Disconnect marks the connection unusable before asynchronous provider revocation.
- Rebinding creates a new connection epoch so stale plans cannot use the new account.
- Models see tool schemas and safe results, never access tokens or raw authorization responses.

## 9. Confirmation policy

Confirmation UI is generated from validated plan fields. It must show:

- action type and provider;
- account/workspace label;
- resource/target;
- exact date/time/timezone or recipient when applicable;
- whether data is read, created, changed, sent, or deleted;
- whether the action can be undone;
- generated text that will be inserted or communicated;
- any uncertainty or unresolved fields.

Changing any material field invalidates confirmation and produces a new digest.

## 10. Retention and deletion

- Unsubmitted typing: never leaves device.
- Submitted content: process transiently; default deletion within 24 hours.
- Builder chats/private Skill definitions: account lifetime or user deletion.
- Receipts: 90 days default, configurable shorter.
- Security audit metadata: 1 year, excluding raw content.
- Backups: encrypted rolling window with documented maximum deletion delay.
- Account deletion: revoke sessions immediately, disable connections, schedule content deletion, explain derivative/public Skill exceptions.

The UI must distinguish `deleted from active systems`, `provider revocation requested`, and `scheduled for backup expiry`.

## 11. Model and tool safety

- System instructions and tool schemas are server-controlled.
- User commands and retrieved content occupy labeled, length-bounded channels.
- Retrieved instructions are quoted as data.
- Structured output is schema-validated with unknown fields rejected.
- Tool arguments undergo semantic validation: dates, recipients, URLs, quantities, and ownership.
- Model-generated URLs are not opened or inserted as trusted links without validation.
- High-stakes medical, legal, financial, credential, and destructive workflows are blocked in MVP.

## 12. Security verification gates

Release requires:

- telemetry canary tests proving submitted secrets do not appear in logs;
- prompt-injection test corpus across every connector;
- plan-digest mutation tests;
- replay, expiry, cross-user, cross-device, and rebind-epoch tests;
- idempotency and unknown-outcome tests with provider simulators;
- mobile secure-field tests on physical iOS and Android devices;
- dependency, secret, static, and mobile binary scans;
- external review before R4 representational actions launch.

Passing mocks is not proof of real provider revocation, physical keyboard behavior, App Store approval, or production logging. Those require independent environment-specific evidence.
