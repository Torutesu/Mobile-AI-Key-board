#!/usr/bin/env node

/**
 * Deterministic source/evidence boundary for release qualification.
 *
 * This command deliberately does not turn simulator, JVM, fixture, or local
 * runs into physical-device evidence. The default mode is fail-closed when
 * protected evidence is absent; --static-only is for CI's source checks and
 * still records not_proven in the JSON report.
 */
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DIGEST = /^sha256:[a-f0-9]{64}$/;
const COMMIT_SHA = /^[a-f0-9]{40}$/i;
const DEFAULTS = {
  manifest: 'docs/release-evidence-manifest.json',
  matrix: 'docs/release-e2e-matrix.json',
  performance: 'docs/release-performance-evidence.json',
  workflow: '.github/workflows/ci.yml',
  iosArchive: 'docs/ios-archive-entitlement-privacy.json',
  benchmark: null,
};

const requiredScenarios = [
  'ordinary_typing', 'selection_rewrite', 'long_press_and_tap',
  'emoji_and_newline', 'japanese_input', 'url_input', 'rtl_input',
  'app_and_keyboard_switch', 'rotation_and_background_resume',
  'secure_field_suppression', 'unsupported_custom_keyboard',
  'accessibility_screen_reader', 'accessibility_font_scale',
];
const requiredMetrics = [
  'key_to_commit_p50_ms', 'key_to_commit_p95_ms', 'keyboard_cold_open_p95_ms',
  'keyboard_warm_open_p95_ms', 'long_press_false_activation_rate',
  'ordinary_tap_drop_rate', 'skill_completion_p95_ms', 'skill_failure_rate',
  'skill_cancel_rate', 'memory_pressure_extension_ime_kill_rate',
  'crash_free_sessions_rate', 'android_anr_rate', 'offline_success_rate',
  'provider_timeout_recovery_rate',
];
const benchmarkMetrics = {
  key_to_commit_p50_ms: { unit: 'ms', maximum: 35 },
  key_to_commit_p95_ms: { unit: 'ms', maximum: 50 },
  keyboard_cold_open_p95_ms: { unit: 'ms', maximum: 400 },
  keyboard_warm_open_p95_ms: { unit: 'ms', maximum: 150 },
  long_press_false_activation_rate: { unit: 'ratio', maximum: 0.001 },
  ordinary_tap_drop_rate: { unit: 'ratio', maximum: 0.001 },
};

function parseArgs(argv) {
  const args = { staticOnly: false, report: null, candidateSha: process.env.GITHUB_SHA ?? null, ...DEFAULTS };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--') continue;
    if (arg === '--static-only') args.staticOnly = true;
    else if (arg === '--report') args.report = argv[++i];
    else if (arg === '--candidate-sha') args.candidateSha = argv[++i];
    else if (arg === '--manifest') args.manifest = argv[++i];
    else if (arg === '--matrix') args.matrix = argv[++i];
    else if (arg === '--performance') args.performance = argv[++i];
    else if (arg === '--workflow') args.workflow = argv[++i];
    else if (arg === '--ios-archive') args.iosArchive = argv[++i];
    else if (arg === '--benchmark') args.benchmark = argv[++i];
    else throw new Error(`unknown argument: ${arg}`);
  }
  return args;
}

function readText(relativePath) {
  const file = path.resolve(ROOT, relativePath);
  return { file, text: fs.readFileSync(file, 'utf8') };
}

function readJson(relativePath) {
  const { file, text } = readText(relativePath);
  try { return { file, value: JSON.parse(text) }; }
  catch (error) { throw new Error(`${relativePath}: invalid JSON (${error.message})`); }
}

function check(code, status, detail) { return { code, status, detail }; }

function canonicalJson(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  return `{${Object.entries(value).sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0).map(([key, child]) => `${JSON.stringify(key)}:${canonicalJson(child)}`).join(',')}}`;
}

function reportDigest(unsigned) { return `sha256:${createHash('sha256').update(canonicalJson(unsigned), 'utf8').digest('hex')}`; }

