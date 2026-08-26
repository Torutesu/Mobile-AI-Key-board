#!/usr/bin/env node

/*
 * Content-free, deterministic diagnostic benchmark. It intentionally measures
 * contract fixtures rather than wall-clock device performance. A passing
 * diagnostic is useful for regression detection but never qualifies a release.
 */
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DIGEST = /^sha256:[a-f0-9]{64}$/;
export const BENCHMARK_THRESHOLDS = Object.freeze({
  key_to_commit_p50_ms: { maximum: 35, unit: 'ms' },
  key_to_commit_p95_ms: { maximum: 50, unit: 'ms' },
  keyboard_cold_open_p95_ms: { maximum: 400, unit: 'ms' },
  keyboard_warm_open_p95_ms: { maximum: 150, unit: 'ms' },
  long_press_false_activation_rate: { maximum: 0.001, unit: 'ratio' },
  ordinary_tap_drop_rate: { maximum: 0.001, unit: 'ratio' },
});

const baseline = {
  key_to_commit_p50_ms: [24, 27, 29, 30, 31, 31, 32, 33],
  key_to_commit_p95_ms: [41, 43, 44, 45, 46, 47, 48, 49],
  keyboard_cold_open_p95_ms: [278, 291, 305, 318, 327, 339, 351, 367],
  keyboard_warm_open_p95_ms: [82, 89, 94, 101, 108, 115, 121, 132],
  long_press_false_activation_rate: [0, 0, 0, 0, 0, 0, 0, 0],
  ordinary_tap_drop_rate: [0, 0, 0, 0, 0, 0, 0, 0],
};
const platforms = ['ios', 'android'];

function canonical(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  return `{${Object.entries(value).sort(([a], [b]) => a.localeCompare(b)).map(([key, child]) => `${JSON.stringify(key)}:${canonical(child)}`).join(',')}}`;
}
function digest(value) { return `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`; }
function percentile(values, fraction) {
  const ordered = [...values].sort((a, b) => a - b);
  return ordered[Math.max(0, Math.ceil(fraction * ordered.length) - 1)];
}
function parseArgs(argv) {
  const args = { report: null, input: null, candidateDigest: `sha256:${'0'.repeat(64)}` };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--') continue;
    if (arg === '--report') args.report = argv[++index];
    else if (arg === '--input') args.input = argv[++index];
    else if (arg === '--candidate-digest') args.candidateDigest = argv[++index];
    else throw new Error(`unknown argument: ${arg}`);
  }
  if (!DIGEST.test(args.candidateDigest)) throw new Error('--candidate-digest must be a sha256 digest');
  return args;
}
function loadSamples(file) {
  if (!file) return baseline;
  const value = JSON.parse(fs.readFileSync(path.resolve(ROOT, file), 'utf8'));
  if (!value || typeof value !== 'object' || !value.samples) throw new Error('benchmark input must contain samples');
  return value.samples;
}
export function buildReport({ candidateDigest, samples = baseline, environment = 'fixture' }) {
  const observations = [];
  const failures = [];
  for (const platform of platforms) {
    for (const [metric, threshold] of Object.entries(BENCHMARK_THRESHOLDS)) {
      const values = samples[metric];
      if (!Array.isArray(values) || values.length === 0 || values.some((value) => typeof value !== 'number' || !Number.isFinite(value) || value < 0)) {
        failures.push(`${platform}:${metric}:invalid_samples`);
        continue;
      }
      const percentileValue = metric.endsWith('_p50_ms') ? percentile(values, 0.5) : percentile(values, 0.95);
      const value = metric.includes('rate') ? values.reduce((sum, item) => sum + item, 0) / values.length : percentileValue;
      if (value > threshold.maximum) failures.push(`${platform}:${metric}`);
      observations.push({ metric, platform, value, unit: threshold.unit, sample_count: values.length, candidate_digest: candidateDigest, environment, evidence: { kind: 'deterministic_fixture', test_run_id: 'fixture_benchmark_v1' } });
    }
  }
  const report = { schema_version: 'mobile-ai-keyboard.performance-benchmark.v1', candidate_digest: candidateDigest, environment, diagnostic_status: failures.length === 0 ? 'passed' : 'failed', qualification_status: failures.length === 0 && environment === 'protected_device' ? 'passed' : (failures.length === 0 ? 'not_proven' : 'failed'), observations, evidence: { kind: environment === 'protected_device' ? 'protected_external' : 'deterministic_fixture', test_run_id: 'fixture_benchmark_v1' } };
  return { ...report, report_digest: digest(report), failures };
}
export function run(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  return buildReport({ candidateDigest: args.candidateDigest, samples: loadSamples(args.input) });
}
function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const { failures: _failures, ...report } = buildReport({ candidateDigest: args.candidateDigest, samples: loadSamples(args.input) });
    const output = `${JSON.stringify(report, null, 2)}\n`;
    if (args.report) { const target = path.resolve(ROOT, args.report); fs.mkdirSync(path.dirname(target), { recursive: true }); fs.writeFileSync(target, output); }
    console.log(output.trimEnd());
    process.exitCode = report.qualification_status === 'failed' ? 1 : 0;
  } catch (error) { console.error(error.message); process.exitCode = 2; }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
