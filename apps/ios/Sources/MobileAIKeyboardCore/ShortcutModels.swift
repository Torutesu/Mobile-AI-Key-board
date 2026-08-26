import CryptoKit
import Foundation

/// The only physical keys that can be assigned in v1. The semantic code is
/// stable across case, locale presentation, and keyboard redraws.
public enum ShortcutKeyCode: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case keyA = "KeyA", keyB = "KeyB", keyC = "KeyC", keyD = "KeyD", keyE = "KeyE", keyF = "KeyF", keyG = "KeyG"
    case keyH = "KeyH", keyI = "KeyI", keyJ = "KeyJ", keyK = "KeyK", keyL = "KeyL", keyM = "KeyM", keyN = "KeyN"
    case keyO = "KeyO", keyP = "KeyP", keyQ = "KeyQ", keyR = "KeyR", keyS = "KeyS", keyT = "KeyT", keyU = "KeyU"
    case keyV = "KeyV", keyW = "KeyW", keyX = "KeyX", keyY = "KeyY", keyZ = "KeyZ"

    public var displayLabel: String { String(rawValue.dropFirst(3)) }
    public var lowercaseLabel: String { displayLabel.lowercased() }

    public init?(displayLabel: String) {
        guard displayLabel.count == 1, let scalar = displayLabel.uppercased().unicodeScalars.first,
              (65...90).contains(scalar.value) else { return nil }
        self.init(rawValue: "Key\(scalar)")
    }
}

public enum ShortcutActivationGesture: String, Codable, Equatable, Sendable {
    case longPress = "long_press"
}

public struct ShortcutTriggerKeyV1: Codable, Equatable, Sendable {
    public let layoutID: String
    public let keyCode: ShortcutKeyCode
    public let displayLabel: String
    public let activationGesture: ShortcutActivationGesture

    public init(keyCode: ShortcutKeyCode, layoutID: String = "latin_qwerty_v1", activationGesture: ShortcutActivationGesture = .longPress) {
        self.layoutID = layoutID
        self.keyCode = keyCode
        self.displayLabel = keyCode.displayLabel
        self.activationGesture = activationGesture
    }

    private enum CodingKeys: String, CodingKey { case layoutID = "layout_id", keyCode = "key_code", displayLabel = "display_label", activationGesture = "activation_gesture" }
}

public enum ShortcutExecutionRoute: String, Codable, Equatable, Sendable {
    case keyboardLocal = "keyboard_local"
    case keyboardNetwork = "keyboard_network"
    case hostHandoff = "host_handoff"
}

public enum ShortcutRiskCeiling: String, Codable, Equatable, Sendable {
    case r0 = "R0"
    case r1 = "R1"
    case r2 = "R2"
    case r3 = "R3"
}

public enum ShortcutOutputType: String, Codable, Equatable, Sendable {
    case insertText = "insert_text"
    case replaceSelection = "replace_selection"
    case copy
    case json
}

public enum ShortcutConfirmation: String, Codable, Equatable, Sendable {
    case none
    case policyRequired = "policy_required"
}

public enum ShortcutSource: String, Codable, Equatable, Sendable {
    case command
    case selection
    case surroundingText = "surrounding_text"
    case clipboard
    case currentDateTime = "current_datetime"
    case locale
    case location
}

public enum ShortcutTintToken: String, Codable, Equatable, Sendable {
    case neutral, accent, read, write
}

public struct ShortcutPresentation: Codable, Equatable, Sendable {
    public let iconKind: String
    public let iconValue: String
    public let shortLabel: String
    public let accessibilityLabel: String
    public let accessibilityHint: String
    public let tintToken: ShortcutTintToken

    private enum CodingKeys: String, CodingKey {
        case iconKind = "icon_kind", iconValue = "icon_value", shortLabel = "short_label", accessibilityLabel = "accessibility_label", accessibilityHint = "accessibility_hint", tintToken = "tint_token"
    }

