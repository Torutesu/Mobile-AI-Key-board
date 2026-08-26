# P0 beta implementation verification

Date: 2026-08-26  
Baseline: `e93cac9`  
Evidence class: local source, unit test, lint, simulator build, and fresh simulator screenshots. This is not physical-device or store-release qualification.

## Implemented

- iOS onboarding explains enablement, Full Access, App Group metadata, local-only typing, and unavailable network/Calendar boundaries.
- Android onboarding requires IME enablement plus a successful test-field input before completion.
- iOS and Android expose A-Z Trigger Keys with accessible minimum targets; occupied keys are visibly unavailable.
- Short tap and long-press paths are mutually exclusive in the Android touch owner; movement, multi-touch, and cancellation suppress ordinary commit.
- iOS long press has a fixed 450 ms threshold, movement allowance, haptic feedback, and same-sequence tap suppression.
- Both consumers reject non-local/host-handoff bindings. Calendar remains visible only as unavailable on iOS and is absent from Android's executable catalog.
- Shared policy rejects a network or write Skill projected as `keyboard_local` and requires active connections for enabled connected bindings.
- Full Access declarations, App Group entitlements, privacy documentation, and release evidence schemas are checked by a fail-closed release command.

## Local verification

| Check | Result |
|---|---|
| `corepack pnpm check` | PASS |
| Shared release-gate regression tests | PASS: 5 |
| `swift test` | PASS: 85 |
| Signed iOS Simulator Host + Extension build | PASS |
| Android unit tests | PASS: 73 |
| Android `lintDebug` | PASS |
| Android `assembleDebug` | PASS |
| `corepack pnpm audit --prod --audit-level high` | PASS: no known vulnerabilities |
| Static release readiness | PASS as a source gate; overall remains `not_proven` |
| `git diff --check` | PASS |

## Fresh visual evidence

- `ios-onboarding.png`: permission and privacy boundary in the built app.
- `ios-skill-keys.png`: A-Z preview, H/M assignments, executable local Skills, and unavailable host handoff.
- `ios-trigger-key-sheet.png`: occupied H/M are disabled, remaining letters are assignable, and CTA state is fail-closed until a key is selected.

## Deliberately not proven

- iOS and Android physical-device touch, haptic, VoiceOver/TalkBack, Switch Control, OEM, and restart behavior.
- Real App Group/provisioning behavior on an App Store-signed archive.
- Major-app E2E on Messages, Mail, Safari, LINE, Slack, Gmail, and Notion.
- Protected performance evidence for key-to-commit, cold/warm open, false activation, drop rate, crashes, ANR, and memory pressure.
- Real OAuth/provider/Calendar execution. The product does not expose it as executable in this milestone.

The non-static `pnpm release:readiness` command must continue to exit non-zero until the protected physical-device, performance, and signed-archive records are supplied and candidate-bound.
