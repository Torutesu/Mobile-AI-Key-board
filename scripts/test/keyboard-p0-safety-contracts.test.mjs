import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');

test('Android bound keys expose an accessibility long-click without changing ordinary click input', () => {
  const surface = read('apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/ime/KeyboardSurface.kt');
  assert.match(surface, /setOnLongClickListener\s*\{[\s\S]*?callbacks\.onShortcut\(shortcut\)[\s\S]*?true[\s\S]*?\}/);
  assert.match(surface, /val trigger = Runnable[\s\S]*?performLongClick\(\)/);
  assert.match(surface, /setOnClickListener\s*\{[\s\S]*?commitBoundCharacter\(\)/);
});

test('Android selection-only shortcuts cannot use their label as transformable content', () => {
  const service = read('apps/android/app/src/main/java/com/torutesu/mobileaikeyboard/ime/KeyboardImeService.kt');
  assert.match(service, /capture\(command = "", useSelection = true, useSurrounding = false\)/);
  assert.doesNotMatch(service, /capture\(exact\.skillName, useSelection = true/);
});

test('iOS local shortcut execution is selection-only and refreshes live sensitive-field traits', () => {
  const controller = read('apps/ios/MobileAIKeyboardExtension/KeyboardViewController.swift');
  const shortcutExecution = controller.match(/private func invokeShortcut[\s\S]*?\/\/ MARK: Command, capture review/)?.[0] ?? '';
  assert.match(shortcutExecution, /ShortcutCapturePolicy\.localSelection\(skill: skill, selectedText: textDocumentProxy\.selectedText\)/);
  assert.doesNotMatch(shortcutExecution, /source = \.surroundingContext/);
  assert.match(controller, /guard draft\.source != \.surroundingContext else[\s\S]*?surroundingContextApplyUnavailable/);
  assert.match(controller, /func textDidChange[\s\S]*?refreshFieldSecurityFromProxy\(\)/);
  assert.match(controller, /textDocumentProxy\.textContentType\?\.rawValue/);
  assert.match(controller, /textDocumentProxy\.isSecureTextEntry \?\? false/);
});
