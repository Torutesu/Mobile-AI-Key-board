import Combine
import Foundation
import MobileAIKeyboardCore

struct ShortcutSkillOption: Identifiable, Equatable, Codable {
    let id: String
    let versionID: String
    let version: Int
    let digest: String
    let name: String
    let description: String
    let icon: String
    let inputSources: [ShortcutSource]
    let toolSummaries: [ShortcutToolSummary]
    let route: ShortcutExecutionRoute

    /// A host handoff is not executable from the keyboard extension yet. Keep it
    /// visible only as an explicit roadmap item; never let it reach assignment.
    var isAssignable: Bool { route == .keyboardLocal }

    var projection: ShortcutSkillProjectionV1 {
        ShortcutSkillProjectionV1(id: id, versionID: versionID, skillVersion: version, skillDigest: digest, name: name, description: description, inputSources: inputSources, toolSummaries: toolSummaries, executionRoute: route)
    }
}

enum ShortcutRegistryError: Error, LocalizedError, Equatable {
    case accountBoundaryUnavailable
    case skillUnavailable
    case keyOccupied(String)
    case invalidSnapshot(String)
    case persistenceUnavailable

    var errorDescription: String? {
        switch self {
        case .accountBoundaryUnavailable: return "Skill Keyのアカウント境界が有効ではありません。"
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
    @Published private(set) var skills: [ShortcutSkillOption]
    private let storage: AppGroupShortcutSnapshotStore
    private let candidateDefaults: UserDefaults
    private static let candidateStorageKey = "mobile-ai-keyboard.private-skill-candidates.v1"
    // Opaque IDs follow the shared contract shape; they contain no email or
    // account credential and remain device-local until authenticated sync is
    // implemented.
    private let deviceID = ShortcutDeviceIdentity.localFixtureID
    private let userID = "usr_local_device_0001"
    private var ownerSubjectHash: String?
    private var sessionEpoch: Int?

    init(storage: AppGroupShortcutSnapshotStore = AppGroupShortcutSnapshotStore(), candidateDefaults: UserDefaults = .standard) {
        self.storage = storage
        self.candidateDefaults = candidateDefaults
        let boundary = storage.loadActiveBoundary()
        let loaded = storage.loadLastKnownGood()
        ownerSubjectHash = boundary?.ownerSubjectHash
        sessionEpoch = boundary?.sessionEpoch
        snapshot = loaded ?? ShortcutSnapshotV1.empty(deviceID: ShortcutDeviceIdentity.localFixtureID, userID: "usr_local_device_0001")
        statusMessage = loaded == nil ? "この端末だけの安全な既定値" : (storage.isUsingSharedAppGroup ? "キーボードと共有済み" : "App Group未確認のためSkill Key登録を停止")
        // Unassigned candidates persist as host-only metadata and digest. Only
        // an assigned projection enters the extension's validated snapshot.
        let persisted = loaded?.skills.compactMap(Self.skillOption(from:)) ?? []
        let candidates = Self.loadPrivateCandidates(from: candidateDefaults)
        skills = Self.fixtureSkills + Self.mergingPrivateSkills(persisted + candidates)
    }

    var activeBindings: [ShortcutBindingV1] { snapshot.bindings.filter(\.enabled) }
    var allBindings: [ShortcutBindingV1] { snapshot.bindings }
    var assignableSkills: [ShortcutSkillOption] { skills.filter(\.isAssignable) }
    var unavailableSkills: [ShortcutSkillOption] { skills.filter { !$0.isAssignable } }
    var assignedKeyCount: Int { activeBindings.count }
    var canPublishToKeyboard: Bool { storage.isUsingSharedAppGroup || isUITestFallbackEnabled }

    func binding(for key: ShortcutKeyCode) -> ShortcutBindingV1? {
        activeBindings.first { $0.keyCode == key }
    }

    func skill(for binding: ShortcutBindingV1) -> ShortcutSkillOption? {
        skills.first { $0.id == binding.skillID && $0.versionID == binding.versionID }
    }

    func assign(skillID: String, key: ShortcutKeyCode) throws {
        try requireActiveBoundary()
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
        try requireActiveBoundary()
        guard let old = snapshot.bindings.first(where: { $0.id == bindingID }), let oldSkill = skill(for: old), oldSkill.isAssignable else { throw ShortcutRegistryError.skillUnavailable }
        do {
            let nextBindings = try ShortcutRegistryMutation.move(bindings: snapshot.bindings, bindingID: bindingID, to: key)
            try publish(bindings: nextBindings, skills: snapshot.skills, revision: snapshot.layout.revision + 1)
        } catch { throw registryError(for: error) }
    }

    /// Explicitly replace the binding occupying `key` with a new Skill.
    func replace(skillID: String, key: ShortcutKeyCode) throws {
        try requireActiveBoundary()
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
        try requireActiveBoundary()
        guard let old = snapshot.bindings.first(where: { $0.id == bindingID }), let oldSkill = skill(for: old), oldSkill.isAssignable else { throw ShortcutRegistryError.skillUnavailable }
        do {
            let nextBindings = try ShortcutRegistryMutation.swap(bindings: snapshot.bindings, bindingID: bindingID, to: key)
            try publish(bindings: nextBindings, skills: snapshot.skills, revision: snapshot.layout.revision + 1)
        } catch { throw registryError(for: error) }
    }

    /// Explicitly remove the current owner of `key` and move the selected key.
    func replace(bindingID: String, to key: ShortcutKeyCode) throws {
        try requireActiveBoundary()
        guard let old = snapshot.bindings.first(where: { $0.id == bindingID }), let oldSkill = skill(for: old), oldSkill.isAssignable else { throw ShortcutRegistryError.skillUnavailable }
        do {
            let nextBindings = try ShortcutRegistryMutation.replace(bindings: snapshot.bindings, bindingID: bindingID, to: key)
            try publish(bindings: nextBindings, skills: skills(for: nextBindings), revision: snapshot.layout.revision + 1)
        } catch { throw registryError(for: error) }
    }

    func setEnabled(bindingID: String, enabled: Bool) throws {
        try requireActiveBoundary()
        guard let old = snapshot.bindings.first(where: { $0.id == bindingID }) else { throw ShortcutRegistryError.skillUnavailable }
        if enabled, let oldSkill = skill(for: old), !oldSkill.isAssignable { throw ShortcutRegistryError.skillUnavailable }
        let updated = ShortcutBindingV1(id: old.id, userID: old.userID, deviceID: old.deviceID, skillID: old.skillID, versionID: old.versionID, skillVersion: old.skillVersion, skillDigest: old.skillDigest, keyCode: old.keyCode, presentation: old.presentation, enabled: enabled, executionRoute: old.executionRoute, requiredConnectionIDs: old.requiredConnectionIDs, createdAt: old.createdAt, updatedAt: Date())
        try publish(bindings: snapshot.bindings.map { $0.id == bindingID ? updated : $0 }, skills: snapshot.skills, revision: snapshot.layout.revision + 1)
    }

    func remove(bindingID: String) throws {
        try requireActiveBoundary()
        let bindings = snapshot.bindings.filter { $0.id != bindingID }
        guard bindings.count != snapshot.bindings.count else { throw ShortcutRegistryError.skillUnavailable }
        let referenced = Set(bindings.map { "\($0.skillID)|\($0.versionID)" })
        let skills = snapshot.skills.filter { referenced.contains("\($0.id)|\($0.versionID)") }
        try publish(bindings: bindings, skills: skills, revision: snapshot.layout.revision + 1)
    }

    func refresh() {
        guard let loaded = storage.loadLastKnownGood() else {
            ownerSubjectHash = storage.loadActiveBoundary()?.ownerSubjectHash
            sessionEpoch = storage.loadActiveBoundary()?.sessionEpoch
            snapshot = ShortcutSnapshotV1.empty(deviceID: deviceID, userID: userID)
            skills = Self.fixtureSkills + Self.loadPrivateCandidates(from: candidateDefaults)
            statusMessage = "有効なSkill Key境界がありません。登録状態を閉じました"
            return
        }
        // Keep host-persisted candidates until the user assigns them. They do
        // not enter the extension's executable snapshot before assignment.
        let unassignedCandidates = skills.filter { candidate in
            candidate.id.hasPrefix("skill_private_") &&
            !loaded.skills.contains { $0.id == candidate.id && $0.versionID == candidate.versionID }
        }
        snapshot = loaded
        let persisted = loaded.skills.compactMap(Self.skillOption(from:))
        let restored = persisted.filter { option in !Self.fixtureSkills.contains { $0.id == option.id && $0.versionID == option.versionID } }
        skills = Self.fixtureSkills + restored + unassignedCandidates.filter { candidate in
            !Self.fixtureSkills.contains { $0.id == candidate.id && $0.versionID == candidate.versionID } &&
            !restored.contains { $0.id == candidate.id && $0.versionID == candidate.versionID }
        }
        persistPrivateCandidates()
        statusMessage = storage.isUsingSharedAppGroup ? "キーボードと共有済み" : "App Group未確認のためSkill Key登録を停止"
    }

    /// Changes the executable authority before any new owner state is exposed.
    /// A valid previous snapshot therefore becomes unreadable to the extension
    /// immediately, even if later cleanup is interrupted.
    func activateOwner(subject: String) throws {
        let ownerHash = ShortcutDigest.sha256("shortcut-owner-v1:\(subject)")
        let wasSameOwner = ownerSubjectHash == ownerHash && sessionEpoch != nil
        let boundary = try storage.activateBoundary(ownerSubjectHash: ownerHash)
        ownerSubjectHash = ownerHash
        sessionEpoch = boundary.sessionEpoch
        if wasSameOwner, storage.loadLastKnownGood() != nil {
            refresh()
            return
        }
        // Seal the old executable generation. The boundary already points at
        // the new owner, so a crash here is closed rather than cross-account.
        try storage.publishTombstone(reason: .signedOut, deviceID: deviceID, userID: userID)
        let generation = storage.latestKnownGeneration()
        snapshot = ShortcutSnapshotV1(
            id: "ss_\(UUID().uuidString)",
            generation: generation,
            userSubjectHash: ownerHash,
            deviceID: deviceID,
            layout: ShortcutLayoutV1(id: "layout_\(UUID().uuidString)", userID: userID, deviceID: deviceID, revision: 0, keyBindingIDs: []),
            bindings: [],
            skills: [],
            policyEpoch: boundary.sessionEpoch
        ).withComputedDigest()
        skills = Self.fixtureSkills
        persistPrivateCandidates()
        statusMessage = "新しいアカウント境界でSkill Keysを開始しました"
    }

    func deactivateOwner(reason: ShortcutTombstoneReason = .signedOut) throws {
        if ownerSubjectHash == nil, storage.loadActiveBoundary() == nil { return }
        // Close through two independent persisted paths. A tombstone advances
        // the revocation floor; an inactive boundary removes owner authority.
        // Attempt both even if one App Group write fails.
        var closureErrors: [Error] = []
        do { try storage.publishTombstone(reason: reason, deviceID: deviceID, userID: userID) } catch { closureErrors.append(error) }
        do { _ = try storage.deactivateBoundary() } catch { closureErrors.append(error) }
        ownerSubjectHash = nil
        sessionEpoch = nil
        snapshot = ShortcutSnapshotV1.empty(deviceID: deviceID, userID: userID)
        skills = Self.fixtureSkills
        persistPrivateCandidates()
        statusMessage = "Skill Keyの実行権限を解除しました"
        if closureErrors.count == 2 { throw closureErrors[0] }
    }

    /// Deploy and keyboard assignment are separate actions. This only exposes
    /// an immutable, closed local executor candidate; the next step still asks
    /// the user to select an A–Z trigger in Skill Keys.
    func addPrivateSkill(_ version: PrivateSkillVersion) throws {
        try requireActiveBoundary()
        guard version.versionNumber > 0,
              version.digest.hasPrefix("sha256:"),
              version.digest.count == 71,
              !version.draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ShortcutRegistryError.skillUnavailable
        }
        let option = ShortcutSkillOption(
            id: version.skillID,
            versionID: version.id,
            version: version.versionNumber,
            digest: version.digest,
            name: version.draft.name,
            description: version.draft.plainDescription,
            icon: version.draft.icon,
            // The closed private executor only supports explicit selection. Do
            // not advertise surrounding context until range replacement is
            // implemented and independently verified.
            inputSources: [.selection],
            toolSummaries: [ShortcutToolSummary(operation: "local.text.normalize", sideEffect: "none")],
            route: .keyboardLocal
        )
        if let existing = skills.first(where: { $0.id == option.id }) {
            guard existing.versionID == option.versionID, existing.digest == option.digest else { throw ShortcutRegistryError.skillUnavailable }
            return
        }
        skills.append(option)
        persistPrivateCandidates()
        statusMessage = "「\(option.name)」をキーボード候補に追加しました。A–Zキーを割り当ててください"
    }

    /// Private builder output is account-bound even though execution is local.
    /// Losing that account boundary must remove both unassigned candidates and
    /// assigned projections so another subject cannot inherit a trigger key.
    func clearPrivateSkillsForAccountBoundary() throws {
        let privateIDs = Set(skills.filter { $0.id.hasPrefix("skill_private_") }.map(\.id))
        guard !privateIDs.isEmpty else { return }
        let retainedBindings = snapshot.bindings.filter { !privateIDs.contains($0.skillID) }
        let retainedProjections = snapshot.skills.filter { !privateIDs.contains($0.id) }
        try publish(bindings: retainedBindings, skills: retainedProjections, revision: snapshot.layout.revision + 1)
        let restored = retainedProjections.compactMap(Self.skillOption(from:))
        skills = Self.fixtureSkills + restored.filter { option in
            !Self.fixtureSkills.contains { $0.id == option.id && $0.versionID == option.versionID }
        }
        persistPrivateCandidates()
        statusMessage = "アカウント境界の変更によりPrivate Skill Keysを削除しました"
    }

#if DEBUG
    /// Deterministic host-only reset used by the Simulator UI harness. It
    /// creates a new empty validated generation rather than deleting files.
    func resetForUITest() {
        try? publish(bindings: [], skills: [], revision: snapshot.layout.revision + 1)
        skills = Self.fixtureSkills
        persistPrivateCandidates()
    }

    func seedQAStateIfNeeded() {
        guard activeBindings.isEmpty else { return }
        try? assign(skillID: "skill_polite_local_v1", key: .keyH)
        try? assign(skillID: "skill_punctuation_local_v1", key: .keyM)
    }
#endif

    private func publish(bindings: [ShortcutBindingV1], skills: [ShortcutSkillProjectionV1], revision: Int) throws {
        guard canPublishToKeyboard else {
            statusMessage = "App Groupを確認できないためSkill Keyは登録されませんでした"
            throw ShortcutRegistryError.persistenceUnavailable
        }
        try requireActiveBoundary()
        guard let ownerSubjectHash, let sessionEpoch else { throw ShortcutRegistryError.accountBoundaryUnavailable }
        let highestGeneration = max(snapshot.generation, storage.latestKnownGeneration())
        guard highestGeneration < ShortcutSnapshotValidator.maxMonotonicValue,
              revision <= ShortcutSnapshotValidator.maxMonotonicValue else {
            throw ShortcutRegistryError.invalidSnapshot(ShortcutValidationError.generation.localizedDescription)
        }
        let activeIDs = bindings.filter(\.enabled).map(\.id)
        let layout = ShortcutLayoutV1(id: snapshot.layout.id, userID: userID, deviceID: deviceID, revision: revision, keyBindingIDs: activeIDs, paletteBindingIDs: activeIDs)
        let next = ShortcutSnapshotV1(id: "ss_\(UUID().uuidString)", generation: highestGeneration + 1, userSubjectHash: ownerSubjectHash, deviceID: deviceID, layout: layout, bindings: bindings, skills: skills, connectionStates: snapshot.connectionStates, policyEpoch: sessionEpoch, createdAt: Date(), expiresAt: nil).withComputedDigest()
        do {
            try ShortcutSnapshotValidator.validate(next, lastGeneration: storage.latestKnownGeneration(), expectedDeviceID: deviceID, expectedOwnerSubjectHash: ownerSubjectHash, expectedPolicyEpoch: sessionEpoch)
            try storage.publish(next)
        } catch let error as ShortcutStoreError {
            throw ShortcutRegistryError.invalidSnapshot(error.localizedDescription)
        } catch let error as ShortcutValidationError {
            throw ShortcutRegistryError.invalidSnapshot(error.localizedDescription)
        } catch {
            throw ShortcutRegistryError.persistenceUnavailable
        }
        snapshot = next
        statusMessage = "\(activeIDs.count)個のSkill Keyをキーボードと共有済み"
    }

    private func requireActiveBoundary() throws {
        guard let ownerSubjectHash, let sessionEpoch,
              let active = storage.loadActiveBoundary(),
              active.ownerSubjectHash == ownerSubjectHash,
              active.sessionEpoch == sessionEpoch else { throw ShortcutRegistryError.accountBoundaryUnavailable }
    }

    /// Simulator UI tests exercise the interaction contract without claiming
    /// cross-process App Group qualification. This branch is compiled out of
    /// production builds and requires an explicit test launch argument.
    private var isUITestFallbackEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-skill-builder-qa") ||
        ProcessInfo.processInfo.arguments.contains("-skill-keys-qa") ||
        ProcessInfo.processInfo.arguments.contains("-trigger-key-sheet-qa")
#else
        false
#endif
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

    private func persistPrivateCandidates() {
        let privateSkills = skills.filter { $0.id.hasPrefix("skill_private_") }
        guard let data = try? JSONEncoder().encode(privateSkills) else { return }
        candidateDefaults.set(data, forKey: Self.candidateStorageKey)
    }

    private static func loadPrivateCandidates(from defaults: UserDefaults) -> [ShortcutSkillOption] {
        guard let data = defaults.data(forKey: candidateStorageKey),
              let decoded = try? JSONDecoder().decode([ShortcutSkillOption].self, from: data) else { return [] }
        return decoded.filter { option in
            option.id.hasPrefix("skill_private_") && option.version > 0 &&
            option.digest.hasPrefix("sha256:") && option.digest.count == 71 && option.route == .keyboardLocal
        }
    }

    private static func mergingPrivateSkills(_ values: [ShortcutSkillOption]) -> [ShortcutSkillOption] {
        var seen = Set<String>()
        return values.filter { option in
            guard !fixtureSkills.contains(where: { $0.id == option.id && $0.versionID == option.versionID }) else { return false }
            return seen.insert("\(option.id)|\(option.versionID)").inserted
        }
    }

    static let fixtureSkills: [ShortcutSkillOption] = [
        ShortcutSkillOption(id: "skill_polite_local_v1", versionID: "sv_polite_local_1", version: 1, digest: ShortcutDigest.sha256("skill_polite_local:v1"), name: "丁寧に整える", description: "選択した文章のトーンを丁寧に整えます。", icon: "text.badge.checkmark", inputSources: [.selection], toolSummaries: [ShortcutToolSummary(operation: "local.text.polite")], route: .keyboardLocal),
        ShortcutSkillOption(id: "skill_punctuation_local_v1", versionID: "sv_punctuation_local_1", version: 1, digest: ShortcutDigest.sha256("skill_punctuation_local:v1"), name: "句読点を整える", description: "選択した文章の空白と句読点を端末内で読みやすく整えます。", icon: "text.alignleft", inputSources: [.selection], toolSummaries: [ShortcutToolSummary(operation: "local.text.punctuation")], route: .keyboardLocal),
        ShortcutSkillOption(id: "skill_calendar_local_v1", versionID: "sv_calendar_local_1", version: 1, digest: ShortcutDigest.sha256("skill_calendar_local:v1"), name: "空き時間を探す", description: "接続済みカレンダーの読み取りレビューを開きます。", icon: "calendar", inputSources: [.command, .currentDateTime], toolSummaries: [], route: .hostHandoff)
    ]

    private static func skillOption(from projection: ShortcutSkillProjectionV1) -> ShortcutSkillOption? {
        guard projection.executionRoute == .keyboardLocal,
              projection.skillVersion > 0,
              projection.skillDigest.hasPrefix("sha256:"),
              projection.skillDigest.count == 71,
              projection.inputSources == [.selection],
              projection.outputType == .replaceSelection,
              projection.toolSummaries.contains(where: { LocalSkillExecutor.supportedOperations.contains($0.operation) }) else { return nil }
        return ShortcutSkillOption(id: projection.id, versionID: projection.versionID, version: projection.skillVersion, digest: projection.skillDigest, name: projection.name, description: projection.description, icon: "wand.and.stars", inputSources: projection.inputSources, toolSummaries: projection.toolSummaries, route: projection.executionRoute)
    }
}
