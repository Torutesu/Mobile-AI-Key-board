# iOS product audit evidence — 2026-08-27

Evidence class: local source, iOS Simulator build/UI tests, and visual comparison. Physical-device and signed-archive qualification are not proven.

## Captures

- `01-current-skill-builder.png`: previous schema/provider-oriented builder.
- `02-new-skill-builder.png`: intent-first builder after redesign.
- `03-reference-vs-builder.png`: supplied Acti creation reference and new builder in one comparison image.
- `05-trigger-key-qwerty.png`: revised A–Z trigger picker using QWERTY 10/9/7 rows.
- `06-reference-vs-trigger.png`: supplied Acti assignment reference and revised picker in one comparison image.
- `04-trigger-key-sheet.png`: superseded intermediate 6-column layout, retained to show the caught visual regression.

## Verified locally

- Swift core: 118 tests passed.
- iOS Simulator UI: 5 tests passed, including onboarding-before-permission, Full Access explanation, all 26 trigger keys at accessibility text size, creation→preview→install→assign, and unsupported-intent rejection.
- Generic iOS Simulator app + keyboard extension build passed.
- Repository `pnpm check` passed after updating the localized vertical-slice source anchors.

## Release boundary

The signed archive attempt for team `BAF4U6PT5S` failed before compilation because Xcode has no signed-in developer account and no profiles for either bundle identifier. No physical iPhone is connected. TestFlight upload and physical keyboard behavior therefore remain blocked, not passed.
