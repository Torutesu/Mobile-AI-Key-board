import test from 'node:test';
import assert from 'node:assert/strict';
import { BENCHMARK_THRESHOLDS, buildReport } from '../performance-benchmark.mjs';

const candidate = `sha256:${'e'.repeat(64)}`;

test('deterministic benchmark emits identical content-free diagnostics', () => {
  const first = buildReport({ candidateDigest: candidate });
  const second = buildReport({ candidateDigest: candidate });
  assert.deepEqual(first, second);
  assert.equal(first.observations.length, 12);
  assert.equal(first.diagnostic_status, 'passed');
  assert.equal(first.qualification_status, 'not_proven');
  assert.ok(first.observations.every((observation) => observation.candidate_digest === candidate));
});

test('benchmark catches a threshold regression for both platforms', () => {
  const samples = Object.fromEntries(Object.keys(BENCHMARK_THRESHOLDS).map((metric) => [metric, [0, 0, 0, 0, 0, 0, 0, 0]]));
  samples.key_to_commit_p95_ms = [51, 51, 51, 51, 51, 51, 51, 51];
  const report = buildReport({ candidateDigest: candidate, samples });
  assert.equal(report.diagnostic_status, 'failed');
  assert.equal(report.qualification_status, 'failed');
  assert.deepEqual(report.failures, ['ios:key_to_commit_p95_ms', 'android:key_to_commit_p95_ms']);
});

test('fixture diagnostic cannot be upgraded by changing only its status', () => {
  const report = buildReport({ candidateDigest: candidate });
  assert.equal(report.evidence.kind, 'deterministic_fixture');
  assert.notEqual(report.qualification_status, 'passed');
});
