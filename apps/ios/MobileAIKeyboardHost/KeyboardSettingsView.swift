import SwiftUI
import MobileAIKeyboardCore

struct KeyboardSettingsView: View {
    @EnvironmentObject private var store: AccountActivityStore
    @EnvironmentObject private var shortcutRegistry: ShortcutRegistryStore
    @State private var previewText = "田中さんへ https://example.com/path よろしく。明日は123です。"
    @State private var selectedPack: JapaneseWorkflowPack = .polite
    @State private var preview: WorkflowPackResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                boundaryCard
                NavigationLink {
                    OnboardingView(startsAtAccess: true)
                        .environmentObject(store)
                        .environmentObject(shortcutRegistry)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("キーボードを有効にする").font(.headline)
                            Text("追加・フルアクセス・動作確認をもう一度案内").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    } icon: {
                        Image(systemName: "checklist").foregroundStyle(.cyan)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("reopen-keyboard-setup")
                if let settingsSyncError = store.settingsSyncError {
                    Label(settingsSyncError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("keyboard-settings-sync-error")
                }
                NavigationLink {
                    SkillKeysView()
                        .environmentObject(shortcutRegistry)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Skill Keys").font(.headline)
                            Text("文字キーの長押しにSkillを割り当てる").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    } icon: {
                        Image(systemName: "keyboard.badge.ellipsis").foregroundStyle(.cyan)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                appearanceSection
                workflowSection
                previewSection
                Button("設定を初期値に戻す", role: .destructive) {
                    store.send(.reset)
                    preview = nil
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
            }
            .padding()
        }
        .background(Color(red: 0.94, green: 0.96, blue: 0.98).ignoresSafeArea())
        .navigationTitle("キーボード設定")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selectedPack = store.settings.enabledJapanesePacks.first ?? .polite }
    }

    private var boundaryCard: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("キーボードに反映")
                    .font(.headline)
                Text("変更はMobile AI Keyboardを次に開いたとき反映されます。入力内容は設定に保存しません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "keyboard.badge.ellipsis")
                .foregroundStyle(.blue)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("キーボードに反映。変更は次にキーボードを開いたとき反映されます。入力内容は保存しません")
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("見た目と入力")
                .font(.title3.weight(.semibold))
            Picker("テーマ", selection: Binding(get: { store.settings.theme }, set: { store.send(.setTheme($0)) })) {
                Text("システム").tag(KeyboardThemePreference.system)
                Text("ライト").tag(KeyboardThemePreference.light)
                Text("ダーク").tag(KeyboardThemePreference.dark)
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            Toggle("キー入力の触覚フィードバック", isOn: Binding(get: { store.settings.hapticsEnabled }, set: { store.send(.setHaptics($0)) }))
                .frame(minHeight: 44)
            Picker("キーサイズ", selection: Binding(get: { store.settings.keySize }, set: { store.send(.setKeySize($0)) })) {
                Text("コンパクト").tag(KeyboardKeySize.compact)
                Text("標準").tag(KeyboardKeySize.standard)
                Text("大きめ").tag(KeyboardKeySize.large)
            }
            .pickerStyle(.menu)
            .frame(minHeight: 44)
            Picker("片手モード", selection: Binding(get: { store.settings.oneHandedMode }, set: { store.send(.setOneHandedMode($0)) })) {
                Text("オフ").tag(KeyboardHandedness.off)
                Text("左寄せ").tag(KeyboardHandedness.left)
                Text("右寄せ").tag(KeyboardHandedness.right)
            }
            .pickerStyle(.menu)
            .frame(minHeight: 44)
        }
        .accessibilityElement(children: .contain)
    }

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("文章アシスト")
                .font(.title3.weight(.semibold))
            Toggle("英語の文章アシスト", isOn: Binding(get: { store.settings.englishWorkflowPackEnabled }, set: { store.send(.setEnglishWorkflowEnabled($0)) }))
                .frame(minHeight: 44)
            Text("日本語")
                .font(.headline)
            ForEach(JapaneseWorkflowPack.allCases, id: \.self) { pack in
                Toggle(isOn: Binding(get: { store.settings.isEnabled(pack) }, set: { store.send(.setPackEnabled(pack, $0)) })) {
                    Label(pack.rawValue, systemImage: pack.icon)
                }
                .frame(minHeight: 44)
            }
            Text("文章の変換は端末内で行います。入力した文章を外部へ送りません。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("プレビュー")
                .font(.title3.weight(.semibold))
            TextField("入力例", text: $previewText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .accessibilityLabel("プレビュー入力")
            Picker("アシスト", selection: $selectedPack) {
                ForEach(JapaneseWorkflowPack.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(minHeight: 44)
            Button("試してみる") {
                preview = JapaneseWorkflowEngine().transform(previewText, pack: selectedPack)
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
            if let preview {
                VStack(alignment: .leading, spacing: 8) {
                    Text("変換後").font(.headline)
                    Text(preview.rewritten).textSelection(.enabled)
                    Text("保護entity: \(preview.preservedEntities.isEmpty ? "なし" : preview.preservedEntities.joined(separator: "、"))")
                        .font(.footnote)
                    Text(preview.sourceDisclosure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
            }
        }
    }
}
