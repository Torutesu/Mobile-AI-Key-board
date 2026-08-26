import SwiftUI
import MobileAIKeyboardCore

/// No-code private Skill builder. Every operation is a local fixture transition;
/// there is intentionally no public publish or provider/LLM client.
struct SkillBuilderView: View {
    @EnvironmentObject private var store: AccountActivityStore
    @EnvironmentObject private var shortcutRegistry: ShortcutRegistryStore
    @State private var desiredOutcome = ""
    @State private var name = ""
    @State private var icon = "wand.and.stars"
    @State private var plainDescription = ""
    @State private var advancedSchema = SkillTypedManifest.defaultFixture.canonicalSchema
    @State private var trigger: SkillTrigger = .manual
    @State private var input: SkillInputKind = .typedText
    @State private var output: SkillOutputKind = .rewrittenText
    @State private var allowedTool: SkillAllowedTool = .localTextTransform
    @State private var retention: SkillRetentionMode = .ephemeral
    @State private var exampleInput = ""
    @State private var exampleExpected = ""
    @State private var recipient = ""
    @State private var shareExpiry = Date().addingTimeInterval(86_400)
    @State private var registryMessage: String?
    @State private var registryError: String?

    private var manifest: SkillTypedManifest {
        SkillTypedManifest(trigger: trigger, input: input, output: output, allowedTools: [allowedTool], riskCeiling: .r1LocalTransform, confirmation: .always, retention: retention, testExamples: [SkillTestExample(input: exampleInput, expectedOutput: exampleExpected)])
    }

    private var draft: SkillBuilderDraft {
        SkillBuilderDraft(name: name, icon: icon, desiredOutcome: desiredOutcome, plainDescription: plainDescription, advancedSchema: advancedSchema, bindingIdentifier: bindingIdentifier, manifest: manifest)
    }

    private var bindingIdentifier: String {
        let slug = name.lowercased().replacingOccurrences(of: " ", with: ".")
        return slug.isEmpty ? "private.skill.binding" : "private.\(slug)"
    }

