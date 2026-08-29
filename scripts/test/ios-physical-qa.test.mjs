import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { finalize, prepare } from '../ios-physical-qa.mjs';

const digest = (value) => `sha256:${crypto.createHash('sha256').update(value).digest('hex')}`;

function fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'mik-ios-physical-'));
  const ipa = path.join(root, 'candidate.ipa');
  fs.writeFileSync(ipa, 'signed candidate bytes');
  const candidate = path.join(root, 'candidate.json');
  fs.writeFileSync(candidate, JSON.stringify({
    source_commit: 'a'.repeat(40),
    artifact_digest: digest('candidate'),
    ipa_digest: digest('signed candidate bytes'),
  }));
  const devices = path.join(root, 'devices.json');
  fs.writeFileSync(devices, JSON.stringify({ result: { devices: [{
    identifier: '00008110-TESTDEVICE',
    hardwareProperties: { marketingName: 'iPhone 16 Pro' },
    deviceProperties: { osVersionNumber: '18.6' },
  }] } }));
  const output = path.join(root, 'session.json');
  return { root, ipa, candidate, devices, output };
}

test('prepares an exact non-qualifying physical QA checklist bound to candidate and device', () => {
  const value = fixture();
  const { run, mapPath } = prepare({
    candidate: value.candidate, ipa: value.ipa, devices: value.devices,
    'device-id': '00008110-TESTDEVICE', 'device-class': 'iphone_current',
    'run-id': 'ios-run-123456', 'runner-id': 'protected-lab-01', output: value.output,
  });
  assert.equal(run.qualification_status, 'not_proven');
  assert.equal(run.device_model, 'iPhone 16 Pro');
  assert.equal(run.scenario_results.length, 13);
  assert.equal(run.field_class_results.length, 10);
  assert.equal(run.lifecycle_results.length, 6);
  assert.equal(run.app_evidence.length, 7);
  assert.ok(fs.existsSync(mapPath));
});

test('rejects an IPA or physical device that is not bound to the evidence', () => {
  const value = fixture();
  fs.writeFileSync(value.ipa, 'tampered');
  assert.throws(() => prepare({
    candidate: value.candidate, ipa: value.ipa, devices: value.devices,
    'device-id': '00008110-TESTDEVICE', 'device-class': 'iphone_current',
    'run-id': 'ios-run-123456', 'runner-id': 'protected-lab-01', output: value.output,
  }), /IPA digest does not match/);

  const second = fixture();
  assert.throws(() => prepare({
    candidate: second.candidate, ipa: second.ipa, devices: second.devices,
    'device-id': 'missing-device', 'device-class': 'iphone_current',
    'run-id': 'ios-run-123456', 'runner-id': 'protected-lab-01', output: second.output,
  }), /not present/);
});

test('finalize hashes every evidence file but remains not_proven pending protected attestation', () => {
  const value = fixture();
  const prepared = prepare({
    candidate: value.candidate, ipa: value.ipa, devices: value.devices,
    'device-id': '00008110-TESTDEVICE', 'device-class': 'iphone_current',
    'run-id': 'ios-run-123456', 'runner-id': 'protected-lab-01', output: value.output,
  });
  const evidenceDir = path.join(value.root, 'captures');
  fs.mkdirSync(evidenceDir);
  fs.writeFileSync(path.join(evidenceDir, 'capture.mov'), 'physical capture bytes');
  const map = JSON.parse(fs.readFileSync(prepared.mapPath, 'utf8'));
  for (const id of Object.keys(map.scenarios)) map.scenarios[id] = ['capture.mov'];
  for (const id of Object.keys(map.field_classes)) map.field_classes[id] = ['capture.mov'];
  for (const id of Object.keys(map.lifecycle_events)) map.lifecycle_events[id] = ['capture.mov'];
  for (const id of Object.keys(map.apps)) map.apps[id] = { app_identifier: `physical.${id.toLowerCase()}`, files: ['capture.mov'] };
  fs.writeFileSync(prepared.mapPath, JSON.stringify(map));
  const output = path.join(value.root, 'captured.json');
  const { result } = finalize({ session: value.output, 'evidence-map': prepared.mapPath, 'evidence-dir': evidenceDir, output });
  assert.equal(result.capture_status, 'captured_pending_protected_attestation');
  assert.equal(result.qualification_status, 'not_proven');
  assert.match(result.evidence_manifest_digest, /^sha256:[0-9a-f]{64}$/);
  assert.ok(result.evidence_manifest.every((item) => item.evidence_digest === digest('physical capture bytes')));
});

test('finalize rejects missing evidence instead of manufacturing a pass', () => {
  const value = fixture();
  const prepared = prepare({
    candidate: value.candidate, ipa: value.ipa, devices: value.devices,
    'device-id': '00008110-TESTDEVICE', 'device-class': 'iphone_current',
    'run-id': 'ios-run-123456', 'runner-id': 'protected-lab-01', output: value.output,
  });
  assert.throws(() => finalize({
    session: value.output, 'evidence-map': prepared.mapPath,
    'evidence-dir': value.root, output: path.join(value.root, 'captured.json'),
  }), /Missing evidence files/);
});
