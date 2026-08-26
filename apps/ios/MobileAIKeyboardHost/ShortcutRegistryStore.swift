import Combine
import Foundation
import MobileAIKeyboardCore

struct ShortcutSkillOption: Identifiable, Equatable {
    let id: String
    let versionID: String
    let version: Int
    let digest: String
    let name: String
    let description: String
    let icon: String
    let inputSources: [ShortcutSource]
    let route: ShortcutExecutionRoute

    /// A host handoff is not executable from the keyboard extension yet. Keep it
    /// visible only as an explicit roadmap item; never let it reach assignment.
    var isAssignable: Bool { route == .keyboardLocal }

    var projection: ShortcutSkillProjectionV1 {
        ShortcutSkillProjectionV1(id: id, versionID: versionID, skillVersion: version, skillDigest: digest, name: name, description: description, inputSources: inputSources, executionRoute: route)
    }
}

enum ShortcutRegistryError: Error, LocalizedError, Equatable {
    case skillUnavailable
    case keyOccupied(String)
    case invalidSnapshot(String)
    case persistenceUnavailable

    var errorDescription: String? {
        switch self {
        case .skillUnavailable: return "このSkillは現在利用できません。"
        case .keyOccupied(let name): return "このキーは「\(name)」に割り当て済みです。先に再割り当てを選んでください。"
        case .invalidSnapshot(let reason): return "設定を保存できませんでした: \(reason)"
        case .persistenceUnavailable: return "この端末では共有設定を保存できませんでした。通常入力は影響を受けません。"
        }
    }
}

/// Host-only authority for physical Skill Keys. The extension never gets a
/// mutation API; it reads the sanitized snapshot as an immutable projection.
@MainActor
final class ShortcutRegistryStore: ObservableObject {
    @Published private(set) var snapshot: ShortcutSnapshotV1
    @Published private(set) var statusMessage: String
    let skills: [ShortcutSkillOption]
    private let storage: AppGroupShortcutSnapshotStore
    // Opaque IDs follow the shared contract shape; they contain no email or
    // account credential and remain device-local until authenticated sync is
    // implemented.
    private let deviceID = "dev_local_device_0001"
    private let userID = "usr_local_device_0001"

    init(storage: AppGroupShortcutSnapshotStore = AppGroupShortcutSnapshotStore()) {
        self.storage = storage
        let loaded = storage.loadLastKnownGood()
        snapshot = loaded ?? ShortcutSnapshotV1.empty(deviceID: "dev_local_device_0001", userID: "usr_local_device_0001")
        statusMessage = loaded == nil ? "この端末だけの安全な既定値" : (storage.isUsingSharedAppGroup ? "キーボードと共有済み" : "App Group未設定のためhost内fallback")
        skills = Self.fixtureSkills
    }

    var activeBindings: [ShortcutBindingV1] { snapshot.bindings.filter(\.enabled) }
    var assignableSkills: [ShortcutSkillOption] { skills.filter(\.isAssignable) }
    var unavailableSkills: [ShortcutSkillOption] { skills.filter { !$0.isAssignable } }
    var assignedKeyCount: Int { activeBindings.count }

    func binding(for key: ShortcutKeyCode) -> ShortcutBindingV1? {
        activeBindings.first { $0.keyCode == key }
    }

    func skill(for binding: ShortcutBindingV1) -> ShortcutSkillOption? {
        skills.first { $0.id == binding.skillID && $0.versionID == binding.versionID }
    }

    func assign(skillID: String, key: ShortcutKeyCode) throws {
        guard let skill = skills.first(where: { $0.id == skillID }) else { throw ShortcutRegistryError.skillUnavailable }
        guard skill.isAssignable else { throw ShortcutRegistryError.skillUnavailable }
        let now = Date()
        let binding = ShortcutBindingV1(id: "bind_\(UUID().uuidString)", userID: userID, deviceID: deviceID, skillID: skill.id, versionID: skill.versionID, skillVersion: skill.version, skillDigest: skill.digest, keyCode: key, presentation: ShortcutPresentation(iconValue: skill.icon, shortLabel: skill.name, accessibilityLabel: "\(key.displayLabel)、\(skill.name)", accessibilityHint: "長押しで\(skill.name)を実行", tintToken: .accent), executionRoute: skill.route, createdAt: now, updatedAt: now)
        do {
            let nextBindings = try ShortcutRegistryMutation.assign(bindings: snapshot.bindings, binding: binding)
            try publish(bindings: nextBindings, skills: skills(for: nextBindings, adding: skill.projection), revision: snapshot.layout.revision + 1)
        } catch { throw registryError(for: error) }
    }

