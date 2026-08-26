# Mobile AI Keyboard — QA / World-class Gap Audit

監査日: 2026-08-26  
対象: `main` / `e93cac9`  
結論: **Skill Key基盤は成立しているが、世界トップ製品としての一般公開判定は `not_ready`。** 現状は「安全性を意識したプログラマブル・ショートカットのα基盤」であり、「毎日使える最高品質のキーボード」や「Acti級のAgentic Keyboard」には未到達。

## 1. 質問への直接回答

### 他のキーも登録できるか

**できる。iOS / Androidとも、現在はラテンQWERTYの A〜Z、最大26キーが対象。**

- 未使用キーを選び、Skillを割り当てられる。
- 使用中のキーは競合防止で選択不可になる。
- 割り当て変更と削除のモデル・テストがある。
- 通常タップは文字入力、約450msの長押しでSkill実行という二重用途。
- 現在の実効上限は「1キーにつき1つの有効Skill」「同一Skillは1箇所」。

未対応:

- 数字、記号、Space、Return、Shift、Globe、Emojiキーへの割り当て
- ダブルタップ、スワイプ、修飾キー、複数キー同時押し、レイヤー
- アプリ別・入力欄別・言語別のキーマップ
- ハードウェアキーボードのショートカット
- キーボード上からの直接割り当て・入れ替え

証拠:

1. `01-skill-keys-dashboard.png`: H/Mが割り当て済み。
2. `02-trigger-key-sheet.png`: A〜Zを表示し、使用中のH/Mのみ無効。
3. `03-trigger-q-selected.png`: 未使用のQを選択でき、Addが有効化。

## 2. 今回確認したユーザーフロー

1. HostアプリのSkill Keys画面を開く。
2. 未設定Skillの「追加」を押す。
3. A〜Zから未使用キーを選ぶ。
4. Addで保存し、HostからKeyboard Extension / IMEへ同期する。
5. 任意アプリの入力欄でカスタムキーボードへ切り替える。
6. 通常タップで文字入力、長押しで割り当てSkillを呼び出す。
7. 入力内容を確認し、生成結果をレビュー、編集、適用またはコピーする。
8. 適用直後ならUndoする。

今回のfresh visual evidenceは1〜3。4はSimulator上のApp Group同期表示まで確認。5〜8の他社アプリ内E2E、実機、物理タッチは今回未証明。

## 3. 自動検証結果

| 対象 | 結果 | 意味 | 限界 |
|---|---:|---|---|
| Shared JS/TS | PASS | contracts / policy / runtimeのテストと型検査が通る | 実サービス接続ではない |
| iOS Core | PASS: 83 tests | 状態遷移、編集ロック、Undo、Shortcut検証 | 実キーボード操作ではない |
| iOS Simulator build | PASS | Host + Extensionを署名付きSimulatorビルド可能 | App Store署名・実機ではない |
| Android unit/lint/APK | PASS | unit test、lint、debug APK生成 | 実IME・OEM差・Play配布ではない |
| Fresh screenshot QA | PASS: 3 states | 割り当て画面とQ選択を視認 | 実行E2Eではない |

署名付きSimulatorビルドでは、未署名インストール時に出たApp Group entitlementエラーは再現しなかった。ただし実機provisioning、端末再起動後の永続化、複数端末同期は `not_proven`。

## 4. 世界トップ製品に足りないもの

### P0 — 公開前のブロッカー

#### P0-1. 「普通のキーボード」としての品質が不足

現在は基本的なQWERTY入力面。日常の主キーボードに必要な以下がない。

- 日本語かな/ローマ字変換、変換候補、学習辞書
- 自動修正、予測入力、次単語候補、句読点/大文字のスマート処理
- 絵文字、音声入力、スワイプ入力、長押し代替文字
- Caps Lock、入力タイプ別Return表示、数字・記号レイヤー
- 片手モード、サイズ/位置調整、多言語切替
- 入力音、触覚、文字プレビュー、テーマ

世界トップを狙うなら、AIが便利でも通常入力が遅い製品は常用されない。Gboard / Apple / Samsung / SwiftKeyと同等のベースラインが先。

#### P0-2. Agentic実行がfixture中心

キーボード内で確実に実行できるのは、現時点では端末内の2つの決定的変換のみ。

- 丁寧に整える
- 句読点を整える

「空き時間を探す」はHost handoffとして一覧に出るが、Extension側は「Hostアプリで確認」と表示するだけ。OAuth、実Google Calendar読取、結果レビューへの復帰、入力欄への反映までのE2Eはない。UI上で追加可能に見えるため、現状のままでは期待違反になる。

#### P0-3. 実機・実アプリE2E未証明

最低でも以下のマトリクスが必要。

- iOS実機: Messages、Mail、Safari、LINE、Slack、Gmail、Notion
- Android実機: Pixel + Samsung、同じ主要アプリ
- 選択あり/なし、長文、絵文字、改行、日本語、URL、RTL
- 入力欄切替、アプリ切替、キーボード切替、回転、バックグラウンド復帰
- Secure field、電話番号欄、アプリ側がcustom keyboardを拒否するケース