    public init(iconKind: String = "system", iconValue: String, shortLabel: String, accessibilityLabel: String, accessibilityHint: String, tintToken: ShortcutTintToken = .accent) {
        self.iconKind = iconKind
        self.iconValue = iconValue
        self.shortLabel = String(shortLabel.prefix(24))
        self.accessibilityLabel = String(accessibilityLabel.prefix(80))
        self.accessibilityHint = String(accessibilityHint.prefix(160))
        self.tintToken = tintToken
    }
}

public struct ShortcutBindingV1: Codable, Equatable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let id: String
    public let userID: String
    public let deviceID: String
    public let skillID: String
    public let versionID: String
    public let skillVersion: Int
    public let skillDigest: String
    public let triggerKey: ShortcutTriggerKeyV1
    public let presentation: ShortcutPresentation
    public let enabled: Bool
    public let localEligibility: String
    public let requiredConnectionIDs: [String]
    public let createdAt: Date
    public let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", id = "binding_id", userID = "user_id", deviceID = "device_id", skillID = "skill_id", versionID = "version_id", skillVersion = "skill_version", skillDigest = "skill_digest", triggerKey = "trigger_key", presentation, enabled, localEligibility = "local_eligibility", requiredConnectionIDs = "required_connection_ids", createdAt = "created_at", updatedAt = "updated_at"
    }

    public init(id: String, userID: String, deviceID: String, skillID: String, versionID: String, skillVersion: Int, skillDigest: String, keyCode: ShortcutKeyCode, presentation: ShortcutPresentation, enabled: Bool = true, executionRoute: ShortcutExecutionRoute = .keyboardLocal, requiredConnectionIDs: [String] = [], createdAt: Date = Date(), updatedAt: Date = Date(), activationGesture: ShortcutActivationGesture = .longPress, schemaVersion: Int = 1) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.userID = userID
        self.deviceID = deviceID
        self.skillID = skillID
        self.versionID = versionID
        self.skillVersion = skillVersion
        self.skillDigest = skillDigest
        self.triggerKey = ShortcutTriggerKeyV1(keyCode: keyCode, activationGesture: activationGesture)
        self.presentation = presentation
        self.enabled = enabled
        self.localEligibility = executionRoute == .keyboardLocal ? "local" : (executionRoute == .hostHandoff ? "connected_read" : "connected_read")
        self.requiredConnectionIDs = Array(requiredConnectionIDs.prefix(5))
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var keyCode: ShortcutKeyCode { triggerKey.keyCode }
    public var activationGesture: ShortcutActivationGesture { triggerKey.activationGesture }
    public var executionRoute: ShortcutExecutionRoute { localEligibility == "local" ? .keyboardLocal : .hostHandoff }
}

public struct ShortcutSkillProjectionV1: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let versionID: String
    public let skillVersion: Int
    public let skillDigest: String
    public let name: String
    public let description: String
    public let inputSources: [ShortcutSource]
    public let outputType: ShortcutOutputType
    public let riskCeiling: ShortcutRiskCeiling
    public let confirmation: ShortcutConfirmation
    public let retention: String
    public let toolSummaries: [ShortcutToolSummary]
    public let executionRoute: ShortcutExecutionRoute

    private enum CodingKeys: String, CodingKey {
        case id = "skill_id", versionID = "version_id", skillVersion = "skill_version", skillDigest = "skill_digest", name, description, inputSources = "input_sources", outputType = "output_type", riskCeiling = "risk_ceiling", confirmation, retention, toolSummaries = "tool_summaries", executionRoute = "execution_route"
    }

    public init(id: String, versionID: String, skillVersion: Int, skillDigest: String, name: String, description: String, inputSources: [ShortcutSource] = [.selection], outputType: ShortcutOutputType = .replaceSelection, riskCeiling: ShortcutRiskCeiling = .r1, confirmation: ShortcutConfirmation = .policyRequired, retention: String = "none", toolSummaries: [ShortcutToolSummary] = [], executionRoute: ShortcutExecutionRoute = .keyboardLocal) {
        self.id = id
        self.versionID = versionID
        self.skillVersion = skillVersion
        self.skillDigest = skillDigest
        self.name = String(name.prefix(120))
        self.description = String(description.prefix(240))
        self.inputSources = Array(inputSources.prefix(8))
        self.outputType = outputType
        self.riskCeiling = riskCeiling
        self.confirmation = confirmation
        self.retention = String(retention.prefix(40))
        self.toolSummaries = Array(toolSummaries.prefix(16))
        self.executionRoute = executionRoute
    }
}

