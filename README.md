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
- [Implementation status](docs/08-implementation-status.md)
- [W2 local text slice](docs/09-w2-local-text-slice.md)
- [W3 identity, receipts, and retention](docs/10-w3-identity-receipts.md)
- [W4 read-only connections](docs/11-w4-read-only-connections.md)
- [W5 confirmed private Calendar write](docs/12-w5-confirmed-calendar-write.md)

## Current status

The W0-W5 local and provider-neutral foundations are implemented:

- iOS host app and keyboard extension with Command, explicit source selection, Capture Review, local rewrite, editable Result Preview, stale-safe Apply, and Undo;
- Android host app and IME with the equivalent local workflow, bounded `InputConnection` capture, implicit-replacement rejection, stale-safe Apply, and Undo;
- shared TypeScript contracts and policy for local-only R1 plans, disclosure acknowledgement, bounded capture, revision binding, telemetry minimization, and undo lifecycle;
- provider-neutral device proof, rotating/revocable sessions, immutable authenticated run bindings, append-only content-free receipts/audit, retention, and account deletion state machines;
- iOS and Android Account, Devices, Activity, and Privacy fixture surfaces that expose success, partial, failure, revocation, retention, and deletion states without pretending to be connected services;
- provider-neutral OAuth state/PKCE, incremental grant, rebind/disconnect, exact read-only scope, source provenance/freshness, provider-taint, bounded pagination, and typed connector outcome contracts;
- iOS and Android Connections and source-linked Results fixture surfaces for Calendar availability, Notion search, and Maps search, with explicit reconnect/rebind/disconnect and no external writes;
- one R3 write fixture for an invite-free private Calendar event, with exact capability separation, canonical digest confirmation, owner/grant/connection-epoch binding, idempotency, honest partial/unknown outcomes, exact-key reconciliation, and bounded exact-resource Undo;
- iOS and Android draft/review/confirm/receipt/reconciliation/Undo fixture surfaces that clearly label OAuth, provider network, and real external effects as unconnected;
- API identity boundary, worker receipt projection, execution ledger, and tests;
- content-free telemetry contracts and three-platform CI.

This is not a production release. Real-device keyboard lifecycle, Japanese conversion, third-party app compatibility, signed distribution, external identity verification, live OAuth/provider APIs and writes, encrypted credential custody, hardware-backed device proof, durable multi-instance infrastructure, and an external R3 security assessment remain explicit qualification gates. See [implementation status](docs/08-implementation-status.md).

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
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/mobile-ai-keyboard-derived build
```

Use an installed simulator destination for extension lifecycle checks. A generic
unsigned build proves compilation only and cannot qualify keyboard discovery or
switching.

Android core and debug build:

```sh
cd apps/android
./gradlew --no-daemon testDebugUnitTest lintDebug assembleDebug
```
