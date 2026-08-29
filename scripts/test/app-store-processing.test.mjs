import assert from 'node:assert/strict';
import test from 'node:test';
import { validateProcessingStatus } from '../validate-app-store-processing.mjs';

const expected = { appleId: '1234567890', marketingVersion: '1.2.3', buildVersion: '456' };

test('accepts a terminal status bound to the exact app version and build', () => {
  const errors = validateProcessingStatus({
    data: { appleId: '1234567890', bundleShortVersionString: '1.2.3', bundleVersion: '456', processingState: 'COMPLETE' },
  }, expected);
  assert.deepEqual(errors, []);
});

test('rejects a successful response for a different build', () => {
  const errors = validateProcessingStatus({
    data: { appleId: '1234567890', bundleShortVersionString: '1.2.3', bundleVersion: '455', processingState: 'COMPLETE' },
  }, expected);
  assert.match(errors.join('; '), /build version 456 is not present/);
});

test('rejects a syntactically valid failure or non-terminal response', () => {
  assert.match(validateProcessingStatus({
    data: { appleId: '1234567890', bundleShortVersionString: '1.2.3', bundleVersion: '456', processingState: 'FAILED' },
  }, expected).join('; '), /failure marker/);
  assert.match(validateProcessingStatus({
    data: { appleId: '1234567890', bundleShortVersionString: '1.2.3', bundleVersion: '456', processingState: 'PROCESSING' },
  }, expected).join('; '), /no recognized successful terminal state/);
});
