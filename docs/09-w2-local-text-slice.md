# W2 Local Text Slice

## Scope

W2の最初のshared sliceは、外部サービスを呼ばないR1 text actionに限定する。対象は rewrite / translate / shorten / custom の typed actionで、通常入力と同じくローカルで完結する。provider、OAuth、network queue、backendへの本文送信はこのsliceに含めない。

## Contract

`packages/contracts` が次の境界を所有する。

- `LocalDisclosure`: capture source、sourceごとのhard character limit、`destination=local_device`、`network_required=false`、`retention=none`。
- `LocalTextCapture`: disclosed items、field snapshot fingerprint、disclosure acknowledgement digest、immutable capture fingerprint。
- `LocalTextPreview`: exact / locally-redacted modeと文字数・digest・redaction metadata。本文はローカルUI専用で、telemetry契約には存在しない。
- `LocalTextPlan`: R1、local_device、network false、空のtools、capture fingerprint、result revision、apply method、canonical digest。
- `LocalTextResult`: revision、本文（最大10,000文字）、apply method、undo token/state/expiry。

`LocalTextCaptureItem.text` はschemaで最大4,000文字、source固有の限界はpolicyでさらに狭める。command 500、selection 4,000、surrounding 1,500（before 1,000 + after 500）、clipboard 4,000を既定値とする。

## Invariants

1. Clipboardとsurrounding textは既定でdisabled。enabledにする場合は同一disclosure内でexplicit opt-inが必要。
2. acknowledgement digestはcanonical disclosure全体から計算し、一バイトでも異なるdisclosureを承認できない。
3. capture fingerprintはcapture items、field fingerprint、acknowledgement digestから計算し、後から本文やfield snapshotを差し替えられない。
4. local planはR1、`destination=local_device`、`network_required=false`、external toolsなしを全て満たさなければfail-closedで拒否する。
5. exact / locally-redacted previewの本文はlocal capture/resultに留まり、telemetryはランダムなaction ID・source type・mode・revisionのみを受け入れる。本文、selection、clipboard、capture fingerprintはtelemetry schemaに存在しない。
6. result revisionがactive field snapshotと一致しない場合、applyを拒否する。
7. `undo.state=available` はtokenとexpiryを必須とし、それ以外のstateはtoken/expiryを持てない。expiry後のundoは拒否する。
8. canonical digest、acknowledgement、fingerprint、revision、undoの違反はtyped errorとして扱い、暗黙のfallbackやnetwork送信を行わない。

## Tests

- clipboard/surrounding default opt-in
- disclosure acknowledgement digest mismatch
- capture source limits and source enablement
- local plan external tool contamination
- telemetry content/fingerprint field rejection
- local plan digest and R1 boundary
- result revision mismatch
- undo state/token/expiry consistency

## Unverified gates

- iOS Keyboard Extension / Android IMEから実際のselection・clipboard・surrounding textを取得するOS実機挙動
- secure field、OTP、password fieldでcaptureを完全抑止する物理端末証明
- network disabled enforcementをOS firewallまたはproduction egress policyで独立検証すること
- local rewrite/translation engineの品質、エンティティ保持、性能予算
- telemetry collectorがschema外のpayloadを保存しない実運用証明
- crash/kill/restart中のundo persistenceとfield fingerprint再検証
