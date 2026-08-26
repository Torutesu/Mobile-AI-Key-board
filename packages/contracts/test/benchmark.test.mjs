import test from 'node:test';
import assert from 'node:assert/strict';
import {
  BENCHMARK_THRESHOLDS,
  BenchmarkReport,
  benchmarkPercentile,
  benchmarkReportDigest,
  evaluateBenchmarkReport,
} from '@mobile-ai-keyboard/contracts';

const candidate = `sha256:${'a'.repeat(64)}`;
const metrics = Object.entries(BENCHMARK_THRESHOLDS);
function observation(metric, platform = 'ios', overrides = {}) {
  const threshold = BENCHMARK_THRESHOLDS[metric];
  return {
    metric, platform, value: Math.min(1, threshold.maximum / 2), unit: threshold.unit,
    sample_count: 8, candidate_digest: candidate, environment: 'fixture',
    evidence: { kind: 'deterministic_fixture', test_run_id: 'fixture_benchmark_v1' }, ...overrides,
  };
}
function report(overrides = {}) {
  const observations = metrics.flatMap(([metric]) => [observation(metric, 'ios'), observation(metric, 'android')]);
  const unsigned = {
    schema_version: 'mobile-ai-keyboard.performance-benchmark.v1', candidate_digest: candidate,
    environment: 'fixture', diagnostic_status: 'passed', qualification_status: 'not_proven', observations,
    evidence: { kind: 'deterministic_fixture', test_run_id: 'fixture_benchmark_v1' }, ...overrides,
  };
  return { ...unsigned, report_digest: benchmarkReportDigest(unsigned) };
}

test('uses deterministic nearest-rank percentile and strict 0.1% thresholds', () => {
  assert.equal(benchmarkPercentile([4, 1, 3, 2], 0.95), 4);
  assert.equal(BENCHMARK_THRESHOLDS.long_press_false_activation_rate.maximum, 0.001);
  assert.equal(BENCHMARK_THRESHOLDS.ordinary_tap_drop_rate.maximum, 0.001);
});

test('fixture benchmark can pass diagnostics but remains not_proven', () => {
  const value = report();
  assert.equal(evaluateBenchmarkReport(value).diagnostic_status, 'passed');
  assert.equal(evaluateBenchmarkReport(value).qualification_status, 'not_proven');
});

test('rejects report digest tampering and candidate/platform/environment drift', () => {
  const value = report();
  assert.throws(() => evaluateBenchmarkReport({ ...value, report_digest: `sha256:${'b'.repeat(64)}` }), /digest mismatch/);
  assert.throws(() => evaluateBenchmarkReport({ ...report({ observations: report().observations.map((item, index) => index === 0 ? { ...item, candidate_digest: `sha256:${'c'.repeat(64)}` } : item) }) }), /report candidate/);
  assert.throws(() => evaluateBenchmarkReport({ ...report({ observations: report().observations.map((item, index) => index === 0 ? { ...item, environment: 'simulator' } : item) }) }), /report environment/);
});

test('rejects duplicate observations and fixture spoofing as protected proof', () => {
  const value = report();
  assert.throws(() => evaluateBenchmarkReport(report({ observations: [...value.observations, value.observations[0]] })), /duplicate platform\/metric/);
  assert.throws(() => evaluateBenchmarkReport(report({ environment: 'protected_device', qualification_status: 'passed', evidence: { kind: 'protected_external', test_run_id: 'run-protected', verifier_kind: 'protected_runner', verifier_id: 'runner-1', artifact_digest: `sha256:${'d'.repeat(64)}` } })), /observations/);
});

test('a diagnostic threshold regression is reported as failed without becoming a production pass', () => {
  const value = report({ observations: report().observations.map((item, index) => index === 0 ? { ...item, value: 999 } : item), diagnostic_status: 'failed', qualification_status: 'failed' });
  const decision = evaluateBenchmarkReport(value);
  assert.equal(decision.diagnostic_status, 'failed');
  assert.equal(decision.qualification_status, 'failed');
  assert.deepEqual(decision.failed_metrics, ['ios:key_to_commit_p50_ms']);
});