function sourceChecks(args, manifest) {
  const results = [];
  const project = readText('apps/ios/project.yml').text;
  const info = readText('apps/ios/MobileAIKeyboardExtension/Info.plist').text;
  const docs = readText('docs/16-store-privacy-declarations.md').text;
  const privacyDocs = readText('docs/05-security-privacy.md').text;
  const hostPrivacy = readText('apps/ios/MobileAIKeyboardHost/PrivacyInfo.xcprivacy').text;
  const extensionPrivacy = readText('apps/ios/MobileAIKeyboardExtension/PrivacyInfo.xcprivacy').text;
  const hostEntitlements = readText('apps/ios/MobileAIKeyboardHost/Host.entitlements').text;
  const extensionEntitlements = readText('apps/ios/MobileAIKeyboardExtension/Extension.entitlements').text;

  const projectAccess = [...project.matchAll(/RequestsOpenAccess:\s*(true|false)/g)].map((m) => m[1]);
  const infoAccess = info.match(/<key>RequestsOpenAccess<\/key>\s*<(true|false)\s*\/>/)?.[1];
  results.push(projectAccess.length === 1 && projectAccess[0] === 'true' && infoAccess === 'true'
    ? check('ios.full_access.source_consistency', 'pass', 'project.yml and extension Info.plist both request Full Access')
    : check('ios.full_access.source_consistency', 'fail', `expected true in project.yml and Info.plist (project=${projectAccess.join(',') || 'missing'}, plist=${infoAccess ?? 'missing'})`));
  results.push(!/RequestsOpenAccess\s*=\s*false|RequestsOpenAccess=false/.test(docs)
    && /RequestsOpenAccess=true/.test(docs)
    && /Full Access disclosure boundary/.test(docs)
    ? check('privacy.docs.full_access', 'pass', 'store declaration documents the current true value and rationale')
    : check('privacy.docs.full_access', 'fail', 'store declaration is stale or lacks the Full Access rationale'));
  results.push(/requests Full Access \(`RequestsOpenAccess=true`\)/.test(privacyDocs)
    ? check('privacy.docs.security_boundary', 'pass', 'security specification explains why Full Access is requested')
    : check('privacy.docs.security_boundary', 'fail', 'security specification must explain the current Full Access boundary'));

  for (const [name, xml] of [['host', hostPrivacy], ['extension', extensionPrivacy]]) {
    const valid = /^\s*<\?xml[\s\S]*<plist[\s\S]*<\/plist>\s*$/.test(xml)
      && /<key>NSPrivacyTracking<\/key>\s*<false\s*\/>/.test(xml)
      && /<key>NSPrivacyCollectedDataTypes<\/key>\s*<array\s*\/?>(?:\s*<\/array>)?/.test(xml)
      && /<key>NSPrivacyAccessedAPITypes<\/key>\s*<array\s*\/?>(?:\s*<\/array>)?/.test(xml);
    results.push(valid
      ? check(`ios.privacy_manifest.${name}`, 'pass', 'source privacy manifest is present, non-tracking, and declares no collected data')
      : check(`ios.privacy_manifest.${name}`, 'fail', 'privacy manifest is malformed or diverges from the local no-collection behavior'));
  }

  const groups = (xml) => [...xml.matchAll(/<string>(group\.[^<]+)<\/string>/g)].map((m) => m[1]);
  const hostGroups = groups(hostEntitlements);
  const extensionGroups = groups(extensionEntitlements);
  results.push(hostGroups.length === 1 && hostGroups[0] === extensionGroups[0]
    ? check('ios.entitlements.app_group', 'pass', `host and extension share ${hostGroups[0]}`)
    : check('ios.entitlements.app_group', 'fail', 'host and extension must declare exactly one identical App Group'));

  const shortcut = readText('apps/ios/MobileAIKeyboardHost/ShortcutRegistryStore.swift').text;
  const unlabelledHandoff = shortcut.split('\n').filter((line) => /hostHandoff/.test(line) && !/(fixture|未接続|not_proven|unconnected)/i.test(line));
  const skillKeys = readText('apps/ios/MobileAIKeyboardHost/SkillKeysView.swift').text;
  const guardedUnavailableHandoff = /assignableSkills/.test(shortcut)
    && /ForEach\(registry\.unavailableSkills\)/.test(skillKeys)
    && /割り当て不可/.test(skillKeys);
  results.push(unlabelledHandoff.length === 0 || guardedUnavailableHandoff
    ? check('fixture.disclosure.static_scan', 'pass', guardedUnavailableHandoff
      ? 'host-handoff Skill is excluded from assignment and visibly marked unavailable'
      : 'host-handoff Skill lines carry an explicit fixture/unconnected boundary')
    : check('fixture.disclosure.static_scan', 'fail', `${unlabelledHandoff.length} host-handoff line(s) expose a route without a fixture/unconnected disclaimer`));

  const workflow = readText(args.workflow).text;
  const artifactContractValid = Array.isArray(manifest.required_artifacts)
    && manifest.required_artifacts.length > 0
    && manifest.required_artifacts.every((artifact) => artifact.id && artifact.path && artifact.class);
  results.push(artifactContractValid
    ? check('evidence.artifact_manifest', 'pass', 'required release artifacts have ids, paths, and evidence classes')
    : check('evidence.artifact_manifest', 'fail', 'required_artifacts must declare an id, path, and evidence class'));
  for (const artifact of manifest.required_artifacts ?? []) {
    if (artifact.class === 'protected_external') {
      let proof = null;
      if (artifact.id === 'real_device_e2e_matrix') {
        try { proof = readJson(args.matrix).value.status === 'passed'; } catch { proof = false; }
      } else if (artifact.id === 'performance_evidence') {
        try { proof = readJson(args.performance).value.status === 'passed'; } catch { proof = false; }
      } else if (artifact.id === 'ios_archive_entitlement_privacy_report' && args.iosArchive) {
        try { proof = readJson(args.iosArchive).value.status === 'passed'; } catch { proof = false; }
      }
      results.push(proof
        ? check(`evidence.artifact.${artifact.id}`, 'pass', `${artifact.path} is supplied as protected evidence`)
        : check(`evidence.artifact.${artifact.id}`, 'not_proven', `${artifact.path} requires protected external evidence and is not proven in this checkout`));
    } else {
      results.push(workflow.includes(path.basename(artifact.path))
        ? check(`ci.artifact.${artifact.id}`, 'pass', `${artifact.path} is represented in CI`)
        : check(`ci.artifact.${artifact.id}`, 'fail', `${artifact.path} is required by the release manifest but is absent from CI`));
    }
  }
  for (const required of manifest.required_commands ?? []) {
    results.push(workflow.includes(required.command)
      ? check(`ci.command.${required.id}`, 'pass', `${required.command} is wired in CI`)
      : check(`ci.command.${required.id}`, 'fail', `${required.command} is required by the release manifest but is absent from CI`));
  }
  results.push(/release-readiness\.json/.test(workflow)
    ? check('ci.artifact.release_readiness', 'pass', 'CI writes and uploads a release-readiness report')
    : check('ci.artifact.release_readiness', 'fail', 'CI must preserve the machine-readable release-readiness report'));
  const hasIosUiTestCommand = /\bxcodebuild[\s\S]{0,1200}\btest\b/.test(workflow);
  const hasAndroidInstrumentationCommand = /\bconnected(?:Debug|Release)AndroidTest\b/.test(workflow)
    || /\badb\s+shell\s+am\s+instrument\b/.test(workflow);
  results.push(hasIosUiTestCommand && hasAndroidInstrumentationCommand
    ? check('ci.ui_test_lane', 'pass', 'CI declares both iOS UI-test and Android instrumentation lanes')
    : check('ci.ui_test_lane', 'not_proven', 'CI currently builds the iOS Simulator and Android debug APK but does not execute both UI-test/instrumentation lanes'));
  return results;
}

