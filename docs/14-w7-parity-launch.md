# W7 parity / launch foundation

## Scope

W7 adds provider-neutral contracts and an in-memory fixture for parity and launch qualification. It does not claim a live iOS/Android release, protected CI runner, external provider, KMS, crash service, or production migration.

## Invariants

- A `ReleaseCandidate` is bound to a lowercase source commit SHA, artifact digest, schema version, privacy declaration digest, test-run IDs, owner, release epoch, and canonical candidate digest. Tampering with any bound field invalidates the candidate.
- `QualificationEvidence` must bind exactly to the candidate and its complete test-run set. Fixture, simulator, mock, self-attested, and untrusted evidence evaluate to typed `not_proven`; only an injected trusted protected-runner identity can produce a production `passed` decision.
- Kill switches are scoped by owner, release epoch, target kind/identifier, and monotonic revision. Incidents are append-only metadata and contain no captured text. Ordinary typing is outside the kill-switch authority ceiling.
- Beta migration requests are owner/epoch/environment/candidate bound. Forward migration requires a strictly newer schema version; rollback requires the exact recorded candidate ID and digest. Request IDs are idempotent, while reuse with a changed payload is rejected.
- Performance and crash metrics are strict, content-free schemas bound to a candidate test-run ID and protected-runner attestation. All five quality budgets are required; fixture/simulator, self-attested, untrusted-run, malformed, or content-bearing records cannot qualify production.
- Release qualification requires all five metrics for both iOS and Android. Results identify the platform in `missing_metrics` / `failed_metrics`; one platform cannot be hidden by map overwrite or ordering.
- The release evaluator accepts trusted test-run IDs only by dependency injection, requires its observed run set to equal the candidate run set, and rejects impossible cold P50/P95 ordering. With no injected trusted run set, production quality remains `not_proven`.
- Caller-selected `QualityBudget` values are diagnostic-only and always `not_proven`. The release evaluator owns the fixed ceilings from `docs/06-quality-release.md`: cold p50 250 ms, cold p95 400 ms, warm open p95 150 ms, key-to-commit p95 50 ms, crash-free beta 99.8% and broad release 99.95%.
- A production forward migration requires exact candidate-bound `QualificationDecision(status=passed, reason=protected_evidence)` and a fixed-policy `ReleaseQualityDecision(status=passed)`, and both canonical decisions must be injected into the migration manager by a trusted authority. Caller-constructed pass-shaped objects fail closed. Protected evidence is bounded to a seven-day window and cannot be future-dated.

## Fixture usage

`QualificationGate`, `KillSwitchRegistry`, and `BetaMigrationManager` are deliberately in-memory. They are useful for contract and adversarial tests only. Durable append-only storage, authenticated protected runners, deployment attestation, real crash/performance collection, rollback orchestration, and external release evidence remain unimplemented and must be qualified separately.

## Verification

W7 tests cover candidate/digest and evidence/test-run tampering, self-attested evidence, kill-switch stale revision/owner/epoch and ordinary-typing attempts, migration idempotency and request collision, cross-environment and rollback target confusion, malformed telemetry content, and quality-budget not-proven behavior.
