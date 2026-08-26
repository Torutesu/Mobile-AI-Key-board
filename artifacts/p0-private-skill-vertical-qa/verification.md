# P0 Private Skill → Skill Keys → IME verification

Date: 2026-08-26 (Asia/Tokyo)

## Verified implementation

- iOS and Android keep Deploy, Add To My Keyboard, and A–Z assignment as three explicit transitions.
- Private Skills are pinned by immutable Skill ID, version ID/number, and SHA-256 digest.
- The keyboard executes only a closed, deterministic local text executor; user-authored instructions are metadata and are never evaluated as code, URL, provider, or network authority.
- Ordinary key taps still type normally. Skill execution remains a separate long-press/accessibility action and requires explicit selection plus Capture Review.
- Unknown, stale, disabled, version-mismatched, or digest-mismatched bindings fail closed. They do not fall back to a different Skill.
- Android clears Private Skill catalog and shortcut snapshot on sign-out, session expiry/revoke, current-device revoke, and completed deletion.
- Assigned Skills restore from the validated native snapshot after restart. On iOS, an unassigned Add-to-Keyboard candidate is intentionally process-local until A–Z assignment persists it.

## Executed QA

- `corepack pnpm check`: pass; shared packages and 18 release/source-contract tests pass.
- `swift test`: 102 tests, 0 failures.
- iOS Simulator Debug build (`iPhone 17 Pro`): `BUILD SUCCEEDED`.
- Android `testDebugUnitTest lintDebug assembleDebug`: 90 tests, 0 failures; lint pass; APK produced.
- Builder vertical-slice source gate (`--strict`): iOS pass, Android pass.
- Shortcut golden vectors: 7 checked; native consumers present on both platforms.
- `pnpm audit --audit-level=high`: no known vulnerabilities.
- `git diff --check`: pass.
- repository secret-pattern scan: no matches.

## Qualification boundary

This evidence proves source wiring, deterministic tests, simulator compilation, Android JVM tests/lint, and debug artifact production. It does **not** prove physical-device keyboard registration, third-party app interaction, OS process-restart behavior, TalkBack/VoiceOver operation, device performance, signed iOS archive entitlements, or store distribution. Those release-readiness items remain `not_proven` until protected external evidence is captured.
