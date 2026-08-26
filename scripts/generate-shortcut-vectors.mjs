#!/usr/bin/env node

/* TypeScript contracts are authoritative; this file only serializes their vectors. */
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { ShortcutSnapshot, shortcutSnapshotDigest, buildShortcutGoldenVectors } from '../packages/contracts/dist/index.js';
import { validateShortcutSnapshot } from '../packages/policy/dist/index.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const FIXTURE = path.join(ROOT, 'fixtures/shortcut-golden-vectors.json');
const user = 'usr_1234567890abcdef';
const device = 'dev_1234567890abcdef';

export function buildFixture() { return buildShortcutGoldenVectors(); }

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
  if (fixture.schema_version !== 'mobile-ai-keyboard.shortcut-golden.v1') failures.push('fixture schema_version');
  if (fixture.authority !== 'typescript-contracts') failures.push('fixture authority');
  if (fixture.native_consumption_status !== 'not_proven') failures.push('native consumption must remain not_proven');
  const seen = new Set();
  for (const vector of fixture.vectors ?? []) {
    if (seen.has(vector.id)) failures.push(`duplicate vector ${vector.id}`);
    seen.add(vector.id);
    const digest = vector.input?.content_digest;
    const unsigned = vector.input ? { ...vector.input } : {};
    delete unsigned.content_digest;
    const digestMatches = typeof digest === 'string' && shortcutSnapshotDigest(unsigned) === digest;
    if (vector.expected.contract_valid && !digestMatches) failures.push(`${vector.id}: digest mismatch`);
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
