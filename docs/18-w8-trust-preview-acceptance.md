# W8 Trust Preview acceptance baseline

## Purpose

W8 may improve discovery and decision quality, but it does not grant new execution authority. Trust Preview, contextual suggestions, team policy, and catalog metadata are advisory inputs to the same typed Skill, disclosure, confirmation, and runtime-policy boundaries already established in W2-W7.

The current implementation remains a local/provider-neutral fixture. A local badge, fixture signature, simulator result, install count, or completion percentage must never be rendered as production verification.

## Trust Preview

Before install, bind, upgrade, or run, show the exact immutable Skill version and digest plus:

- publisher label and verification provenance;
- requested connector operations and scopes;
- declared input-source types and retention;
- risk class, confirmation policy, effects, reversibility, and unavailable operations;
- last independent review time and whether the evidence is current;
- installs, completion numerator/denominator, derived completion rate, and issue counts;
- team-policy decision, policy version/epoch, and the specific blocking rule if denied;
- revocation, report, rollback, and explicit-upgrade state.

Unknown, missing, stale, fixture, self-attested, or candidate-mismatched fields display `not_proven`. The UI must not collapse them into a green verified state.

## Metric integrity

- Completion rate is derived from bounded integer completed/attempted counts; callers cannot submit an independent rate.
- Attempts must be at least completions. Zero attempts produce no rate, not 100%.
- Fixture and self-attested counts may demonstrate layout only and cannot establish catalog quality.
- Low sample sizes remain visibly low-confidence. Installs are never treated as proof of safety.
- Reports are categorized counts without report text, typed content, recipients, URLs, provider payloads, or reporter identity in public metadata.
- Review and metric evidence is immutable-version and publisher bound, freshness checked, and rejected across owner/team/release epochs.

## Local contextual suggestions

Suggestions may be derived on-device from coarse, typed signals such as field capability, selected workflow pack, locale, and whether bounded text is present. They must:

- contain no captured text, output text, contact, URL, location, document title, host-app fingerprint, or clipboard value in their stored or telemetry representation;
- remain deterministic and local-only in this fixture;
- disappear in secure/sensitive fields and when the editor boundary changes;
- require explicit user invocation before Capture Review;
- never insert, replace, send, call a tool, enable a connector, install a Skill, or acknowledge disclosure by themselves;
- preserve ordinary typing when suggestions are unavailable, revoked, denied, or malformed.

## Team policy

A team policy package is immutable and bound to team, owner, version, epoch, canonical digest, risk ceiling, allowed operations/scopes, confirmation floor, and publisher requirements. Installation and upgrade are explicit. Content, provider output, catalog rank, or publisher popularity cannot widen it.

Policy evaluation uses the intersection of user authority, team policy, Skill declaration, connector grant, and server runtime policy. Any disagreement fails closed and reports the exact typed reason. Revocation disables the exact policy/package or Skill version without disabling ordinary typing.

## R4 boundary

No W8 fixture may send an email, message, invite, post, or other representational communication. An R4 connector remains blocked until all of the following are independently present and exact-candidate bound:

- separately approved operation and scope contract;
- recipient/target and generated-content confirmation UX;
- external security and privacy review;
- physical-device and real-provider evidence;
- idempotency, unknown-outcome reconciliation, receipts, revocation, and kill-switch evidence;
- signed release artifact, protected runner, live support/incident ownership, and rollback evidence.

Absent evidence is `not_proven`; it is not a request to downgrade risk or reuse R3 approval.

## Adversarial acceptance cases

- forged verified badge or caller-provided completion rate;
- swapped publisher, Skill version, digest, team, epoch, or review evidence;
- stale review, revoked publisher/package, silent upgrade, or rollback to an unrecorded version;
- catalog/provider content requesting broader tools, scopes, inputs, or risk;
- suggestion state carrying raw content or surviving secure/editor boundaries;
- suggestion tap directly applying text or executing a tool;
- issue metadata containing report text or user content;
- R4 operation disguised as read, draft, local insertion, or reversible write;
- kill switch targeting ordinary typing.

All cases must fail closed in shared policy/runtime tests and in the applicable native reducer tests. Physical-device, public catalog, production signature, real team administration, and R4 provider behavior remain separate external qualification gates.
