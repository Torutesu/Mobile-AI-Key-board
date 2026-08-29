import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const controller = fs.readFileSync('apps/ios/MobileAIKeyboardExtension/KeyboardViewController.swift', 'utf8');
const shortcutModels = fs.readFileSync('apps/ios/Sources/MobileAIKeyboardCore/ShortcutModels.swift', 'utf8');
const generationGate = shortcutModels.slice(shortcutModels.indexOf('public struct ShortcutGenerationGate'), shortcutModels.indexOf('public final class AppGroupShortcutSnapshotStore'));

test('missing Skill authority cannot erase an unrelated local command flow', () => {
  const applyStart = controller.indexOf('private func applyShortcutSnapshot');
  const applyEnd = controller.indexOf('private func updateBoundKeyPresentation', applyStart);
  const apply = controller.slice(applyStart, applyEnd);
  assert.match(apply, /pendingShortcutActivation != nil \|\| pendingShortcutSkill != nil \|\| paletteWasVisible/);
  assert.match(apply, /shortcutGenerationGate\.accepts\(generation: snapshot\.generation, boundary: boundary\)/);
  assert.match(generationGate, /AuthorityScope\(boundary: boundary\)/);
  assert.match(generationGate, /guard generation >= floor/);
  assert.doesNotMatch(generationGate, /expiresAt|contentDigest/);
  assert.doesNotMatch(apply, /shortcutSkills = \[:\]\s*\n\s*clearEphemeralState/);
});

test('document mutations resynchronize autocapitalization and cancelled holds cannot eat the next tap', () => {
  for (const method of ['space()', 'returnKey()', 'startDeleteRepeat()', 'repeatDeleteBackward()']) {
    const start = controller.indexOf(`private func ${method}`);
    assert.ok(start >= 0, `missing ${method}`);
    const body = controller.slice(start, controller.indexOf('\n    }', start) + 6);
    assert.match(body, /synchronizeAutocapitalizationAfterDocumentMutation\(\)/, method);
  }
  const cancelled = controller.slice(controller.indexOf('case .cancelled, .failed:'), controller.indexOf('default: break', controller.indexOf('case .cancelled, .failed:')));
  assert.doesNotMatch(cancelled, /consumedLongPressKey = nil/);
  assert.match(controller, /touchDown\)\n\s*button\.addTarget\(self, action: #selector\(letterPressed/);
  assert.match(controller, /private func letterTouchBegan[\s\S]*consumedLongPressKey = nil/);
  assert.match(controller, /Most hosts update proxy context synchronously[\s\S]*synchronizeAutocapitalization\(\)[\s\S]*DispatchQueue\.main\.async/);
});

test('two-finger letter chords are suppressed before tap commit or Skill invocation', () => {
  assert.match(controller, /private var activeLetterTouchKeys: Set<ShortcutKeyCode>/);
  assert.match(controller, /private var suppressedMultiTouchKeys: Set<ShortcutKeyCode>/);
  const touchBegan = controller.slice(controller.indexOf('private func letterTouchBegan'), controller.indexOf('private func letterTouchEnded'));
  assert.match(touchBegan, /otherKeys = activeLetterTouchKeys\.subtracting/);
  assert.match(touchBegan, /suppressedMultiTouchKeys\.formUnion\(otherKeys\)/);
  const pressed = controller.slice(controller.indexOf('private func letterPressed'), controller.indexOf('private func letterTouchBegan'));
  assert.match(pressed, /if suppressedMultiTouchKeys\.contains\(key\) \{ return \}/);
  const longPress = controller.slice(controller.indexOf('private func skillKeyLongPress'), controller.indexOf('private func invokeShortcut'));
  assert.match(longPress, /activeLetterTouchKeys\.count <= 1/);
  assert.match(longPress, /!suppressedMultiTouchKeys\.contains\(key\)/);
});

test('warm keyboard rechecks Full Access and numeric fields cannot expose QWERTY', () => {
  const refresh = controller.slice(controller.indexOf('private func refreshVisibleShortcutAuthority'), controller.indexOf('private func refreshShortcutSnapshot'));
  assert.match(refresh, /updateFullAccessState\(\)/);
  assert.match(controller, /func textDidChange[\s\S]*updateFullAccessState\(\)/);
  assert.match(controller, /if usesNumericOnlySurface/);
  assert.match(controller, /case \.phonePad, \.numberPad, \.decimalPad, \.asciiCapableNumberPad/);
});

test('phone orientation is derived from traits rather than the constrained input-view aspect ratio', () => {
  const heightStart = controller.indexOf('private var keyboardHeight');
  const heightEnd = controller.indexOf('private func updateInstalledKeyboardHeightIfNeeded', heightStart);
  const height = controller.slice(heightStart, heightEnd);
  assert.match(height, /verticalSizeClass == \.compact/);
  assert.doesNotMatch(height, /view\.bounds\.width > view\.bounds\.height/);
});
