#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const MATRIX_PATH = path.join(ROOT, 'docs/release-e2e-matrix.json');
const DIGEST = /^sha256:[0-9a-f]{64}$/;
const COMMIT = /^[0-9a-f]{40}$/;
const DEVICE_CLASSES = ['iphone_baseline', 'iphone_current', 'iphone_small', 'ipad_portrait_landscape'];

function parseArgs(argv) {
  const command = argv.shift();
  if (!['prepare', 'finalize'].includes(command)) throw new Error('Usage: ios-physical-qa.mjs <prepare|finalize> [options]');
  const args = { command };
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith('--') || value === undefined) throw new Error(`Invalid argument: ${key ?? 'missing'}`);
    args[key.slice(2)] = value;
  }
  return args;
}

function required(args, keys) {
  for (const key of keys) if (!args[key]) throw new Error(`Missing --${key}`);
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(path.resolve(file), 'utf8'));
}

function digestFile(file) {
  return `sha256:${crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')}`;
}

function allObjects(value, result = []) {
  if (Array.isArray(value)) value.forEach((item) => allObjects(item, result));
  else if (value && typeof value === 'object') {
    result.push(value);
    Object.values(value).forEach((item) => allObjects(item, result));
  }
  return result;
}

function scalarValues(value, result = []) {
  if (Array.isArray(value)) value.forEach((item) => scalarValues(item, result));
  else if (value && typeof value === 'object') Object.values(value).forEach((item) => scalarValues(item, result));
  else if (value !== null && value !== undefined) result.push(String(value));
  return result;
}

function firstValue(value, keys) {
  for (const object of allObjects(value)) {
    for (const key of keys) {
      const candidate = object[key];
      if (['string', 'number'].includes(typeof candidate) && String(candidate).trim()) return String(candidate);
    }
  }
  return null;
}

function findDevice(devices, deviceId) {
  const candidates = allObjects(devices).filter((object) => scalarValues(object).includes(deviceId));
  const device = candidates.find((object) => /iphone|ipad/i.test(JSON.stringify(object))) ?? candidates[0];
  if (!device) throw new Error(`Physical device ${deviceId} is not present in devicectl evidence`);
  const serialized = JSON.stringify(device);
  if (/simulator|virtual/i.test(serialized)) throw new Error(`Device ${deviceId} is not a physical iOS device`);
  return {
    device_id: deviceId,
    device_model: firstValue(device, ['marketingName', 'productType', 'modelName', 'name']) ?? 'unknown',
    os_version: firstValue(device, ['osVersionNumber', 'operatingSystemVersion', 'osVersion', 'buildVersion']) ?? 'unknown',
    devicectl_record: device,
  };
}

function checklist(matrix, runId) {
  const ios = matrix.targets.find((target) => target.platform === 'ios');
  const pending = (id, key) => ({ [key]: id, run_id: runId, status: 'pending', evidence_ref: null, evidence_digest: null });
  return {
    scenario_results: matrix.required_scenarios.map((id) => pending(id, 'scenario_id')),
    field_class_results: matrix.required_field_classes.map((id) => pending(id, 'field_class')),
    lifecycle_results: matrix.required_lifecycle_events.map((id) => pending(id, 'lifecycle_event')),
    app_evidence: ios.apps.map((id) => ({ app_id: id, app_identifier: null, run_id: runId, status: 'pending', evidence_ref: null, evidence_digest: null })),
  };
}

function evidenceMapTemplate(packet) {
  return {
    schema_version: 'mobile-ai-keyboard.ios-physical-evidence-map.v1',
    run_id: packet.run_id,
    note: 'Use paths relative to --evidence-dir. One capture may be referenced by multiple checks.',
    scenarios: Object.fromEntries(packet.scenario_results.map((item) => [item.scenario_id, []])),
    field_classes: Object.fromEntries(packet.field_class_results.map((item) => [item.field_class, []])),
    lifecycle_events: Object.fromEntries(packet.lifecycle_results.map((item) => [item.lifecycle_event, []])),
    apps: Object.fromEntries(packet.app_evidence.map((item) => [item.app_id, { app_identifier: '', files: [] }])),
    accessibility_tools: ['voiceover'],
  };
}