function validateCandidate(candidate, status, label, expectedSha = null) {
  if (status !== 'passed') return null;
  if (!candidate || !candidate.source_commit || !candidate.artifact_digest) return `${label} passed without candidate source_commit and artifact_digest`;
  if (!COMMIT_SHA.test(candidate.source_commit)) return `${label} source_commit is not a full git SHA-1`;
  if (!DIGEST.test(candidate.artifact_digest)) return `${label} artifact_digest is not a sha256 digest`;
  if (!expectedSha) return `${label} passed without an expected candidate_sha input`;
  if (expectedSha && candidate.source_commit !== expectedSha) return `${label} source_commit does not match candidate_sha`;
  return null;
}

function validateMatrix(matrix, expectedSha = null) {
  const errors = [];
  if (matrix.schema_version !== 'mobile-ai-keyboard.real-device-e2e.v1') errors.push('wrong schema_version');
  if (matrix.evidence_class !== 'protected_external') errors.push('evidence_class must be protected_external');
  for (const scenario of requiredScenarios) if (!matrix.required_scenarios?.includes(scenario)) errors.push(`missing scenario ${scenario}`);
  const platforms = new Set((matrix.targets ?? []).map((target) => target.platform));
  for (const platform of ['ios', 'android']) if (!platforms.has(platform)) errors.push(`missing ${platform} target`);
  for (const target of matrix.targets ?? []) {
    if (!Array.isArray(target.devices) || target.devices.length === 0) errors.push(`${target.platform} has no devices`);
    if (!Array.isArray(target.apps) || target.apps.length < 7) errors.push(`${target.platform} has fewer than seven apps`);
    if (!['not_proven', 'in_progress', 'passed', 'failed'].includes(target.status)) errors.push(`${target.platform} has an invalid status`);
    if (target.status === 'passed') {
      for (const run of target.runs ?? []) {
        if (run.evidence_class !== 'protected_external' || !run.run_id || !run.runner_id || run.attested !== true) errors.push(`${target.platform} passed run is not protected/attested`);
        if (run.environment !== 'protected_device') errors.push(`${target.platform} passed run is not explicitly classified as protected_device`);
        if (!run.device_id || !run.source_commit || !run.artifact_digest) errors.push(`${target.platform} passed run is missing device_id/source_commit/artifact_digest binding`);
        if (run.source_commit !== matrix.candidate?.source_commit) errors.push(`${target.platform} passed run source_commit does not match matrix candidate`);
        if (run.artifact_digest !== matrix.candidate?.artifact_digest) errors.push(`${target.platform} passed run artifact_digest does not match matrix candidate`);
        if (!DIGEST.test(run.artifact_digest ?? '')) errors.push(`${target.platform} passed run artifact_digest is invalid`);
        if (!Array.isArray(run.scenarios) || run.scenarios.length === 0) errors.push(`${target.platform} passed run is missing scenario coverage`);
        if (!Array.isArray(run.accessibility_tools) || run.accessibility_tools.length === 0) errors.push(`${target.platform} passed run is missing accessibility tool evidence`);
        if (/(fixture|simulator|emulator|jvm|ui[-_ ]?test|local|self[-_ ]?attest)/i.test(JSON.stringify(run))) errors.push(`${target.platform} passed run contains a fixture/simulator/emulator/UI-test/local marker`);
      }
      const coveredScenarios = new Set((target.runs ?? []).flatMap((run) => Array.isArray(run.scenarios) ? run.scenarios : []));
      for (const scenario of requiredScenarios) if (!coveredScenarios.has(scenario)) errors.push(`${target.platform} passed evidence does not cover scenario ${scenario}`);
      const requiredAccessibilityTool = target.platform === 'ios' ? 'voiceover' : 'talkback';
      if (!(target.runs ?? []).some((run) => run.accessibility_tools?.includes(requiredAccessibilityTool))) errors.push(`${target.platform} passed evidence does not include ${requiredAccessibilityTool} coverage`);
    }
  }
  if (matrix.status === 'passed') {
    for (const target of matrix.targets ?? []) {
      if (target.status !== 'passed' || !Array.isArray(target.runs) || target.runs.length === 0) errors.push(`${target.platform} passed without a protected run`);
    }
  }
  const candidateError = validateCandidate(matrix.candidate, matrix.status === 'passed' || (matrix.targets ?? []).some((target) => target.status === 'passed') ? 'passed' : matrix.status, 'E2E matrix', expectedSha);
  if (candidateError) errors.push(candidateError);
  return errors;
}

