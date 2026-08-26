import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { generateKeyPairSync, sign as signPayload } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { evaluate } from '../release-readiness.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(',')}}`;
  return JSON.stringify(value);
}

function protectedRunPayload(run) {
  const copy = structuredClone(run);
  delete copy.attestation.signature;
  return Buffer.from(stableJson({ schema: 'mobile-ai-keyboard.protected-run.v1', run: copy }), 'utf8');
}

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
  const testNow = Date.parse('2026-08-27T05:00:00.000Z');
  matrix.status = 'passed';
  matrix.candidate = { source_commit: sourceCommit, artifact_digest: artifactDigest };
  matrix.targets = matrix.targets.map((target) => ({
    ...target,
    device_classes: target.platform === 'ios'
      ? ['iphone_baseline', 'iphone_current', 'iphone_small', 'ipad_portrait_landscape']
      : ['android11_baseline', 'pixel_current', 'samsung_current', 'android_low_memory'],
    status: 'passed',
    runs: (target.platform === 'ios'
      ? ['iphone_baseline', 'iphone_current', 'iphone_small', 'ipad_portrait_landscape']
      : ['android11_baseline', 'pixel_current', 'samsung_current', 'android_low_memory']).map((deviceClass, deviceIndex) => ({
      status: 'passed',
      run_id: `protected-${target.platform}-${deviceIndex + 1}`,
      runner_id: `runner-${target.platform}-${deviceIndex + 1}`,
      evidence_class: 'protected_external',
      environment: 'protected_device',
      device_id: `${target.platform}-device-${deviceIndex + 1}`,
      device_class: deviceClass,
      device_model: target.platform === 'ios' ? `iPhone ${17 - deviceIndex}` : ['Android 11 baseline', 'Pixel 9', 'Samsung Galaxy S25', 'Android low-memory'][deviceIndex],
      os_version: target.platform === 'ios' ? 'iOS 18.6' : 'Android 35',
      source_commit: sourceCommit,
      artifact_digest: artifactDigest,
      attestation: {
        status: 'verified', verifier_kind: 'protected_runner', verifier_id: `runner-${target.platform}-${deviceIndex + 1}`, verification_id: `attestation-${target.platform}-${deviceIndex + 1}`,
        signature: 'pending', issued_at: new Date(testNow - 60_000).toISOString(), expires_at: new Date(testNow + 86_400_000).toISOString(), nonce: `nonce_${target.platform}_${deviceIndex + 1}_protected`,
        run_id: `protected-${target.platform}-${deviceIndex + 1}`, device_id: `${target.platform}-device-${deviceIndex + 1}`, source_commit: sourceCommit, artifact_digest: artifactDigest,
      },
      scenario_results: matrix.required_scenarios.map((scenario) => ({ scenario_id: scenario, status: 'passed', run_id: `protected-${target.platform}-${deviceIndex + 1}`, evidence_ref: `e2e:${target.platform}:${scenario}`, evidence_digest: `sha256:${'d'.repeat(64)}` })),
      field_class_results: matrix.required_field_classes.map((fieldClass) => ({ field_class: fieldClass, status: 'passed', run_id: `protected-${target.platform}-${deviceIndex + 1}`, evidence_ref: `e2e:${target.platform}:${fieldClass}`, evidence_digest: `sha256:${'d'.repeat(64)}` })),
      lifecycle_results: matrix.required_lifecycle_events.map((lifecycleEvent) => ({ lifecycle_event: lifecycleEvent, status: 'passed', run_id: `protected-${target.platform}-${deviceIndex + 1}`, evidence_ref: `e2e:${target.platform}:${lifecycleEvent}`, evidence_digest: `sha256:${'d'.repeat(64)}` })),
      accessibility_tools: [target.platform === 'ios' ? 'voiceover' : 'talkback'],
      app_evidence: target.apps.map((app) => ({ app_id: app, app_identifier: `com.example.${app.toLowerCase()}`, run_id: `protected-${target.platform}-${deviceIndex + 1}`, evidence_ref: `e2e:${target.platform}:app:${app}`, evidence_digest: `sha256:${'d'.repeat(64)}` })),
    })),
  }));
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const publicKeyPem = publicKey.export({ type: 'spki', format: 'pem' });
  const trustedAttestationKeys = {};
  for (const target of matrix.targets) {
    for (const run of target.runs) {
      trustedAttestationKeys[run.runner_id] = publicKeyPem;
      run.attestation.signature = signPayload(null, protectedRunPayload(run), privateKey).toString('base64');
    }
  }
  const evaluateSigned = (options) => evaluate({ trustedAttestationKeys, nowMillis: testNow, ...options });
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mobile-ai-keyboard-e2e-'));
  const file = path.join(tempDir, 'matrix.json');
  try {
    fs.writeFileSync(file, `${JSON.stringify(matrix)}\n`);
    const valid = evaluateSigned({ staticOnly: true, matrix: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(valid.status, 'pass');

    const untrusted = evaluate({ staticOnly: true, matrix: file, candidateSha: sourceCommit, trustedAttestationKeys: {}, nowMillis: testNow }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(untrusted.status, 'fail');
    assert.match(untrusted.detail, /verifier is not trusted/);

    const forgedSignature = structuredClone(matrix);
    forgedSignature.targets[0].runs[0].attestation.signature = Buffer.from('forged').toString('base64');
    fs.writeFileSync(file, `${JSON.stringify(forgedSignature)}\n`);
    const rejectedSignature = evaluateSigned({ staticOnly: true, matrix: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(rejectedSignature.status, 'fail');
    assert.match(rejectedSignature.detail, /signature verification failed/);
    fs.writeFileSync(file, `${JSON.stringify(matrix)}\n`);

    const { publicKey: rsaPublicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
    const rsaTrustedKeys = Object.fromEntries(Object.keys(trustedAttestationKeys).map((id) => [id, rsaPublicKey.export({ type: 'spki', format: 'pem' })]));
    const rejectedRsa = evaluate({ staticOnly: true, matrix: file, candidateSha: sourceCommit, trustedAttestationKeys: rsaTrustedKeys, nowMillis: testNow }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(rejectedRsa.status, 'fail');
    assert.match(rejectedRsa.detail, /signature verification failed/);

    const staleAttestation = structuredClone(matrix);
    staleAttestation.targets[0].runs[0].attestation.expires_at = new Date(testNow - 1).toISOString();
    fs.writeFileSync(file, `${JSON.stringify(staleAttestation)}\n`);
    const rejectedFreshness = evaluateSigned({ staticOnly: true, matrix: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(rejectedFreshness.status, 'fail');
    assert.match(rejectedFreshness.detail, /freshness window is invalid/);
    fs.writeFileSync(file, `${JSON.stringify(matrix)}\n`);

    const missingCoverage = {
      ...matrix,
      targets: matrix.targets.map((target) => ({
        ...target,
        runs: target.runs.map(({ field_class_results: _fieldResults, lifecycle_results: _lifecycleResults, ...run }) => run),
      })),
    };
    fs.writeFileSync(file, `${JSON.stringify(missingCoverage)}\n`);
    const rejectedCoverage = evaluateSigned({ staticOnly: true, matrix: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(rejectedCoverage.status, 'fail');
    assert.match(rejectedCoverage.detail, /field class|lifecycle event/);

    const fakeAppCoverage = {
      ...matrix,
      targets: matrix.targets.map((target) => ({
        ...target,
        apps: target.apps.map((app, index) => index === 0 ? 'Unbound Test App' : app),
        runs: target.runs.map((run) => ({ ...run, app_evidence: run.app_evidence.map((app, index) => index === 0 ? { ...app, app_id: 'Unbound Test App' } : app) })),
      })),
    };
    fs.writeFileSync(file, `${JSON.stringify(fakeAppCoverage)}\n`);
    const rejectedApps = evaluateSigned({ staticOnly: true, matrix: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(rejectedApps.status, 'fail');
    assert.match(rejectedApps.detail, /required app/);

    const tampered = { ...matrix, targets: matrix.targets.map((target) => ({ ...target, runs: target.runs.map((run) => ({ ...run, artifact_digest: `sha256:${'c'.repeat(64)}` })) })) };
    fs.writeFileSync(file, `${JSON.stringify(tampered)}\n`);
    const rejected = evaluateSigned({ staticOnly: true, matrix: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(rejected.status, 'fail');
    assert.match(rejected.detail, /artifact_digest/);

    fs.writeFileSync(file, `${JSON.stringify(matrix)}\n`);
    const missingSha = evaluateSigned({ staticOnly: true, matrix: file, candidateSha: null }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(missingSha.status, 'fail');
    assert.match(missingSha.detail, /candidate_sha/);

    const noRunStatus = {
      ...matrix,
      targets: matrix.targets.map((target) => ({ ...target, runs: target.runs.map(({ status: _status, ...run }) => run) })),
    };
    fs.writeFileSync(file, `${JSON.stringify(noRunStatus)}\n`);
    const rejectedStatus = evaluateSigned({ staticOnly: true, matrix: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(rejectedStatus.status, 'fail');
    assert.match(rejectedStatus.detail, /status passed/);

    const badScenarioEvidence = {
      ...matrix,
      targets: matrix.targets.map((target) => ({ ...target, runs: target.runs.map((run) => ({ ...run, scenario_results: run.scenario_results.map((result, index) => index === 0 ? { ...result, evidence_ref: '' } : result) })) })),
    };
    fs.writeFileSync(file, `${JSON.stringify(badScenarioEvidence)}\n`);
    const rejectedScenarioEvidence = evaluateSigned({ staticOnly: true, matrix: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(rejectedScenarioEvidence.status, 'fail');
    assert.match(rejectedScenarioEvidence.detail, /scenario .*evidence binding/);

    const unboundEvidence = {
      ...matrix,
      targets: matrix.targets.map((target) => ({ ...target, runs: target.runs.map((run) => ({ ...run, scenario_results: run.scenario_results.map((result, index) => index === 0 ? { ...result, run_id: 'different-run' } : result) })) })),
    };
    fs.writeFileSync(file, `${JSON.stringify(unboundEvidence)}\n`);
    const rejectedUnboundEvidence = evaluateSigned({ staticOnly: true, matrix: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(rejectedUnboundEvidence.status, 'fail');
    assert.match(rejectedUnboundEvidence.detail, /not bound to run_id/);

    const labelUnion = {
      ...matrix,
      targets: matrix.targets.map((target) => ({ ...target, runs: target.runs.map((run) => ({ ...run, scenarios: ['arbitrary_label_union'], attested: true })) })),
    };
    fs.writeFileSync(file, `${JSON.stringify(labelUnion)}\n`);
    const rejectedLabelUnion = evaluateSigned({ staticOnly: true, matrix: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(rejectedLabelUnion.status, 'fail');
    assert.match(rejectedLabelUnion.detail, /legacy label\/self-attestation/);

    const arbitraryRequiredLabel = { ...matrix, required_scenarios: [...matrix.required_scenarios, 'arbitrary_label'] };
    fs.writeFileSync(file, `${JSON.stringify(arbitraryRequiredLabel)}\n`);
    const rejectedArbitraryLabel = evaluateSigned({ staticOnly: true, matrix: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(rejectedArbitraryLabel.status, 'fail');
    assert.match(rejectedArbitraryLabel.detail, /exactly the known required IDs/);

    const oneDevice = { ...matrix, targets: matrix.targets.map((target) => ({ ...target, device_classes: [target.device_classes[0]] })) };
    fs.writeFileSync(file, `${JSON.stringify(oneDevice)}\n`);
    const rejectedDevices = evaluateSigned({ staticOnly: true, matrix: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(rejectedDevices.status, 'fail');
    assert.match(rejectedDevices.detail, /exactly the required device classes/);

    const mismatchedAttestation = {
      ...matrix,
      targets: matrix.targets.map((target) => ({ ...target, runs: target.runs.map((run) => ({ ...run, attestation: { ...run.attestation, device_id: 'different-device' } })) })),
    };
    fs.writeFileSync(file, `${JSON.stringify(mismatchedAttestation)}\n`);
    const rejectedAttestation = evaluateSigned({ staticOnly: true, matrix: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.e2e.schema');
    assert.equal(rejectedAttestation.status, 'fail');
    assert.match(rejectedAttestation.detail, /attestation device_id/);
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
  const successMinimumMetrics = new Set(['crash_free_sessions_rate', 'offline_success_rate', 'provider_timeout_recovery_rate']);
  performance.measurements = performance.required_metrics.flatMap((metric, metricIndex) => ['ios', 'android'].map((platform, platformIndex) => ({
    metric_id: metric,
    platform,
    device: `${platform}-device-${metricIndex}`,
    status: 'passed',
    value: metric.endsWith('_ms') ? 1 : successMinimumMetrics.has(metric) ? 1 : 0,
    unit: metric.endsWith('_ms') ? 'ms' : 'ratio',
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

    const aboveThreshold = {
      ...performance,
      measurements: performance.measurements.map((measurement) => measurement.metric_id === 'keyboard_cold_open_p95_ms' && measurement.platform === 'ios'
        ? { ...measurement, value: 60_000 }
        : measurement),
    };
    fs.writeFileSync(file, `${JSON.stringify(aboveThreshold)}\n`);
    const rejectedThreshold = evaluate({ staticOnly: true, performance: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.performance.schema');
    assert.equal(rejectedThreshold.status, 'fail');
    assert.match(rejectedThreshold.detail, /exceeds maximum/);

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

test('signed Android AAB evidence is candidate-bound and enforces the offline IME manifest', () => {
  const sourceCommit = '9'.repeat(40);
  const artifactDigest = `sha256:${'8'.repeat(64)}`;
  const report = JSON.parse(fs.readFileSync(path.join(root, 'docs/android-aab-signing-manifest.json'), 'utf8'));
  Object.assign(report, {
    status: 'passed',
    candidate: { source_commit: sourceCommit, artifact_digest: artifactDigest },
    artifact: { signed: true, digest: artifactDigest, signing_certificate_sha256: `sha256:${'7'.repeat(64)}` },
    merged_manifest: {
      internet_permission: false,
      ime_service_permission: 'android.permission.BIND_INPUT_METHOD',
      ime_service_exported: true,
      allow_backup: false,
      data_extraction_rules_present: true,
      full_backup_rules_present: true,
    },
    evidence: {
      class: 'protected_external', environment: 'protected_release_runner', source_commit: sourceCommit,
      artifact_digest: artifactDigest, run_id: 'release-aab-1', runner_id: 'protected-release-1', attested: true,
    },
    notes: 'protected release archive inspection',
  });
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mobile-ai-keyboard-aab-'));
  const file = path.join(tempDir, 'aab.json');
  try {
    fs.writeFileSync(file, `${JSON.stringify(report)}\n`);
    const valid = evaluate({ staticOnly: true, androidAab: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.android_aab.schema');
    assert.equal(valid.status, 'pass');

    fs.writeFileSync(file, `${JSON.stringify({ ...report, merged_manifest: { ...report.merged_manifest, internet_permission: true } })}\n`);
    const networked = evaluate({ staticOnly: true, androidAab: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.android_aab.schema');
    assert.equal(networked.status, 'fail');
    assert.match(networked.detail, /INTERNET/);

    fs.writeFileSync(file, `${JSON.stringify({ ...report, artifact: { ...report.artifact, signing_certificate_sha256: null } })}\n`);
    const unsigned = evaluate({ staticOnly: true, androidAab: file, candidateSha: sourceCommit }).checks.find((check) => check.code === 'evidence.android_aab.schema');
    assert.equal(unsigned.status, 'fail');
    assert.match(unsigned.detail, /signed|certificate/);
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
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
