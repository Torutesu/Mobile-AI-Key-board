import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const onboarding = fs.readFileSync('apps/ios/MobileAIKeyboardHost/OnboardingView.swift', 'utf8');
const launchScreen = fs.readFileSync('apps/ios/MobileAIKeyboardHost/LaunchScreen.storyboard', 'utf8');

test('cold launch and fixed white onboarding surfaces share one light visual system', () => {
  assert.match(onboarding, /\.preferredColorScheme\(\.light\)/);
  assert.match(launchScreen, /backgroundColor" red="0\.94" green="0\.96" blue="0\.98"/);
  assert.doesNotMatch(launchScreen, /systemBackgroundColor/);
});

test('first screen presents value and local demo before keyboard access', () => {
  const welcome = onboarding.indexOf('private var welcomePage');
  const localDemo = onboarding.indexOf('private var tryItPage');
  const access = onboarding.indexOf('private var accessPage');
  assert.ok(welcome >= 0 && localDemo > welcome && access > localDemo);
  assert.match(onboarding, /試すだけなら、アクセス許可は不要です/);
  assert.match(onboarding, /LocalRewriteEngine\(\)\.politeRewrite/);
});
