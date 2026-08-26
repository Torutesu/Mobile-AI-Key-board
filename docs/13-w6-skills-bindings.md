# W6: private Skills, bindings, and quota controls

## Implemented slice

The shared TypeScript contracts now model a typed Skill definition, draft/revision, immutable private version, device binding, private share, quota usage, and cost reservation. Skill definitions require a name, description, trigger, typed inputs/sources, exact tool declarations, risk ceiling, confirmation policy, output, retention, instruction, and at least one user-visible fixture. A typed `SkillTestRun` must bind draft ID/revision/contract digest, cover every fixture exactly once, carry a digest over each fixture's name/input/expected object, and provide typed actual fields that policy compares against every expected field; there is no caller-provided `passed` switch.

`SkillRegistry` implements draft → validated → tested → private-published lifecycle. A published version stores an immutable contract digest and cannot be silently replaced. `SkillBindingRegistry` binds the exact version/digest and owner/device, rejects ordinary typing shortcuts, duplicate triggers, accessibility order/label collisions, and cross-Skill or cross-owner upgrades. Upgrades require an explicit flag and remain owner/Skill-bound.

Private sharing is constrained to `visibility=private` and `public_publish=false`; recipient lists are unique, owner/version/digest-bound, expiry-bounded, and share IDs are idempotent/immutable. Public publishing is a typed fail-closed policy error.

`QuotaLedger` reserves run, input, output, and estimated cost budgets atomically against existing usage. Reservations are owner/period-bound, require a period-valid non-future reservation timestamp, and use idempotent request IDs; changed payloads, exhausted limits, owner confusion, and invalid state transitions fail closed.

## Safety invariants

- Canonical `sha256` digest covers the complete Skill definition. Version/binding/share records refer to it as `contract_digest`/`skill_digest`; changing any material definition field creates a new digest.
- The operation catalog requires exact operation-to-scope and operation-to-side-effect pairs. Unknown operations, destructive/external communication tools, and calendar undo are outside the W6 Skill authority ceiling.
- R2 read-only and R3 write Skills require policy confirmation. Static validation scans instructions, descriptions, triggers, output templates, and fixture data for prompt-injection markers; structured schemas reject unknown fields and duplicate input/source declarations.
- Provider/tool content is data and cannot expand Skill tools, scopes, risk, or bindings.

## Verification and unproven gates

Policy tests cover exact schema/effect/scope, R2 confirmation, fixture requirement, static injection, duplicate inputs/sources, and digest behavior. Runtime tests cover lifecycle/version immutability, typed fixture-run tamper/stale/missing/duplicate/expected-mismatch rejection, explicit upgrades, typing/accessibility/existing binding conflicts, cross-owner/cross-Skill confusion, private-share binding/expiry/idempotency/public rejection, and quota reservation usage/cost/period/idempotency/commit/release. The in-memory fixture runner validates the submitted typed actual against the declared expected contract; it does not independently qualify an LLM, provider, or production execution environment.

`corepack pnpm check` is the repository gate. This is an in-memory/provider-neutral fixture: persistent DB transactions, signed Skill packages, moderation/reporting/kill switches, public marketplace controls, external billing/provider cost reconciliation, and production accessibility/physical-device qualification remain `not_proven`.
