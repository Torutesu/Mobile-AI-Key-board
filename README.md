# Mobile AI Keyboard

AI-first input layer for real smartphone workflows. The product turns explicit user intent into a reviewed result or action without forcing the user to leave the app they are already using.

Working title only. Product naming and visual identity are intentionally deferred.

## Product contract

1. Normal typing must remain fast, predictable, and local.
2. No typed content leaves the device until the user explicitly invokes AI.
3. Before execution, show exactly what data will be used, which services will be called, and what will change.
4. Text generation may be applied in place; external actions require risk-based confirmation.
5. Every external action produces a durable receipt and an honest success, partial-success, or failure state.
6. Unsupported fields and apps are reported plainly; the product never claims universal OS access.

## Specification index

- [Product charter](docs/00-product-charter.md)
- [Product requirements](docs/01-product-requirements.md)
- [UX workflows and screen states](docs/02-ux-workflows.md)
- [System architecture](docs/03-system-architecture.md)
- [API and data contracts](docs/04-api-data-contracts.md)
- [Security and privacy specification](docs/05-security-privacy.md)
- [Quality, acceptance, and release plan](docs/06-quality-release.md)
- [Delivery roadmap](docs/07-delivery-roadmap.md)

## Current status

The first engineering milestone is implemented as a local-first foundation:

- iOS host app, keyboard extension, state machine, sensitive-field lockout, local rewrite fixture, and Swift tests;
- Android host app, IME, equivalent local safety/core behavior, and JVM tests;
- shared TypeScript contracts, policy engine, run state machine, API skeleton, worker execution ledger, and tests;
- content-free telemetry contracts and three-platform CI.

This is not a production release. Real-device keyboard lifecycle, Japanese conversion, third-party app compatibility, signed distribution, durable infrastructure, and production identity verification remain explicit qualification gates. See [implementation status](docs/08-implementation-status.md).

## Local verification

Shared contracts and services:

```sh
corepack pnpm install --frozen-lockfile
corepack pnpm check
```

iOS core and simulator build:

```sh
cd apps/ios
swift test
xcodegen generate --spec project.yml
xcodebuild -project MobileAIKeyboard.xcodeproj -scheme MobileAIKeyboard \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Android core and debug build:

```sh
cd apps/android
./gradlew --no-daemon testDebugUnitTest assembleDebug
```
