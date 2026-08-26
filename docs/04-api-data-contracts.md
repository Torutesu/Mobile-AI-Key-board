# API and Data Contracts

## 1. API conventions

- Base path: `/v1`
- JSON over TLS.
- UTC timestamps in RFC 3339; user timezone is an explicit IANA identifier.
- IDs are opaque UUIDs or provider-scoped opaque strings.
- All mutating requests require `Idempotency-Key`.
- Responses include `request_id` and a typed `status`.
- Client-provided risk, scope, user ID, and success fields are ignored or rejected.

## 2. Core endpoints

### Session and device

- `POST /v1/auth/exchange`
- `POST /v1/devices/register`
- `POST /v1/devices/{id}/revoke`
- `POST /v1/sessions/revoke-all`

### Skills

- `GET /v1/skills`
- `POST /v1/skills/drafts`
- `POST /v1/skills/drafts/{id}/validate`
- `POST /v1/skills/drafts/{id}/test`
- `POST /v1/skills/drafts/{id}/publish-private`
- `POST /v1/skills/{id}/versions`
- `POST /v1/skill-bindings`

### Connections

- `GET /v1/connections`
- `POST /v1/connections/{provider}/authorize`
- `POST /v1/connections/{id}/disconnect`
- `POST /v1/connections/{id}/rebind`

### Runs

- `POST /v1/runs`
- `POST /v1/runs/{id}/inputs`
- `GET /v1/runs/{id}`
- `POST /v1/runs/{id}/confirm`
- `POST /v1/runs/{id}/cancel`
- `GET /v1/runs/{id}/events`
- `GET /v1/receipts/{id}`
- `POST /v1/receipts/{id}/undo`

## 3. Create-run example

Request:

```json
{
  "skill": { "id": "schedule_from_text", "version": 1 },
  "client": {
    "platform": "ios",
    "app_version": "0.1.0",
    "keyboard_version": "0.1.0",
    "locale": "ja-JP",
    "timezone": "Asia/Tokyo"
  },
  "available_input_sources": ["command", "selection", "clipboard"],
  "target_capabilities": ["insert_text", "replace_selection"]
}
```

Response:

```json
{
  "request_id": "req_...",
  "run_id": "run_...",
  "status": "awaiting_input_disclosure",
  "disclosure": {
    "accepted_sources": ["command", "selection"],
    "rejected_sources": ["clipboard"],
    "max_characters": { "command": 500, "selection": 4000 },
    "destinations": ["service", "model_provider", "google_calendar"],
    "retention_class": "transient_content",
    "external_access": ["calendar.availability.read"]
  },
  "expires_at": "2026-08-26T12:01:00Z"
}
```

## 4. Submit-input example

```json
{
  "disclosure_acknowledgement": "sha256:...",
  "inputs": [
    { "source": "command", "text": "この日程で空いているか確認" },
    { "source": "selection", "text": "来週火曜15時から30分どうですか？" }
  ],
  "user_locks": ["来週火曜", "15時", "30分"]
}
```

Content is accepted only after the acknowledgement digest matches the server-issued disclosure and the run is unexpired.

## 5. Action plan

```json
{
  "plan_id": "plan_...",
  "plan_version": 1,
  "run_id": "run_...",
  "risk_class": "R3",
  "summary": "空き時間を確認し、非公開の予定を作成します",
  "resolved_facts": {
    "start": "2026-09-01T15:00:00+09:00",
    "end": "2026-09-01T15:30:00+09:00",
    "timezone": "Asia/Tokyo"
  },
  "steps": [
    {
      "step_id": "step_1",
      "operation": "calendar.availability.read",
      "risk_class": "R2",
      "arguments": { "start": "...", "end": "..." },
      "side_effect": "none"
    },
    {
      "step_id": "step_2",
      "operation": "calendar.event.create_private",
      "risk_class": "R3",
      "arguments": {
        "title": "打ち合わせ",
        "start": "...",
        "end": "...",
        "attendees": []
      },
      "side_effect": "creates_private_event",
      "reversible": true
    }
  ],
  "output": { "type": "insert_text", "template": "..." },
  "confirmation": {
    "required": true,
    "reason": "external_write",
    "expires_at": "..."
  },
  "canonical_digest": "sha256:..."
}
```