function validatePerformance(performance, expectedSha = null) {
  const errors = [];
  if (performance.schema_version !== 'mobile-ai-keyboard.performance-evidence.v1') errors.push('wrong schema_version');
  if (performance.evidence_class !== 'protected_external') errors.push('evidence_class must be protected_external');
  for (const metric of requiredMetrics) if (!performance.required_metrics?.includes(metric)) errors.push(`missing metric ${metric}`);
  const seen = new Set();
  for (const measurement of performance.measurements ?? []) {
    if (!requiredMetrics.includes(measurement.metric_id)) errors.push(`unknown performance metric ${measurement.metric_id ?? 'missing'}`);
    if (!['ios', 'android'].includes(measurement.platform)) errors.push(`unknown performance platform ${measurement.platform ?? 'missing'}`);
    if (!['not_proven', 'in_progress', 'passed', 'failed'].includes(measurement.status)) errors.push(`${measurement.metric_id ?? 'missing'} has an invalid status`);
    if (seen.has(measurement.metric_id)) errors.push(`duplicate metric ${measurement.metric_id}`);
    seen.add(measurement.metric_id);
    if (measurement.status === 'passed') {
      const evidence = measurement.evidence ?? {};
      if (evidence.class !== 'protected_external' || !evidence.run_id || !evidence.runner_id || evidence.attested !== true || !evidence.artifact_digest) errors.push(`${measurement.metric_id} passed without protected evidence binding`);
      if (evidence.environment !== 'protected_device') errors.push(`${measurement.metric_id} passed measurement is not explicitly classified as protected_device`);
      if (evidence.source_commit !== performance.candidate?.source_commit) errors.push(`${measurement.metric_id} source_commit does not match performance candidate`);
      if (evidence.artifact_digest !== performance.candidate?.artifact_digest) errors.push(`${measurement.metric_id} artifact_digest does not match performance candidate`);
      if (!DIGEST.test(evidence.artifact_digest ?? '')) errors.push(`${measurement.metric_id} evidence artifact_digest is invalid`);
      if (typeof measurement.device !== 'string' || measurement.device.trim() === '') errors.push(`${measurement.metric_id} passed measurement has no device identity`);
      if (/(fixture|simulator|emulator|jvm|ui[-_ ]?test|local|self[-_ ]?attest)/i.test(JSON.stringify(measurement))) errors.push(`${measurement.metric_id} passed measurement contains a fixture/simulator/emulator/UI-test/local marker`);
    }
  }
  if (performance.status === 'passed') {
    for (const metric of requiredMetrics) if (!performance.measurements?.some((m) => m.metric_id === metric && m.status === 'passed')) errors.push(`performance status passed but ${metric} is not passed`);
  }
  const candidateError = validateCandidate(performance.candidate, performance.status, 'Performance evidence', expectedSha);
  if (candidateError) errors.push(candidateError);
  return errors;
}

