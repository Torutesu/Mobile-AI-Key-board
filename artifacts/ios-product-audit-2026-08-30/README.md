# iOS Acti-parity visual QA — 2026-08-30

Evidence class: current source at the recorded Git tree, iPhone 16 Pro / iOS 18.6 Simulator capture, simulator build and UI automation. These captures do not prove signed physical-device behavior or TestFlight processing.

## Same-state captures

- `onboarding.png`: value-first welcome before requesting keyboard access.
- `access.png`: keyboard registration, Full Access explanation and in-app verification path.
- `builder.png`: private Skill natural-language composer with fixed creation CTA.
- `skill-type.png`: Acti-inspired Public / Private chooser; Public is truthfully marked as unavailable and Private supports drag or tap.
- `shell.png`: persistent Keyboard / Skills / Profile navigation plus independent creation action.

Reference screenshots supplied by the product owner:

- `FFC1E5FB-F171-4676-8828-20DE35D9616A.png`: keyboard home and persistent navigation.
- `B23F15E6-43CC-4D0C-BE50-0B0A258A58B5.png` and `ECFFAAF4-75EF-4BC9-9898-1FA3116C417B.png`: Public / Private chooser.
- `C9405CC1-487C-46EA-984F-92395CBD641A.png`: natural-language Skill builder.
- `5ED96C0A-4290-47C2-B68F-5D172ED5EB8D.png`: A–Z trigger assignment sheet.

## Verified locally

- Generic iOS Simulator host + keyboard extension build: passed.
- iOS Simulator UI automation: 9/9 passed.
- The suite covers value-before-permission onboarding, reversible Full Access explanation, all 26 trigger keys at accessibility size, private creation through assignment and restart, unsupported-intent rejection, unassigned Skill persistence, setup reopening, and the new floating Create → Private → Builder journey.
- Swift package and repository checks are recorded in the corresponding commit/CI run.

## Remaining physical boundary

No iPhone was connected during this run. Profiles for the host and keyboard extension, the App Store Connect environment, signed IPA install, third-party app typing, warm Full Access revoke/restore, long-press feel, keyboard process restart and TestFlight processing remain `not_proven` until the physical runbook is executed against the exact candidate.
