# W4 Read-only Connections

## Scope

W4はGoogle Calendar availability read、Notion page search、Maps place searchだけをprovider-neutral fixtureとして定義する。write operation、OAuth実交換、provider API、refresh token、KMSは実装・qualification対象外で、read-only authority ceilingを超えた入力はfail-closedに拒否する。

## Contracts

- OAuth stateはuser/device/session、provider、redirect URI、requested scopes、S256 PKCE challenge、nonce、expiryへ束縛する。
- Connection grantはopaque grant ID、provider、incremental scopes、credential reference、status、user/device ownerだけを保持する。raw secretはcontract/storeに保存しない。
- Calendar/Notion/Maps queryはoperation、grant ID、page size/cursorをtyped化し、各providerのread scopeのみを許可する。
- Resultsはsource reference、grant、provider、fetched/freshness timestamps、`untrusted_provider_content` taintを必須とする。本文はprovider dataでありauthorityではない。
- Calendarのendはstartより後、sourceのfreshness expiryはfetch時刻以後でなければならない。
- Connector outcomeはsucceeded / partial / failed / unknownとtyped failureへ投影する。

## Lifecycle and policy invariants

1. OAuth stateは一度だけconsumeできる。state欠落、expiry、nonce/PKCE mismatch、callback replayを拒否する。
2. grantのscope wideningはexplicit incremental consentなしに実行できない。provider write scopeはallowlistに存在しない。
3. grant、query、user/device ownerが一致しない場合は実行前に拒否する。disconnect/revoke後のreadは許可しない。
4. rebindは同一userのauthenticated ownerだけが実行でき、別userのgrantを横取りできない。
   既存active grantを別deviceから暗黙に更新することも拒否し、明示的rebindを要求する。
5. paginationはpage count/item count/page sizeにhard boundを持ち、provider tokenが残っていてもbudget超過で停止する。
6. provider本文やtainted metadataにoperation、tools、scopes、risk、authorizationが混入しても、tool/plan命令へ昇格させない。
7. source-linked result metadataはreceipt projectionにstep/status/provider/resource referenceだけを残し、本文・prompt・provider payloadを監査へ流さない。
8. encrypted credential storeはinterface boundaryのみ。W4のNoop実装はsecretを保持せず、未設定時はtyped errorを返す。
9. revoked grantだけが`revoked_at`を持ち、revoked grantは必ず`revoked_at`を持つ。native fixtureのscope IDとplan digestはshared contractへ一致させる。
10. succeededだけでなくpartial outcomeも同一のsource provenance・freshness・provider-taint検証を通る。

## Tests

- OAuth state/PKCE binding、expiry、replay
- scope widening、provider scope ceiling
- cross-user grant、grant/query mismatch、rebind confusion
- disconnect/revoke lifecycle
- read-only write operation contamination
- provider taint escalation rejection
- source provenance validation
- reversed calendar/freshness timestamps、caller-owned OAuth state mutation
- pagination bound
- invalid native connection transitions、disconnect cleanup、query/page-size preservation、result-selection binding
- typed unknown/partial connector outcomes

## 未証明ゲート

- 実OAuth authorization server、production redirect URI allowlist、callback issuer/account検証、refresh/revoke
- Google Calendar / Notion / Maps APIの実scope・quota・pagination・freshness
- KMS/HSMでのcredential envelope encryption、rotation、zeroization
- durable DBのunique constraint、transaction、multi-instance OAuth replay race
- provider response prompt-injection red-team qualification
- production receipt/telemetry data pathでの本文非保存証明
