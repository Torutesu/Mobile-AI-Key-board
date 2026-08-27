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
import { createHash, createPublicKey, verify as verifySignature } from 'node:crypto';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DIGEST = /^sha256:[a-f0-9]{64}$/;
const COMMIT_SHA = /^[a-f0-9]{40}$/i;
const VALID_STATUSES = new Set(['not_proven', 'in_progress', 'passed', 'failed']);
const DEFAULTS = {
  manifest: 'docs/release-evidence-manifest.json',
  matrix: 'docs/release-e2e-matrix.json',
  performance: 'docs/release-performance-evidence.json',
  workflow: '.github/workflows/ci.yml',
  iosArchive: 'docs/ios-archive-entitlement-privacy.json',
  androidAab: 'docs/android-aab-signing-manifest.json',
  benchmark: null,
};

const requiredScenarios = [
  'ordinary_typing', 'selection_rewrite', 'long_press_and_tap',
  'emoji_and_newline', 'japanese_input', 'url_input', 'rtl_input',
  'app_and_keyboard_switch', 'rotation_and_background_resume',
  'secure_field_suppression', 'unsupported_custom_keyboard',
  'accessibility_screen_reader', 'accessibility_font_scale',
];
const requiredFieldClasses = [
  'ordinary_text', 'long_text', 'emoji', 'newline', 'japanese', 'url', 'rtl',
  'secure_password', 'one_time_code', 'phone_number',
];
const requiredLifecycleEvents = [
  'input_field_switch', 'app_switch', 'keyboard_switch', 'rotation',
  'background_resume', 'process_restart',
];
const requiredApps = {
  ios: ['Messages', 'Mail', 'Safari', 'LINE', 'Slack', 'Gmail', 'Notion'],
  android: ['Messages', 'Mail', 'Chrome', 'LINE', 'Slack', 'Gmail', 'Notion'],
};
const requiredDeviceClasses = {
  ios: ['iphone_baseline', 'iphone_current', 'iphone_small', 'ipad_portrait_landscape'],
  android: ['android11_baseline', 'pixel_current', 'samsung_current', 'android_low_memory'],
};
const evidenceDigest = /^sha256:[a-f0-9]{64}$/;
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
const performanceMetrics = {
  key_to_commit_p50_ms: { unit: 'ms', maximum: 35 },
  key_to_commit_p95_ms: { unit: 'ms', maximum: 50 },
  keyboard_cold_open_p95_ms: { unit: 'ms', maximum: 400 },
  keyboard_warm_open_p95_ms: { unit: 'ms', maximum: 150 },
  long_press_false_activation_rate: { unit: 'ratio', maximum: 0.001 },
  ordinary_tap_drop_rate: { unit: 'ratio', maximum: 0.001 },
  skill_completion_p95_ms: { unit: 'ms', maximum: 5_000 },
  skill_failure_rate: { unit: 'ratio', maximum: 0.05 },
  skill_cancel_rate: { unit: 'ratio', maximum: 1 },
  memory_pressure_extension_ime_kill_rate: { unit: 'ratio', maximum: 0.01 },
  crash_free_sessions_rate: { unit: 'ratio', minimum: 0.998, maximum: 1 },
  android_anr_rate: { unit: 'ratio', maximum: 0.001 },
  offline_success_rate: { unit: 'ratio', minimum: 0.99, maximum: 1 },
  provider_timeout_recovery_rate: { unit: 'ratio', minimum: 0.99, maximum: 1 },
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
    else if (arg === '--android-aab') args.androidAab = argv[++i];
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
      } else if (artifact.id === 'android_aab_signing_manifest_report' && args.androidAab) {
        try { proof = readJson(args.androidAab).value.status === 'passed'; } catch { proof = false; }
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

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(',')}}`;
  return JSON.stringify(value);
}

function attestationPayload(run) {
  const copy = structuredClone(run);
  if (copy.attestation) delete copy.attestation.signature;
  return Buffer.from(stableJson({ schema: 'mobile-ai-keyboard.protected-run.v1', run: copy }), 'utf8');
}

function reportAttestationPayload(report) {
  const copy = structuredClone(report);
  if (copy.attestation) delete copy.attestation.signature;
  return Buffer.from(stableJson({ schema: 'mobile-ai-keyboard.protected-report.v1', report: copy }), 'utf8');
}

function validateSignedAttestation({
  attestation,
  payload,
  label,
  expectedBindings,
  trustedAttestationKeys,
  nowMillis,
  attestationNonces = new Set(),
  verificationIDs = new Set(),
}) {
  const errors = [];
  const value = attestation && typeof attestation === 'object' ? attestation : {};
  if (value.status !== 'verified' || value.verifier_kind !== 'protected_runner' || !value.verifier_id || !value.verification_id || !value.signature) {
    errors.push(`${label} is missing verified protected-runner attestation`);
  }
  for (const [field, expected] of Object.entries(expectedBindings)) {
    if (value[field] !== expected) errors.push(`${label} attestation ${field} does not match evidence`);
  }
  const trustedKey = trustedAttestationKeys?.[value.verifier_id];
  if (!trustedKey) errors.push(`${label} attestation verifier is not trusted by release environment`);
  else {
    try {
      const publicKey = createPublicKey(trustedKey);
      const signature = Buffer.from(value.signature ?? '', 'base64');
      const strictBase64 = signature.toString('base64') === value.signature;
      if (publicKey.asymmetricKeyType !== 'ed25519' || !strictBase64 || signature.length !== 64 || !verifySignature(null, payload, publicKey, signature)) {
        errors.push(`${label} attestation signature verification failed`);
      }
    } catch {
      errors.push(`${label} attestation signature verification failed`);
    }
  }
  const issuedAt = Date.parse(value.issued_at ?? '');
  const expiresAt = Date.parse(value.expires_at ?? '');
  if (!Number.isFinite(issuedAt) || !Number.isFinite(expiresAt) || issuedAt > nowMillis + 5 * 60_000 || expiresAt < nowMillis || expiresAt <= issuedAt || expiresAt - issuedAt > 30 * 24 * 60 * 60_000) {
    errors.push(`${label} attestation freshness window is invalid`);
  }
  if (typeof value.nonce !== 'string' || !/^[A-Za-z0-9_-]{16,128}$/.test(value.nonce)) errors.push(`${label} attestation nonce is invalid`);
  else if (attestationNonces.has(value.nonce)) errors.push(`${label} reuses an attestation nonce`);
  else attestationNonces.add(value.nonce);
  if (verificationIDs.has(value.verification_id)) errors.push(`${label} reuses verification_id ${value.verification_id}`);
  else if (value.verification_id) verificationIDs.add(value.verification_id);
  return errors;
}

function validateMatrix(matrix, expectedSha = null, trustedAttestationKeys = {}, nowMillis = Date.now()) {
  const errors = [];
  const attestationNonces = new Set();
  const verificationIDs = new Set();
  if (matrix.schema_version !== 'mobile-ai-keyboard.real-device-e2e.v1') errors.push('wrong schema_version');
  if (matrix.evidence_class !== 'protected_external') errors.push('evidence_class must be protected_external');
  if (!VALID_STATUSES.has(matrix.status)) errors.push(`invalid matrix status ${matrix.status ?? 'missing'}`);
  const exactContract = (declared, required, label) => {
    if (!Array.isArray(declared) || declared.length !== required.length || new Set(declared).size !== declared.length || declared.some((id) => !required.includes(id))) {
      errors.push(`${label} contract must contain exactly the known required IDs`);
    }
    for (const id of required) if (!Array.isArray(declared) || !declared.includes(id)) errors.push(`missing ${label} ${id}`);
  };
  exactContract(matrix.required_scenarios, requiredScenarios, 'scenario');
  exactContract(matrix.required_field_classes, requiredFieldClasses, 'field class');
  exactContract(matrix.required_lifecycle_events, requiredLifecycleEvents, 'lifecycle event');
  const platforms = new Set((matrix.targets ?? []).map((target) => target.platform));
  if (!Array.isArray(matrix.targets) || matrix.targets.length !== 2 || platforms.size !== 2) errors.push('E2E matrix must contain exactly one iOS and one Android target');
  for (const platform of ['ios', 'android']) if (!platforms.has(platform)) errors.push(`missing ${platform} target`);
  for (const target of matrix.targets ?? []) {
    if (!requiredApps[target.platform]) errors.push(`unknown target platform ${target.platform ?? 'missing'}`);
    if (!Array.isArray(target.devices) || target.devices.length === 0) errors.push(`${target.platform} has no devices`);
    const platformApps = requiredApps[target.platform];
    const platformDevices = requiredDeviceClasses[target.platform];
    if (!Array.isArray(target.apps)) errors.push(`${target.platform} has no app contract`);
    else if (platformApps) {
      if (new Set(target.apps).size !== target.apps.length) errors.push(`${target.platform} app contract contains duplicates`);
      if (target.apps.length !== platformApps.length || target.apps.some((app) => !platformApps.includes(app))) errors.push(`${target.platform} app contract must contain exactly the required seven apps`);
      for (const app of platformApps) if (!target.apps.includes(app)) errors.push(`${target.platform} is missing required app ${app}`);
    }
    if (!['not_proven', 'in_progress', 'passed', 'failed'].includes(target.status)) errors.push(`${target.platform} has an invalid status`);
    if (target.status === 'passed') {
      if (!Array.isArray(target.device_classes) || target.device_classes.length !== platformDevices?.length || new Set(target.device_classes).size !== target.device_classes.length || target.device_classes.some((deviceClass) => !platformDevices.includes(deviceClass))) errors.push(`${target.platform} passed target must declare exactly the required device classes`);
      if (!Array.isArray(target.runs) || target.runs.length === 0) errors.push(`${target.platform} passed without a protected run`);
      const runIDs = new Set();
      const coveredDeviceClasses = new Set();
      for (const runValue of Array.isArray(target.runs) ? target.runs : []) {
        const run = runValue && typeof runValue === 'object' ? runValue : {};
        if (run.status !== 'passed') errors.push(`${target.platform} passed target contains a run without status passed`);
        if (run.evidence_class !== 'protected_external' || !run.run_id || !run.runner_id) errors.push(`${target.platform} passed run is not protected/attested`);
        if (runIDs.has(run.run_id)) errors.push(`${target.platform} passed evidence contains duplicate run_id ${run.run_id}`);
        if (run.run_id) runIDs.add(run.run_id);
        if (run.environment !== 'protected_device') errors.push(`${target.platform} passed run is not explicitly classified as protected_device`);
        if (!run.device_id || !run.device_class || !run.device_model || !run.os_version || !run.source_commit || !run.artifact_digest) errors.push(`${target.platform} passed run is missing concrete device/source/artifact binding`);
        if (platformDevices && !platformDevices.includes(run.device_class)) errors.push(`${target.platform} passed run has an unknown device class`);
        if (Array.isArray(target.device_classes) && !target.device_classes.includes(run.device_class)) errors.push(`${target.platform} passed run device class is not declared by target`);
        if (run.device_class) coveredDeviceClasses.add(run.device_class);
        if (run.source_commit !== matrix.candidate?.source_commit) errors.push(`${target.platform} passed run source_commit does not match matrix candidate`);
        if (run.artifact_digest !== matrix.candidate?.artifact_digest) errors.push(`${target.platform} passed run artifact_digest does not match matrix candidate`);
        if (!DIGEST.test(run.artifact_digest ?? '')) errors.push(`${target.platform} passed run artifact_digest is invalid`);
        if (['attested', 'scenarios', 'field_classes', 'lifecycle_events', 'apps'].some((field) => Object.prototype.hasOwnProperty.call(run, field))) errors.push(`${target.platform} passed run contains legacy label/self-attestation fields`);
        const attestation = run.attestation ?? {};
        if (attestation.verifier_id !== run.runner_id) errors.push(`${target.platform} passed run attestation verifier_id does not match runner_id`);
        errors.push(...validateSignedAttestation({
          attestation,
          payload: attestationPayload(run),
          label: `${target.platform} passed run`,
          expectedBindings: { run_id: run.run_id, device_id: run.device_id, source_commit: run.source_commit, artifact_digest: run.artifact_digest },
          trustedAttestationKeys,
          nowMillis,
          attestationNonces,
          verificationIDs,
        }));
        const validateResults = (results, key, required, label) => {
          if (!Array.isArray(results) || results.length !== required.length) {
            errors.push(`${target.platform} passed run is missing exact ${label} results`);
            return;
          }
          const seen = new Set();
          for (const result of results) {
            const id = result?.[key];
            if (!required.includes(id)) errors.push(`${target.platform} passed run has unknown ${label} ${id ?? 'missing'}`);
            if (seen.has(id)) errors.push(`${target.platform} passed run has duplicate ${label} ${id}`);
            seen.add(id);
            if (result?.run_id !== run.run_id) errors.push(`${target.platform} passed run ${label} ${id ?? 'missing'} evidence is not bound to run_id`);
            if (result?.status !== 'passed' || !result?.evidence_ref || !evidenceDigest.test(result?.evidence_digest ?? '')) errors.push(`${target.platform} passed run ${label} ${id ?? 'missing'} lacks passed outcome/evidence binding`);
          }
          for (const id of required) if (!seen.has(id)) errors.push(`${target.platform} passed run does not cover ${label} ${id}`);
        };
        validateResults(run.scenario_results, 'scenario_id', requiredScenarios, 'scenario');
        validateResults(run.field_class_results, 'field_class', requiredFieldClasses, 'field class');
        validateResults(run.lifecycle_results, 'lifecycle_event', requiredLifecycleEvents, 'lifecycle event');
        if (!Array.isArray(run.accessibility_tools) || run.accessibility_tools.length === 0 || run.accessibility_tools.some((tool) => !['voiceover', 'talkback'].includes(tool))) errors.push(`${target.platform} passed run has invalid accessibility tool evidence`);
        const requiredAccessibilityTool = target.platform === 'ios' ? 'voiceover' : 'talkback';
        if (!run.accessibility_tools?.includes(requiredAccessibilityTool)) errors.push(`${target.platform} passed run does not name ${requiredAccessibilityTool}`);
        if (!Array.isArray(run.app_evidence) || run.app_evidence.length !== platformApps?.length) errors.push(`${target.platform} passed run is missing exact app evidence`);
        const seenApps = new Set();
        for (const app of run.app_evidence ?? []) {
          if (!platformApps?.includes(app?.app_id)) errors.push(`${target.platform} passed run has unknown app evidence ${app?.app_id ?? 'missing'}`);
          if (seenApps.has(app?.app_id)) errors.push(`${target.platform} passed run has duplicate app evidence ${app.app_id}`);
          seenApps.add(app?.app_id);
          if (app?.run_id !== run.run_id) errors.push(`${target.platform} app evidence ${app?.app_id ?? 'missing'} evidence is not bound to run_id`);
          if (!app?.app_identifier || !app?.evidence_ref || !evidenceDigest.test(app?.evidence_digest ?? '')) errors.push(`${target.platform} app evidence ${app?.app_id ?? 'missing'} lacks concrete identifier/evidence binding`);
        }
        for (const app of platformApps ?? []) if (!seenApps.has(app)) errors.push(`${target.platform} passed run does not cover app ${app}`);
        if (/(fixture|simulator|emulator|jvm|ui[-_ ]?test|local|self[-_ ]?attest)/i.test(JSON.stringify(run))) errors.push(`${target.platform} passed run contains a fixture/simulator/emulator/UI-test/local marker`);
      }
      for (const deviceClass of platformDevices ?? []) if (!coveredDeviceClasses.has(deviceClass)) errors.push(`${target.platform} passed evidence does not cover device class ${deviceClass}`);
    }
  }
  if (matrix.status === 'passed') for (const target of matrix.targets ?? []) if (target.status !== 'passed' || !Array.isArray(target.runs) || target.runs.length === 0) errors.push(`${target.platform} passed without a protected run`);
  const candidateError = validateCandidate(matrix.candidate, matrix.status === 'passed' || (matrix.targets ?? []).some((target) => target.status === 'passed') ? 'passed' : matrix.status, 'E2E matrix', expectedSha);
  if (candidateError) errors.push(candidateError);
  return errors;
}

function validatePerformance(performance, expectedSha = null, trustedAttestationKeys = {}, nowMillis = Date.now()) {
  const errors = [];
  if (performance.schema_version !== 'mobile-ai-keyboard.performance-evidence.v1') errors.push('wrong schema_version');
  if (performance.evidence_class !== 'protected_external') errors.push('evidence_class must be protected_external');
  if (!VALID_STATUSES.has(performance.status)) errors.push(`invalid performance status ${performance.status ?? 'missing'}`);
  for (const metric of requiredMetrics) {
    if (!performance.required_metrics?.includes(metric)) errors.push(`missing metric ${metric}`);
    if (!performanceMetrics[metric]) errors.push(`missing fixed threshold contract for ${metric}`);
  }
  const seen = new Set();
  for (const measurement of performance.measurements ?? []) {
    if (!requiredMetrics.includes(measurement.metric_id)) errors.push(`unknown performance metric ${measurement.metric_id ?? 'missing'}`);
    if (!['ios', 'android'].includes(measurement.platform)) errors.push(`unknown performance platform ${measurement.platform ?? 'missing'}`);
    if (!VALID_STATUSES.has(measurement.status)) errors.push(`${measurement.metric_id ?? 'missing'} has an invalid status`);
    const pair = `${measurement.platform}:${measurement.metric_id}`;
    if (seen.has(pair)) errors.push(`duplicate metric/platform pair ${pair}`);
    seen.add(pair);
    if (measurement.status === 'passed') {
      const threshold = performanceMetrics[measurement.metric_id];
      if (typeof measurement.value !== 'number' || !Number.isFinite(measurement.value)) errors.push(`${measurement.metric_id} passed measurement has no finite value`);
      if (threshold && measurement.unit !== threshold.unit) errors.push(`${measurement.metric_id} passed measurement has wrong unit; expected ${threshold.unit}`);
      if (threshold && typeof measurement.value === 'number' && Number.isFinite(measurement.value)) {
        if (measurement.value < (threshold.minimum ?? 0)) errors.push(`${measurement.metric_id} value is below minimum ${threshold.minimum}`);
        if (measurement.value > threshold.maximum) errors.push(`${measurement.metric_id} value exceeds maximum ${threshold.maximum}`);
      }
      if (!Number.isInteger(measurement.sample_count) || measurement.sample_count <= 0) errors.push(`${measurement.metric_id} passed measurement has an invalid sample_count`);
      const evidence = measurement.evidence ?? {};
      if (Object.prototype.hasOwnProperty.call(evidence, 'attested')) errors.push(`${measurement.metric_id} contains legacy self-attestation`);
      if (evidence.class !== 'protected_external' || !evidence.run_id || !evidence.runner_id || !evidence.artifact_digest || !evidence.evidence_ref || !evidenceDigest.test(evidence.evidence_digest ?? '')) errors.push(`${measurement.metric_id} passed without protected evidence binding`);
      if (evidence.environment !== 'protected_device') errors.push(`${measurement.metric_id} passed measurement is not explicitly classified as protected_device`);
      if (evidence.source_commit !== performance.candidate?.source_commit) errors.push(`${measurement.metric_id} source_commit does not match performance candidate`);
      if (evidence.artifact_digest !== performance.candidate?.artifact_digest) errors.push(`${measurement.metric_id} artifact_digest does not match performance candidate`);
      if (!DIGEST.test(evidence.artifact_digest ?? '')) errors.push(`${measurement.metric_id} evidence artifact_digest is invalid`);
      if (typeof measurement.device !== 'string' || measurement.device.trim() === '') errors.push(`${measurement.metric_id} passed measurement has no device identity`);
      if (/(fixture|simulator|emulator|jvm|ui[-_ ]?test|local|self[-_ ]?attest)/i.test(JSON.stringify(measurement))) errors.push(`${measurement.metric_id} passed measurement contains a fixture/simulator/emulator/UI-test/local marker`);
    }
  }
  if (performance.status === 'passed') {
    for (const platform of ['ios', 'android']) {
      for (const metric of requiredMetrics) {
        if (!performance.measurements?.some((m) => m.metric_id === metric && m.platform === platform && m.status === 'passed')) errors.push(`performance status passed but ${platform}:${metric} is not passed`);
      }
    }
    if (typeof performance.report_id !== 'string' || performance.report_id.trim() === '') errors.push('performance passed without report_id');
    errors.push(...validateSignedAttestation({
      attestation: performance.attestation,
      payload: reportAttestationPayload(performance),
      label: 'performance report',
      expectedBindings: { report_id: performance.report_id, source_commit: performance.candidate?.source_commit, artifact_digest: performance.candidate?.artifact_digest },
      trustedAttestationKeys,
      nowMillis,
    }));
  }
  const candidateError = validateCandidate(performance.candidate, performance.status, 'Performance evidence', expectedSha);
  if (candidateError) errors.push(candidateError);
  return errors;
}

function validateIosArchive(archive, expectedSha = null, trustedAttestationKeys = {}, nowMillis = Date.now()) {
  const errors = [];
  if (archive.schema_version !== 'mobile-ai-keyboard.ios-archive.v1') errors.push('wrong schema_version');
  if (archive.evidence_class !== 'protected_external') errors.push('evidence_class must be protected_external');
  if (!VALID_STATUSES.has(archive.status)) errors.push(`invalid iOS archive status ${archive.status ?? 'missing'}`);
  if (archive.status === 'passed') {
    const evidence = archive.evidence ?? {};
    if (Object.prototype.hasOwnProperty.call(evidence, 'attested')) errors.push('archive contains legacy self-attestation');
    if (evidence.class !== 'protected_external' || !evidence.run_id || !evidence.runner_id || !evidence.artifact_digest || !evidence.evidence_ref || !evidenceDigest.test(evidence.evidence_digest ?? '')) errors.push('archive passed without protected evidence binding');
    if (evidence.environment !== 'protected_device') errors.push('archive passed evidence is not explicitly classified as protected_device');
    if (evidence.source_commit !== archive.candidate?.source_commit) errors.push('archive evidence source_commit does not match candidate');
    if (evidence.artifact_digest !== archive.candidate?.artifact_digest) errors.push('archive evidence artifact_digest does not match candidate');
    if (archive.attestation?.verifier_id !== evidence.runner_id) errors.push('iOS archive report signer does not match evidence runner');
    if (!DIGEST.test(evidence.artifact_digest ?? '')) errors.push('archive evidence artifact_digest is invalid');
    if (/(fixture|simulator|emulator|jvm|ui[-_ ]?test|local|self[-_ ]?attest)/i.test(JSON.stringify(archive))) errors.push('archive passed evidence contains a fixture/simulator/emulator/UI-test/local marker');
    if (!archive.entitlements?.host?.app_group || archive.entitlements.host.app_group !== archive.entitlements?.extension?.app_group) errors.push('archived host and extension must contain the same App Group entitlement');
    if (archive.extension_info?.requests_open_access !== true) errors.push('archived extension Info.plist must request the declared Full Access value');
    for (const component of ['host', 'extension']) {
      const manifest = archive.privacy_manifests?.[component];
      if (manifest?.embedded !== true || manifest?.declares_no_collected_data !== true) errors.push(`archived ${component} privacy manifest must explicitly confirm embedded and no collected data`);
    }
    if (typeof archive.report_id !== 'string' || archive.report_id.trim() === '') errors.push('archive passed without report_id');
    errors.push(...validateSignedAttestation({
      attestation: archive.attestation,
      payload: reportAttestationPayload(archive),
      label: 'iOS archive report',
      expectedBindings: { report_id: archive.report_id, source_commit: archive.candidate?.source_commit, artifact_digest: archive.candidate?.artifact_digest },
      trustedAttestationKeys,
      nowMillis,
    }));
  }
  const candidateError = validateCandidate(archive.candidate, archive.status, 'iOS archive evidence', expectedSha);
  if (candidateError) errors.push(candidateError);
  return errors;
}

function validateAndroidAab(report, expectedSha = null, trustedAttestationKeys = {}, nowMillis = Date.now()) {
  const errors = [];
  if (report.schema_version !== 'mobile-ai-keyboard.android-aab.v1') errors.push('wrong schema_version');
  if (report.evidence_class !== 'protected_external') errors.push('evidence_class must be protected_external');
  if (!VALID_STATUSES.has(report.status)) errors.push(`invalid Android AAB status ${report.status ?? 'missing'}`);
  if (report.status === 'passed') {
    const evidence = report.evidence ?? {};
    if (Object.prototype.hasOwnProperty.call(evidence, 'attested')) errors.push('Android AAB contains legacy self-attestation');
    if (evidence.class !== 'protected_external' || evidence.environment !== 'protected_release_runner' || !evidence.run_id || !evidence.runner_id || !evidence.evidence_ref || !evidenceDigest.test(evidence.evidence_digest ?? '')) errors.push('Android AAB passed without protected release-runner evidence');
    if (evidence.source_commit !== report.candidate?.source_commit || evidence.artifact_digest !== report.candidate?.artifact_digest) errors.push('Android AAB evidence is not bound to the candidate');
    if (report.attestation?.verifier_id !== evidence.runner_id) errors.push('Android AAB report signer does not match evidence runner');
    if (!DIGEST.test(evidence.artifact_digest ?? '')) errors.push('Android AAB evidence artifact_digest is invalid');
    if (report.package_id !== 'com.torutesu.mobileaikeyboard') errors.push('Android AAB package_id is invalid');
    if (report.artifact?.signed !== true || !DIGEST.test(report.artifact?.digest ?? '') || !DIGEST.test(report.artifact?.signing_certificate_sha256 ?? '')) errors.push('Android AAB must be signed and bind artifact/certificate SHA-256 digests');
    if (report.artifact?.digest !== report.candidate?.artifact_digest) errors.push('Android AAB artifact digest does not match candidate');
    const manifest = report.merged_manifest ?? {};
    if (manifest.internet_permission !== false) errors.push('Android AAB merged manifest must prove INTERNET is absent');
    if (manifest.ime_service_permission !== 'android.permission.BIND_INPUT_METHOD' || manifest.ime_service_exported !== true) errors.push('Android AAB merged manifest has an invalid IME service boundary');
    if (manifest.allow_backup !== false || manifest.data_extraction_rules_present !== true || manifest.full_backup_rules_present !== true) errors.push('Android AAB merged manifest must disable backup and embed extraction/backup rules');
    if (/(fixture|simulator|emulator|jvm|ui[-_ ]?test|local|self[-_ ]?attest|debug)/i.test(JSON.stringify(report))) errors.push('Android AAB passed evidence contains a debug/fixture/local marker');
    if (typeof report.report_id !== 'string' || report.report_id.trim() === '') errors.push('Android AAB passed without report_id');
    errors.push(...validateSignedAttestation({
      attestation: report.attestation,
      payload: reportAttestationPayload(report),
      label: 'Android AAB report',
      expectedBindings: { report_id: report.report_id, source_commit: report.candidate?.source_commit, artifact_digest: report.candidate?.artifact_digest },
      trustedAttestationKeys,
      nowMillis,
    }));
  }
  const candidateError = validateCandidate(report.candidate, report.status, 'Android AAB evidence', expectedSha);
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
  let androidAab;
  let benchmark;
  try { matrix = readJson(args.matrix).value; } catch (error) { results.push(check('evidence.e2e.schema', 'fail', error.message)); }
  try { performance = readJson(args.performance).value; } catch (error) { results.push(check('evidence.performance.schema', 'fail', error.message)); }
  if (args.iosArchive) {
    try { archive = readJson(args.iosArchive).value; } catch (error) { results.push(check('evidence.ios_archive.schema', 'fail', error.message)); }
  }
  if (args.androidAab) {
    try { androidAab = readJson(args.androidAab).value; } catch (error) { results.push(check('evidence.android_aab.schema', 'fail', error.message)); }
  }
  if (args.benchmark) {
    try { benchmark = readJson(args.benchmark).value; } catch (error) { results.push(check('evidence.benchmark.schema', 'fail', error.message)); }
  }
  if (matrix) {
    const errors = validateMatrix(matrix, args.candidateSha, args.trustedAttestationKeys, args.nowMillis);
    results.push(check('evidence.e2e.schema', errors.length ? 'fail' : 'pass', errors.length ? errors.join('; ') : 'E2E matrix contains both platforms and all required dimensions'));
    results.push(check('evidence.e2e.proof', errors.length ? 'fail' : (matrix.status === 'passed' ? 'pass' : 'not_proven'), matrix.status === 'not_proven' ? 'no protected physical-device/app runs are recorded' : (errors.length ? 'matrix contains invalid proof' : 'protected physical-device/app runs are bound to this candidate')));
  }
  if (performance) {
    const errors = validatePerformance(performance, args.candidateSha, args.trustedAttestationKeys, args.nowMillis);
    results.push(check('evidence.performance.schema', errors.length ? 'fail' : 'pass', errors.length ? errors.join('; ') : 'performance evidence contains all required metrics'));
    results.push(check('evidence.performance.proof', errors.length ? 'fail' : (performance.status === 'passed' ? 'pass' : 'not_proven'), performance.status === 'not_proven' ? 'no protected device performance captures are recorded' : (errors.length ? 'performance evidence contains invalid proof' : 'protected device performance captures are bound to this candidate')));
  }
  if (archive) {
    const errors = validateIosArchive(archive, args.candidateSha, args.trustedAttestationKeys, args.nowMillis);
    results.push(check('evidence.ios_archive.schema', errors.length ? 'fail' : 'pass', errors.length ? errors.join('; ') : 'archive report contains the required entitlement/privacy inspection fields'));
    results.push(check('evidence.ios_archive.proof', errors.length ? 'fail' : (archive.status === 'passed' ? 'pass' : 'not_proven'), archive.status === 'not_proven' ? 'no protected signed archive inspection is recorded' : (errors.length ? 'archive evidence contains invalid proof' : 'protected archive inspection is bound to this candidate')));
  }
  if (androidAab) {
    const errors = validateAndroidAab(androidAab, args.candidateSha, args.trustedAttestationKeys, args.nowMillis);
    results.push(check('evidence.android_aab.schema', errors.length ? 'fail' : 'pass', errors.length ? errors.join('; ') : 'Android AAB report contains signing and merged-manifest inspection fields'));
    results.push(check('evidence.android_aab.proof', errors.length ? 'fail' : (androidAab.status === 'passed' ? 'pass' : 'not_proven'), androidAab.status === 'not_proven' ? 'no protected signed Android AAB inspection is recorded' : (errors.length ? 'Android AAB evidence contains invalid proof' : 'protected signed Android AAB is bound to this candidate')));
  }
  if (benchmark) {
    const errors = validateBenchmark(benchmark, args.candidateSha);
    results.push(check('evidence.benchmark.schema', errors.length ? 'fail' : 'pass', errors.length ? errors.join('; ') : 'benchmark report contains all platform/metric bindings'));
    results.push(check('evidence.benchmark.proof', errors.length ? 'fail' : (benchmark.qualification_status === 'passed' ? 'pass' : 'not_proven'), benchmark.qualification_status === 'failed' ? 'deterministic benchmark regression detected' : (benchmark.qualification_status === 'not_proven' ? 'diagnostic result is not physical-device qualification' : 'protected benchmark is bound to this candidate')));
  }
  return results;
}

export function evaluate(options = {}) {
  let envTrustedAttestationKeys = {};
  if (process.env.MOBILE_AI_KEYBOARD_TRUSTED_ATTESTATION_KEYS_JSON) {
    try { envTrustedAttestationKeys = JSON.parse(process.env.MOBILE_AI_KEYBOARD_TRUSTED_ATTESTATION_KEYS_JSON); }
    catch { envTrustedAttestationKeys = {}; }
  }
  const args = { ...parseArgs([]), trustedAttestationKeys: envTrustedAttestationKeys, nowMillis: Date.now(), ...options };
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
