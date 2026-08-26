import assert from 'node:assert/strict';
import test from 'node:test';
import { inspectVerticalSlice } from '../check-shortcut-vertical-slice.mjs';

test('vertical slice reports implemented source seams without claiming runtime proof', () => {
  const report = inspectVerticalSlice();
  assert.equal(report.schema_version, 'mobile-ai-keyboard.shortcut-vertical-slice.v1');
  assert.equal(report.evidence_class, 'static_source_contract');
  assert.equal(report.qualification_status, 'not_proven');
  assert.match(report.claim_boundary, /never proves device/);
  assert.equal(report.status, 'passed');

  for (const platform of ['ios', 'android']) {
    const checks = report.platforms[platform];
    assert.equal(checks.length, 6);
    assert.equal(checks.find((check) => check.id === 'builder_immutable_skill_identity').status, 'passed');
    assert.equal(checks.find((check) => check.id === 'builder_deploy_requires_exact_confirmation').status, 'passed');
    assert.equal(checks.find((check) => check.id === 'az_assignment_publishes_snapshot').status, 'passed');
    assert.equal(checks.find((check) => check.id === 'closed_local_executor_binds_exact_identity').status, 'passed');
    assert.equal(checks.find((check) => check.id.includes('restart_persistence')).status, 'passed');
  }

  const addChecks = ['ios', 'android'].map((platform) => report.platforms[platform].find((check) => check.id === 'explicit_add_separates_deploy_and_assignment'));
  assert.ok(addChecks.every((check) => check.status === 'passed'));
  assert.ok(addChecks.every((check) => check.missing.length === 0));
});

test('strict vertical-slice source mode can pass while device qualification stays fail-closed', () => {
  const report = inspectVerticalSlice();
  assert.equal(report.status, 'passed');
  assert.equal(report.qualification_status, 'not_proven');
  assert.equal(report.disclosures.every((check) => check.status === 'passed'), true);
  assert.ok(Object.values(report.platforms).flat().every((check) => check.status === 'passed'));
});
