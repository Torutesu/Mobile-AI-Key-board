# W8 beyond-parity foundation

W8 adds provider-neutral contracts and in-memory governance fixtures for verified Skill publishers, team policy packages, local suggestions, safety metadata, and moderation controls. It does not add live connectors, marketplace delivery, cryptographic key custody, external moderation, or production verification.

## Safety invariants

- Signed package and publisher identity digests are immutable. `self_attested` and fixture evidence can only produce `not_proven`; production verification requires an injected trusted protected-verifier evidence ID within the bounded freshness window.
- Team policies bind owner, team, version, epoch, exact operation-to-scope allowlists, risk ceiling, and confirmation. Install and upgrade require explicit consent. R4 operations and R4/R5 ceilings remain prohibited/not proven without separately injected external security evidence.
- Contextual suggestions contain only opaque IDs, source types, and lifecycle metadata. They have `local_only=true`, `network_required=false`, `auto_execute=false`, and `requires_user_action=true`; there is no raw text field and runtime execution is rejected.
- SK-006 safety metadata exposes publisher, requested operations/scopes, input types, risk, version, review date, installs, derived completion rate, confidence, and bounded category counts (`security`, `privacy`, `malware`, `quality`, `policy`). Category totals derive the reported count; resolved/critical counts cannot exceed that total. A zero-denominator record has no completion-rate evidence; samples are low/medium/high confidence only at the fixed thresholds, and review metadata is future/stale rejected. `fixture`/`not_proven` provenance cannot claim verified publisher status.
- Reports are content-free, canonical digests. Moderation receives the exact validated package, requires every referenced report to exist for that same skill/version/digest, protects moderation IDs and monotonic revisions, and requires a protected moderator for approval. Suggestion telemetry is parsed, owner/device-bound to an existing suggestion, chronological, and immutable/idempotent by event ID; one `shown` event must precede at most one terminal event (`accepted`, `dismissed`, or `expired`). Rollback requires an explicit immutable current-package activation before any rollback and rechecks the active package before idempotent replay. Team-policy installs/upgrades reject revoked package digests; revocations bind owner/team/epoch and monotonic revision, while upgrades keep the immutable `policy_id`.

## What remains not proven

The repository has no live publisher identity service, hardware-backed signing-key custody, external security review, moderation operator, durable governance store, marketplace, provider connector, or production evidence verifier. W8 tests are local fixtures and cannot qualify a production release. R4 connectors remain intentionally absent.

## Verification

W8 adversarial tests cover signed digest and evidence tampering, self-attested/stale/future verification and expiry, exact scopes and R4 rejection, silent/cross-owner policy upgrades, suggestion text injection and auto-execution, telemetry owner/device/chronology/content boundaries and duplicate-ID mutation, rate/confidence/sample/review manipulation, report-digest and moderation package/report binding, control revision/package/owner replay, and rollback version/epoch confusion.
