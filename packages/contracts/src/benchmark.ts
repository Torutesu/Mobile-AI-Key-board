import { createHash } from "node:crypto";
import { z } from "zod";
import { canonicalJson } from "./canonical.js";

const Digest = z.string().regex(/^sha256:[a-f0-9]{64}$/);

/** Metrics that can be measured without retaining typed text or output. */
export const BenchmarkMetric = z.enum([
  "key_to_commit_p50_ms",
  "key_to_commit_p95_ms",
  "keyboard_cold_open_p95_ms",
  "keyboard_warm_open_p95_ms",
  "long_press_false_activation_rate",
  "ordinary_tap_drop_rate"
]);
export type BenchmarkMetric = z.infer<typeof BenchmarkMetric>;

export const BenchmarkPlatform = z.enum(["ios", "android"]);
export type BenchmarkPlatform = z.infer<typeof BenchmarkPlatform>;
export const BenchmarkEnvironment = z.enum(["fixture", "simulator", "protected_device"]);
export type BenchmarkEnvironment = z.infer<typeof BenchmarkEnvironment>;
export const BenchmarkEvidenceKind = z.enum(["deterministic_fixture", "simulator", "protected_external"]);
export type BenchmarkEvidenceKind = z.infer<typeof BenchmarkEvidenceKind>;

export const BENCHMARK_THRESHOLDS = {
  key_to_commit_p50_ms: { maximum: 35, unit: "ms" },
  key_to_commit_p95_ms: { maximum: 50, unit: "ms" },
  keyboard_cold_open_p95_ms: { maximum: 400, unit: "ms" },
  keyboard_warm_open_p95_ms: { maximum: 150, unit: "ms" },
  long_press_false_activation_rate: { maximum: 0.001, unit: "ratio" },
  ordinary_tap_drop_rate: { maximum: 0.001, unit: "ratio" }
} as const satisfies Record<BenchmarkMetric, { maximum: number; unit: "ms" | "ratio" }>;

export const BenchmarkEvidence = z.object({
  kind: BenchmarkEvidenceKind,
  test_run_id: z.string().min(1).max(200),
  verifier_kind: z.enum(["self_attested", "protected_runner"]).optional(),
  verifier_id: z.string().min(1).max(200).optional(),
  artifact_digest: Digest.optional()
}).strict();
export type BenchmarkEvidence = z.infer<typeof BenchmarkEvidence>;

export const BenchmarkObservation = z.object({
  metric: BenchmarkMetric,
  platform: BenchmarkPlatform,
  value: z.number().finite().nonnegative().max(60_000),
  unit: z.enum(["ms", "ratio"]),
  sample_count: z.number().int().positive().max(10_000_000),
  candidate_digest: Digest,
  environment: BenchmarkEnvironment,
  evidence: BenchmarkEvidence
}).strict().superRefine((value, context) => {
  const expectedUnit = BENCHMARK_THRESHOLDS[value.metric].unit;
  if (value.unit !== expectedUnit) context.addIssue({ code: z.ZodIssueCode.custom, path: ["unit"], message: `metric ${value.metric} requires ${expectedUnit}` });
  if (value.environment === "protected_device" && value.evidence.kind !== "protected_external") context.addIssue({ code: z.ZodIssueCode.custom, path: ["evidence", "kind"], message: "protected device measurements require protected external evidence" });
  if (value.evidence.kind === "protected_external" && (value.evidence.verifier_kind !== "protected_runner" || value.evidence.verifier_id === undefined || value.evidence.artifact_digest === undefined)) context.addIssue({ code: z.ZodIssueCode.custom, path: ["evidence"], message: "protected evidence requires protected runner, verifier, and artifact binding" });
});
export type BenchmarkObservation = z.infer<typeof BenchmarkObservation>;

