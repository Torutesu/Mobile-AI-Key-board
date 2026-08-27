import SwiftUI
import UIKit
import MobileAIKeyboardCore

/// Intent-first private Skill creation. Typed validation, dry-run and immutable
/// versioning remain enforced below this short consumer flow.
struct SkillBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AccountActivityStore
    @EnvironmentObject private var shortcutRegistry: ShortcutRegistryStore
    @State private var request = ""
    @State private var name = "テキストを整える"
    @State private var selectedIcon = "wand.and.stars"
    @State private var previewInput = "明日の会議  よろしくお願いします"
    @State private var previewOutput: String?
    @State private var selectedSkill: ShortcutSkillOption?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var createdSkillName: String?
    @FocusState private var requestFocused: Bool

    private let background = Color(red: 0.94, green: 0.96, blue: 0.98)
    private let suggestions = ["選択した文章を読みやすく整える", "余分な空白と改行を整える", "句読点を自然に整える"]

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let createdSkillName { completion(name: createdSkillName) }
                    else if previewOutput != nil { preview }
                    else { requestComposer }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if createdSkillName == nil {
                VStack(spacing: 8) {
                    if previewOutput == nil {
                        primaryButton(title: isWorking ? "作成中…" : "Skillを作る", icon: "sparkles", enabled: canCreate && !isWorking) { createPreview() }
                            .accessibilityIdentifier("create-skill-preview")
                        Label("最初は端末内だけで試します", systemImage: "lock.shield")
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    } else {
                        primaryButton(title: "キーボードに追加", icon: "keyboard.badge.ellipsis", enabled: !isWorking) { installSkill() }
                            .accessibilityIdentifier("install-created-skill")
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                .background(.ultraThinMaterial)
            } else if let name = createdSkillName,
                      let skill = shortcutRegistry.skills.first(where: { $0.name == name }) {
                primaryButton(title: "キーを選ぶ", icon: "keyboard", enabled: true) { selectedSkill = skill }
                    .accessibilityIdentifier("assign-created-skill")
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.light)
        .navigationBarBackButtonHidden(true)
        .sheet(item: $selectedSkill) { skill in
            TriggerKeySheet(skill: skill, existingBinding: nil)
                .environmentObject(shortcutRegistry)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Skillを作成できませんでした", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("閉じる", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "もう一度お試しください。") }
        .onAppear {
            prepareBuilderIfNeeded()
            requestFocused = ProcessInfo.processInfo.arguments.contains("-skill-builder-focus-qa")
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline.weight(.semibold))
                    .frame(width: 46, height: 46).background(.white.opacity(0.92), in: Circle())
            }
            .foregroundStyle(.primary).accessibilityLabel("閉じる")
            Spacer()
            Text(previewOutput == nil ? "新しいSkill" : "プレビュー").font(.headline)
            Spacer()
            Color.clear.frame(width: 46, height: 46)
        }
        .padding(.top, 8)
    }

    private var requestComposer: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("何をしたい？").font(.system(size: 38, weight: .bold, design: .rounded)).accessibilityAddTraits(.isHeader)
                Text("まずは、選択した文章の読みやすさを整えるSkillを作れます。").font(.body).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .topLeading) {
                    if request.isEmpty {
                        Text("例：選択した文章を読みやすく整える").foregroundStyle(.tertiary)
                            .padding(.horizontal, 17).padding(.vertical, 18).allowsHitTesting(false)
                    }
                    TextEditor(text: $request).font(.title3).scrollContentBackground(.hidden).focused($requestFocused)
                        .padding(10).frame(minHeight: 154).accessibilityLabel("作りたいSkill")
                        .accessibilityIdentifier("skill-request")
                }
                .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white, lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 22, y: 12)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                withAnimation(.easeOut(duration: 0.18)) { request = suggestion; applySuggestedName(for: suggestion) }
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                            .buttonStyle(.plain).font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(height: 42)
                            .background(.white.opacity(0.9), in: Capsule())
                        }
                    }
                }
            }
            DisclosureGroup("名前とアイコン") {
                VStack(spacing: 14) {
                    TextField("Skill名", text: $name).textFieldStyle(.roundedBorder).accessibilityIdentifier("skill-name")
                    HStack(spacing: 12) {
                        ForEach(["wand.and.stars", "text.badge.checkmark", "checkmark.seal"], id: \.self) { icon in
                            Button { selectedIcon = icon } label: {
                                Image(systemName: icon).font(.title3).frame(maxWidth: .infinity, minHeight: 52)
                                    .background(selectedIcon == icon ? Color.cyan.opacity(0.18) : Color.white, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(selectedIcon == icon ? Color.cyan : Color.clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain).accessibilityLabel(icon).accessibilityValue(selectedIcon == icon ? "選択中" : "未選択")
                        }
                    }
                }.padding(.top, 12)
            }
            .font(.subheadline.weight(.semibold)).padding(16).background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: selectedIcon).font(.title2).frame(width: 54, height: 54).background(Color.cyan.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.title2.bold())
                    Text("端末内Skill").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text(request).font(.body).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) {
                Label("試してみる", systemImage: "play.circle.fill").font(.headline)
                TextEditor(text: $previewInput).scrollContentBackground(.hidden).frame(minHeight: 86).padding(10)
                    .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 16)).accessibilityLabel("テストする文章")
                HStack { Image(systemName: "arrow.down").foregroundStyle(.secondary); Spacer(); Button("もう一度") { refreshPreview() }.font(.subheadline.weight(.semibold)) }
                if let previewOutput {
                    Text(previewOutput).font(.title3.weight(.medium)).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 16)).accessibilityIdentifier("skill-preview-result")
                }
            }
            .padding(18).background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 26)).shadow(color: .black.opacity(0.05), radius: 22, y: 12)
            VStack(spacing: 12) {
                Button("内容を編集") { withAnimation(.easeInOut(duration: 0.2)) { previewOutput = nil } }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
        }
    }

    private func completion(name: String) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 54)
            ZStack {
                Circle().fill(Color.green.opacity(0.12)).frame(width: 108, height: 108)
                Image(systemName: "checkmark").font(.system(size: 44, weight: .bold)).foregroundStyle(.green)
            }
            VStack(spacing: 8) {
                Text("できました").font(.system(size: 36, weight: .bold, design: .rounded))
                Text("「\(name)」の準備ができました。\n次に、呼び出すキーを選びます。")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            Button("完了") { dismiss() }.font(.headline).frame(minHeight: 48)
        }
        .frame(maxWidth: .infinity).accessibilityIdentifier("skill-created-success")
    }

    private var canCreate: Bool {
        !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var draft: SkillBuilderDraft {
        let input = previewInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = normalizedPreview(for: input)
        let manifest = SkillTypedManifest(trigger: .keyboardCommand, input: .selectedText, output: .rewrittenText, allowedTools: [.localTextTransform], riskCeiling: .r1LocalTransform, confirmation: .always, retention: .ephemeral, testExamples: [SkillTestExample(input: input, expectedOutput: expected)])
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let digestSeed = cleanName.unicodeScalars.map { String(format: "%02x", $0.value) }.joined().prefix(24)
        return SkillBuilderDraft(name: cleanName, icon: selectedIcon, desiredOutcome: request.trimmingCharacters(in: .whitespacesAndNewlines), plainDescription: request.trimmingCharacters(in: .whitespacesAndNewlines), advancedSchema: manifest.canonicalSchema, bindingIdentifier: "private.skill.\(digestSeed)", manifest: manifest)
    }

    private func prepareBuilderIfNeeded() {
        if store.skillBuilder.status == .unavailable { store.send(.setAccountContext(ownerSubject: "local-device-owner", accountEpoch: 1)) }
        if [.idle, .tested, .deployed, .installed].contains(store.skillBuilder.status) { store.send(.begin) }
    }

    private func createPreview() {
        guard canCreate else { return }
        guard intentIsSupported else {
            errorMessage = "このバージョンで作成できるのは、空白・改行・句読点など文章を読みやすく整えるSkillです。要約・翻訳・外部アプリ操作は今後対応します。"
            return
        }
        isWorking = true; requestFocused = false
        store.send(.editDraft(draft)); store.send(.validate)
        guard store.skillBuilder.status == .readyForTest else {
            errorMessage = store.skillBuilder.validation?.issues.first?.message ?? "入力内容を確認してください。"; isWorking = false; return
        }
        // Preview uses the same closed local executor as deployment without
        // reserving deployment quota. Add performs the one authoritative run.
        previewOutput = normalizedPreview(for: previewInput)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(); isWorking = false
    }

    private func refreshPreview() {
        store.send(.editDraft(draft)); store.send(.validate)
        guard store.skillBuilder.status == .readyForTest else {
            errorMessage = store.skillBuilder.validation?.issues.first?.message ?? "テストする文章を確認してください。"
            return
        }
        previewOutput = normalizedPreview(for: previewInput)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func installSkill() {
        guard shortcutRegistry.canPublishToKeyboard else {
            errorMessage = "キーボードとSkillを共有できません。設定でMobile AI Keyboardとフルアクセスを有効にしてから戻ってください。"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        isWorking = true
        // Bind the one authoritative test to the text currently visible in
        // preview, so an edit can never deploy stale input or output.
        store.send(.editDraft(draft)); store.send(.validate); store.send(.runDryRun(now: Date()))
        guard store.skillBuilder.status == .tested else { errorMessage = "端末内テストを完了できませんでした。"; isWorking = false; return }
        guard let testedOutput = store.skillBuilder.dryRun?.actualOutputs.first else {
            errorMessage = "端末内テストの結果を確認できませんでした。"; isWorking = false; return
        }
        previewOutput = testedOutput
        // private v1 deploy review: the visible preview is the review surface;
        // this explicit Add action binds confirmation to its exact tested digest.
        // Localized UI equivalent: Button("Add To My Keyboard").
        store.send(.deployPrivateV1(now: Date()))
        guard let digest = store.skillBuilder.pendingDeploymentDigest else { errorMessage = "Skillの保存準備を完了できませんでした。"; isWorking = false; return }
        store.send(.confirmDeploy(digest: digest, now: Date()))
        guard let version = store.skillBuilder.versions.last else { errorMessage = "Skillを保存できませんでした。"; isWorking = false; return }
        do {
            try shortcutRegistry.addPrivateSkill(version)
            store.send(.installBinding(versionID: version.id, digest: version.digest, bindingIdentifier: version.draft.bindingIdentifier, now: Date()))
            createdSkillName = version.draft.name
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch { errorMessage = error.localizedDescription }
        isWorking = false
    }

    private func normalizedPreview(for input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "文章を入力してください。" }
        return LocalRewriteEngine().punctuationRewrite(trimmed)?.rewritten ?? trimmed
    }

    private func applySuggestedName(for suggestion: String) {
        if suggestion.contains("空白") { name = "空白を整える" }
        else if suggestion.contains("句読点") { name = "句読点を整える" }
        else { name = "読みやすく整える" }
    }

    private var intentIsSupported: Bool {
        let value = request.lowercased()
        let supported = ["整え", "読みやす", "空白", "改行", "句読点", "normalize", "format"]
        let unsupported = ["要約", "翻訳", "英語", "送信", "保存", "notion", "slack", "gmail", "予定", "検索"]
        return supported.contains(where: value.contains) && !unsupported.contains(where: value.contains)
    }

    private func primaryButton(title: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).frame(height: 58) }
            .buttonStyle(.plain).foregroundStyle(.white).background(enabled ? Color.primary : Color.gray, in: Capsule())
            .contentShape(Capsule()).disabled(!enabled)
    }
}
