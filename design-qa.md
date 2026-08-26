# Skill Keys design QA

**Final result:** passed

## Evidence

- Source visual truth:
  - `/Users/torutano/Downloads/FFC1E5FB-F171-4676-8828-20DE35D9616A.png` (Acti Skill Keys dashboard, 1170 x 2532 px)
  - `/Users/torutano/Downloads/5ED96C0A-4290-47C2-B68F-5D172ED5EB8D.png` (Acti trigger-key sheet, 1170 x 2532 px)
- Rendered implementation:
  - `artifacts/design-qa/skill-keys-ios-final.png` (1206 x 2622 px)
  - `artifacts/design-qa/trigger-key-sheet-ios-final.png` (1206 x 2622 px)
- Combined comparison inputs:
  - `artifacts/design-qa/skill-keys-comparison-final.png`
  - `artifacts/design-qa/trigger-key-comparison-final.png`
- Viewport/state: iPhone 16 Pro Simulator, iOS 18.6, 402 x 874 pt at 3x, light appearance. QA-only launch arguments seeded two exact local Skills and opened the assignment sheet without changing release behavior.
- Density normalization: each source and implementation pair was independently scaled to 1266 px height before horizontal composition. The source and implementation were judged from those combined equal-height inputs.

## Findings

- No actionable P0/P1/P2 visual findings remain.
- Typography: the implementation uses the native iOS rounded/system stack rather than Acti's proprietary-looking rounded face. Weight, hierarchy, wrapping, and small metadata remain legible and close to the reference; this is an intentional platform-safe substitution.
- Spacing/layout: the QWERTY preview, large white cards, blue-grey canvas, Skill Key rows, disabled occupied keys, and bottom assignment actions reproduce the reference hierarchy. The implementation intentionally uses a standard navigation title and includes the available-Skill list below the matched above-the-fold core.
- Colors/tokens: the pale blue-grey background, white cards, cyan assigned-key indicator, black primary type, muted metadata, and disabled grey action match the reference semantics. The view explicitly uses light appearance because its benchmark-derived token set is light-only; a separate dark token set remains future polish.
- Image quality/assets: these two states require no proprietary logo or illustration. System icons are SF Symbols; no placeholder image, emoji substitute, hand-drawn SVG, or rasterized UI is used.
- Copy/content: Japanese labels are product-accurate rather than literal English copies. They clearly state tap versus long press, Review-before-execution, exact local Skill names, and occupied-key state.
- Accessibility/interaction: A-Z keys expose assigned/available state, occupied keys are disabled, minimum key/action heights are preserved, ordinary tap behavior is separately implemented, and the primary Add action remains disabled until a valid free key is selected.

## Comparison history

1. The initial capture exposed a P1 contrast failure: dynamic dark-mode foregrounds were rendered over a fixed light benchmark background. It also placed a large explanatory card ahead of the core keyboard.
2. Fixed by applying the coherent light benchmark token set to the Skill Keys flow and moving safety/full-access disclosure below the core task.
3. Trigger-sheet comparison then found a P2 structural mismatch: Add/Cancel lived in the navigation bar while the reference uses large bottom actions. Fixed with safe-area bottom capsule actions and recaptured as `artifacts/design-qa/trigger-key-sheet-ios-final.png`.
4. Final combined comparisons show no remaining P0/P1/P2 mismatch. Residual differences are intentional product/platform choices described above.

## Focused-region evidence

- Dashboard focus: QWERTY key rows and the H/M assigned-key underline/background treatment are readable in `skill-keys-comparison-final.png`.
- Assignment focus: occupied H/M states, enabled A-Z key geometry, explanatory copy, and bottom Add/Cancel hierarchy are readable in `trigger-key-comparison-final.png`.

## Follow-up polish

- P3: add a separately designed dark token set rather than dynamically mixing system dark foregrounds with the benchmark light canvas.
- P3: add a branded top-level keyboard-tab shell after the product name and identity system are finalized.
