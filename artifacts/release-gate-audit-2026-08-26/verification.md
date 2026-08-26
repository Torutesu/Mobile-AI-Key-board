# Release evidence gate audit

Date: 2026-08-26 (Asia/Tokyo)  
Evidence class: local source and contract-test audit only. This artifact is not
physical-device, emulator, UI-test, store-signing, or production qualification.

## Gate changes

- Protected E2E `passed` runs now require `environment: "protected_device"`, an
  attested protected runner, stable `device_id`, full candidate `source_commit`,
  and an exact candidate `artifact_digest` match.
- E2E `passed` targets must cover every declared scenario, including
  `accessibility_screen_reader` and `accessibility_font_scale`, and must name
  `voiceover` on iOS or `talkback` on Android.
- Protected performance measurements and iOS archive evidence now require the
  same candidate SHA/artifact binding and reject simulator, emulator, JVM,
  UI-test-only, fixture, local, or self-attested markers.
- CI invokes the strict Builder-to-IME shortcut source contract explicitly and
  executes host-level assignment flows on an iOS Simulator and Android
  Emulator. These lanes remain visibly classified as non-qualification evidence.

## Local verification

| Check | Result |
|---|---|
| `node --test scripts/test/*.test.mjs` | PASS: 20 tests |
| `swift test` | PASS: 102 tests |
| iOS Simulator UI test | PASS: Builder → private deploy → Add → H assignment → local fixture → save |
| Android `testDebugUnitTest lintDebug assembleDebug assembleDebugAndroidTest` | PASS |
| `pnpm release:readiness -- --static-only` | PASS source/schema checks; aggregate `not_proven` |
| E2E candidate/run binding adversarial test | PASS |
| Performance candidate/measurement binding adversarial test | PASS |
| JSON schema parse checks | PASS |

Observed local native checks are also intentionally below qualification: the
iOS host flow passed on a booted iPhone 16 Pro Simulator (iOS 18.6), while the
Android instrumentation APK compiled locally and its emulator execution is
wired into CI. These results can be retained as local diagnostic artifacts, but cannot populate a
`protected_external`/`protected_device` passed run.

## Remaining qualification boundary

The checked-in E2E matrix has no protected runs, so physical iOS/Android
keyboard registration, process restart, VoiceOver/TalkBack interaction,
font-scale behavior, third-party editor compatibility, and OEM behavior remain
`not_proven`. No local artifact in this audit can be promoted to protected
evidence without an independently attested runner, exact candidate SHA, exact
artifact digest, and the required physical-device records.
