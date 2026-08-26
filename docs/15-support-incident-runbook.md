# W7 support and incident runbook

## Operating boundary

This runbook covers the provider-neutral W7 fixture and the future production service. It does not turn simulator, JVM, mock-provider, or self-attested evidence into production qualification. Until an on-call owner, support address, deployed environment, signed candidate, and independent device/provider evidence are recorded, operational readiness is `not_proven`.

Ordinary typing is the protected fallback. A response may disable a Skill version, tool operation, provider, or model, but must not disable local ordinary typing.

## Required incident record

Record only content-free fields:

- incident ID, severity, opened/updated/resolved timestamps;
- reporter channel and authenticated operator ID;
- affected candidate SHA/artifact digest/environment;
- affected component identifiers and kill-switch revision;
- first/last observed time, bounded event counts, and typed failure class;
- rollback target and verification run IDs;
- user-notification status and regulatory/privacy assessment status.

Never paste typed text, selected content, OAuth tokens, provider payloads, prompts, receipts containing content, or credentials into tickets, chat, analytics, or crash reports.

## Severity and first response

| Severity | Examples | First response |
| --- | --- | --- |
| SEV-0 | secret/content leakage, cross-user authority, unconfirmed external write | freeze affected release and external authority; preserve ordinary typing; page security/privacy owners |
| SEV-1 | duplicate write, bad Skill version, provider-wide unsafe output, deletion failure | disable exact Skill/tool/provider/model; block promotion; begin reconciliation |
| SEV-2 | sustained crash/performance budget breach, broken migration, major workflow outage | stop rollout or roll back to bound target; publish support status |
| SEV-3 | isolated UI defect or recoverable fixture failure | triage into normal release workflow; do not weaken gates |

The production paging target, security owner, privacy owner, and support address are currently `not_configured`; a public rollout is blocked until they are externally provisioned and recorded outside the repository.

## Scenario playbooks

### Token or credential compromise

1. Disable the exact provider/tool authority and revoke affected session/credential families.
2. Rotate broker/KMS material through the external secret-management process; never commit replacement secrets.
3. Determine owner/environment/epoch scope from content-free audit metadata.
4. Re-run revocation, replay, and connection-epoch checks before re-enablement.

### Accidental logging or content disclosure

1. Stop the emitting component and preserve ordinary local typing.
2. Restrict access to the affected log store and apply the approved deletion/legal-hold decision.
3. Record field names and counts, not leaked values, in the incident record.
4. Re-enable only after canary text is absent from network, backend, analytics, and crash evidence.

### Bad or malicious Skill

1. Disable the exact immutable Skill version; do not mutate it in place.
2. Keep other versions and ordinary typing available unless separately implicated.
3. Revoke active shares/bindings and show a typed unavailable reason.
4. Require a new signed version, static/runtime policy evidence, migration plan, and explicit rebind.

### Duplicate or unknown external action

1. Disable blind retry for the affected operation key.
2. Reconcile only with the exact provider operation key/resource binding.
3. Never infer success from a timeout. Resolve to succeeded, failed, or safe manual action.
4. Audit idempotency namespace, connection epoch, and receipt sequence before reopening.

### Provider or model outage

1. Disable the exact provider/model route while retaining local typing and local fixtures.
2. Surface an honest unavailable/partial state; do not silently widen to another destination.
3. A destination change requires a new disclosure and, where required, confirmation.

### Migration or release regression

1. Halt rollout and bind the incident to candidate/source/artifact/schema/test identifiers.
2. Verify the declared rollback target and backward-compatibility constraints.
3. Execute idempotent rollback; reject cross-environment or unrelated-candidate targets.
4. Re-run clean-install, upgrade, rollback, deletion, receipt, and keyboard isolation gates.

## Recovery and closure gates

- exact affected authority is disabled or proven safe;
- source candidate and executed artifacts are digest-bound;
- content-free evidence shows no cross-owner, replay, or silent-transmission path;
- rollback/forward migration is independently repeatable;
- user communication and privacy/regulatory decisions are recorded;
- regression tests and the applicable physical-device/provider evidence are attached;
- post-incident actions have owners and deadlines outside this fixture repository.
