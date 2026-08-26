# W5: confirmed private calendar write fixture

## Scope

W5 defines one external-write fixture: `calendar.event.create_private`. It creates a private event with `send_updates=none` and an empty attendee list. The only allowed grant scope is the exact `calendar.events.create_private` scope; the policy authority is R3 and requires an explicit per-execution confirmation. Undo is a separate, exact-resource `calendar.event.delete_own` operation.

The implementation is provider-neutral. `CalendarWriteAdapter` is an interface/fixture boundary; it does not perform OAuth, call a calendar API, store credentials, or provide production provider/KMS qualification.

## Invariants

- Plans are canonicalized and bound to a SHA-256 digest. The digest covers run, step, user, device, grant, connection epoch, operation, input, expiry, and confirmation requirement. A changed plan cannot reuse a confirmation.
- Confirmation is bound to plan/version digest, run, step, user, device, grant, and connection epoch. It must be explicit and valid at execution time; expiry cannot exceed plan expiry and future confirmations are rejected against the executor clock.
- Grant validation is fail-closed: active status, provider, owner, connection epoch, and the exact create-private scope are required. Provider text/provenance is data only and cannot authorize a plan or tool.
- Idempotency is scoped to `run_id + plan_digest + step_id + client_idempotency_key`. Concurrent identical requests share one in-flight execution; a client-key collision with another digest is rejected. A different run or step remains independent.
- Receipts contain only operation/status, opaque owner and provider references, digest, expiry, idempotency, and typed outcome metadata. Event title, body, attendees, and provider content are never projected into receipt/audit metadata.
- `unknown` results persist the executor-derived provider operation key and block blind retry. Reconciliation requires that exact key and binds a successful provider resource key before undo becomes available.
- Undo accepts only the exact successful receipt resource, owner, grant, connection epoch, run, digest, operation, and scope. It has bounded expiry and its idempotency key is consumed once; failed/unknown/double/mismatched undo cannot silently mutate another resource.

## Verification

Policy tests cover digest tampering, no-attendee/invitation rejection, R3 confirmation expiry/future/epoch binding, strict grant authority, and content-free receipt/undo invariants. Runtime tests cover replay, concurrent idempotency, digest collision, cross-owner/grant confusion, run/step isolation, unknown retry blocking and exact-key reconciliation, resource-confused/expired/double undo, and receipt minimization.

`corepack pnpm check` and `git diff --check` are the intended repository gates. This fixture has no live OAuth/provider/KMS evidence; production qualification remains `not_proven` until those external gates are independently exercised.
