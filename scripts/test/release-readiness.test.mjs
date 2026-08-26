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

test('passed E2E evidence is bound to a real-device classification and one candidate artifact', () => {
  const matrix = JSON.parse(fs.readFileSync(path.join(root, 'docs/release-e2e-matrix.json'), 'utf8'));
  const sourceCommit = 'a'.repeat(40);
  const artifactDigest = `sha256:${'b'.repeat(64)}`;
  matrix.status = 'passed';
  matrix.candidate = { source_commit: sourceCommit, artifact_digest: artifactDigest };
  matrix.targets = matrix.targets.map((target) => ({
    ...target,
    status: 'passed',
    runs: [{
      run_id: `protected-${target.platform}-1`,
      runner_id: `runner-${target.platform}-1`,
      attested: true,
      evidence_class: 'protected_external',
      environment: 'protected_device',
      device_id: `${target.platform}-device-1`,
      source_commit: sourceCommit,
      artifact_digest: artifactDigest,
      scenarios: matrix.required_scenarios,
      accessibility_tools: [target.platform === 'ios' ? 'voiceover' : 'talkback'],
      field_classes: matrix.required_field_classes,
      lifecycle_events: matrix.required_lifecycle_events,
    }],
  }));
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mobile-ai-keyboard-e2e-'));
  const file = path.join(tempDir, 'matrix.json');
  try {
    fs.writeFileSync(file, `${JSON.stringify(matrix)}\n`);
    const valid = evaluate({ staticOnly: true, matrix: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(valid.status, 'pass');

    const missingCoverage = {
      ...matrix,
      targets: matrix.targets.map((target) => ({
        ...target,
        runs: target.runs.map(({ field_classes: _fieldClasses, lifecycle_events: _lifecycleEvents, ...run }) => run),
      })),
    };
    fs.writeFileSync(file, `${JSON.stringify(missingCoverage)}\n`);
    const rejectedCoverage = evaluate({ staticOnly: true, matrix: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(rejectedCoverage.status, 'fail');
    assert.match(rejectedCoverage.detail, /field-class|lifecycle-event/);

    const tampered = { ...matrix, targets: matrix.targets.map((target) => ({ ...target, runs: target.runs.map((run) => ({ ...run, artifact_digest: `sha256:${'c'.repeat(64)}` })) })) };
    fs.writeFileSync(file, `${JSON.stringify(tampered)}\n`);
    const rejected = evaluate({ staticOnly: true, matrix: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(rejected.status, 'fail');
    assert.match(rejected.detail, /artifact_digest/);

    fs.writeFileSync(file, `${JSON.stringify(matrix)}\n`);
    const missingSha = evaluate({ staticOnly: true, matrix: file, candidateSha: null }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(missingSha.status, 'fail');
    assert.match(missingSha.detail, /candidate_sha/);
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

test('passed performance evidence binds every measurement to the candidate artifact and protected device', () => {
  const performance = JSON.parse(fs.readFileSync(path.join(root, 'docs/release-performance-evidence.json'), 'utf8'));
  const sourceCommit = 'd'.repeat(40);
  const artifactDigest = `sha256:${'e'.repeat(64)}`;
  performance.status = 'passed';
  performance.candidate = { source_commit: sourceCommit, artifact_digest: artifactDigest };
  performance.measurements = performance.required_metrics.flatMap((metric, metricIndex) => ['ios', 'android'].map((platform, platformIndex) => ({
    metric_id: metric,
    platform,
    device: `${platform}-device-${metricIndex}`,
    status: 'passed',
    value: 1,
    unit: 'ms',
    sample_count: 100,
    evidence: {
      class: 'protected_external',
      environment: 'protected_device',
      source_commit: sourceCommit,
      artifact_digest: artifactDigest,
      run_id: `performance-${platform}-${metricIndex}`,
      runner_id: `protected-runner-${platformIndex + 1}`,
      attested: true,
    },
  })));
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mobile-ai-keyboard-performance-'));
  const file = path.join(tempDir, 'performance.json');
  try {
    fs.writeFileSync(file, `${JSON.stringify(performance)}\n`);
    const valid = evaluate({ staticOnly: true, performance: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.performance.schema');
    assert.equal(valid.status, 'pass');

    const missingAndroid = { ...performance, measurements: performance.measurements.filter((measurement) => measurement.platform === 'ios') };
    fs.writeFileSync(file, `${JSON.stringify(missingAndroid)}\n`);
    const rejectedPlatform = evaluate({ staticOnly: true, performance: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.performance.schema');
    assert.equal(rejectedPlatform.status, 'fail');
    assert.match(rejectedPlatform.detail, /android:/);

    const invalidMeasurement = {
      ...performance,
      measurements: performance.measurements.map((measurement, index) => index === 0 ? { ...measurement, value: null, sample_count: 0 } : measurement),
    };
    fs.writeFileSync(file, `${JSON.stringify(invalidMeasurement)}\n`);
    const rejectedMeasurement = evaluate({ staticOnly: true, performance: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.performance.schema');
    assert.equal(rejectedMeasurement.status, 'fail');
    assert.match(rejectedMeasurement.detail, /finite value|sample_count/);

    const tampered = { ...performance, measurements: performance.measurements.map((measurement, index) => index === 0 ? { ...measurement, evidence: { ...measurement.evidence, artifact_digest: `sha256:${'f'.repeat(64)}` } } : measurement) };
    fs.writeFileSync(file, `${JSON.stringify(tampered)}\n`);
    const rejected = evaluate({ staticOnly: true, performance: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.performance.schema');
    assert.equal(rejected.status, 'fail');
    assert.match(rejected.detail, /artifact_digest/);
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
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

test('release evidence rejects invalid top-level statuses and incomplete archive privacy inspection', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mobile-ai-keyboard-status-'));
  const write = (name, value) => {
    const file = path.join(tempDir, name);
    fs.writeFileSync(file, `${JSON.stringify(value)}\n`);
    return file;
  };
  try {
    const matrix = JSON.parse(fs.readFileSync(path.join(root, 'docs/release-e2e-matrix.json'), 'utf8'));
    matrix.status = 'bogus';
    const matrixResult = evaluate({ staticOnly: true, matrix: write('matrix.json', matrix) }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(matrixResult.status, 'fail');
    assert.match(matrixResult.detail, /invalid matrix status/);

    const performance = JSON.parse(fs.readFileSync(path.join(root, 'docs/release-performance-evidence.json'), 'utf8'));
    performance.status = 'bogus';
    const performanceResult = evaluate({ staticOnly: true, performance: write('performance.json', performance) }).checks.find((check) => check.code === 'evidence.performance.schema');
    assert.equal(performanceResult.status, 'fail');
    assert.match(performanceResult.detail, /invalid performance status/);

    const archive = JSON.parse(fs.readFileSync(path.join(root, 'docs/ios-archive-entitlement-privacy.json'), 'utf8'));
    archive.status = 'bogus';
    const archiveStatusResult = evaluate({ staticOnly: true, iosArchive: write('archive-status.json', archive) }).checks.find((check) => check.code === 'evidence.ios_archive.schema');
    assert.equal(archiveStatusResult.status, 'fail');
    assert.match(archiveStatusResult.detail, /invalid iOS archive status/);

    const sourceCommit = 'f'.repeat(40);
    const artifactDigest = `sha256:${'a'.repeat(64)}`;
    archive.status = 'passed';
    archive.candidate = { source_commit: sourceCommit, artifact_digest: artifactDigest };
    archive.entitlements = { host: { app_group: 'group.example' }, extension: { app_group: 'group.example' } };
    archive.extension_info = { requests_open_access: true };
    archive.privacy_manifests = {
      host: { embedded: true, declares_no_collected_data: false },
      extension: { embedded: true, declares_no_collected_data: true },
    };
    archive.evidence = {
      class: 'protected_external',
      environment: 'protected_device',
      source_commit: sourceCommit,
      artifact_digest: artifactDigest,
      run_id: 'archive-run-1',
      runner_id: 'protected-runner-1',
      attested: true,
    };
    archive.notes = 'protected archive inspection';
    const archivePrivacyResult = evaluate({ staticOnly: true, iosArchive: write('archive-privacy.json', archive), candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.ios_archive.schema');
    assert.equal(archivePrivacyResult.status, 'fail');
    assert.match(archivePrivacyResult.detail, /privacy manifest.*embedded and no collected data/);
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
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
