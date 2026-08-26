# W3 Identity, Devices, Sessions, Receipts, and Retention

## Scope and honesty boundary

W3のshared coreはprovider-neutralな契約と、敵対ケースを検証できるin-memory実装を提供する。`DeviceRegistry`はchallenge/proof verifierを注入する境界であり、`IdentityService`は外部IdP・durable DB・KMS・本番token verifierを内包しない。従って、現時点でproduction-qualifiedなidentity/security基盤とは主張しない。

## Identity and device contract

- User、device、challenge、session、receipt、audit IDはopaque prefix付きIDで、内部連番やemailをIDに使わない。
- device registrationは32-byte Ed25519 public key、64-byte proof signature、server challenge ID/nonce、platform/versionをtyped contractで要求する。verifierにはchallenge/user/device/platform/key/app versionを含むcanonical payloadだけを渡し、key substitutionや別deviceへのproof転用を防ぐ境界を固定する。
- challengeはuserに束縛され、期限切れ・nonce不一致・proof拒否・再利用をfail-closedにする。
- public keyを保存するが、private key・raw access token・proof materialをaudit/receiptへコピーしない。

## Session family

`SessionManager`はraw tokenではなくSHA-256 token hashをrecordに保存する。familyごとにcurrent sessionとgenerationを管理し、rotate時は旧sessionをrotatedにして新tokenを発行する。stale tokenのreplayはfamily全体をrevokedにするため、競合・replayを黙って成功扱いしない。device revoke時はそのdeviceのactive familyを失効させる。

## Run ownership and plan binding

`PlanBindingStore`はrunごとにuser/device、plan id/version/digest、policy epochを一度だけ束縛する。同一bindingの再送は同じbindingを返すが、plan version/digestまたはownerが異なる再送はconflict、他ownerのgetは拒否する。これはAPI/workerに渡すauthenticated owner境界のshared primitiveである。

## Receipts and audit

Receiptはsequence 1から始まるappend-only event。sequence gap、順序逆転、全receipt横断のevent replayを拒否する。同一receiptのrun/user/device/plan digest/request IDは最初のeventから不変で、API境界でもowner-bound plan bindingとの一致を要求する。receipt/audit schemaはstep operation、status、provider resource reference、plan digest、request ID、actor/object IDs、timestampsだけを保持し、本文・clipboard・selection・prompt・provider payloadを持たない。

## Retention and deletion

`RetentionRule`はrecord type、retention class、max age、purge strategyを明示する。scheduled expiryはdue一覧として取り出し、legal holdは自動purge対象外。account deletionはactive → requested → grace_period → deleting → deleted（またはfailed）という明示的なstate machineで、許可されないskipやdeletedへの直接遷移を拒否する。

iOS/Androidの保持期間選択肢はローカルfixtureであり、地域別のproduction defaultを確定するものではない。正確な既定値、法的保持、backup expiryは別途qualificationする。

## Tests

- challenge-bound proof、challenge expiry、challenge replay
- session rotation、stale-token replayによるfamily revoke
- immutable plan binding、owner mismatch、binding conflict
- receipt sequence/replay/content-field rejection
- audit content-field rejection
- deletion invalid transition
- retention expiry/apply
- API identity composition

## 未証明ゲート

- 外部IdPの署名・issuer/audience/expiry/revocation検証
- Secure Enclave/Android Keystoreでの実Ed25519 proof
- KMS/HSMによるtoken hashing・key rotation・秘密情報保護
- durable DBのtransaction/unique constraint/append-only enforcement
- multi-instance race、queue retry、clock skew、disaster recovery
- provider token revoke、account deletionの法的保持・実データ消去
- 実機、staging、production deploymentでの認証・監査・保持期間qualification
