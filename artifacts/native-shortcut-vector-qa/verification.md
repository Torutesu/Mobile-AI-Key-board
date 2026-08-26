# Native shortcut vector verification

Date: 2026-08-26 (Asia/Tokyo)

This checkpoint verifies that the TypeScript-authoritative shortcut fixture is
consumed directly by both native unit suites. It is static/local evidence and
does not qualify physical-device behavior, cross-process synchronization, or a
store release.

## Results

- Shared: `corepack pnpm check` passed, including 13 release tests.
- Dependency audit: `corepack pnpm audit --prod --audit-level high` reported no known vulnerabilities.
- Golden vectors: `corepack pnpm shortcuts:vectors:check` passed for all 7 vectors.
- Native consumer gate: both iOS and Android reported `native_unit_consumers` for fixture SHA-256 `36b984ea6ac815d4baa4d4bbfe7d22909d51ee843ca7b8d13976776e44585c16`.
- iOS: `swift test` passed 96 tests with 0 failures; the host, keyboard extension, and core simulator build succeeded.
- Android: a forced, non-cached `:app:testDebugUnitTest --rerun-tasks` passed 83 tests with 0 failures, 0 errors, and 0 skipped; `lintDebug` and `assembleDebug` succeeded.
- Release readiness: the static gate passed its source/CI checks and correctly remained `not_proven` because protected device, performance, and signed-archive evidence is absent.
- Hygiene: `git diff --check` passed and the repository secret-pattern scan found no matches.

## Adversarial coverage

Both native parsers reject or detect the checked-in negative vectors for schema
drift, lowercase physical keys, digest tampering, duplicate physical-key
conflicts, and non-local authority. Additional native tests reject duplicate
JSON object members, trailing bytes, expected-result tampering, and digest
expectation tampering.

## Remaining external qualification

- iOS host-to-keyboard-extension persistence and execution on physical devices.
- Android host-to-IME persistence and execution on physical devices.
- Representative third-party app matrix, secure fields, multilingual input,
  accessibility services, crash/restart behavior, and measured device latency.
- Signed archive/AAB inspection and protected CI evidence bound to an exact
  candidate commit.