    private var status: SkillBuilderStatus { store.skillBuilder.status }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                boundaryCard
                quotaCard
                if status == .unavailable {
                    stateMessage("Accountのfixtureサインイン後にprivate Skillを作成できます。公開publishは常に無効です。", icon: "lock.shield")
                } else {
                    statusCard
                    if [.idle].contains(status) {
                        Button("コードを書かずにSkill作成を開始") { store.send(.begin) }
                            .buttonStyle(.borderedProminent)
                            .frame(minHeight: 44)
                    }
                    if [.collectingMissingInfo, .draft, .validationFailed].contains(status) {
                        builderForm
                    }
                    if status == .readyForTest { readyForTestCard }
                    if status == .testing { testingCard }
                    if status == .tested { testedCard }
                    if status == .deployReview { deployReviewCard }
                    if [.deployed, .installed].contains(status) { deploymentCard }
                    if status == .quotaExceeded { stateMessage("fixture quotaを使い切りました。外部課金は発生していません。", icon: "gauge.with.dots.needle.67percent") }
                }
            }
            .padding()
        }
        .navigationTitle("Private Skill Builder")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadDraftIfPresent() }
        .alert("キーボード候補に追加しました", isPresented: Binding(get: { registryMessage != nil }, set: { if !$0 { registryMessage = nil } })) {
            Button("閉じる", role: .cancel) { registryMessage = nil }
        } message: {
            Text(registryMessage ?? "")
        }
        .alert("キーボード候補へ追加できませんでした", isPresented: Binding(get: { registryError != nil }, set: { if !$0 { registryError = nil } })) {
            Button("閉じる", role: .cancel) { registryError = nil }
        } message: {
            Text(registryError ?? "")
        }
    }

    private var boundaryCard: some View {
        Label {
            VStack(alignment: .leading, spacing: 5) {
                Text("private Skill / v1 fixture").font(.headline)
                Text("外部LLM、provider、URLSession、ネットワークは未接続です。入力・schema・検証・deploy receiptは端末内fixtureだけで処理します。public publishは実装されていません。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "wand.and.stars").foregroundStyle(.purple)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("private Skill v1 fixture。外部LLM、provider、ネットワークは未接続。public publishは無効です。")
    }

    private var quotaCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Usage / cost", systemImage: "gauge.with.dots.needle.67percent").font(.headline)
            Text("fixture quota: \(store.skillBuilder.quotaRemaining) remaining / \(store.skillBuilder.quotaLimit)")
            Text("reservation: \(store.skillBuilder.quotaReserved) / 1 per test")
                .font(.footnote).foregroundStyle(.secondary)
            Text("cost: \(store.skillBuilder.fixtureCostDisclosure)。\(store.skillBuilder.externalCostDisclosure)")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Usageとcost。残り\(store.skillBuilder.quotaRemaining)回、reservation \(store.skillBuilder.quotaReserved)回。fixtureは0 credits、外部LLMとproviderは未接続です。")
    }

    private var statusCard: some View {
        Label(status.title, systemImage: statusIcon)
            .font(.headline)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Skill Builder状態: \(status.title)")
    }

    private var builderForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("1. 達成したい結果", systemImage: "target").font(.headline)
            TextEditor(text: $desiredOutcome)
                .frame(minHeight: 74)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                .accessibilityLabel("達成したい結果")
            Text("例: 会議メモから次の一歩を表示").font(.caption).foregroundStyle(.secondary)

            Label("2. Skillの名前とアイコン", systemImage: "tag").font(.headline)
            TextField("Skill名", text: $name).textFieldStyle(.roundedBorder).accessibilityLabel("Skill名")
            Picker("SF Symbol", selection: $icon) {
                ForEach(["wand.and.stars", "calendar", "list.bullet.rectangle", "text.badge.checkmark", "checkmark.seal"], id: \.self) { symbol in
                    Label(symbol, systemImage: symbol).tag(symbol)
                }
            }
            .frame(minHeight: 44)
            .accessibilityLabel("SF Symbolアイコン")
            Text("emojiではなくallowlisted SF Symbolだけを使います。bindingはSkill名から自動生成されます: \(bindingIdentifier)")
                .font(.caption).foregroundStyle(.secondary)

            Label("3. plain description", systemImage: "text.alignleft").font(.headline)
            TextEditor(text: $plainDescription)
                .frame(minHeight: 74)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                .accessibilityLabel("plain description")

            Label("4. typed manifest", systemImage: "list.bullet.rectangle").font(.headline)
            Picker("trigger", selection: $trigger) { ForEach(SkillTrigger.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Picker("input", selection: $input) { ForEach(SkillInputKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Picker("output", selection: $output) { ForEach(SkillOutputKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Picker("allowed tool", selection: $allowedTool) { ForEach(SkillAllowedTool.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            LabeledContent("risk ceiling", value: SkillRiskCeiling.r1LocalTransform.rawValue)
            LabeledContent("confirmation", value: SkillConfirmationMode.always.rawValue)
            Picker("retention", selection: $retention) { ForEach(SkillRetentionMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }

            Label("5. user-visible test example", systemImage: "checkmark.circle").font(.headline)
            TextField("入力例", text: $exampleInput).textFieldStyle(.roundedBorder).accessibilityLabel("テスト入力例")
            TextField("期待する出力例", text: $exampleExpected).textFieldStyle(.roundedBorder).accessibilityLabel("期待する出力例")
            Text("fixture testではこの入力例と期待出力例を実際に表示・検証します。")
                .font(.caption).foregroundStyle(.secondary)

            DisclosureGroup("advanced schema（typed manifestから反映）") {
                TextEditor(text: $advancedSchema)
                    .font(.caption.monospaced())
                    .frame(minHeight: 150)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    .accessibilityLabel("advanced typed schema JSON")
                Button("typed manifestをschemaへ反映") { advancedSchema = manifest.canonicalSchema }
                    .frame(minHeight: 44)
            }
            if !store.skillBuilder.missingInfo.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("不足情報").font(.subheadline.bold())
                    ForEach(store.skillBuilder.missingInfo) { item in
                        Label("\(item.id.title): \(item.explanation)", systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
            }
            VStack(spacing: 8) {
                Button("下書きを保存") { store.send(.editDraft(draft)) }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, minHeight: 44)
                Button("schema / policy / static検証") {
                    // The advanced schema is a projection of the typed manifest,
                    // not a second source of truth. Re-canonicalize immediately
                    // before validation so changing a picker or test example
                    // cannot leave a stale schema that the user must repair by
                    // discovering the Advanced disclosure control.
                    let candidate = SkillBuilderDraft(
                        name: name,
                        icon: icon,
                        desiredOutcome: desiredOutcome,
                        plainDescription: plainDescription,
                        advancedSchema: manifest.canonicalSchema,
                        bindingIdentifier: bindingIdentifier,
                        manifest: manifest
                    )
                    advancedSchema = candidate.advancedSchema
                    store.send(.editDraft(candidate))
                    store.send(.validate)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            if let validation = store.skillBuilder.validation, !validation.issues.isEmpty {
                ForEach(validation.issues) { issue in
                    Label("[\(issue.code)] \(issue.message)", systemImage: issue.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(issue.severity == .error ? .red : .orange)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private var readyForTestCard: some View {
        actionCard(title: "検証済み。fixture testを予約できます", icon: "checkmark.shield", message: "typed manifest、schema、private policy、static injection、binding conflictを通過しました。", action: {
            store.send(.beginDryRun(now: Date()))
        }, label: "fixture testを開始")
    }

    private var testingCard: some View {
        actionCard(title: "fixture test reservation中", icon: "hourglass", message: "1 quota unitを予約中です。入力例と期待出力例を端末内で検証します。", action: {
            store.send(.finishDryRun(now: Date()))
        }, label: "fixture testを完了")
    }

    private var testedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("fixture test passed", systemImage: "checkmark.circle.fill").font(.headline)
            if let result = store.skillBuilder.dryRun {
                Text(result.safeSummary).font(.body)
                ForEach(Array(result.validatedExamples.enumerated()), id: \.offset) { index, example in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("例\(index + 1) input: \(example.input)").font(.footnote)
                        Text("expected: \(example.expectedOutput)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Button("private v1 deploy planを作成") { store.send(.deployPrivateV1(now: Date())) }
                .buttonStyle(.borderedProminent).frame(minHeight: 44)
        }
        .cardStyle()
    }

    private var deployReviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("private v1 deploy review", systemImage: "doc.badge.gearshape").font(.headline)
            Text("このdigestはtyped manifest、plain/advanced schema、owner、account epoch、version、public publish disabledを束ねています。編集すると破棄されます。")
                .font(.body)
            if let digest = store.skillBuilder.pendingDeploymentDigest {
                Text(digest).font(.caption.monospaced()).textSelection(.enabled)
                Text("確認期限: \(store.skillBuilder.pendingDeploymentExpiresAt?.formatted(date: .abbreviated, time: .shortened) ?? "-")")
                    .font(.caption).foregroundStyle(.secondary)
                Button("このdigestでprivate v1 deployを確定") {
                    store.send(.confirmDeploy(digest: digest, now: Date()))
                }
                .buttonStyle(.borderedProminent).frame(minHeight: 44)
                .accessibilityIdentifier("confirm-private-deploy")
            }
            Button("編集してdeploy確認を破棄") { store.send(.editDraft(draft)) }
                .buttonStyle(.bordered).frame(minHeight: 44)
        }
        .cardStyle()
    }

    private var deploymentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(status.title, systemImage: "shippingbox.fill").font(.headline)
            Text("versionはimmutableです。installed bindingは明示的なpin操作まで旧versionを保持します。")
                .font(.body)
            ForEach(store.skillBuilder.versions) { version in
                VStack(alignment: .leading, spacing: 4) {
                    Text("v\(version.versionNumber): \(version.draft.name)").font(.subheadline.bold())
                    Text(version.digest).font(.caption.monospaced()).textSelection(.enabled)
                    Button("Add To My Keyboard") {
                        do {
                            try shortcutRegistry.addPrivateSkill(version)
                            registryMessage = "「\(version.draft.name)」を候補に追加しました。Skill KeysでA–Zキーを選び、fixture確認後に保存してください。"
                        } catch {
                            registryError = error.localizedDescription
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("add-private-\(version.id)")
                    Button(store.skillBuilder.installedBinding?.versionID == version.id ? "installed binding pin済み" : "このversionをbinding pin") {
                        store.send(.installBinding(versionID: version.id, digest: version.digest, bindingIdentifier: version.draft.bindingIdentifier, now: Date()))
                    }
                    .buttonStyle(.bordered).frame(minHeight: 44)
                    .disabled(store.skillBuilder.installedBinding?.versionID == version.id)
                }
                .padding(.vertical, 4)
            }
            if let pin = store.skillBuilder.installedBinding {
                Text("installed: v\(pin.versionNumber) / \(pin.bindingIdentifier) / \(pin.digest)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            NavigationLink {
                SkillKeysView().environmentObject(shortcutRegistry)
            } label: {
                Label("Skill KeysでA–Zキーを割り当てる", systemImage: "keyboard.badge.ellipsis")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("open-skill-keys")
            Divider()
            Label("private sharing（fixture）", systemImage: "person.badge.plus").font(.subheadline.bold())
            Text("recipient・version・digest・expiryに束縛したprivate shareだけを作成できます。public publishは無効です。")
                .font(.footnote).foregroundStyle(.secondary)
            TextField("recipient（fixture）", text: $recipient).textFieldStyle(.roundedBorder).accessibilityLabel("private share recipient")
            DatePicker("expiry", selection: $shareExpiry, displayedComponents: [.date, .hourAndMinute]).frame(minHeight: 44)
            if let latest = store.skillBuilder.versions.last {
                Button("v\(latest.versionNumber)をprivate share") {
                    store.send(.createPrivateShare(versionID: latest.id, digest: latest.digest, recipient: recipient, expiresAt: shareExpiry, now: Date()))
                }
                .buttonStyle(.bordered).frame(minHeight: 44)
            }
            if let share = store.skillBuilder.privateShare {
                Text("share: v\(share.versionNumber) / \(share.recipient) / expires \(share.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Button("private shareを破棄") { store.send(.revokePrivateShare) }
                    .frame(minHeight: 44)
            }
            Button("新しいimmutable versionを作成") { store.send(.begin) }
                .buttonStyle(.borderedProminent).frame(minHeight: 44)
        }
        .cardStyle()
    }

    private var statusIcon: String {
        switch status {
        case .unavailable: return "lock.shield"
        case .testing: return "hourglass"
        case .tested, .readyForTest: return "checkmark.shield"
        case .deployReview: return "doc.badge.gearshape"
        case .deployed, .installed: return "shippingbox"
        case .quotaExceeded: return "gauge.with.dots.needle.67percent"
        default: return "wand.and.stars"
        }
    }

    private func actionCard(title: String, icon: String, message: String, action: @escaping () -> Void, label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline)
            Text(message).font(.body).foregroundStyle(.secondary)
            Button(label) { action() }
                .buttonStyle(.borderedProminent).frame(minHeight: 44)
        }
        .cardStyle()
    }

    private func stateMessage(_ message: String, icon: String) -> some View {
        Label(message, systemImage: icon)
            .font(.footnote).foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .combine)
    }

    private func loadDraftIfPresent() {
        guard let saved = store.skillBuilder.draft else { return }
        name = saved.name
        icon = saved.icon
        desiredOutcome = saved.desiredOutcome
        plainDescription = saved.plainDescription
        advancedSchema = saved.advancedSchema
        trigger = saved.manifest.trigger
        input = saved.manifest.input
        output = saved.manifest.output
        allowedTool = saved.manifest.allowedTools.first ?? .localTextTransform
        retention = saved.manifest.retention
        exampleInput = saved.manifest.testExamples.first?.input ?? ""
        exampleExpected = saved.manifest.testExamples.first?.expectedOutput ?? ""
    }
}

private extension View {
    func cardStyle() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityElement(children: .contain)
    }
}