/// v1 local transforms can safely replace only an explicit editor selection.
/// Surrounding context is readable on some hosts, but UIInputViewController
/// cannot atomically replace that arbitrary range; treating it as replaceable
/// would duplicate the original text when the result is inserted.
public enum ShortcutCapturePolicy {
    public static func localSelection(skill: ShortcutSkillProjectionV1, selectedText: String?) -> String? {
        guard skill.executionRoute == .keyboardLocal,
              skill.outputType == .replaceSelection,
              skill.inputSources.contains(.selection),
              let selectedText,
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return selectedText
    }
}

public struct ShortcutToolSummary: Codable, Equatable, Sendable {
    public let operation: String
    public let requiredScopes: [String]
    public let sideEffect: String

    private enum CodingKeys: String, CodingKey { case operation, requiredScopes = "required_scopes", sideEffect = "side_effect" }

    public init(operation: String, requiredScopes: [String] = [], sideEffect: String = "none") {
        self.operation = String(operation.prefix(80))
        self.requiredScopes = Array(requiredScopes.prefix(8)).map { String($0.prefix(80)) }
        self.sideEffect = String(sideEffect.prefix(40))
    }
}

public struct ShortcutLayoutV1: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let userID: String
    public let deviceID: String
    public let revision: Int
    public let keyBindingIDs: [String]
    public let paletteBindingIDs: [String]
    public let longPressDurationMilliseconds: Int
    public let cancellationDistance: Double
    public let commandPosition: String
    public let overflowEnabled: Bool
    public let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", id = "layout_id", userID = "user_id", deviceID = "device_id", revision, keyBindingIDs = "key_binding_ids", paletteBindingIDs = "palette_binding_ids", longPressDurationMilliseconds = "long_press_duration_ms", cancellationDistance = "cancellation_distance", commandPosition = "command_position", overflowEnabled = "overflow_enabled", updatedAt = "updated_at"
    }

    public init(id: String, userID: String, deviceID: String, revision: Int, keyBindingIDs: [String], paletteBindingIDs: [String] = [], longPressDurationMilliseconds: Int = 450, cancellationDistance: Double = 10, commandPosition: String = "leading", overflowEnabled: Bool = true, updatedAt: Date = Date(), schemaVersion: Int = 1) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.userID = userID
        self.deviceID = deviceID
        self.revision = revision
        self.keyBindingIDs = Array(keyBindingIDs.prefix(26))
        self.paletteBindingIDs = Array(paletteBindingIDs.prefix(32))
        self.longPressDurationMilliseconds = longPressDurationMilliseconds
        self.cancellationDistance = cancellationDistance
        self.commandPosition = commandPosition
        self.overflowEnabled = overflowEnabled
        self.updatedAt = updatedAt
    }
}

public struct ShortcutConnectionState: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let state: String
    public let epoch: Int

    private enum CodingKeys: String, CodingKey { case id = "connection_id", state, epoch }

    public init(id: String, state: String, epoch: Int) {
        self.id = id
        self.state = state
        self.epoch = epoch
    }
}