#### P0-4. リリース品質と性能証拠がない

- key-to-commit p50/p95
- keyboard cold/warm open p95
- long-press誤発火率、通常タップ取りこぼし率
- Skill完了時間、失敗率、キャンセル率
- メモリ圧迫・Extension kill・IME再生成耐性
- crash-free sessions、ANR、offline、弱回線、provider timeout

コード内にquality gateの契約はあるが、保護されたproduction相当環境の実測証拠はない。

#### P0-5. iOS Full Accessの信頼設計が未完成

現ビルドは`RequestsOpenAccess=true`。App Group共有に必要な一方、ユーザーからは「入力内容を送れるキーボード」に見える。必要事項:

- Full Accessが必要な理由を機能単位で説明
- 実行時に「何を・どこへ・なぜ送るか」を表示
- Skillごとのnetwork/offlineバッジ
- 外部送信のmaster kill switch
- 接続先、保持、削除、監査履歴
- release archiveのentitlement/privacy manifest検査

### P1 — 世界トップ水準に必要

#### P1-1. Skill Builder / Connector / Marketplaceが製品化されていない

Actiは自然言語Skill Builder、キー割り当て、公開/非公開Skill Hub、アプリ/API接続を主価値にしている。必要:

- 自然言語→型付きSkill manifest→テスト→公開
- Gmail、Calendar、Notion、Slack、MeetなどのOAuth connector
- capabilityとside effectの明示
- private/team/publicの配布
- 署名、version pin、rollback、revocation、通報、moderation
- 検索、ランキング、信頼スコア、creator analytics

契約・policyの土台は強いが、ユーザーが使えるサービスとして閉じていない。

#### P1-2. 割り当てUXが26件で破綻する

- 一覧に検索、カテゴリ、並び替え、利用頻度がない
- occupied keyは無効化だけで、Swap / Move / Replaceがない
- 同一Skillを複数キー/文脈へ割り当てられない
- 実キーボード上のプレビュー、編集導線がない
- 割り当て成功後のテスト実行導線がない
- long-press 450msを調整できない

#### P1-3. 発見性と誤操作防止が弱い

色付き枠だけでは長押しSkillを学習しにくい。必要:

- 初回だけのhold progress ring / haptic threshold
- 押下中にSkill名を表示
- 指をずらしてキャンセル
- 誤発火時の即時cancel
- 利用頻度に基づくgentle reminder
- VoiceOver custom actionと同等のSwitch Control経路

#### P1-4. アクセシビリティ未完

- Trigger sheetの10キー横一列は、狭い端末で44pt幅を満たしにくい
- Dynamic Type最大、Bold Text、Button Shapes、Reduce Motion未検証
- disabled H/Mと補助文のコントラストが弱い
- VoiceOver順序、読み上げ、Rotor、Switch Controlを実機未検証
- 文字サイズ拡大時のsheet下部CTAとスクロール挙動未検証

#### P1-5. 文脈知能と反復編集が弱い

トップ製品は単発変換から、画面文脈、個人化、custom prompt、前ドラフト比較、反復調整へ進んでいる。必要:

- 選択範囲/段落/全文の明示
- tone、長さ、言語、対象読者のquick controls
- 生成履歴とprevious draft
- follow-up refinement
- app/field/language-aware Skill suggestion
- 個人辞書・固有名詞保護

### P2 — 差別化と運用品質

- ダークモードとブランドシステム
- 日英UIの統一、完全なlocalization
- per-app profile / Focus profile / team policy
- Skill利用履歴、成功率、Undo率、誤発火率
- import/export、端末移行、conflict merge
- offline modelとprivate cloudの選択
- enterprise audit、DLP、managed configuration
- creator revenue / team catalog / verified publisher

## 5. 実装上の具体的リスク

1. **Host handoffの未完了:** `ShortcutRegistryStore.swift`のCalendar Skillは`.hostHandoff`だが、Extensionは実行せず状態文だけを出す。
2. **長押し競合:** iOSは`cancelsTouchesInView=false`と非同期suppressionで通常tapとの競合を抑えているが、アプリ/OS差を物理タッチで証明していない。
3. **Full Access説明との不整合:** docsには`RequestsOpenAccess=false`前提の記述が残る一方、projectは`true`。ストア説明・privacy manifest・実装を一つに揃える必要がある。
4. **同期のidentity:** Host fixtureはlocal device/user固定のαデータ。ログイン、複数端末、logout/revocation時のsnapshot invalidationは製品化未完。
5. **iOS/Android parity:** 共通契約はあるが、同一snapshot/digestを両OSが相互運用するE2Eは未証明。
6. **Clipboard:** iOSのCopyはgeneral pasteboard、Androidもsystem clipboardを使用。明示操作ではあるが、保存時間・OS通知・履歴への露出を説明すべき。
7. **Host context制約:** iOS custom keyboardは選択操作、secure field、phone pad、mic、custom keyboard拒否などOS制約を受ける。製品文言で「どこでも」を約束しない。