export function prepare(args) {
  required(args, ['candidate', 'ipa', 'devices', 'device-id', 'device-class', 'run-id', 'runner-id', 'output']);
  if (!DEVICE_CLASSES.includes(args['device-class'])) throw new Error(`Unknown --device-class ${args['device-class']}`);
  if (!/^[A-Za-z0-9._-]{6,128}$/.test(args['run-id'])) throw new Error('Invalid --run-id');
  const candidate = readJson(args.candidate);
  if (!COMMIT.test(candidate.source_commit ?? '')) throw new Error('Candidate evidence has no exact source_commit');
  if (!DIGEST.test(candidate.artifact_digest ?? '')) throw new Error('Candidate evidence has no valid artifact_digest');
  if (!DIGEST.test(candidate.ipa_digest ?? '')) throw new Error('Candidate evidence has no valid ipa_digest');
  const ipaPath = path.resolve(args.ipa);
  if (digestFile(ipaPath) !== candidate.ipa_digest) throw new Error('IPA digest does not match candidate evidence');
  const devicesPath = path.resolve(args.devices);
  const device = findDevice(readJson(devicesPath), args['device-id']);
  const matrix = readJson(MATRIX_PATH);
  const run = {
    schema_version: 'mobile-ai-keyboard.ios-physical-qa-session.v1',
    qualification_status: 'not_proven',
    capture_status: 'prepared',
    evidence_class: 'physical_capture_pending_protected_attestation',
    environment: 'protected_device',
    run_id: args['run-id'],
    runner_id: args['runner-id'],
    device_id: device.device_id,
    device_class: args['device-class'],
    device_model: device.device_model,
    os_version: device.os_version,
    source_commit: candidate.source_commit,
    artifact_digest: candidate.artifact_digest,
    ipa_digest: candidate.ipa_digest,
    candidate_evidence_digest: digestFile(path.resolve(args.candidate)),
    device_inventory_digest: digestFile(devicesPath),
    accessibility_tools: ['voiceover'],
    ...checklist(matrix, args['run-id']),
    attestation: { status: 'pending_protected_runner' },
  };
  const output = path.resolve(args.output);
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, `${JSON.stringify(run, null, 2)}\n`);
  const mapPath = `${output.slice(0, -path.extname(output).length)}-evidence-map.json`;
  fs.writeFileSync(mapPath, `${JSON.stringify(evidenceMapTemplate(run), null, 2)}\n`);
  return { output, mapPath, run };
}

function evidenceEntry(evidenceDir, relativePath) {
  if (typeof relativePath !== 'string' || !relativePath.trim()) throw new Error('Evidence path must be a non-empty string');
  const absolute = path.resolve(evidenceDir, relativePath);
  const relative = path.relative(evidenceDir, absolute);
  if (relative.startsWith('..') || path.isAbsolute(relative)) throw new Error(`Evidence path escapes evidence directory: ${relativePath}`);
  const stat = fs.statSync(absolute);
  if (!stat.isFile()) throw new Error(`Evidence is not a file: ${relativePath}`);
  return { evidence_ref: relative, evidence_digest: digestFile(absolute), size_bytes: stat.size };
}

function applyEvidence(items, idKey, mapping, evidenceDir, manifest) {
  return items.map((item) => {
    const id = item[idKey];
    const refs = mapping[id];
    if (!Array.isArray(refs) || refs.length === 0) throw new Error(`Missing evidence files for ${id}`);
    const entries = refs.map((ref) => evidenceEntry(evidenceDir, ref));
    entries.forEach((entry) => manifest.push({ category: idKey, id, ...entry }));
    return { ...item, status: 'captured_pending_attestation', evidence_ref: entries.map((entry) => entry.evidence_ref).join(','), evidence_digest: entries[0].evidence_digest };
  });
}

export function finalize(args) {
  required(args, ['session', 'evidence-map', 'evidence-dir', 'output']);
  const session = readJson(args.session);
  const map = readJson(args['evidence-map']);
  if (session.schema_version !== 'mobile-ai-keyboard.ios-physical-qa-session.v1') throw new Error('Invalid session schema');
  if (map.run_id !== session.run_id) throw new Error('Evidence map run_id does not match session');
  const evidenceDir = path.resolve(args['evidence-dir']);
  const manifest = [];
  const result = structuredClone(session);
  result.scenario_results = applyEvidence(result.scenario_results, 'scenario_id', map.scenarios ?? {}, evidenceDir, manifest);
  result.field_class_results = applyEvidence(result.field_class_results, 'field_class', map.field_classes ?? {}, evidenceDir, manifest);
  result.lifecycle_results = applyEvidence(result.lifecycle_results, 'lifecycle_event', map.lifecycle_events ?? {}, evidenceDir, manifest);
  result.app_evidence = result.app_evidence.map((item) => {
    const mapping = map.apps?.[item.app_id];
    if (!mapping?.app_identifier || !Array.isArray(mapping.files) || mapping.files.length === 0) throw new Error(`Missing app identifier or evidence for ${item.app_id}`);
    const entries = mapping.files.map((ref) => evidenceEntry(evidenceDir, ref));
    entries.forEach((entry) => manifest.push({ category: 'app_id', id: item.app_id, ...entry }));
    return { ...item, app_identifier: mapping.app_identifier, status: 'captured_pending_attestation', evidence_ref: entries.map((entry) => entry.evidence_ref).join(','), evidence_digest: entries[0].evidence_digest };
  });
  if (!Array.isArray(map.accessibility_tools) || !map.accessibility_tools.includes('voiceover')) throw new Error('VoiceOver evidence declaration is required');
  result.accessibility_tools = [...new Set(map.accessibility_tools)];
  result.capture_status = 'captured_pending_protected_attestation';
  result.qualification_status = 'not_proven';
  result.evidence_manifest = manifest;
  result.evidence_manifest_digest = `sha256:${crypto.createHash('sha256').update(JSON.stringify(manifest)).digest('hex')}`;
  const output = path.resolve(args.output);
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, `${JSON.stringify(result, null, 2)}\n`);
  return { output, result };
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const result = args.command === 'prepare' ? prepare(args) : finalize(args);
    console.log(`Physical QA packet ${args.command} complete: ${result.output}`);
    if (result.mapPath) console.log(`Evidence map template: ${result.mapPath}`);
    console.log('Qualification remains not_proven until an independent protected runner verifies and signs the packet.');
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