public struct ShortcutSnapshotV1: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let generation: Int
    public let userSubjectHash: String?
    public let deviceID: String
    public let layout: ShortcutLayoutV1
    public let bindings: [ShortcutBindingV1]
    public let skills: [ShortcutSkillProjectionV1]
    public let connectionStates: [ShortcutConnectionState]
    public let policyEpoch: Int
    public let createdAt: Date
    public let expiresAt: Date?
    public let tombstoneReason: String?
    public let contentDigest: String

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", id = "snapshot_id", generation, userSubjectHash = "user_subject_hash", deviceID = "device_id", layout, bindings, skills, connectionStates = "connection_states", policyEpoch = "policy_epoch", createdAt = "created_at", expiresAt = "expires_at", tombstoneReason = "tombstone_reason", contentDigest = "content_digest"
    }

    public init(id: String, generation: Int, userSubjectHash: String? = nil, deviceID: String, layout: ShortcutLayoutV1, bindings: [ShortcutBindingV1], skills: [ShortcutSkillProjectionV1], connectionStates: [ShortcutConnectionState] = [], policyEpoch: Int = 1, createdAt: Date = Date(), expiresAt: Date? = nil, tombstoneReason: String? = nil, contentDigest: String = "") {
        self.schemaVersion = 1
        self.id = id
        self.generation = generation
        self.userSubjectHash = userSubjectHash
        self.deviceID = deviceID
        self.layout = layout
        self.bindings = bindings
        self.skills = skills
        self.connectionStates = connectionStates
        self.policyEpoch = policyEpoch
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.tombstoneReason = tombstoneReason
        self.contentDigest = contentDigest
    }

    public func withComputedDigest() -> ShortcutSnapshotV1 {
        var copy = self
        copy = ShortcutSnapshotV1(id: id, generation: generation, userSubjectHash: userSubjectHash, deviceID: deviceID, layout: layout, bindings: bindings, skills: skills, connectionStates: connectionStates, policyEpoch: policyEpoch, createdAt: createdAt, expiresAt: expiresAt, tombstoneReason: tombstoneReason, contentDigest: ShortcutDigest.sha256(unsignedData))
        return copy
    }

    public var unsignedData: Data {
        let payload = ShortcutSnapshotUnsigned(schemaVersion: schemaVersion, id: id, generation: generation, userSubjectHash: userSubjectHash, deviceID: deviceID, layout: layout, bindings: bindings, skills: skills, connectionStates: connectionStates, policyEpoch: policyEpoch, createdAt: Int64(createdAt.timeIntervalSince1970), expiresAt: expiresAt.map { Int64($0.timeIntervalSince1970) }, tombstoneReason: tombstoneReason)
        return (try? ShortcutJSON.encoder.encode(payload)) ?? Data()
    }

    public static func empty(deviceID: String = "device-local", userID: String = "") -> ShortcutSnapshotV1 {
        let now = Date()
        let layout = ShortcutLayoutV1(id: "layout_\(UUID().uuidString)", userID: userID, deviceID: deviceID, revision: 0, keyBindingIDs: [])
        return ShortcutSnapshotV1(id: "ss_\(UUID().uuidString)", generation: 0, userSubjectHash: nil, deviceID: deviceID, layout: layout, bindings: [], skills: [], createdAt: now).withComputedDigest()
    }
}

private struct ShortcutSnapshotUnsigned: Codable {
    let schemaVersion: Int
    let id: String
    let generation: Int
    let userSubjectHash: String?
    let deviceID: String
    let layout: ShortcutLayoutV1
    let bindings: [ShortcutBindingV1]
    let skills: [ShortcutSkillProjectionV1]
    let connectionStates: [ShortcutConnectionState]
    let policyEpoch: Int
    let createdAt: Int64
    let expiresAt: Int64?
    let tombstoneReason: String?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", id = "snapshot_id", generation, userSubjectHash = "user_subject_hash", deviceID = "device_id", layout, bindings, skills, connectionStates = "connection_states", policyEpoch = "policy_epoch", createdAt = "created_at", expiresAt = "expires_at", tombstoneReason = "tombstone_reason"
    }
}

private enum ShortcutJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: value) else { throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "invalid ISO8601 date") }
            return date
        }
        return decoder
    }()
}

public enum ShortcutDigest {
    public static func sha256(_ data: Data) -> String {
        "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(_ value: String) -> String { sha256(Data(value.utf8)) }
}

public enum ShortcutValidationError: Error, Equatable, LocalizedError, Sendable {
    case schema
    case oversized
    case generation
    case ownerOrDevice
    case duplicateBinding
    case duplicateSkill
    case duplicateKey
    case invalidKey
    case missingReference
    case digestMismatch
    case chronology
    case tombstone
    case sensitiveField

