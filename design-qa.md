# iOS Skill creation and Trigger Key design QA

**Current result:** passed for the implemented private, on-device text Skill journey. Acti-level public Skills and connected-tool breadth remain an explicit P1 product gap; this report does not claim those capabilities exist.

## Evidence

- Source visual truth:
  - `/Users/torutano/Downloads/C9405CC1-487C-46EA-984F-92395CBD641A.png` — Acti intent/capability builder, 1170 x 2532 px.
  - `/Users/torutano/Downloads/5ED96C0A-4290-47C2-B68F-5D172ED5EB8D.png` — Acti trigger-key sheet, 1170 x 2532 px.
- Current implementation captures:
  - `artifacts/design-qa/current/skill-builder.png` — iPhone 16 Pro, 1206 x 2622 px.
  - `artifacts/design-qa/current/trigger-key.png` — iPhone 16 Pro, 1206 x 2622 px.
- Combined comparison inputs actually inspected:
  - `artifacts/design-qa/current/skill-builder-comparison.png`.
  - `artifacts/design-qa/current/trigger-key-comparison.png`.
- Runtime: iPhone 16 Pro Simulator, iOS 18.6, 402 x 874 pt at 3x, light appearance. Captures use QA launch routes that seed deterministic local Skills; they do not alter release behavior.
- Comparison method: each reference/current pair was scaled to the same 946 x 2048 frame, joined horizontally, and judged from the combined input rather than separate screenshots.

## What now matches

- The builder starts with the same large intent question, generous white prompt surface, quick examples, pale blue-grey canvas, optional customization, and one fixed bottom action.
- The implemented path is shorter than the benchmark for its supported task: intent -> local preview -> Add to Keyboard -> key selection. A second duplicate fixture run is no longer required.
- Preview output becomes stale after test-input edits and blocks installation until refreshed; this prevents a visually reviewed result from diverging from the installed Skill.
- Trigger assignment now opens at a 72% bottom-sheet detent, closely matching the Acti reference. Users may expand it to full height; accessibility Dynamic Type opens directly at the large detent.
- QWERTY row geometry, occupied-key muting, black/grey capsule CTA, secondary Cancel action, light material, corner radii, and hierarchy are visibly close to the reference.
- Normal tap versus long-press behavior is explained before saving. Occupied keys remain selectable so conflict replacement is an explicit action rather than an unexplained dead key.

## Verified interaction and accessibility

- All 26 A-Z keys are exposed to UI automation at accessibility text size.
- The optional local test can be expanded, scrolled above the sticky footer, executed, and its success state reached.
- Save is disabled until a key is selected and shared keyboard authority is available.
- Selection, success, and error states emit iOS haptics; successful assignment also posts a VoiceOver announcement.
- A created but not-yet-assigned private Skill survives a host restart.
- UI regression result: 7/7 tests passed on iPhone 16 Pro / iOS 18.6 after the final interaction fixes; the two new focused detent tests also passed.

## Remaining benchmark gaps

- **P1 — capability breadth:** the Acti reference exposes Apps/APIs/Agents and public/private publishing. The current shipped-safe builder intentionally supports private, on-device selected-text transforms only. Connected-tool Skill composition must not be represented as working until OAuth scopes, review, confirmation, failure recovery, and execution receipts are implemented end to end.
- **P1 — marketplace/creator loop:** public discovery, following, publishing, update history, creator analytics, and ranking are not part of this private-local flow.
- **P1 — physical keyboard qualification:** simulator UI evidence cannot prove third-party editor behavior, long-press timing, globe switching, memory pressure, orientation, or hardware keyboard coexistence. These remain physical-device/TestFlight gates.
- **P2 — typography:** the app uses the native iOS rounded/system stack rather than Acti's proprietary-looking face. Weight and wrapping are matched without embedding an unlicensed font.
- **P3 — dark appearance:** this benchmark-derived flow intentionally uses a coherent light visual system. A separate dark token system remains future polish.

## Comparison history

1. Earlier captures had a nearly full-screen trigger sheet. The combined Acti/current input showed the benchmark starts around one-third down the screen, so the regular detent was changed to 72% while preserving `.large` for expansion.
2. Accessibility UI testing then showed that the optional fixture could sit beneath the sticky Add/Cancel footer. The content now reserves the footer height, and the test scrolls it into a genuinely hittable position.
3. UI isolation exposed persisted builder text leaking between tests. The private, owner/epoch-bound draft is now explicitly cleared by the UI-test reset route while remaining restored during real interrupted creation.
4. The final combined trigger comparison shows matched modal hierarchy, keyboard shape, disabled-key treatment, and bottom actions. The builder comparison shows a faithful visual language but also makes the connected-tool/public capability gap visible and explicit.