The displayed plan is rendered from this contract, not separate model prose.

## 6. Confirmation

```json
{
  "plan_id": "plan_...",
  "canonical_digest": "sha256:...",
  "confirmation_method": "explicit_tap",
  "client_confirmed_at": "..."
}
```

Server checks:

- authenticated user/device owns the run;
- plan is current and unexpired;
- digest matches canonical server representation;
- input, connection, scope, and policy epochs are unchanged;
- idempotency key has not been used for a different payload.

## 7. Receipt states

`pending | executing | succeeded | partial | failed | unknown | undo_pending | undone | undo_failed`

Receipt projection:

```json
{
  "receipt_id": "rcpt_...",
  "run_id": "run_...",
  "status": "succeeded",
  "summary": "非公開の予定を作成しました",
  "steps": [
    {
      "step_id": "step_2",
      "status": "succeeded",
      "provider": "google_calendar",
      "provider_resource_ref": "encrypted-or-opaque",
      "completed_at": "..."
    }
  ],
  "result": {
    "insert_text": "9月1日（火）15:00で大丈夫です。30分で予定を入れました。",
    "resource_link": "https://calendar.google.com/..."
  },
  "undo": { "available": true, "expires_at": "..." }
}
```

## 8. Data entities

| Entity | Important fields | Retention |
|---|---|---|
| User | ID, auth identities, locale, policy version | account lifetime |
| Device | ID, platform, public key, status, last seen | account + 30 days |
| Skill | owner, visibility, current version | until deletion/legal hold |
| SkillVersion | immutable schema, tool allowlist, digest | retained while referenced |
| Binding | device/user, trigger, Skill version | until removed |
| Connection | provider, account label, scopes, status, credential ref | until disconnect |
| Run | Skill version, status, risk, timestamps, digests | 30 days default |
| RunContent | encrypted input/output when strictly required | transient; <= 24 hours default |
| Confirmation | plan digest, method, timestamp, policy epoch | 1 year security audit |
| Receipt | operation metadata and safe summary | 90 days user-configurable |
| AuditEvent | identity, action, object, outcome, request ID | 1 year |

Raw keyboard text that was not explicitly submitted has no server entity.

## 9. Skill schema minimum

```json
{
  "schema_version": 1,
  "name": "日程調整",
  "inputs": [
    { "name": "proposal", "type": "text", "sources": ["selection", "clipboard"], "required": true }
  ],
  "tools": [
    { "operation": "calendar.availability.read" },
    { "operation": "calendar.event.create_private" }
  ],
  "risk_ceiling": "R3",
  "confirmation": "policy_required",
  "output": { "type": "insert_text" },
  "retention": "transient_content",
  "tests": [
    {
      "name": "relative Japanese date",
      "input_fixture": "来週火曜15時から30分",
      "expected": { "requires_absolute_date_preview": true, "attendees": [] }
    }
  ]
}
```

## 10. Error taxonomy

- `AUTH_*`: expired, revoked, wrong device.
- `DISCLOSURE_*`: unacknowledged, changed, oversized input.
- `POLICY_*`: prohibited operation, scope widening, risk mismatch.
- `CONNECTION_*`: missing, expired, insufficient scope, provider denied.
- `PLAN_*`: ambiguous, stale, validation failed.
- `EXECUTION_*`: timeout, provider rejected, partial, unknown outcome.
- `TARGET_*`: field changed, selection lost, insert unsupported.
- `QUOTA_*`: user, provider, or abuse limit.

Errors include a safe user message and machine recovery action, never raw provider bodies or stack traces.