    public var errorDescription: String? {
        switch self {
        case .schema: return "shortcut schema is unsupported"
        case .oversized: return "shortcut snapshot exceeds its bounded limits"
        case .generation: return "shortcut generation is not monotonic"
        case .ownerOrDevice: return "shortcut owner or device does not match"
        case .duplicateBinding: return "shortcut binding IDs must be unique"
        case .duplicateSkill: return "shortcut Skill projections must be unique"
        case .duplicateKey: return "only one active Skill may own a physical key"
        case .invalidKey: return "the key is not assignable in the v1 QWERTY layout"
        case .missingReference: return "snapshot contains a missing binding or Skill reference"
        case .digestMismatch: return "shortcut snapshot digest does not match its content"
        case .chronology: return "shortcut snapshot timestamps are invalid"
        case .tombstone: return "tombstones cannot retain executable Skills"
        case .sensitiveField: return "content or credentials are not allowed in the shortcut projection"
        }
    }
}

public enum ShortcutSnapshotValidator {
    public static let maxEncodedBytes = 256 * 1024

    public static func validate(_ snapshot: ShortcutSnapshotV1, lastGeneration: Int? = nil, expectedDeviceID: String? = nil, now: Date = Date()) throws {
        guard snapshot.schemaVersion == 1, snapshot.layout.schemaVersion == 1 else { throw ShortcutValidationError.schema }
        guard snapshot.bindings.count <= 32, snapshot.skills.count <= 32, snapshot.layout.keyBindingIDs.count <= 32 else { throw ShortcutValidationError.oversized }
        guard snapshot.unsignedData.count <= maxEncodedBytes else { throw ShortcutValidationError.oversized }
        guard snapshot.contentDigest == ShortcutDigest.sha256(snapshot.unsignedData) else { throw ShortcutValidationError.digestMismatch }
        if let lastGeneration, snapshot.generation <= lastGeneration { throw ShortcutValidationError.generation }
        if let expectedDeviceID, (snapshot.deviceID != expectedDeviceID || snapshot.layout.deviceID != expectedDeviceID) { throw ShortcutValidationError.ownerOrDevice }
        guard snapshot.layout.deviceID == snapshot.deviceID else { throw ShortcutValidationError.ownerOrDevice }
        guard snapshot.generation >= 0, snapshot.layout.revision >= 0, snapshot.policyEpoch >= 0 else { throw ShortcutValidationError.generation }
        guard snapshot.createdAt <= now.addingTimeInterval(60) else { throw ShortcutValidationError.chronology }
        if let expiresAt = snapshot.expiresAt {
            guard expiresAt >= snapshot.createdAt, expiresAt >= now else { throw ShortcutValidationError.chronology }
        }

        let bindingIDs = snapshot.bindings.map(\.id)
        guard Set(bindingIDs).count == bindingIDs.count else { throw ShortcutValidationError.duplicateBinding }
        let skillKeys = snapshot.skills.map { "\($0.id)|\($0.versionID)" }
        guard Set(skillKeys).count == skillKeys.count else { throw ShortcutValidationError.duplicateSkill }
        let skillByID = Dictionary(uniqueKeysWithValues: zip(skillKeys, snapshot.skills))
        var activeKeys = Set<ShortcutKeyCode>()
        for binding in snapshot.bindings {
            guard binding.schemaVersion == 1, binding.deviceID == snapshot.deviceID else { throw ShortcutValidationError.ownerOrDevice }
            guard binding.skillVersion > 0, binding.id.isEmpty == false, binding.skillID.isEmpty == false, binding.versionID.isEmpty == false else { throw ShortcutValidationError.schema }
            guard binding.requiredConnectionIDs.count <= 5, binding.requiredConnectionIDs.allSatisfy({ !$0.contains(" ") && $0.count <= 160 }) else { throw ShortcutValidationError.sensitiveField }
            guard skillByID["\(binding.skillID)|\(binding.versionID)"] != nil else { throw ShortcutValidationError.missingReference }
            guard let skill = skillByID["\(binding.skillID)|\(binding.versionID)"], skill.skillDigest == binding.skillDigest, skill.skillVersion == binding.skillVersion else { throw ShortcutValidationError.digestMismatch }
            guard skill.executionRoute == binding.executionRoute else { throw ShortcutValidationError.schema }
            if binding.enabled {
                guard activeKeys.insert(binding.keyCode).inserted else { throw ShortcutValidationError.duplicateKey }
            }
        }
        guard activeKeys.count <= 26 else { throw ShortcutValidationError.oversized }
        guard Set(snapshot.layout.keyBindingIDs).count == snapshot.layout.keyBindingIDs.count,
              snapshot.layout.keyBindingIDs.count <= 26,
              Set(snapshot.layout.paletteBindingIDs).count == snapshot.layout.paletteBindingIDs.count,
              Set(snapshot.layout.keyBindingIDs).isSubset(of: Set(bindingIDs)),
              Set(snapshot.layout.paletteBindingIDs).isSubset(of: Set(bindingIDs)) else { throw ShortcutValidationError.missingReference }
        guard Set(snapshot.layout.keyBindingIDs) == Set(snapshot.bindings.filter(\.enabled).map(\.id)) else { throw ShortcutValidationError.missingReference }
        guard snapshot.layout.longPressDurationMilliseconds == 450, snapshot.layout.cancellationDistance == 10, snapshot.layout.commandPosition == "leading" else { throw ShortcutValidationError.schema }
        if snapshot.tombstoneReason != nil,
           !snapshot.bindings.isEmpty || !snapshot.skills.isEmpty || !snapshot.connectionStates.isEmpty ||
           !snapshot.layout.keyBindingIDs.isEmpty || !snapshot.layout.paletteBindingIDs.isEmpty { throw ShortcutValidationError.tombstone }
    }
}

public enum ShortcutTombstoneReason: String, Codable, Sendable {
    case signedOut = "signed_out"
    case accountDeleted = "account_deleted"
    case deviceRevoked = "device_revoked"
}

public enum ShortcutStoreError: Error, Equatable, LocalizedError, Sendable {
    case invalidSnapshot(ShortcutValidationError)
    case unavailable
    case generationConflict

