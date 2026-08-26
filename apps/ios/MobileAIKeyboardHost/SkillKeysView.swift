import SwiftUI
import MobileAIKeyboardCore

struct SkillKeysView: View {
    @EnvironmentObject private var registry: ShortcutRegistryStore
    @State private var selectedSkill: ShortcutSkillOption?
    @State private var editingBinding: ShortcutBindingV1?
    @State private var errorMessage: String?

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
            ForEach(registry.assignableSkills) { skill in
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
                }
                .disabled(installed)
                .buttonStyle(.plain)
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
            }
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
                    }
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
            .background(Color(red: 0.945, green: 0.961, blue: 0.984).ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button(existingBinding == nil ? "Add" : "再割り当て") { saveSelection() }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(canSave ? Color.black : Color.gray, in: Capsule())
                        .disabled(!canSave)
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
        }
    }

    private var canSave: Bool {
        guard let selectedKey else { return false }
        guard let conflict = registry.binding(for: selectedKey) else { return true }
        return conflict.id == existingBinding?.id
    }

    private func saveSelection() {
        guard let selectedKey else { return }
        do {
            if let existingBinding { try registry.reassign(bindingID: existingBinding.id, to: selectedKey) }
            else { try registry.assign(skillID: skill.id, key: selectedKey) }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
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
                .disabled(conflict != nil && conflict?.id != existingBinding?.id)
                .accessibilityLabel(conflict.map { "\(key.displayLabel)、\(registry.skill(for: $0)?.name ?? "割り当て済み")" } ?? "\(key.displayLabel)、空き")
                .accessibilityValue(isSelected ? "選択中" : (conflict == nil || conflict?.id == existingBinding?.id ? "利用可能" : "利用不可"))
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}
