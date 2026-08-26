# Phase B ordinary-input and benchmark verification

Date: 2026-08-26  
Parent commit: `c5c84c2`  
Evidence class: local source, unit test, lint, signed Simulator build, deterministic fixture diagnostic. No local result qualifies physical-device performance.

## Implemented

- iOS: `123` / `ABC` number-symbol layer, one-shot Shift, Caps Lock, layer reset, and trait-aware Return labels.
- Android: working number-symbol input, one-shot Shift, Caps Lock, layer/lifecycle reset, and EditorInfo-aware Return actions with Enter fallback.
- Android settings v3: haptic mode, key sound, and character preview persist from Host to IME; locked/sensitive fields suppress character preview.
- A-Z Skill gestures remain letter-only and do not attach to number-symbol keys.
- Content-free benchmark contracts cover both platforms, exact metrics, thresholds, candidate/environment/evidence binding, and canonical report digest.
- Benchmark and release gates reject duplicate metrics, digest/status drift, threshold forgery, and fixture/simulator proof spoofing.

## Integrated verification

| Check | Result |
|---|---|
| `corepack pnpm check` | PASS |
| Shared benchmark contract tests | PASS: 5 |
| Release/benchmark script tests | PASS: 9 total release-script tests |
| `swift test` | PASS: 87 |
| Signed iOS Simulator Host + Extension build | PASS |
| Android unit tests | PASS: 76 |
| Android `lintDebug` | PASS |
| Android `assembleDebug` | PASS |
| Production dependency audit | PASS: no known vulnerabilities |
| `git diff --check` | PASS |

`performance-benchmark.json` has `diagnostic_status: passed` and `qualification_status: not_proven`. `release-readiness.json` passes all source/schema/CI checks while intentionally retaining `not_proven` for physical-device E2E, protected performance measurements, and App Store-signed archive inspection.

## Remaining not proven

- Real iOS/Android host-app compatibility for Return actions and input traits.
- Physical haptic, sound, touch cancellation, accessibility service, OEM, memory-pressure, and restart behavior.
- Measured device latency and false-activation/drop rates. The checked-in diagnostic uses deterministic fixture values only.
- Japanese conversion, prediction/autocorrect, emoji, swipe typing, and OS-grade multilingual input.
