import SwiftUI
import MobileAIKeyboardCore

struct SkillKeysView: View {
    @EnvironmentObject private var registry: ShortcutRegistryStore
    @State private var selectedSkill: ShortcutSkillOption?
    @State private var editingBinding: ShortcutBindingV1?
    @State private var errorMessage: String?
    @State private var searchText = ""

    private let background = Color(red: 0.945, green: 0.961, blue: 0.984)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                keyboardPreview
                assignedSection
                availableSection
                unavailableSection
                boundaryCard
            }
            .padding()
        }
        .background(background.ignoresSafeArea())
        .preferredColorScheme(.light)
        .navigationTitle("Skill Keys")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Skillを検索")
        .sheet(item: $selectedSkill) { skill in
            TriggerKeySheet(skill: skill, existingBinding: nil)
                .environmentObject(registry)
        }
        .sheet(item: $editingBinding) { binding in
            if let skill = registry.skill(for: binding) {
                TriggerKeySheet(skill: skill, existingBinding: binding)
                    .environmentObject(registry)
            }
        }
        .alert("保存できませんでした", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("閉じる", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .onAppear {
            registry.refresh()
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-skill-keys-qa") || ProcessInfo.processInfo.arguments.contains("-trigger-key-sheet-qa") {
                registry.seedQAStateIfNeeded()
            }
            if ProcessInfo.processInfo.arguments.contains("-trigger-key-sheet-qa") {
                selectedSkill = registry.skills.first { $0.id == "skill_punctuation_local_v1" }
            }
#endif
        }
    }

    private var keyboardPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 6) {
                ForEach(Array(OrdinaryKeyboardLayout.letterRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 5) {
                        ForEach(Array(row), id: \.self) { character in
                            let key = ShortcutKeyCode(displayLabel: String(character))
                            Text(String(character).uppercased())
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(registry.binding(for: key ?? .keyA) == nil ? Color.white : Color.cyan.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
                                .overlay(alignment: .bottom) {
                                    if let key, registry.binding(for: key) != nil { Capsule().fill(.cyan).frame(height: 2).padding(.horizontal, 5).padding(.bottom, 2) }
                                }
                                .accessibilityLabel(key.flatMap { registry.binding(for: $0).flatMap { "\($0.keyCode.displayLabel)、\(registry.skill(for: $0)?.name ?? "Skill")" } } ?? String(character))
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            Text("タップ = 通常入力 / 長押し = Skill").font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var assignedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Skill Keys").font(.title3.weight(.bold))
            if registry.activeBindings.isEmpty {
                Text("まだキーがありません。下のSkillから追加できます。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(registry.activeBindings) { binding in
                let skill = registry.skill(for: binding)
                let isRunnable = skill?.isAssignable == true
                Button { editingBinding = binding } label: {
                    HStack(spacing: 12) {
                        Text(binding.keyCode.displayLabel)
                            .font(.headline)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(Color.cyan.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(skill?.name ?? binding.skillID).font(.headline)
                            Text(isRunnable ? "長押しで実行 · v\(binding.skillVersion)" : "準備中・割り当て不可 · v\(binding.skillVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("\(binding.keyCode.displayLabel)、\(skill?.name ?? binding.skillID)、\(isRunnable ? "長押しで実行" : "準備中・割り当て不可")")
                .accessibilityHint(isRunnable ? "再割り当てまたは削除" : "削除して割り当てを解除")
            }
        }
    }

    private var availableSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Skillを追加").font(.title3.weight(.bold))
            if filteredAssignableSkills.isEmpty {
                Text(searchText.isEmpty ? "追加できるSkillはありません。" : "「\(searchText)」に一致するSkillはありません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(filteredAssignableSkills) { skill in
                let installed = registry.snapshot.bindings.contains { $0.skillID == skill.id && $0.enabled }
                Button { selectedSkill = skill } label: {
                    HStack(spacing: 12) {
                        Image(systemName: skill.icon).font(.title3).foregroundStyle(.cyan).frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(skill.name).font(.headline)
                            Text(skill.description).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(installed ? "設定済み" : "追加")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(installed ? .secondary : .primary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .disabled(installed)
                .buttonStyle(.plain)
                .accessibilityIdentifier("skill-option-\(skill.id)")
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var filteredAssignableSkills: [ShortcutSkillOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return registry.assignableSkills }
        return registry.assignableSkills.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query)
        }
    }

    private var unavailableSection: some View {
        Group {
            if !registry.unavailableSkills.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("準備中のSkill")
                        .font(.title3.weight(.bold))
                    ForEach(registry.unavailableSkills) { skill in
                        HStack(spacing: 12) {
                            Image(systemName: skill.icon)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(skill.name).font(.headline)
                                Text("Host handoffはまだキーボードから実行できません。割り当て不可")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("準備中")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(skill.name)。Host handoffはまだ実行できないため、割り当てできません")
                    }
                }
            }
        }
    }

    private var boundaryCard: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("安全な同期境界").font(.headline)
                Text("\(registry.statusMessage)。iOSではSkill Keysの共有にフルアクセスが必要ですが、通常入力には不要です。共有するのはキー、Skillのversion/digest、表示名だけで、入力内容・prompt・token・資格情報は保存しません。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "lock.shield").foregroundStyle(.cyan)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

private struct TriggerKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var registry: ShortcutRegistryStore
    let skill: ShortcutSkillOption
    let existingBinding: ShortcutBindingV1?
    @State private var selectedKey: ShortcutKeyCode?
    @State private var errorMessage: String?
    @State private var fixtureInput = "田中さんへ。よろしくお願いいたします。"
    @State private var fixtureOutput: String?
    @State private var fixtureHasRun = false
    @State private var conflictDialogPresented = false
    @State private var successMessage: String?

    init(skill: ShortcutSkillOption, existingBinding: ShortcutBindingV1?) {
        self.skill = skill
        self.existingBinding = existingBinding
        _selectedKey = State(initialValue: existingBinding?.keyCode)
    }

    private let keys = Array("qwertyuiopasdfghjklzxcvbnm")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(existingBinding == nil ? "キーを選ぶ" : "キーを再割り当て")
                            .font(.title2.weight(.bold))
                        Text("「\(skill.name)」を長押しで呼び出すキー")
                            .foregroundStyle(.secondary)
                    }
                    keyGrid
                    if let selectedKey {
                        Label("選択中: \(selectedKey.displayLabel)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.cyan)
                        if let conflict = registry.binding(for: selectedKey), conflict.id != existingBinding?.id {
                            Text("このキーは「\(registry.skill(for: conflict)?.name ?? "別のSkill")」が使用中です。保存時に入れ替えまたは置き換えを選べます。")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                    fixturePreview
                    Text("通常のタップでは必ず \(selectedKey?.displayLabel ?? "文字") を入力します。長押しの実行前には内容を確認します。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                    if existingBinding != nil {
                        Button("このSkill Keyを削除", role: .destructive) {
                            do { try registry.remove(bindingID: existingBinding!.id); dismiss() }
                            catch { errorMessage = error.localizedDescription }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding()
            }
            .accessibilityIdentifier("trigger-key-scroll")
            .background(Color(red: 0.945, green: 0.961, blue: 0.984).ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button(fixtureHasRun ? "もう一度テスト実行" : "端末内でテスト実行") {
                        runFixture()
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.cyan.opacity(0.16), in: Capsule())
                    .accessibilityIdentifier("run-local-fixture")
                    Button(existingBinding == nil ? "Add" : "再割り当て") { saveSelection() }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(canSave ? Color.black : Color.gray, in: Capsule())
                        .disabled(!canSave)
                        .accessibilityIdentifier(existingBinding == nil ? "save-skill-key" : "save-skill-key-reassignment")
                    Button("キャンセル") { dismiss() }
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(.white, in: Capsule())
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Trigger Key")
            .navigationBarTitleDisplayMode(.inline)
            .alert("割り当てを保存しました", isPresented: Binding(get: { successMessage != nil }, set: { if !$0 { successMessage = nil } })) {
                Button("完了") { dismiss() }
            } message: {
                Text(successMessage ?? "")
            }
            .confirmationDialog("このキーは使用中です", isPresented: $conflictDialogPresented, titleVisibility: .visible) {
                if existingBinding != nil {
                    Button("入れ替える") { resolveConflict(.swap) }
                    Button("置き換える", role: .destructive) { resolveConflict(.replace) }
                } else {
                    Button("置き換える", role: .destructive) { resolveConflict(.replace) }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この操作を明示的に選んだ場合だけ、現在の割り当てを変更します。")
            }
            .onChange(of: selectedKey) { _ in
                fixtureHasRun = false
                fixtureOutput = nil
            }
        }
    }

    private var canSave: Bool {
        guard selectedKey != nil, fixtureHasRun else { return false }
        return true
    }

    private func saveSelection() {
        guard let selectedKey else { return }
        do {
            if let existingBinding { try registry.reassign(bindingID: existingBinding.id, to: selectedKey) }
            else { try registry.assign(skillID: skill.id, key: selectedKey) }
            successMessage = "\(selectedKey.displayLabel)キーに「\(skill.name)」を割り当てました。"
        } catch let error as ShortcutRegistryError {
            if case .keyOccupied = error { conflictDialogPresented = true }
            else { errorMessage = error.localizedDescription }
        } catch { errorMessage = error.localizedDescription }
    }

    private enum ConflictResolution { case swap, replace }

    private func resolveConflict(_ resolution: ConflictResolution) {
        guard let selectedKey else { return }
        do {
            if let existingBinding {
                switch resolution {
                case .swap: try registry.swap(bindingID: existingBinding.id, to: selectedKey)
                case .replace: try registry.replace(bindingID: existingBinding.id, to: selectedKey)
                }
            } else {
                try registry.replace(skillID: skill.id, key: selectedKey)
            }
            successMessage = "\(selectedKey.displayLabel)キーの割り当てを更新しました。"
        } catch { errorMessage = error.localizedDescription }
    }

    private var fixturePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("保存前に端末内で確認", systemImage: "checkmark.shield")
                .font(.headline)
            Text("外部送信なしのfixtureを実行し、結果を確認してから保存できます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextEditor(text: $fixtureInput)
                .font(.body)
                .frame(minHeight: 72)
                .padding(8)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08)))
                .accessibilityLabel("fixture入力")
            if let fixtureOutput {
                VStack(alignment: .leading, spacing: 4) {
                    Label("テスト成功", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.weight(.semibold))
                    Text(fixtureOutput)
                        .font(.body)
                        .textSelection(.enabled)
                    Text("端末内fixture・外部送信なし")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("fixture-success")
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .onChange(of: fixtureInput) { _ in
            fixtureHasRun = false
            fixtureOutput = nil
        }
    }

    private func runFixture() {
        let output: String?
        if let pack = fixturePack {
            output = JapaneseWorkflowEngine().transform(fixtureInput, pack: pack)?.rewritten
        } else {
            // Private candidates use the same closed local executor as the
            // extension. Their free-form description is never evaluated.
            output = LocalSkillExecutor.execute(skill.projection, input: fixtureInput)?.rewritten
        }
        guard let output else {
            fixtureHasRun = false
            fixtureOutput = nil
            errorMessage = "fixtureを実行できませんでした。入力を確認してください。"
            return
        }
        fixtureHasRun = true
        fixtureOutput = output
    }

    private var fixturePack: JapaneseWorkflowPack? {
        switch skill.id {
        case "skill_polite_local_v1": return .polite
        case "skill_punctuation_local_v1": return .keyPoints
        default: return nil
        }
    }

    private var keyGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
            ForEach(keys, id: \.self) { character in
                let key = ShortcutKeyCode(displayLabel: String(character))!
                let conflict = registry.binding(for: key)
                let isSelected = selectedKey == key
                Button { selectedKey = key } label: {
                    Text(key.displayLabel)
                        .font(.headline)
                        .frame(minWidth: 44, minHeight: 52)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? Color.cyan.opacity(0.26) : Color.white, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(isSelected ? Color.cyan : Color.clear, lineWidth: 2))
                }
                .accessibilityLabel(conflict.map { "\(key.displayLabel)、\(registry.skill(for: $0)?.name ?? "割り当て済み")" } ?? "\(key.displayLabel)、空き")
                .accessibilityValue(isSelected ? (conflict == nil || conflict?.id == existingBinding?.id ? "選択中" : "選択中、保存時に競合解決が必要") : (conflict == nil || conflict?.id == existingBinding?.id ? "利用可能" : "割り当て済み。選択して置き換えまたは入れ替え"))
                .accessibilityIdentifier("trigger-key-\(key.displayLabel.lowercased())")
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}