    func reassign(bindingID: String, to key: ShortcutKeyCode) throws {
        guard let old = snapshot.bindings.first(where: { $0.id == bindingID }), let oldSkill = skill(for: old), oldSkill.isAssignable else { throw ShortcutRegistryError.skillUnavailable }
        do {
            let nextBindings = try ShortcutRegistryMutation.move(bindings: snapshot.bindings, bindingID: bindingID, to: key)
            try publish(bindings: nextBindings, skills: snapshot.skills, revision: snapshot.layout.revision + 1)
        } catch { throw registryError(for: error) }
    }

    /// Explicitly replace the binding occupying `key` with a new Skill.
    func replace(skillID: String, key: ShortcutKeyCode) throws {
        guard let skill = skills.first(where: { $0.id == skillID }), skill.isAssignable else { throw ShortcutRegistryError.skillUnavailable }
        let now = Date()
        let binding = ShortcutBindingV1(id: "bind_\(UUID().uuidString)", userID: userID, deviceID: deviceID, skillID: skill.id, versionID: skill.versionID, skillVersion: skill.version, skillDigest: skill.digest, keyCode: key, presentation: ShortcutPresentation(iconValue: skill.icon, shortLabel: skill.name, accessibilityLabel: "\(key.displayLabel)、\(skill.name)", accessibilityHint: "長押しで\(skill.name)を実行", tintToken: .accent), executionRoute: skill.route, createdAt: now, updatedAt: now)
        do {
            let nextBindings = try ShortcutRegistryMutation.replace(bindings: snapshot.bindings, binding: binding)
            try publish(bindings: nextBindings, skills: skills(for: nextBindings, adding: skill.projection), revision: snapshot.layout.revision + 1)
        } catch { throw registryError(for: error) }
    }

    /// Explicitly swap an existing Skill Key with the owner of `key`.
    func swap(bindingID: String, to key: ShortcutKeyCode) throws {
        guard let old = snapshot.bindings.first(where: { $0.id == bindingID }), let oldSkill = skill(for: old), oldSkill.isAssignable else { throw ShortcutRegistryError.skillUnavailable }
        do {
            let nextBindings = try ShortcutRegistryMutation.swap(bindings: snapshot.bindings, bindingID: bindingID, to: key)
            try publish(bindings: nextBindings, skills: snapshot.skills, revision: snapshot.layout.revision + 1)
        } catch { throw registryError(for: error) }
    }

    /// Explicitly remove the current owner of `key` and move the selected key.
    func replace(bindingID: String, to key: ShortcutKeyCode) throws {
        guard let old = snapshot.bindings.first(where: { $0.id == bindingID }), let oldSkill = skill(for: old), oldSkill.isAssignable else { throw ShortcutRegistryError.skillUnavailable }
        do {
            let nextBindings = try ShortcutRegistryMutation.replace(bindings: snapshot.bindings, bindingID: bindingID, to: key)
            try publish(bindings: nextBindings, skills: skills(for: nextBindings), revision: snapshot.layout.revision + 1)
        } catch { throw registryError(for: error) }
    }

    func setEnabled(bindingID: String, enabled: Bool) throws {
        guard let old = snapshot.bindings.first(where: { $0.id == bindingID }) else { throw ShortcutRegistryError.skillUnavailable }
        if enabled, let oldSkill = skill(for: old), !oldSkill.isAssignable { throw ShortcutRegistryError.skillUnavailable }
        let updated = ShortcutBindingV1(id: old.id, userID: old.userID, deviceID: old.deviceID, skillID: old.skillID, versionID: old.versionID, skillVersion: old.skillVersion, skillDigest: old.skillDigest, keyCode: old.keyCode, presentation: old.presentation, enabled: enabled, executionRoute: old.executionRoute, requiredConnectionIDs: old.requiredConnectionIDs, createdAt: old.createdAt, updatedAt: Date())
        try publish(bindings: snapshot.bindings.map { $0.id == bindingID ? updated : $0 }, skills: snapshot.skills, revision: snapshot.layout.revision + 1)
    }

    func remove(bindingID: String) throws {
        let bindings = snapshot.bindings.filter { $0.id != bindingID }
        guard bindings.count != snapshot.bindings.count else { throw ShortcutRegistryError.skillUnavailable }
        let referenced = Set(bindings.map { "\($0.skillID)|\($0.versionID)" })
        let skills = snapshot.skills.filter { referenced.contains("\($0.id)|\($0.versionID)") }
        try publish(bindings: bindings, skills: skills, revision: snapshot.layout.revision + 1)
    }

