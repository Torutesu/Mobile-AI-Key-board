# W7 store and privacy declaration baseline

## Declaration rule

Store declarations must match observed release behavior, not roadmap intent. The current repository is a local/provider-neutral fixture and is not a submitted App Store or Play candidate. The public product name, support URL/address, privacy-policy URL, age rating, countries, screenshots, signed archives, and store review IDs are `not_configured`.

## Current candidate behavior

| Surface | Current repository behavior | Store statement boundary |
| --- | --- | --- |
| Ordinary typing | local native keyboard/IME path | no typed content is sent during ordinary typing |
| iOS Full Access | `RequestsOpenAccess=false` | do not instruct users that Full Access is required for the current fixture |
| Android network | no `android.permission.INTERNET` | current APK cannot perform provider/LLM network calls |
| Text fixture | deterministic on-device rewrite | label as local fixture, not cloud AI |
| Account/OAuth/providers | local fixture state only | do not claim real sign-in, OAuth, Calendar, Notion, or Maps connectivity |
| Calendar write | local fixture state only | do not claim a real event was created or deleted |
| Skills | local/in-memory private fixture | public marketplace, signed packages, and production sync are unavailable |
| Telemetry | content-free typed structures; no live collector | do not claim production crash/analytics qualification |
| Deletion/retention | local/provider-neutral state machine | provider-side deletion and backup expiry remain unproven |

## App Store privacy baseline

The checked-in iOS privacy manifest must describe APIs actually present in the built app. Before submission, archive inspection and runtime traffic capture must independently confirm the manifest and App Privacy answers. If production identity, diagnostics, analytics, provider content, or payments are added, update the manifest and store answers before the code is enabled.

Required review evidence:

- signed archive digest and embedded extension identity;
- `RequestsOpenAccess` value from the archived extension;
- privacy manifest aggregation report;
- clean-install and keyboard-enable screenshots on physical devices;
- network capture for ordinary typing and each explicitly invoked destination;
- account/data deletion evidence without support intervention.

## Play Data safety baseline

The current debug APK has no INTERNET permission. Before submission, inspect the final AAB and merged manifest rather than relying on source files. Declare collection/sharing per destination, retention, encryption, deletion, and optionality only after runtime verification of the production SDK set.

Required review evidence:

- signed AAB digest, signing certificate, and merged manifest;
- dependency/SBOM and SDK data-practice review;
- ordinary-typing network canary on representative physical devices;
- account deletion and provider credential revocation evidence;
- Play pre-launch, accessibility, crash, and ANR reports bound to the candidate.

## Copy constraints

- Say “端末内fixture” for local deterministic behavior.
- Say “未接続” or “not_proven” for absent production identity, provider, model, or billing behavior.
- Never say a write, deletion, revocation, crash-free rate, physical-device matrix, or store approval passed based only on a simulator, JVM, mock, or source inspection.
- Do not create store assets under the working title. Naming, identity, legal copy, support endpoint, and privacy-policy endpoint require explicit product decisions.