function validateIosArchive(archive, expectedSha = null) {
  const errors = [];
  if (archive.schema_version !== 'mobile-ai-keyboard.ios-archive.v1') errors.push('wrong schema_version');
  if (archive.evidence_class !== 'protected_external') errors.push('evidence_class must be protected_external');
  if (archive.status === 'passed') {
    const evidence = archive.evidence ?? {};
    if (evidence.class !== 'protected_external' || !evidence.run_id || !evidence.runner_id || evidence.attested !== true || !evidence.artifact_digest) errors.push('archive passed without protected evidence binding');
    if (evidence.environment !== 'protected_device') errors.push('archive passed evidence is not explicitly classified as protected_device');
    if (evidence.source_commit !== archive.candidate?.source_commit) errors.push('archive evidence source_commit does not match candidate');
    if (evidence.artifact_digest !== archive.candidate?.artifact_digest) errors.push('archive evidence artifact_digest does not match candidate');
    if (!DIGEST.test(evidence.artifact_digest ?? '')) errors.push('archive evidence artifact_digest is invalid');
    if (/(fixture|simulator|emulator|jvm|ui[-_ ]?test|local|self[-_ ]?attest)/i.test(JSON.stringify(archive))) errors.push('archive passed evidence contains a fixture/simulator/emulator/UI-test/local marker');
    if (!archive.entitlements?.host?.app_group || archive.entitlements.host.app_group !== archive.entitlements?.extension?.app_group) errors.push('archived host and extension must contain the same App Group entitlement');
    if (archive.extension_info?.requests_open_access !== true) errors.push('archived extension Info.plist must request the declared Full Access value');
    if (!archive.privacy_manifests?.host || !archive.privacy_manifests?.extension) errors.push('archive must contain host and extension privacy manifest inspection');
  }
  const candidateError = validateCandidate(archive.candidate, archive.status, 'iOS archive evidence', expectedSha);
  if (candidateError) errors.push(candidateError);
  return errors;
}

