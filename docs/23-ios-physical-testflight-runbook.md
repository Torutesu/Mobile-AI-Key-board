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

The archive script embeds the exact checked-out 40-character source commit in both the host and extension, rejects a dirty worktree (dirty override is never accepted for upload), validates strict signatures, exact App Group entitlements and privacy manifests, and writes a candidate-scoped `candidate-evidence.json` beside the archive/export directories with executable, archive, exported IPA, and aggregate candidate digests. CI derives a unique numeric build number and candidate directory from the GitHub run. Before signing, it verifies that both supplied profiles match the exact bundle ID, team, non-expired lifetime, and sole App Group. Upload mode then re-verifies the exported distribution-signed host and extension, waits for App Store Connect to finish processing that exact version/build, and stores `TestFlight/processing-status.json`. Preserve both files with the archive evidence. These are signed-archive and App Store processing evidence, not physical-device qualification.

The workflow additionally requires the numeric App Store Connect application ID in `ASC_APPLE_ID`; this is distinct from the bundle ID and API key ID.

## Clean-install permission journey

1. Delete the previous build and install the exact TestFlight candidate.
2. Complete `まず試してみる` and confirm the local rewrite works before any permission request.
3. Tap `設定を開く`; in the app settings open `キーボード`, enable Mobile AI Keyboard and `フルアクセスを許可`.
4. Return to the app, tap the verification field, select Mobile AI Keyboard with the globe key, and type one character.
5. Confirm onboarding changes to `準備できました`. Revoke Full Access and repeat; ordinary typing must remain available while Skill execution is unavailable.

Capture screenshots or video for every step, with device model, iOS build, locale, and TestFlight build visible in the evidence record.

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
- Verify Notes, Messages, Mail, Safari, Slack, Gmail, Notion, and one web view. Test selected text, cursor-only text, empty fields, long text, emoji, URLs, Japanese text, and mixed scripts.
- Verify password, one-time-code, payment, phone, number, and secure fields. AI/Skill surfaces must be unavailable and no content-bearing state may remain after transition.
- With VoiceOver and Switch Control, create and assign a Skill, open the visible Skill list, run, review, cancel, copy, and apply where the editor boundary allows it.
- Toggle theme, haptics, key size, and left/right one-handed mode in the host; reopen the keyboard and verify each setting changes the extension.

## Release stop conditions

Stop the TestFlight rollout for any dropped/duplicated ordinary keystroke, accidental Skill activation, stale-result application, secure-field exposure, assignment loss, crash, layout obstruction, unexplained network traffic, missing App Group entitlement, privacy-manifest mismatch, or archive/source mismatch. File the exact device, OS, app, reproduction, video, and candidate digest with the defect.
