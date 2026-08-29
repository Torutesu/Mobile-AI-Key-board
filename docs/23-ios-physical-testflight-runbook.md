# iOS physical-device and TestFlight runbook

This runbook qualifies one exact commit and archive. Simulator results are useful regression evidence but never replace the physical run below.

## Signing prerequisites

- Register `com.torutesu.mobileaikeyboard` and `com.torutesu.mobileaikeyboard.keyboard` in the same Apple Developer team.
- Register `group.com.torutesu.mobileaikeyboard` and enable it for both identifiers.
- Create the App Store Connect app record for the host bundle ID.
- Ensure the signing account can create App Store profiles with App Groups for both targets.
- Connect an unlocked iPhone, trust this Mac, enable Developer Mode, and verify it appears in `xcrun devicectl list devices`.

## Candidate build and TestFlight upload

```sh
cd apps/ios
IOS_DEVELOPMENT_TEAM=<team-id> ./scripts/archive-testflight.sh
IOS_DEVELOPMENT_TEAM=<team-id> \
ASC_KEY_PATH=<absolute-path-to-AuthKey.p8> \
ASC_KEY_ID=<10-char-key-id> \
ASC_ISSUER_ID=<issuer-uuid> \
ASC_APPLE_ID=<numeric-app-id> \
IOS_BUILD_NUMBER=<unique-monotonic-integer> \
UPLOAD_TO_TESTFLIGHT=1 ./scripts/archive-testflight.sh
```

Do not paste these credentials into chat, commit them, or place them inside the repository. Keep the API key in a private local directory or use the protected `testflight-production` GitHub environment. Every repeated upload requires a new numeric `IOS_BUILD_NUMBER`.

The archive script embeds the exact checked-out 40-character source commit in both the host and extension, rejects a dirty worktree and any non-empty candidate directory, validates strict signatures, exact App Group entitlements and privacy manifests, and writes a candidate-scoped `candidate-evidence.json`. It also writes `archive-sha256-manifest.txt`, requires exactly one exported IPA, binds that IPA digest into the aggregate candidate digest, and requires the archive, exported IPA, and CI-validated Host/Extension provisioning profile UUIDs to match. CI derives a unique numeric build number and candidate directory from the GitHub run. Upload mode re-verifies the exported distribution-signed host and extension, waits for App Store Connect to report a successful terminal state for the exact Apple ID/version/build, and stores `TestFlight/processing-status.json`. Preserve the complete workflow artifact. These are signed-archive and App Store processing evidence, not physical-device qualification.

The workflow additionally requires the numeric App Store Connect application ID in `ASC_APPLE_ID`; this is distinct from the bundle ID and API key ID.

## Clean-install permission journey

1. Delete the previous build and install the exact TestFlight candidate.
2. Complete `まず試してみる` and confirm the local rewrite works before any permission request.
3. Tap `設定を開く`; in the app settings open `キーボード`, enable Mobile AI Keyboard and `フルアクセスを許可`.
4. Return to the app, tap the verification field, select Mobile AI Keyboard with the globe key, and type one character.
5. Confirm onboarding changes to `準備できました`. Revoke Full Access and repeat; ordinary typing must remain available while Skill execution is unavailable.

Capture screenshots or video for every step, with device model, iOS build, locale, and TestFlight build visible in the evidence record.

## Prepare a candidate-bound physical QA packet

`devicectl` JSON is the device identity source. Do not copy a device name or UDID into an unbound spreadsheet.

```sh
mkdir -p artifacts/ios-physical/<run-id>/captures
xcrun devicectl list devices --json-output artifacts/ios-physical/<run-id>/devices.json
pnpm ios:physical-qa -- prepare \
  --candidate <candidate-root>/candidate-evidence.json \
  --ipa <candidate-root>/TestFlight/MobileAIKeyboard.ipa \
  --devices artifacts/ios-physical/<run-id>/devices.json \
  --device-id <devicectl-device-id> \
  --device-class iphone_current \
  --run-id <unique-run-id> \
  --runner-id <protected-runner-id> \
  --output artifacts/ios-physical/<run-id>/session.json
```

Allowed `--device-class` values are `iphone_baseline`, `iphone_current`, `iphone_small`, and `ipad_portrait_landscape`. The command fails if the device is absent, the candidate lacks a full source SHA or digest, or the IPA hash differs from `candidate-evidence.json`. It creates a complete pending checklist and `session-evidence-map.json`; it never marks a local or simulator run passed.

Record each capture relative to the `captures` directory in the evidence map. A single continuous recording may prove several checks, but every required ID must name at least one file. Then hash and bind every referenced file:

