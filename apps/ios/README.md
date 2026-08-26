# iOS foundation

This directory contains the native iOS host app and custom keyboard extension foundation for W1/W2.

## Build the deterministic core now

```sh
cd apps/ios
swift test
```

`MobileAIKeyboardCore` has no network or provider dependencies. It owns the keyboard state reducer, secure-field policy, entity locking/fingerprinting, offline polite-rewrite fixture, and content-free telemetry value type.

## Generate the Apple project

Install [XcodeGen](https://github.com/yonaskolb/XcodeGen), then run:

```sh
xcodegen generate --spec project.yml
open MobileAIKeyboard.xcodeproj
```

The project defines `com.torutesu.mobileaikeyboard` and the extension `com.torutesu.mobileaikeyboard.keyboard`, with a shared App Group for non-secret settings only. OAuth credentials and provider tokens are intentionally absent.

## Qualification boundary

The package tests are executable evidence for pure logic. Xcode project generation, extension lifecycle, secure text-field behavior, Full Access, App Group provisioning, Japanese composition/candidates, and third-party app replacement still require an Xcode build and physical iOS device qualification.
