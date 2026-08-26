#!/usr/bin/env node

/* TypeScript contracts are authoritative; this file only serializes their vectors. */
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { ShortcutSnapshot, shortcutSnapshotDigest, buildShortcutGoldenVectors } from '../packages/contracts/dist/index.js';
import { validateShortcutSnapshot } from '../packages/policy/dist/index.js';
import { inspectNativeConsumers } from './check-native-shortcut-consumers.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const FIXTURE = path.join(ROOT, 'fixtures/shortcut-golden-vectors.json');
const user = 'usr_1234567890abcdef';
const device = 'dev_1234567890abcdef';

const EXPECTED_VECTOR_IDS = [
  'valid_local_snapshot',
  'schema_version_rejects_unknown_version',
  'key_normalization_rejects_lowercase_physical_key',
  'digest_rejects_tampered_content',
  'duplicate_physical_key_conflict_rejects_distinct_bindings',
  'local_route_authority_rejects_host_handoff',
  'local_route_authority_rejects_tools'
];
const EXPECTED_FIXTURE_KEYS = ['schema_version', 'authority', 'native_consumption_status', 'canonicalization', 'vectors'];
const EXPECTED_VECTOR_KEYS = ['id', 'kind', 'input', 'expected'];
const EXPECTED_EXPECTED_KEYS = ['contract_valid', 'content_digest', 'rejection'];

function hasExactKeys(value, expected) {
  return value && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).length === expected.length
    && expected.every((key) => Object.prototype.hasOwnProperty.call(value, key));
}

export function buildFixture() {
  const fixture = buildShortcutGoldenVectors();
  // Native unit consumers are a separate, source-and-test gate.  Reflect only
  // that precise level here; this field never claims physical/runtime parity.
  fixture.native_consumption_status = inspectNativeConsumers(ROOT).status;
  return fixture;
}

function classifyRejection(input) {
  if (input?.schema_version !== 1) return 'schema';
  const bindings = Array.isArray(input?.bindings) ? input.bindings : [];
  if (bindings.some((binding) => !/^Key[A-Z]$/.test(binding?.trigger_key?.key_code ?? ''))) return 'key_normalization';
  try {
    const parsed = ShortcutSnapshot.parse(input);
    validateShortcutSnapshot(parsed, 0, { user_id: user, device_id: device });
    return null;
  } catch (error) {
    const code = error?.details?.code;
    if (code === 'SNAPSHOT_DIGEST_MISMATCH') return 'digest';
    if (code === 'DUPLICATE_TRIGGER_KEY') return 'duplicate_conflict';
    if (code === 'PROJECTION_AUTHORITY_MISMATCH') return 'local_route_authority';
    if (code === 'INVALID_SHORTCUT_SNAPSHOT') return 'schema';
    return `unclassified:${code ?? 'unknown'}`;
  }
}

