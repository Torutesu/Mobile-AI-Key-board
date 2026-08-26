# Skill Keys UX integrated verification

Date: 2026-08-26 (Asia/Tokyo)

## Integrated tree results

- `corepack pnpm check`: PASS, including the TypeScript contracts, policy, Skill runtime, API/worker, release tests, and generated shortcut-vector byte check.
- `corepack pnpm audit --prod --audit-level high`: PASS, no known vulnerabilities.
- `corepack pnpm shortcuts:vectors:check`: PASS, 7 TypeScript-authoritative vectors.
- `swift test`: PASS, 92 tests.
- `xcodegen generate --spec project.yml`: PASS.
- Signed iOS Simulator build of the host and keyboard extension: PASS (`BUILD SUCCEEDED`).
- Android `:app:testDebugUnitTest :app:lintDebug :app:assembleDebug`: PASS, 79 tests and APK assembly.
- `corepack pnpm release:readiness -- --static-only`: executed successfully with the honest aggregate result `not_proven`.
- `git diff --check`: PASS.

## Visual evidence

- `ios-skill-keys-dashboard.png`: iPhone 16 Pro Simulator, A-Z preview, search, current bindings, and assignable/unavailable Skill states.
- `ios-trigger-key-sheet.png`: iPhone 16 Pro Simulator, all A-Z targets, save-before-test gate, local fixture input, and disabled Add state before a passing test.

These screenshots are visual simulator evidence only. They are not physical-device, VoiceOver, App Group, or production performance proof.

## Remaining external gates

- Physical iOS and Android IME lifecycle, ordinary typing, long-press cancellation, app switching, rotation, memory pressure, and offline execution.
- VoiceOver/TalkBack and large Dynamic Type on physical devices.
- Protected device performance capture for latency, false activation, dropped taps, cold/warm open, memory, energy, and crash-free sessions.
- Signed App Store archive entitlement/privacy inspection.
- Cross-language native consumption of the TypeScript shortcut golden vectors.
