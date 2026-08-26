import Foundation

public struct NativeSkillFailureIdentityV1: Codable, Equatable, Hashable, Sendable {
    public let skillID: String
    public let versionID: String
    public let skillVersion: Int
    public let skillDigest: String

    private enum CodingKeys: String, CodingKey {
        case skillID = "skill_id", versionID = "version_id", skillVersion = "skill_version", skillDigest = "skill_digest"
    }

    public init(binding: ShortcutBindingV1) {
        skillID = binding.skillID
        versionID = binding.versionID
        skillVersion = binding.skillVersion
        skillDigest = binding.skillDigest
    }
}

public struct NativeSkillFailureRecordV1: Codable, Equatable, Sendable {
    public let identity: NativeSkillFailureIdentityV1
    public let consecutiveFailures: Int
    public let firstFailureAtMilliseconds: Int64
    public let lastFailureAtMilliseconds: Int64
    public let disabled: Bool

    private enum CodingKeys: String, CodingKey {
        case identity, consecutiveFailures = "consecutive_failures", firstFailureAtMilliseconds = "first_failure_at_ms", lastFailureAtMilliseconds = "last_failure_at_ms", disabled
    }
}

public enum NativeSkillExecutionDecision: Equatable, Sendable {
    case allowed
    case disabled
    case storeUnavailable
}

public enum NativeSkillFailureStoreError: Error, Equatable, Sendable {
    case unavailable
    case invalidIdentity
    case writeFailed
}

/// Content-free, owner/epoch/version-bound circuit breaker shared by the host
/// and keyboard extension. It can suppress Skill actions and decoration only;
/// ordinary typing remains owned by the keyboard buttons.
public final class AppGroupNativeSkillFailureStore: @unchecked Sendable {
    public static let failureThreshold = 3
    public static let failureWindow: TimeInterval = 10 * 60
    private let fileManager: FileManager
    private let appGroupIdentifier: String
    private let fallbackBundleIdentifier: String
    private let fallbackDirectoryURL: URL?
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var unavailableScopes = Set<String>()
    private var forceWriteFailureForTesting = false

    public init(
        appGroupIdentifier: String = AppGroupShortcutSnapshotStore.appGroupIdentifier,
        fileManager: FileManager = .default,
        fallbackBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        fallbackDirectoryURL: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.appGroupIdentifier = appGroupIdentifier
        self.fileManager = fileManager
        self.fallbackBundleIdentifier = fallbackBundleIdentifier ?? "unknown"
        self.fallbackDirectoryURL = fallbackDirectoryURL
        self.now = now
    }

    public func decision(for binding: ShortcutBindingV1, boundary: ShortcutAccountBoundaryV1) -> NativeSkillExecutionDecision {
        lock.lock(); defer { lock.unlock() }
        guard valid(binding: binding), boundary.isValid, boundary.active, boundary.expiresAt > now() else { return .storeUnavailable }
        if unavailableScopes.contains(scopeKey(binding: binding, boundary: boundary)) { return .storeUnavailable }
        switch readLocked(boundary: boundary) {
        case .unavailable: return .storeUnavailable
        case .available(let records):
            let timestamp = Int64((now().timeIntervalSince1970 * 1_000).rounded())
            guard let record = records.first(where: { $0.identity == NativeSkillFailureIdentityV1(binding: binding) }) else { return .allowed }
            guard timestamp >= record.lastFailureAtMilliseconds else { return .storeUnavailable }
            return record.disabled && timestamp - record.lastFailureAtMilliseconds <= Int64(Self.failureWindow * 1_000) ? .disabled : .allowed
        }
    }