## 6. 競合ベンチマーク

| ベンチマーク | 強み | 本製品の差 |
|---|---|---|
| Acti | Skill Keys、自然言語Builder、Skill Hub、connected tools | 基盤のみ。service E2Eとecosystemが未完 |
| Gboard | 通常入力品質、Writing Tools、個人化、音声、文脈 | 通常入力全般と反復AI編集が不足 |
| Apple Writing Tools | OS横断、proofread/rewrite/summarize | system-level reachと文章機能幅が不足 |
| Samsung Writing Assist | 翻訳、style、grammar、composer | 即時ツール群とGalaxy統合が不足 |
| SwiftKey | 成熟したprediction、多言語、Tone/Editor | prediction/learning/多言語が不足 |
| Grammarly | correction、completion、rewrite、language support | 常時補助と説明可能な校正が不足 |

## 7. 勝ち筋

Actiを見た目だけ追うより、**「安全に実行できるprogrammable action keyboard」**へ振り切るべき。

1. 通常入力はOS級にするか、OS機能を最大限再利用する。
2. Skillは型付きcapability manifestで、入力・送信先・副作用を必ずpreviewする。
3. 書き込みはPlan → Confirm → Execute → Receipt → Undoを統一する。
4. 端末内Skill、private cloud、external connectorを明示的に区別する。
5. 公開Skillは署名・version pin・権限差分・revocation・rollbackを標準装備する。
6. 「何でもAI」ではなく、入力中の3秒タスクを1長押しで安全に完了する。

## 8. 最短・最安でトップ水準へ近づく順序

### Phase A — 2週間相当: 信頼できるベータ

- Calendarの見せかけ導線を隠すか、実E2Eまで閉じる
- iOS/Android実機で主要7アプリのE2E suite
- long-press/tap/haptic/cancelの実機調整
- onboardingにEnable → Full Access理由 → Test field → Successを追加
- release entitlement/privacy consistency gate

### Phase B — 4〜8週間相当: 常用できる入力面

- 日本語入力はゼロからIMEを作らず、OS/既存エンジン利用を優先検証
- prediction/autocorrect/emoji/numeric layer/caps/locale-aware return
- accessibility matrixと性能計測をCI/端末ラボへ
- Skill検索、swap、test-run、usage ordering

### Phase C — 8〜16週間相当: Agentic moat

- Calendar + Notion + Gmail/Slackのread-first connector
- typed Skill Builder、private/team distribution
- risk-based confirmation、receipt、exact-resource Undo
- signed package、moderation、rollback、creator trust

## 9. リリース判定ゲート

一般公開前に、最低限すべて満たすこと。

- [ ] iOS/Android実機で主要アプリの通常tap 10,000回相当、欠落/二重入力ゼロ
- [ ] long-press誤発火率 < 0.1%、キャンセル可能
- [ ] cold open / key-to-commit / Skill latencyのp95 budget達成
- [ ] App Group/SharedPreferencesの再起動・更新・migration試験
- [ ] secure field / unsupported fieldでAI機能が確実に閉じる
- [ ] provider timeout、offline、token expiry、revocationの復旧
- [ ] Apply/Undoがfield identity変化時にfail closed
- [ ] Dynamic Type / VoiceOver / Switch Control / contrast pass
- [ ] privacy manifest、entitlement、network destinationのarchive検査
- [ ] Calendar等の表示機能が実際にE2E完了、またはUIから非表示

## 10. 証拠の限界

- 今回はコード、ローカルテスト、signed Simulator、fresh screenshotsによる監査。
- 実機、App Store / Play配布、実OAuth、実provider、production telemetryは未検証。
- したがって「A〜Zの登録UIとローカル基盤」はconfirmed、「世界トップ品質」「実外部アクション」「実機常用性」は `not_proven`。

## 11. 参照した公式情報

- Acti Skill Hub: https://openacti.com/acti-skill-hub/
- Acti Agentic Keyboard: https://openacti.com/what-is-agentic-keyboard/
- Acti Privacy: https://openacti.com/privacy/
- Gboard Writing Tools: https://support.google.com/gboard/answer/16515540?hl=en
- Gboard Gemini Intelligence: https://support.google.com/gboard/answer/17470061?hl=en-EN
- Gboard Voice: https://support.google.com/gboard/answer/11197787?hl=EN
- Apple Writing Tools: https://support.apple.com/en-us/121582
- Apple Custom Keyboard Guide: https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html
- Samsung Writing Assist: https://www.samsung.com/uk/support/mobile-devices/how-to-use-galaxy-ai-features-on-writing-assist/
- Microsoft SwiftKey Tone: https://support.microsoft.com/en-us/swiftkey-keyboard/how-to-use-tone-in-microsoft-swiftkey-keyboard
- Grammarly Mobile AI: https://support.grammarly.com/hc/en-us/articles/24086943816845-How-to-use-Grammarly-s-generative-AI-on-my-mobile-device
