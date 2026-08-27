# Onboarding UX audit — 2026-08-27

## Scope

iOS host app onboarding, local value demo, and keyboard / Full Access setup.

## Flow health

1. **Previous onboarding — poor.** Internal release status, App Group details, sandbox, account links, and setup controls competed on one long screen. The primary action started below the fold.
2. **Redesigned welcome — good.** One product promise, a keyboard preview, one primary action, and an explicit promise that the demo needs no permission.
3. **Redesigned local demo — good.** The user sees a local result before being asked to leave the app for Settings.
4. **Redesigned access setup — improved.** Keyboard installation and Full Access are presented as short, separate steps; status is only complete when Full Access and App Group availability are both fresh and confirmed.

## Highest-impact changes

- Removed release-readiness, Archive, owner/session, and App Group implementation language from the first-run path.
- Changed the sequence to value → permission-free local demo → access setup → Skill Keys.
- Added a plain-language Full Access explanation with data boundary, secure-field behavior, reversibility, and explicit execution language.
- Added a persistent completion flag, skip path, state refresh on foreground return, accessibility labels, and 44-point-or-larger controls.

## Evidence limits

Simulator UI tests prove the app-owned flow. The Settings app path, actual keyboard registration, Full Access toggle, VoiceOver, and keyboard-extension behavior still require signed physical-device E2E qualification.