function validateBenchmark(report, expectedSha = null) {
  const errors = [];
  if (report.schema_version !== 'mobile-ai-keyboard.performance-benchmark.v1') errors.push('wrong schema_version');
  if (!DIGEST.test(report.candidate_digest ?? '')) errors.push('candidate_digest is invalid');
  if (!['fixture', 'simulator', 'protected_device'].includes(report.environment)) errors.push('environment is invalid');
  if (!DIGEST.test(report.report_digest ?? '')) errors.push('report_digest is missing or invalid');
  if (!['passed', 'failed'].includes(report.diagnostic_status)) errors.push('diagnostic_status is invalid');
  if (!['passed', 'not_proven', 'failed'].includes(report.qualification_status)) errors.push('qualification_status is invalid');
  if (!Array.isArray(report.observations) || report.observations.length !== 12) errors.push('benchmark must contain one observation for each metric and platform');
  if (DIGEST.test(report.report_digest ?? '')) {
    const { report_digest: _reportDigest, ...unsigned } = report;
    if (reportDigest(unsigned) !== report.report_digest) errors.push('report_digest does not match the canonical report');
  }
  const expectedKeys = new Set(Object.keys(benchmarkMetrics).flatMap((metric) => ['ios', 'android'].map((platform) => `${platform}:${metric}`)));
  const observedKeys = new Set();
  const failedKeys = [];
  if (!report.evidence || typeof report.evidence.test_run_id !== 'string' || report.evidence.test_run_id.length === 0) errors.push('report evidence test_run_id is required');
  for (const observation of report.observations ?? []) {
    const metric = benchmarkMetrics[observation.metric];
    const key = `${observation.platform}:${observation.metric}`;
    if (!metric) errors.push(`unknown benchmark metric ${observation.metric ?? 'missing'}`);
    if (!['ios', 'android'].includes(observation.platform)) errors.push(`unknown benchmark platform ${observation.platform ?? 'missing'}`);
    if (observedKeys.has(key)) errors.push(`duplicate benchmark observation ${key}`);
    observedKeys.add(key);
    if (metric && observation.unit !== metric.unit) errors.push(`${key} has wrong unit`);
    if (metric && (typeof observation.value !== 'number' || !Number.isFinite(observation.value) || observation.value < 0 || observation.value > 60_000)) errors.push(`${key} has invalid value`);
    if (metric && typeof observation.value === 'number' && observation.value > metric.maximum) failedKeys.push(key);
    if (!Number.isInteger(observation.sample_count) || observation.sample_count <= 0 || observation.sample_count > 10_000_000) errors.push(`${key} has invalid sample_count`);
    if (observation.candidate_digest !== report.candidate_digest) errors.push(`${key} is not bound to report candidate_digest`);
    if (observation.environment !== report.environment) errors.push(`${key} is not bound to report environment`);
    if (observation.evidence?.kind !== report.evidence?.kind) errors.push(`${key} is not bound to report evidence kind`);
    if (observation.evidence?.test_run_id !== report.evidence?.test_run_id) errors.push(`${key} is not bound to report test_run_id`);
    if (report.environment === 'protected_device' && (observation.evidence?.verifier_kind !== report.evidence?.verifier_kind || observation.evidence?.verifier_id !== report.evidence?.verifier_id || observation.evidence?.artifact_digest !== report.evidence?.artifact_digest)) errors.push(`${key} is not fully bound to protected verifier/artifact evidence`);
  }
  for (const key of expectedKeys) if (!observedKeys.has(key)) errors.push(`missing benchmark observation ${key}`);
  const expectedDiagnostic = failedKeys.length === 0 && observedKeys.size === expectedKeys.size ? 'passed' : 'failed';
  if (report.diagnostic_status !== expectedDiagnostic) errors.push(`diagnostic_status ${report.diagnostic_status ?? 'missing'} does not match observations (${expectedDiagnostic})`);
  const expectedEvidenceKind = report.environment === 'fixture' ? 'deterministic_fixture' : report.environment === 'simulator' ? 'simulator' : 'protected_external';
  if (report.evidence?.kind !== expectedEvidenceKind) errors.push('report evidence kind does not match environment');
  if (report.environment === 'protected_device' && (report.evidence?.verifier_kind !== 'protected_runner' || !report.evidence?.verifier_id || !DIGEST.test(report.evidence?.artifact_digest ?? ''))) errors.push('protected benchmark evidence requires runner attestation and artifact binding');
  if (report.environment === 'protected_device' && (report.observations ?? []).some((observation) => observation.evidence?.kind !== 'protected_external')) errors.push('protected benchmark cannot contain fixture or simulator observations');
  if (report.environment === 'protected_device') {
    const candidateError = validateCandidate(report.candidate, 'passed', 'Protected benchmark', expectedSha);
    if (candidateError) errors.push(candidateError);
    if (report.evidence?.source_commit !== report.candidate?.source_commit) errors.push('protected benchmark evidence source_commit does not match candidate');
    if (report.evidence?.artifact_digest !== report.candidate?.artifact_digest) errors.push('protected benchmark evidence artifact_digest does not match candidate');
    for (const observation of report.observations ?? []) {
      if (observation.evidence?.source_commit !== report.candidate?.source_commit) errors.push(`${observation.platform}:${observation.metric} source_commit does not match benchmark candidate`);
      if (observation.evidence?.artifact_digest !== report.candidate?.artifact_digest) errors.push(`${observation.platform}:${observation.metric} artifact_digest does not match benchmark candidate`);
    }
  }
  if (report.qualification_status === 'passed' && (report.environment !== 'protected_device' || report.evidence?.kind !== 'protected_external' || report.evidence?.verifier_kind !== 'protected_runner' || !report.evidence?.verifier_id || !report.evidence?.artifact_digest)) errors.push('benchmark qualification pass requires protected device evidence');
  if (report.qualification_status === 'passed' && report.observations.some((observation) => observation.evidence?.kind !== 'protected_external' || observation.environment !== 'protected_device' || observation.candidate_digest !== report.candidate_digest)) errors.push('protected benchmark observations are not bound to report evidence/environment/candidate');
  const expectedQualification = expectedDiagnostic === 'failed' ? 'failed' : report.environment === 'protected_device' ? 'passed' : 'not_proven';
  if (report.qualification_status !== expectedQualification) errors.push(`qualification_status ${report.qualification_status ?? 'missing'} does not match evidence (${expectedQualification})`);
  if (report.environment !== 'protected_device' && report.qualification_status === 'passed') errors.push('fixture or simulator benchmark cannot qualify a release');
  return errors;
}