export const BenchmarkReport = z.object({
  schema_version: z.literal("mobile-ai-keyboard.performance-benchmark.v1"),
  candidate_digest: Digest,
  environment: BenchmarkEnvironment,
  diagnostic_status: z.enum(["passed", "failed"]),
  qualification_status: z.enum(["passed", "not_proven", "failed"]),
  observations: z.array(BenchmarkObservation).max(100),
  evidence: BenchmarkEvidence,
  report_digest: Digest
}).strict().superRefine((value, context) => {
  if (value.observations.some((observation) => observation.candidate_digest !== value.candidate_digest)) context.addIssue({ code: z.ZodIssueCode.custom, path: ["observations"], message: "every observation must bind to the report candidate" });
  if (value.observations.some((observation) => observation.environment !== value.environment)) context.addIssue({ code: z.ZodIssueCode.custom, path: ["observations"], message: "every observation must bind to the report environment" });
  if (value.observations.some((observation) => observation.evidence.kind !== value.evidence.kind)) context.addIssue({ code: z.ZodIssueCode.custom, path: ["observations"], message: "every observation must bind to the report evidence kind" });
  const observationKeys = value.observations.map((observation) => `${observation.platform}:${observation.metric}`);
  if (new Set(observationKeys).size !== observationKeys.length) context.addIssue({ code: z.ZodIssueCode.custom, path: ["observations"], message: "duplicate platform/metric observations are not allowed" });
  if (value.environment === "protected_device" && value.observations.some((observation) => observation.evidence.kind !== "protected_external")) context.addIssue({ code: z.ZodIssueCode.custom, path: ["observations"], message: "protected reports cannot contain fixture or simulator observations" });
  if (value.environment === "fixture" || value.environment === "simulator") {
    if (value.qualification_status === "passed") context.addIssue({ code: z.ZodIssueCode.custom, path: ["qualification_status"], message: "fixture and simulator benchmarks cannot qualify a release" });
    if (!["deterministic_fixture", "simulator"].includes(value.evidence.kind)) context.addIssue({ code: z.ZodIssueCode.custom, path: ["evidence"], message: "local benchmark evidence kind is invalid" });
  }
  if (value.qualification_status === "passed" && (value.environment !== "protected_device" || value.evidence.kind !== "protected_external" || value.evidence.verifier_kind !== "protected_runner" || value.evidence.verifier_id === undefined || value.evidence.artifact_digest === undefined)) context.addIssue({ code: z.ZodIssueCode.custom, path: ["qualification_status"], message: "qualification pass requires protected device evidence" });
});
export type BenchmarkReport = z.infer<typeof BenchmarkReport>;

export type BenchmarkDecision = {
  candidate_digest: string;
  diagnostic_status: "passed" | "failed";
  qualification_status: "passed" | "not_proven" | "failed";
  failed_metrics: string[];
  missing_metrics: string[];
};

/** Nearest-rank percentile; deterministic and independent of runtime timing. */
export function benchmarkPercentile(values: readonly number[], percentile: number): number {
  if (values.length === 0 || percentile < 0 || percentile > 1) throw new Error("percentile input is invalid");
  const ordered = [...values].sort((left, right) => left - right);
  return ordered[Math.max(0, Math.ceil(percentile * ordered.length) - 1)]!;
}

export function benchmarkReportDigest(report: Omit<BenchmarkReport, "report_digest">): string {
  return `sha256:${createHash("sha256").update(canonicalJson(report), "utf8").digest("hex")}`;
}

export function evaluateBenchmarkReport(value: unknown): BenchmarkDecision {
  const report = BenchmarkReport.parse(value);
  const unsigned = { ...report } as Omit<BenchmarkReport, "report_digest">;
  delete (unsigned as Partial<BenchmarkReport>).report_digest;
  if (benchmarkReportDigest(unsigned) !== report.report_digest) throw new Error("benchmark report digest mismatch");
  const expected = ["ios", "android"].flatMap((platform) => Object.keys(BENCHMARK_THRESHOLDS).map((metric) => `${platform}:${metric}`));
  const observed = new Map(report.observations.map((observation) => [`${observation.platform}:${observation.metric}`, observation]));
  const missing_metrics = expected.filter((metric) => !observed.has(metric));
  const failed_metrics = [...observed.entries()].filter(([key, observation]) => observation.value > BENCHMARK_THRESHOLDS[observation.metric].maximum).map(([key]) => key);
  const diagnostic_status = missing_metrics.length === 0 && failed_metrics.length === 0 ? "passed" : "failed";
  const qualification_status = diagnostic_status === "failed" ? "failed" : report.environment === "protected_device" ? "passed" : "not_proven";
  return { candidate_digest: report.candidate_digest, diagnostic_status, qualification_status, failed_metrics, missing_metrics };
}