    @discardableResult
    public func recordFailure(for binding: ShortcutBindingV1, boundary: ShortcutAccountBoundaryV1) throws -> NativeSkillExecutionDecision {
        lock.lock(); defer { lock.unlock() }
        guard valid(binding: binding) else { throw NativeSkillFailureStoreError.invalidIdentity }
        guard boundary.isValid, boundary.active, boundary.expiresAt > now() else { throw NativeSkillFailureStoreError.unavailable }
        guard case .available(let current) = readLocked(boundary: boundary) else { throw NativeSkillFailureStoreError.unavailable }
        let timestamp = Int64((now().timeIntervalSince1970 * 1_000).rounded())
        guard current.allSatisfy({ $0.lastFailureAtMilliseconds <= timestamp }) else { throw NativeSkillFailureStoreError.unavailable }
        // Expired version records neither keep a Skill disabled nor consume
        // the bounded record budget indefinitely.
        let active = current.filter { timestamp - $0.lastFailureAtMilliseconds <= Int64(Self.failureWindow * 1_000) }
        let identity = NativeSkillFailureIdentityV1(binding: binding)
        let previous = active.first(where: { $0.identity == identity })
        let inWindow = previous.map { timestamp >= $0.lastFailureAtMilliseconds && timestamp - $0.lastFailureAtMilliseconds <= Int64(Self.failureWindow * 1_000) } ?? false
        let count = inWindow ? min(Self.failureThreshold, (previous?.consecutiveFailures ?? 0) + 1) : 1
        let record = NativeSkillFailureRecordV1(
            identity: identity,
            consecutiveFailures: count,
            firstFailureAtMilliseconds: inWindow ? previous!.firstFailureAtMilliseconds : timestamp,
            lastFailureAtMilliseconds: timestamp,
            disabled: count >= Self.failureThreshold
        )
        let next = (active.filter { $0.identity != identity } + [record]).sorted(by: Self.recordOrder)
        do {
            try writeLocked(boundary: boundary, records: next)
        } catch {
            unavailableScopes.insert(scopeKey(binding: binding, boundary: boundary))
            throw error
        }
        return record.disabled ? .disabled : .allowed
    }

    public func recordSuccess(for binding: ShortcutBindingV1, boundary: ShortcutAccountBoundaryV1) throws {
        lock.lock(); defer { lock.unlock() }
        guard valid(binding: binding), boundary.isValid, boundary.active, boundary.expiresAt > now() else { throw NativeSkillFailureStoreError.unavailable }
        guard case .available(let current) = readLocked(boundary: boundary) else { throw NativeSkillFailureStoreError.unavailable }
        let identity = NativeSkillFailureIdentityV1(binding: binding)
        guard current.contains(where: { $0.identity == identity }) else { return }
        try writeLocked(boundary: boundary, records: current.filter { $0.identity != identity })
    }

    public func reset() throws {
        lock.lock(); defer { lock.unlock() }
        unavailableScopes.removeAll()
        if fileManager.fileExists(atPath: fileURL.path) { try fileManager.removeItem(at: fileURL) }
    }

    private enum ReadResult {
        case available([NativeSkillFailureRecordV1])
        case unavailable
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let ownerSubjectHash: String
        let sessionEpoch: Int
        let records: [NativeSkillFailureRecordV1]
        let contentDigest: String