function evidenceChecks(args) {
  const results = [];
  let matrix;
  let performance;
  let archive;
  let benchmark;
  try { matrix = readJson(args.matrix).value; } catch (error) { results.push(check('evidence.e2e.schema', 'fail', error.message)); }
  try { performance = readJson(args.performance).value; } catch (error) { results.push(check('evidence.performance.schema', 'fail', error.message)); }
  if (args.iosArchive) {
    try { archive = readJson(args.iosArchive).value; } catch (error) { results.push(check('evidence.ios_archive.schema', 'fail', error.message)); }
  }
  if (args.benchmark) {
    try { benchmark = readJson(args.benchmark).value; } catch (error) { results.push(check('evidence.benchmark.schema', 'fail', error.message)); }
  }
  if (matrix) {
    const errors = validateMatrix(matrix, args.candidateSha);
    results.push(check('evidence.e2e.schema', errors.length ? 'fail' : 'pass', errors.length ? errors.join('; ') : 'E2E matrix contains both platforms and all required dimensions'));
    results.push(check('evidence.e2e.proof', errors.length ? 'fail' : (matrix.status === 'passed' ? 'pass' : 'not_proven'), matrix.status === 'not_proven' ? 'no protected physical-device/app runs are recorded' : (errors.length ? 'matrix contains invalid proof' : 'protected physical-device/app runs are bound to this candidate')));
  }
  if (performance) {
    const errors = validatePerformance(performance, args.candidateSha);
    results.push(check('evidence.performance.schema', errors.length ? 'fail' : 'pass', errors.length ? errors.join('; ') : 'performance evidence contains all required metrics'));
    results.push(check('evidence.performance.proof', errors.length ? 'fail' : (performance.status === 'passed' ? 'pass' : 'not_proven'), performance.status === 'not_proven' ? 'no protected device performance captures are recorded' : (errors.length ? 'performance evidence contains invalid proof' : 'protected device performance captures are bound to this candidate')));
  }
  if (archive) {
    const errors = validateIosArchive(archive, args.candidateSha);
    results.push(check('evidence.ios_archive.schema', errors.length ? 'fail' : 'pass', errors.length ? errors.join('; ') : 'archive report contains the required entitlement/privacy inspection fields'));
    results.push(check('evidence.ios_archive.proof', errors.length ? 'fail' : (archive.status === 'passed' ? 'pass' : 'not_proven'), archive.status === 'not_proven' ? 'no protected signed archive inspection is recorded' : (errors.length ? 'archive evidence contains invalid proof' : 'protected archive inspection is bound to this candidate')));
  }
  if (benchmark) {
    const errors = validateBenchmark(benchmark, args.candidateSha);
    results.push(check('evidence.benchmark.schema', errors.length ? 'fail' : 'pass', errors.length ? errors.join('; ') : 'benchmark report contains all platform/metric bindings'));
    results.push(check('evidence.benchmark.proof', errors.length ? 'fail' : (benchmark.qualification_status === 'passed' ? 'pass' : 'not_proven'), benchmark.qualification_status === 'failed' ? 'deterministic benchmark regression detected' : (benchmark.qualification_status === 'not_proven' ? 'diagnostic result is not physical-device qualification' : 'protected benchmark is bound to this candidate')));
  }
  return results;
}

