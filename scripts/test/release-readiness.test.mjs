import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
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

test('benchmark gate rejects digest tampering, duplicates, threshold/status drift, and forged protected proof', () => {
  const benchmarkScript = path.join(root, 'scripts/performance-benchmark.mjs');
  const generated = spawnSync(process.execPath, [benchmarkScript], { cwd: root, encoding: 'utf8' });
  assert.equal(generated.status, 0);
  const baseline = JSON.parse(generated.stdout);
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mobile-ai-keyboard-benchmark-'));
  const runGate = (value) => {
    const file = path.join(tempDir, 'benchmark.json');
    fs.writeFileSync(file, `${JSON.stringify(value)}\n`);
    return evaluate({ staticOnly: true, benchmark: file }).checks.find((check) => check.code === 'evidence.benchmark.schema');
  };
  try {
    const digestTampered = runGate({ ...baseline, report_digest: `sha256:${'f'.repeat(64)}` });
    assert.equal(digestTampered.status, 'fail');
    assert.match(digestTampered.detail, /report_digest/);

    const duplicate = runGate({ ...baseline, observations: [...baseline.observations, baseline.observations[0]] });
    assert.equal(duplicate.status, 'fail');
    assert.match(duplicate.detail, /duplicate benchmark observation/);

    const statusDrift = runGate({ ...baseline, diagnostic_status: 'failed' });
    assert.equal(statusDrift.status, 'fail');
    assert.match(statusDrift.detail, /diagnostic_status/);

    const forgedProtected = runGate({ ...baseline, environment: 'protected_device', qualification_status: 'passed', evidence: { kind: 'protected_external', test_run_id: 'protected-run', verifier_kind: 'protected_runner', verifier_id: 'runner', artifact_digest: `sha256:${'a'.repeat(64)}` } });
    assert.equal(forgedProtected.status, 'fail');
    assert.match(forgedProtected.detail, /environment|evidence kind|canonical report/);
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});