export function checkFixture(fixture) {
  const failures = [];
  if (!fixture || typeof fixture !== 'object' || Array.isArray(fixture)) return ['fixture must be an object'];
  if (!hasExactKeys(fixture, EXPECTED_FIXTURE_KEYS)) failures.push('fixture keys are not exact');
  if (fixture.schema_version !== 'mobile-ai-keyboard.shortcut-golden.v1') failures.push('fixture schema_version');
  if (fixture.authority !== 'typescript-contracts') failures.push('fixture authority');
  const nativeStatus = inspectNativeConsumers(ROOT).status;
  if (!['not_proven', 'native_unit_consumers'].includes(fixture.native_consumption_status)) failures.push('native consumption status is invalid');
  if (fixture.native_consumption_status !== nativeStatus) failures.push(`native consumption status=${fixture.native_consumption_status}, source status=${nativeStatus}`);
  if (fixture.canonicalization !== 'RFC8785-like canonicalJson from packages/contracts') failures.push('fixture canonicalization');
  if (!Array.isArray(fixture.vectors)) return [...failures, 'fixture vectors must be an array'];
  if (fixture.vectors.length !== EXPECTED_VECTOR_IDS.length) failures.push(`expected ${EXPECTED_VECTOR_IDS.length} vectors, got ${fixture.vectors.length}`);
  const seen = new Set();
  const ids = [];
  for (const vector of fixture.vectors ?? []) {
    if (!vector || typeof vector !== 'object' || Array.isArray(vector)) { failures.push('vector must be an object'); continue; }
    if (!hasExactKeys(vector, EXPECTED_VECTOR_KEYS)) failures.push(`${vector.id ?? '<unknown>'}: vector keys are not exact`);
    if (vector.kind !== 'shortcut_snapshot') failures.push(`${vector.id ?? '<unknown>'}: kind`);
    if (typeof vector.id !== 'string' || vector.id.length === 0) { failures.push('vector id must be non-empty'); continue; }
    if (seen.has(vector.id)) failures.push(`duplicate vector ${vector.id}`);
    seen.add(vector.id);
    ids.push(vector.id);
    if (!vector.expected || typeof vector.expected !== 'object' || Array.isArray(vector.expected)) { failures.push(`${vector.id}: expected must be an object`); continue; }
    if (!hasExactKeys(vector.expected, EXPECTED_EXPECTED_KEYS)) failures.push(`${vector.id}: expected keys are not exact`);
    if (typeof vector.expected.contract_valid !== 'boolean') failures.push(`${vector.id}: expected contract_valid must be boolean`);
    if (!(vector.expected.content_digest === null || typeof vector.expected.content_digest === 'string')) failures.push(`${vector.id}: expected content_digest must be string or null`);
    if (!(vector.expected.rejection === null || typeof vector.expected.rejection === 'string')) failures.push(`${vector.id}: expected rejection must be string or null`);
    const digest = vector.input?.content_digest;
    const unsigned = vector.input ? { ...vector.input } : {};
    delete unsigned.content_digest;
    const digestMatches = typeof digest === 'string' && shortcutSnapshotDigest(unsigned) === digest;
    if (vector.expected.contract_valid && !digestMatches) failures.push(`${vector.id}: digest mismatch`);
    if (vector.expected.contract_valid && vector.expected.content_digest !== digest) failures.push(`${vector.id}: expected content_digest does not match input`);
    if (!vector.expected.contract_valid && vector.expected.content_digest !== null) failures.push(`${vector.id}: rejected vector must declare content_digest=null`);
    const rejection = classifyRejection(vector.input);
    if (!vector.expected.contract_valid && rejection !== vector.expected.rejection) failures.push(`${vector.id}: expected rejection=${vector.expected.rejection}, got ${rejection}`);
    if (vector.expected.contract_valid && vector.expected.rejection !== null) failures.push(`${vector.id}: valid vector cannot declare rejection=${vector.expected.rejection}`);
    let valid = false;
    try {
      const parsed = ShortcutSnapshot.parse(vector.input);
      validateShortcutSnapshot(parsed, 0, { user_id: user, device_id: device });
      valid = true;
    } catch { valid = false; }
    if (valid !== vector.expected.contract_valid) failures.push(`${vector.id}: expected contract_valid=${vector.expected.contract_valid}, got ${valid}`);
  }
  if (ids.length === EXPECTED_VECTOR_IDS.length && ids.some((id, index) => id !== EXPECTED_VECTOR_IDS[index])) failures.push('vector order/identity is not authoritative');
  return failures;
}

function main() {
  const checkOnly = process.argv.includes('--check');
  const fixture = buildFixture();
  const failures = checkFixture(fixture);
  if (failures.length > 0) { console.error(failures.join('\n')); process.exitCode = 1; return; }
  const serialized = `${JSON.stringify(fixture, null, 2)}\n`;
  if (checkOnly) {
    if (!fs.existsSync(FIXTURE) || fs.readFileSync(FIXTURE, 'utf8') !== serialized) { console.error('shortcut golden vectors are stale; run pnpm shortcuts:vectors:generate'); process.exitCode = 1; return; }
  } else {
    fs.mkdirSync(path.dirname(FIXTURE), { recursive: true });
    fs.writeFileSync(FIXTURE, serialized);
  }
  console.log(`shortcut golden vectors ${checkOnly ? 'checked' : 'generated'}: ${fixture.vectors.length} vectors`);
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