        private enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", ownerSubjectHash = "owner_subject_hash", sessionEpoch = "session_epoch", records, contentDigest = "content_digest"
        }
    }

    private func readLocked(boundary: ShortcutAccountBoundaryV1) -> ReadResult {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .available([]) }
        guard let data = try? Data(contentsOf: fileURL), data.count <= 16 * 1024,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == 1, envelope.records.count <= 32,
              envelope.contentDigest == Self.digest(owner: envelope.ownerSubjectHash, epoch: envelope.sessionEpoch, records: envelope.records),
              Self.valid(records: envelope.records) else { return .unavailable }
        // Never inherit a circuit breaker across an account/session boundary.
        guard envelope.ownerSubjectHash == boundary.ownerSubjectHash, envelope.sessionEpoch == boundary.sessionEpoch else { return .available([]) }
        return .available(envelope.records)
    }

    private func writeLocked(boundary: ShortcutAccountBoundaryV1, records: [NativeSkillFailureRecordV1]) throws {
        if forceWriteFailureForTesting { throw NativeSkillFailureStoreError.writeFailed }
        guard let owner = boundary.ownerSubjectHash, !owner.isEmpty, records.count <= 32, Self.valid(records: records) else { throw NativeSkillFailureStoreError.unavailable }
        let envelope = Envelope(schemaVersion: 1, ownerSubjectHash: owner, sessionEpoch: boundary.sessionEpoch, records: records, contentDigest: Self.digest(owner: owner, epoch: boundary.sessionEpoch, records: records))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(envelope), data.count <= 16 * 1024 else { throw NativeSkillFailureStoreError.writeFailed }
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let temporary = directoryURL.appendingPathComponent("native-skill-failures.\(boundary.sessionEpoch).tmp")
            try data.write(to: temporary, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporary, backupItemName: nil, options: [.usingNewMetadataOnly])
            } else {
                try fileManager.moveItem(at: temporary, to: fileURL)
            }
        } catch { throw NativeSkillFailureStoreError.writeFailed }
    }

    internal func failWritesForTesting() {
        lock.lock(); defer { lock.unlock() }
        forceWriteFailureForTesting = true
    }

    private func scopeKey(binding: ShortcutBindingV1, boundary: ShortcutAccountBoundaryV1) -> String {
        [boundary.ownerSubjectHash ?? "", String(boundary.sessionEpoch), binding.skillID, binding.versionID, String(binding.skillVersion), binding.skillDigest].joined(separator: "\u{0}")
    }

    private func valid(binding: ShortcutBindingV1) -> Bool {
        !binding.skillID.isEmpty && !binding.versionID.isEmpty && binding.skillVersion > 0 && binding.skillDigest.range(of: #"^sha256:[0-9a-f]{64}$"#, options: .regularExpression) != nil
    }

    private static func valid(records: [NativeSkillFailureRecordV1]) -> Bool {
        Set(records.map(\.identity)).count == records.count && records.allSatisfy { record in
            !record.identity.skillID.isEmpty && !record.identity.versionID.isEmpty && record.identity.skillVersion > 0 &&
            record.identity.skillDigest.range(of: #"^sha256:[0-9a-f]{64}$"#, options: .regularExpression) != nil &&
            (1...failureThreshold).contains(record.consecutiveFailures) && record.firstFailureAtMilliseconds >= 0 &&
            record.lastFailureAtMilliseconds >= record.firstFailureAtMilliseconds &&
            record.disabled == (record.consecutiveFailures >= failureThreshold)
        }
    }

    private static func recordOrder(_ lhs: NativeSkillFailureRecordV1, _ rhs: NativeSkillFailureRecordV1) -> Bool {
        (lhs.identity.skillID, lhs.identity.versionID, lhs.identity.skillVersion, lhs.identity.skillDigest) <
        (rhs.identity.skillID, rhs.identity.versionID, rhs.identity.skillVersion, rhs.identity.skillDigest)
    }

    private static func digest(owner: String, epoch: Int, records: [NativeSkillFailureRecordV1]) -> String {
        let body = records.sorted(by: recordOrder).map { record in
            [record.identity.skillID, record.identity.versionID, String(record.identity.skillVersion), record.identity.skillDigest, String(record.consecutiveFailures), String(record.firstFailureAtMilliseconds), String(record.lastFailureAtMilliseconds), record.disabled ? "1" : "0"].joined(separator: "\u{0}")
        }.joined(separator: "\u{1f}")
        return ShortcutDigest.sha256("native-skill-failures-v1\u{0}\(owner)\u{0}\(epoch)\u{0}\(body)")
    }

    private var directoryURL: URL {
        if let fallbackDirectoryURL { return fallbackDirectoryURL.appendingPathComponent("NativeSkillFailures", isDirectory: true) }
        if let shared = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return shared.appendingPathComponent("NativeSkillFailures", isDirectory: true)
        }
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        return support.appendingPathComponent("MobileAIKeyboard-\(fallbackBundleIdentifier)/NativeSkillFailures", isDirectory: true)
    }
    private var fileURL: URL { directoryURL.appendingPathComponent("native-skill-failures.current.json") }
}