export function evaluate(options = {}) {
  const args = { ...parseArgs([]), ...options };
  const manifest = readJson(args.manifest).value;
  const checks = [...sourceChecks(args, manifest), ...evidenceChecks(args)];
  const hasFailure = checks.some((result) => result.status === 'fail');
  const hasNotProven = checks.some((result) => result.status === 'not_proven');
  const status = hasFailure ? 'fail' : (hasNotProven ? 'not_proven' : 'passed');
  return { schema_version: 'mobile-ai-keyboard.release-readiness.v1', status, candidate_sha: args.candidateSha, checks };
}

function main() {
  let args;
  try { args = parseArgs(process.argv.slice(2)); }
  catch (error) { console.error(error.message); process.exitCode = 2; return; }
  let report;
  try { report = evaluate(args); }
  catch (error) {
    report = { schema_version: 'mobile-ai-keyboard.release-readiness.v1', status: 'fail', candidate_sha: args.candidateSha, checks: [check('gate.input', 'fail', error.message)] };
  }
  const serialized = `${JSON.stringify(report, null, 2)}\n`;
  if (args.report) {
    const output = path.resolve(ROOT, args.report);
    fs.mkdirSync(path.dirname(output), { recursive: true });
    fs.writeFileSync(output, serialized);
  }
  console.log(serialized.trimEnd());
  if (report.status === 'fail' || (!args.staticOnly && report.status !== 'passed')) process.exitCode = 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
