import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { evaluate } from '../release-readiness.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

test('source gate catches the historical false Full Access declaration', () => {
  const file = path.join(root, 'docs/16-store-privacy-declarations.md');
  const original = fs.readFileSync(file, 'utf8');
  try {
    fs.writeFileSync(file, original.replace('`RequestsOpenAccess=true`', '`RequestsOpenAccess=false`'));
    const report = evaluate({ staticOnly: true });
    const result = report.checks.find((check) => check.code === 'privacy.docs.full_access');
    assert.equal(result.status, 'fail');
  } finally {
    fs.writeFileSync(file, original);
  }
});

test('repository readiness is not proven without protected physical evidence', () => {
  const report = evaluate({ staticOnly: true });
  const matrix = report.checks.find((check) => check.code === 'evidence.e2e.proof');
  const performance = report.checks.find((check) => check.code === 'evidence.performance.proof');
  assert.equal(matrix.status, 'not_proven');
  assert.equal(performance.status, 'not_proven');
});

test('normal release invocation fails closed for absent protected evidence', () => {
  const script = path.join(root, 'scripts/release-readiness.mjs');
  const result = spawnSync(process.execPath, [script], { cwd: root, encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.equal(JSON.parse(result.stdout).status, 'not_proven');
});

test('fixture and simulator markers cannot qualify a passed E2E run', () => {
  const file = path.join(root, 'docs/release-e2e-matrix.json');
  const original = fs.readFileSync(file, 'utf8');
  try {
    const matrix = JSON.parse(original);
    matrix.status = 'passed';
    matrix.candidate = { source_commit: 'abc', artifact_digest: 'sha256:abc' };
    matrix.targets = matrix.targets.map((target) => ({
      ...target,
      status: 'passed',
      runs: [{ run_id: 'run-1', runner_id: 'runner-1', attested: true, evidence_class: 'protected_external', note: 'simulator only' }],
    }));
    fs.writeFileSync(file, `${JSON.stringify(matrix, null, 2)}\n`);
    const report = evaluate({ staticOnly: true });
    const result = report.checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(result.status, 'fail');
  } finally {
    fs.writeFileSync(file, original);
  }
});

test('archive evidence distinguishes extension Info.plist from code-signing entitlements', () => {
  const file = path.join(root, 'docs/ios-archive-entitlement-privacy.json');
  const original = fs.readFileSync(file, 'utf8');
  try {
    const archive = JSON.parse(original);
    archive.status = 'passed';
    archive.candidate = { source_commit: 'abc', artifact_digest: 'sha256:abc' };
    archive.entitlements = { host: { app_group: 'group.example' }, extension: { app_group: 'group.example' } };
    archive.extension_info = { requests_open_access: false };
    archive.privacy_manifests = { host: { embedded: true }, extension: { embedded: true } };
    archive.evidence = { class: 'protected_external', run_id: 'run-archive-1', runner_id: 'protected-macos-1', attested: true, artifact_digest: 'sha256:archive' };
    fs.writeFileSync(file, `${JSON.stringify(archive, null, 2)}\n`);
    const report = evaluate({ staticOnly: true });
    const result = report.checks.find((check) => check.code === 'evidence.ios_archive.schema');
    assert.equal(result.status, 'fail');
    assert.match(result.detail, /Info\.plist/);
  } finally {
    fs.writeFileSync(file, original);
  }
});
