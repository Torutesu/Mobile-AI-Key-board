#!/usr/bin/env node

/*
 * Source-level contract for the cross-language shortcut-vector consumers.
 *
 * The TypeScript contracts remain authoritative.  This gate only proves that
 * both native unit-test suites are wired to read the checked-in fixture and
 * exercise its positive, conflict, digest, and rejection fields.  It does not
 * turn a source scan into runtime, device, or release evidence.
 */
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

export const NATIVE_CONSUMER_MARKER = 'MOBILE_AI_KEYBOARD_SHORTCUT_GOLDEN_CONSUMER_V1';
export const FIXTURE_BASENAME = 'shortcut-golden-vectors.json';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const consumerContracts = [
  {
    platform: 'ios',
    directory: path.join('apps', 'ios', 'Tests'),
    extensions: new Set(['.swift']),
    required: [
      NATIVE_CONSUMER_MARKER,
      FIXTURE_BASENAME,
      'valid_local_snapshot',
      'duplicate_physical_key_conflict_rejects_distinct_bindings',
      ['content_digest', 'contentDigest'],
      ['contract_valid', 'contractValid'],
      'rejection',
      'XCTAssert',
      'ShortcutWireValidator.inspect',
      'ShortcutWireValidator.decodeSnapshot',
      'locateRepositoryFixture'
    ],
    forbidden: [/XCTSkip/i, /#if\s+false/i]
  },
  {
    platform: 'android',
    directory: path.join('apps', 'android', 'app', 'src', 'test'),
    extensions: new Set(['.kt']),
    required: [
      NATIVE_CONSUMER_MARKER,
      FIXTURE_BASENAME,
      'valid_local_snapshot',
      'duplicate_physical_key_conflict_rejects_distinct_bindings',
      ['content_digest', 'contentDigest'],
      ['contract_valid', 'contractValid'],
      'rejection',
      'assert',
      'assertEquals',
      'ShortcutGoldenFixture.repositoryFixture',
      'ShortcutGoldenFixture.validate'
    ],
    forbidden: [/@Ignore/i, /@Disabled/i]
  }
];

function listSourceFiles(directory, extensions) {
  if (!fs.existsSync(directory)) return [];
  const entries = fs.readdirSync(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const child = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...listSourceFiles(child, extensions));
    else if (extensions.has(path.extname(entry.name))) files.push(child);
  }
  return files.sort();
}

function inspectContract(contract, root = ROOT) {
  const directory = path.resolve(root, contract.directory);
  const files = listSourceFiles(directory, contract.extensions);
  const candidates = files.map((file) => ({ file, text: fs.readFileSync(file, 'utf8') }))
    .filter(({ text }) => text.includes(NATIVE_CONSUMER_MARKER));
  const failures = [];
  if (candidates.length === 0) {
    failures.push(`missing ${contract.platform} native golden-vector consumer marker`);
  }
  const matching = candidates.filter(({ text }) => {
    return contract.required.every((needle) => Array.isArray(needle)
      ? needle.some((alternative) => text.includes(alternative))
      : text.includes(needle))
      && contract.forbidden.every((pattern) => !pattern.test(text));
  });
  if (candidates.length > 0 && matching.length === 0) {
    failures.push(`${contract.platform} consumer does not exercise the required fixture assertions`);
  }
  return {
    platform: contract.platform,
    status: matching.length > 0 ? 'present' : 'missing',
    files: matching.map(({ file }) => path.relative(root, file)),
    failures
  };
}

export function inspectNativeConsumers(root = ROOT) {
  const checks = consumerContracts.map((contract) => inspectContract(contract, root));
  return {
    status: checks.every((check) => check.status === 'present') ? 'native_unit_consumers' : 'not_proven',
    checks
  };
}

export function nativeConsumerFailures(root = ROOT) {
  const report = inspectNativeConsumers(root);
  return report.checks.flatMap((check) => check.failures.map((failure) => `${check.platform}: ${failure}`));
}

function evidenceReport(report, root = ROOT) {
  const fixturePath = path.join(root, 'fixtures', FIXTURE_BASENAME);
  const fixtureBytes = fs.existsSync(fixturePath) ? fs.readFileSync(fixturePath) : null;
  return {
    schema_version: 'mobile-ai-keyboard.shortcut-native-consumption.v1',
    evidence_class: 'static_ci_report',
    source_commit: process.env.GITHUB_SHA ?? null,
    fixture_path: path.relative(root, fixturePath),
    fixture_sha256: fixtureBytes ? createHash('sha256').update(fixtureBytes).digest('hex') : null,
    ...report
  };
}

function main() {
  const report = inspectNativeConsumers();
  const evidence = evidenceReport(report);
  const reportArg = process.argv.indexOf('--report');
  if (reportArg >= 0 && process.argv[reportArg + 1]) {
    const output = path.resolve(process.argv[reportArg + 1]);
    fs.mkdirSync(path.dirname(output), { recursive: true });
    fs.writeFileSync(output, `${JSON.stringify(evidence, null, 2)}\n`);
  }
  console.log(JSON.stringify(evidence, null, 2));
  const failures = nativeConsumerFailures();
  if (failures.length > 0) {
    console.error(failures.join('\n'));
    process.exitCode = 1;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
