# Mobile AI Keyboard — Android

Native Android companion app and `InputMethodService` foundation for W1/W2.

## Local guarantees

- Normal key commits happen through `InputConnection` and do not require an account, network, or quota.
- The manifest intentionally has no `INTERNET` permission.
- Password, one-time-code, and phone fields enter a locked typing surface before context capture.
- Clipboard is never read speculatively; copying a reviewed result is an explicit action.
- The local polite rewrite fixture locks URLs, email addresses, handles, dates, and numeric entities.
- Telemetry is a typed, content-free event surface; no command, selection, clipboard, or output fields exist.
- Host Activity receipts expose only immutable plan metadata, risk, typed status, timestamps, and safe summaries.
- Account, device revocation, session expiry, retention, and deletion controls are local fixtures until a verified backend exists.
- Calendar, Notion, and Maps connections are read-only fixtures with explicit scope review, reconnect/rebind/disconnect states, bounded pagination, source references, freshness, partial/failure status, and an untrusted-provider-content warning.

## Build

```sh
./gradlew testDebugUnitTest
./gradlew assembleDebug
```

The project pins Gradle 8.13, Android Gradle Plugin 8.13.2, compileSdk/targetSdk 36, and minSdk 30.

The keyboard UI is intentionally dependency-light (`InputMethodService` + accessible Views). The companion onboarding and local sandbox use Jetpack Compose.

## Current scope

This milestone contains local English/number/symbol typing, layout switching, IME switching, command invocation, local preview/apply/copy/undo, stale-field fingerprint protection, onboarding/sandbox, provider-neutral local Account/Devices/Activity/Privacy fixtures, and read-only Calendar/Notion/Maps result fixtures. It does not contain network, OAuth, LLM, external identity, secrets, or external tool execution. Remote identity/backend/provider behavior remains unproven.