    func refresh() {
        guard let loaded = storage.loadLastKnownGood() else { return }
        snapshot = loaded
        statusMessage = storage.isUsingSharedAppGroup ? "キーボードと共有済み" : "App Group未設定のためhost内fallback"
    }

#if DEBUG
    func seedQAStateIfNeeded() {
        guard activeBindings.isEmpty else { return }
        try? assign(skillID: "skill_polite_local_v1", key: .keyH)
        try? assign(skillID: "skill_punctuation_local_v1", key: .keyM)
    }
#endif

    private func publish(bindings: [ShortcutBindingV1], skills: [ShortcutSkillProjectionV1], revision: Int) throws {
        let activeIDs = bindings.filter(\.enabled).map(\.id)
        let layout = ShortcutLayoutV1(id: snapshot.layout.id, userID: userID, deviceID: deviceID, revision: revision, keyBindingIDs: activeIDs, paletteBindingIDs: activeIDs)
        let next = ShortcutSnapshotV1(id: "ss_\(UUID().uuidString)", generation: snapshot.generation + 1, userSubjectHash: snapshot.userSubjectHash, deviceID: deviceID, layout: layout, bindings: bindings, skills: skills, connectionStates: snapshot.connectionStates, policyEpoch: snapshot.policyEpoch, createdAt: Date(), expiresAt: nil).withComputedDigest()
        do {
            try ShortcutSnapshotValidator.validate(next, lastGeneration: snapshot.generation, expectedDeviceID: deviceID)
            try storage.publish(next)
        } catch let error as ShortcutStoreError {
            throw ShortcutRegistryError.invalidSnapshot(error.localizedDescription)
        } catch let error as ShortcutValidationError {
            throw ShortcutRegistryError.invalidSnapshot(error.localizedDescription)
        } catch {
            throw ShortcutRegistryError.persistenceUnavailable
        }
        snapshot = next
        statusMessage = storage.isUsingSharedAppGroup ? "\(activeIDs.count)個のSkill Keyをキーボードと共有済み" : "\(activeIDs.count)個をhost内fallbackに保存。App Group同期は未証明"
    }

    private func skills(for bindings: [ShortcutBindingV1], adding skill: ShortcutSkillProjectionV1? = nil) -> [ShortcutSkillProjectionV1] {
        var projections = snapshot.skills.filter { projection in
            bindings.contains { $0.skillID == projection.id && $0.versionID == projection.versionID }
        }
        if let skill, !projections.contains(where: { $0.id == skill.id && $0.versionID == skill.versionID }) {
            projections.append(skill)
        }
        return projections
    }

    private func registryError(for error: Error) -> ShortcutRegistryError {
        guard let mutationError = error as? ShortcutRegistryMutationError else {
            return (error as? ShortcutRegistryError) ?? .persistenceUnavailable
        }
        switch mutationError {
        case .keyOccupied(let key):
            let name = binding(for: key).flatMap { skill(for: $0)?.name } ?? key.displayLabel
            return .keyOccupied(name)
        case .hostHandoffUnavailable, .bindingNotFound:
            return .skillUnavailable
        case .keyIsAvailable, .bindingIDAlreadyExists:
            return .invalidSnapshot("この競合解決は現在の割り当てと一致しません")
        }
    }

    static let fixtureSkills: [ShortcutSkillOption] = [
        ShortcutSkillOption(id: "skill_polite_local_v1", versionID: "sv_polite_local_1", version: 1, digest: ShortcutDigest.sha256("skill_polite_local:v1"), name: "丁寧に整える", description: "選択した文章のトーンを丁寧に整えます。", icon: "text.badge.checkmark", inputSources: [.selection, .surroundingText], route: .keyboardLocal),
        ShortcutSkillOption(id: "skill_punctuation_local_v1", versionID: "sv_punctuation_local_1", version: 1, digest: ShortcutDigest.sha256("skill_punctuation_local:v1"), name: "句読点を整える", description: "空白と句読点を端末内で読みやすく整えます。", icon: "text.alignleft", inputSources: [.selection, .surroundingText], route: .keyboardLocal),
        ShortcutSkillOption(id: "skill_calendar_local_v1", versionID: "sv_calendar_local_1", version: 1, digest: ShortcutDigest.sha256("skill_calendar_local:v1"), name: "空き時間を探す", description: "接続済みカレンダーの読み取りレビューを開きます。", icon: "calendar", inputSources: [.command, .currentDateTime], route: .hostHandoff)
    ]
}
