# P0 input and accessibility safety verification

Date: 2026-08-26 (Asia/Tokyo)

## Closed source-level defects

- Android bound keys now expose a real long-click accessibility action; a normal click continues to type the letter.
- Android selection-only Skill invocation passes no command fallback, so an empty selection cannot transform or insert the Skill display name.
- iOS bundled local transforms advertise and enforce explicit-selection input only. Surrounding context cannot be inserted as a duplicate pseudo-replacement.
- The general iOS workflow may still preview and copy a surrounding-context result, but automatic Apply now fails closed because the keyboard extension has no authoritative arbitrary-range replacement API.
- iOS reads live `isSecureTextEntry`, `textContentType`, and numeric keyboard traits when the extension appears and whenever the editor changes, then routes them through `SensitiveFieldPolicy`.

## Local verification

- iOS: 97 Swift tests passed with 0 failures.
- iOS: host, keyboard extension, and core generic Simulator build succeeded.
- Android: 84 unit tests passed with 0 failures/errors/skips; lint and debug APK assembly succeeded.
- Shared: the complete workspace check passed, including all 16 release/source contract tests; the production dependency audit reported no known vulnerabilities.
- Shared source contract: `scripts/test/keyboard-p0-safety-contracts.test.mjs` prevents removal of the Android accessibility action, reintroduction of Skill-label fallback, iOS surrounding-context execution, or disconnection of live field-trait refresh.

## Evidence boundary

This is local source, unit, lint, and Simulator/JVM evidence. TalkBack/VoiceOver gestures, OEM/third-party editor behavior, actual secure-field keyboard replacement, and process-restart synchronization still require protected physical-device runs and remain `not_proven`.