    public var errorDescription: String? {
        switch self {
        case .invalidSnapshot(let error): return error.localizedDescription
        case .unavailable: return "shared shortcut storage is unavailable"
        case .generationConflict: return "shortcut generation must increase atomically"
        }
    }
}

/// A content-free, atomic App Group repository. When provisioning is absent,
/// it falls back to an app-private directory; the fallback is intentionally
/// not shared between the host and extension and therefore cannot leak data.
public final class AppGroupShortcutSnapshotStore: @unchecked Sendable {
    public static let appGroupIdentifier = "group.com.torutesu.mobileaikeyboard"
    private let fileManager: FileManager
    private let appGroupIdentifier: String
    private let fallbackBundleIdentifier: String
    private let fallbackDirectoryURL: URL?
    private let lock = NSLock()

    public init(appGroupIdentifier: String = AppGroupShortcutSnapshotStore.appGroupIdentifier, fileManager: FileManager = .default, fallbackBundleIdentifier: String? = Bundle.main.bundleIdentifier, fallbackDirectoryURL: URL? = nil) {
        self.appGroupIdentifier = appGroupIdentifier
        self.fileManager = fileManager
        self.fallbackBundleIdentifier = fallbackBundleIdentifier ?? "unknown"
        self.fallbackDirectoryURL = fallbackDirectoryURL
    }

    public var isUsingSharedAppGroup: Bool { fallbackDirectoryURL == nil && fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil }

    public func loadLastKnownGood() -> ShortcutSnapshotV1? {
        lock.lock(); defer { lock.unlock() }
        for path in [currentURL, previousURL] {
            guard let data = try? Data(contentsOf: path), data.count <= ShortcutSnapshotValidator.maxEncodedBytes,
                  let snapshot = try? ShortcutJSON.decoder.decode(ShortcutSnapshotV1.self, from: data),
                  (try? ShortcutSnapshotValidator.validate(snapshot)) != nil else { continue }
            return snapshot
        }
        return nil
    }

    public func publish(_ snapshot: ShortcutSnapshotV1) throws {
        let candidate = snapshot.contentDigest.isEmpty ? snapshot.withComputedDigest() : snapshot
        guard candidate.contentDigest == ShortcutDigest.sha256(candidate.unsignedData) else { throw ShortcutStoreError.invalidSnapshot(.digestMismatch) }
        if let current = loadLastKnownGood(), candidate.generation <= current.generation { throw ShortcutStoreError.generationConflict }
        do { try ShortcutSnapshotValidator.validate(candidate, lastGeneration: loadLastKnownGood()?.generation) } catch let error as ShortcutValidationError { throw ShortcutStoreError.invalidSnapshot(error) }
        guard let data = try? ShortcutJSON.encoder.encode(candidate), data.count <= ShortcutSnapshotValidator.maxEncodedBytes else { throw ShortcutStoreError.invalidSnapshot(.oversized) }
        lock.lock(); defer { lock.unlock() }
        let directory = directoryURL
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent("shortcut-snapshot.\(candidate.generation).tmp")
        try data.write(to: temporary, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if fileManager.fileExists(atPath: currentURL.path) {
            try? fileManager.removeItem(at: previousURL)
            try? fileManager.moveItem(at: currentURL, to: previousURL)
        }
        try? fileManager.removeItem(at: currentURL)
        try fileManager.moveItem(at: temporary, to: currentURL)
    }

    public func publishTombstone(reason: ShortcutTombstoneReason, deviceID: String, userID: String = "") throws {
        let old = loadLastKnownGood()
        let nextGeneration = (old?.generation ?? 0) + 1
        let tombstone = ShortcutSnapshotV1(id: "ss_\(UUID().uuidString)", generation: nextGeneration, userSubjectHash: nil, deviceID: deviceID, layout: ShortcutLayoutV1(id: old?.layout.id ?? "layout_\(UUID().uuidString)", userID: userID, deviceID: deviceID, revision: (old?.layout.revision ?? 0) + 1, keyBindingIDs: []), bindings: [], skills: [], policyEpoch: (old?.policyEpoch ?? 0) + 1, tombstoneReason: reason.rawValue).withComputedDigest()
        try publish(tombstone)
    }

    private var directoryURL: URL {
        if let fallbackDirectoryURL { return fallbackDirectoryURL.appendingPathComponent("ShortcutSnapshots", isDirectory: true) }
        if let shared = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return shared.appendingPathComponent("ShortcutSnapshots", isDirectory: true)
        }
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        return support.appendingPathComponent("MobileAIKeyboard-\(fallbackBundleIdentifier)/ShortcutSnapshots", isDirectory: true)
    }
    private var currentURL: URL { directoryURL.appendingPathComponent("shortcut-snapshot.current.json") }
    private var previousURL: URL { directoryURL.appendingPathComponent("shortcut-snapshot.previous.json") }
}

public struct ShortcutActivationV1: Equatable, Sendable {
    public let id: String
    public let bindingID: String
    public let skillID: String
    public let versionID: String
    public let skillDigest: String
    public let snapshotGeneration: Int
    public let deviceID: String
    public let editorSessionID: String
    public let requestedAt: Date
    public let expiresAt: Date

    public init(binding: ShortcutBindingV1, snapshot: ShortcutSnapshotV1, editorSessionID: String, now: Date = Date()) {
        id = "act_\(UUID().uuidString)"
        bindingID = binding.id
        skillID = binding.skillID
        versionID = binding.versionID
        skillDigest = binding.skillDigest
        snapshotGeneration = snapshot.generation
        deviceID = snapshot.deviceID
        self.editorSessionID = editorSessionID
        requestedAt = now
        expiresAt = now.addingTimeInterval(120)
    }
}