```sh
pnpm ios:physical-qa -- finalize \
  --session artifacts/ios-physical/<run-id>/session.json \
  --evidence-map artifacts/ios-physical/<run-id>/session-evidence-map.json \
  --evidence-dir artifacts/ios-physical/<run-id>/captures \
  --output artifacts/ios-physical/<run-id>/captured-pending-attestation.json
```

The finalized packet remains `not_proven`. A protected runner with an out-of-band Ed25519 key must independently re-hash the files, verify the physical device and candidate, add the attestation required by `scripts/release-readiness.mjs`, and register the run in `docs/release-e2e-matrix.json`. Never use repository-controlled or operator-generated self-attestation as release proof.

## Core physical matrix

Run on the oldest supported iPhone available and one current iPhone, in Japanese and English locale, light and dark appearance, default and accessibility text sizes.

The v1 extension is explicitly an English/ASCII QWERTY input surface (`en-US`) with local Skill execution. It can transform an explicitly selected Japanese passage, but it does not provide kana composition or Japanese conversion candidates. For Japanese text entry, switch with the globe key to the iOS Japanese keyboard, select the passage, then return to Mobile AI Keyboard to run a Skill. Do not describe this build as a Japanese IME until a composition/candidate pipeline is implemented and physically qualified.

- Create a Skill from natural-language intent, preview it, add it, assign `H`, run the local fixture, and save.
- Assign a second Skill to `M`; verify both appear in the host and keyboard.
- Tap `H` and `M` 100 times each: every short tap must type the character and must never invoke a Skill.
- Long-press each assigned key at and around the threshold; one deliberate hold must invoke exactly once.
- Move the finger outside the key, cancel the touch, rotate, background/foreground, switch apps, kill the host, kill the extension through memory pressure, and reboot. Assignments must either restore exactly or fail closed without breaking ordinary typing.
- Verify Q–P, A–L, Z–M, Shift, Delete repeat, Space, truthful newline Return, number/symbol layer, globe switching, host-field autocapitalization (`none`, `words`, `sentences`, `allCharacters`), and Dynamic Type.
- Rotate portrait → landscape → portrait and repeat on iPad/Split View when available. Record keyboard height, missing/clipped keys, Auto Layout warnings, and whether the host input remains visible; simulator layout coverage is not physical proof.
- Verify Messages, Mail, Safari, LINE, Slack, Gmail, and Notion. Notes and another web view are useful optional coverage but do not replace LINE. Test selected text, cursor-only text, empty fields, long text, emoji, URLs, Japanese text, mixed scripts, and an RTL passage with the correct caret direction.
- Verify password, one-time-code, payment, phone, number, and secure fields. AI/Skill surfaces must be unavailable and no content-bearing state may remain after transition.
- Open an app/field where iOS suppresses or does not support third-party keyboards and record that the system keyboard takes over without stale Mobile AI Keyboard UI or retained content.
- With VoiceOver and Switch Control, create and assign a Skill, open the visible Skill list, run, review, cancel, copy, and apply where the editor boundary allows it.
- Toggle theme, haptics, key size, and left/right one-handed mode in the host; reopen the keyboard and verify each setting changes the extension.

## Exact release matrix IDs

Use these IDs verbatim in the evidence map so the release gate and the human runbook cannot drift.

| Dimension | Required IDs and physical action |
| --- | --- |
| Scenarios | `ordinary_typing` (short taps never invoke Skills), `selection_rewrite` (selected text review/apply/cancel), `long_press_and_tap` (threshold/move/cancel/exactly-once), `emoji_and_newline` (emoji plus truthful Return), `japanese_input` (iOS Japanese keyboard selection then Skill), `url_input` (URL fields and punctuation), `rtl_input` (Arabic/Hebrew passage and caret), `app_and_keyboard_switch` (globe and app round trips), `rotation_and_background_resume` (portrait/landscape/background), `secure_field_suppression` (password/OTP/payment/phone/number), `unsupported_custom_keyboard` (system suppression of third-party keyboard), `accessibility_screen_reader` (VoiceOver), `accessibility_font_scale` (largest supported Dynamic Type). |
| Field classes | `ordinary_text`, `long_text`, `emoji`, `newline`, `japanese`, `url`, `rtl`, `secure_password`, `one_time_code`, `phone_number`. |
| Lifecycle | `input_field_switch`, `app_switch`, `keyboard_switch`, `rotation`, `background_resume`, `process_restart`. |
| Apps | `Messages`, `Mail`, `Safari`, `LINE`, `Slack`, `Gmail`, `Notion`. |

## Release stop conditions

Stop the TestFlight rollout for any dropped/duplicated ordinary keystroke, accidental Skill activation, stale-result application, secure-field exposure, assignment loss, crash, layout obstruction, unexplained network traffic, missing App Group entitlement, privacy-manifest mismatch, or archive/source mismatch. File the exact device, OS, app, reproduction, video, and candidate digest with the defect.
