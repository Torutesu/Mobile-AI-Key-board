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
        .navigationTitle("キーボード設定")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selectedPack = store.settings.enabledJapanesePacks.first ?? .polite }
    }

    private var boundaryCard: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("拡張機能で消費可能な設定モデル")
                    .font(.headline)
                Text("schema v\(store.settings.schemaVersion)。現在はmemory-onlyで、拡張機能とのruntime同期はnot_provenです。通常入力とlocal workflowはネットワーク接続しません。Skill KeyのApp Group共有にはFull Accessが必要です。通常入力用の設定は境界後も保持します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "keyboard.badge.ellipsis")
                .foregroundStyle(.blue)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("拡張機能で消費可能な設定モデル。memory-only。runtime同期は未証明。schemaバージョン\(store.settings.schemaVersion)。通常入力とlocal workflowはネットワーク接続しません。Skill KeyのApp Group共有にはFull Accessが必要です")
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
            Text("Workflow packs")
                .font(.title3.weight(.semibold))
            Toggle("English workflow pack (local baseline)", isOn: Binding(get: { store.settings.englishWorkflowPackEnabled }, set: { store.send(.setEnglishWorkflowEnabled($0)) }))
                .frame(minHeight: 44)
            Text("Japanese workflow packs")
                .font(.headline)
            ForEach(JapaneseWorkflowPack.allCases, id: \.self) { pack in
                Toggle(isOn: Binding(get: { store.settings.isEnabled(pack) }, set: { store.send(.setPackEnabled(pack, $0)) })) {
                    Label(pack.rawValue, systemImage: pack.icon)
                }
                .frame(minHeight: 44)
            }
            Text("各packは端末内の型付きfixtureです。IME変換、LLM、外部送信は実装していません。高信頼entityは変換前後で保護します。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ローカルpreview")
                .font(.title3.weight(.semibold))
            TextField("入力例", text: $previewText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .accessibilityLabel("workflow preview入力")
            Picker("pack", selection: $selectedPack) {
                ForEach(JapaneseWorkflowPack.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(minHeight: 44)
            Button("previewを実行") {
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
