import Foundation

public enum KeyboardThemePreference: String, CaseIterable, Equatable, Sendable {
    case system
    case light
    case dark
}

public enum KeyboardKeySize: String, CaseIterable, Equatable, Sendable {
    case compact
    case standard
    case large
}

public enum KeyboardHandedness: String, CaseIterable, Equatable, Sendable {
    case off
    case left
    case right
}

public enum JapaneseWorkflowPack: String, CaseIterable, Equatable, Sendable {
    case polite = "丁寧化"
    case concise = "短縮"
    case keyPoints = "要点"
    case absoluteDate = "日付絶対化"

    public var icon: String {
        switch self {
        case .polite: return "text.badge.checkmark"
        case .concise: return "text.badge.minus"
        case .keyPoints: return "list.bullet"
        case .absoluteDate: return "calendar"
        }
    }
}

public struct KeyboardSettingsState: Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public var schemaVersion: Int
    public var theme: KeyboardThemePreference
    public var hapticsEnabled: Bool
    public var keySize: KeyboardKeySize
    public var oneHandedMode: KeyboardHandedness
    public var englishWorkflowPackEnabled: Bool
    public var enabledJapanesePacks: [JapaneseWorkflowPack]

    public init(schemaVersion: Int = KeyboardSettingsState.currentSchemaVersion, theme: KeyboardThemePreference = .system, hapticsEnabled: Bool = true, keySize: KeyboardKeySize = .standard, oneHandedMode: KeyboardHandedness = .off, englishWorkflowPackEnabled: Bool = true, enabledJapanesePacks: [JapaneseWorkflowPack] = [.polite]) {
        self.schemaVersion = schemaVersion
        self.theme = theme
        self.hapticsEnabled = hapticsEnabled
        self.keySize = keySize
        self.oneHandedMode = oneHandedMode
        self.englishWorkflowPackEnabled = englishWorkflowPackEnabled
        self.enabledJapanesePacks = Array(Set(enabledJapanesePacks)).sorted { $0.rawValue < $1.rawValue }
    }

    public static var defaultFixture: KeyboardSettingsState { KeyboardSettingsState() }

    public func isEnabled(_ pack: JapaneseWorkflowPack) -> Bool { enabledJapanesePacks.contains(pack) }
}

public enum KeyboardSettingsAction: Equatable, Sendable {
    case setTheme(KeyboardThemePreference)
    case setHaptics(Bool)
    case setKeySize(KeyboardKeySize)
    case setOneHandedMode(KeyboardHandedness)
    case setEnglishWorkflowEnabled(Bool)
    case setPackEnabled(JapaneseWorkflowPack, Bool)
    case reset
    case migrate(fromSchemaVersion: Int)
    case clearBoundary
}

public struct KeyboardSettingsReducer: Sendable {
    public init() {}

    public func reduce(_ state: KeyboardSettingsState, _ action: KeyboardSettingsAction) -> KeyboardSettingsState {
        var next = state
        switch action {
        case .setTheme(let value): next.theme = value
        case .setHaptics(let value): next.hapticsEnabled = value
        case .setKeySize(let value): next.keySize = value
        case .setOneHandedMode(let value): next.oneHandedMode = value
        case .setEnglishWorkflowEnabled(let value): next.englishWorkflowPackEnabled = value
        case .setPackEnabled(let pack, let enabled):
            if enabled, !next.enabledJapanesePacks.contains(pack) { next.enabledJapanesePacks.append(pack) }
            if !enabled { next.enabledJapanesePacks.removeAll { $0 == pack } }
            next.enabledJapanesePacks.sort { $0.rawValue < $1.rawValue }
        case .reset:
            next = .defaultFixture
        case .clearBoundary:
            // Session/owner boundaries clear protected work, but ordinary typing preferences
            // remain available as a safe keyboard fallback. Account deletion uses .reset.
            return next
        case .migrate(let version):
            guard version <= KeyboardSettingsState.currentSchemaVersion else { return next }
            next.schemaVersion = KeyboardSettingsState.currentSchemaVersion
            if version < 2, next.enabledJapanesePacks.isEmpty { next.enabledJapanesePacks = [.polite] }
        }
        next.schemaVersion = KeyboardSettingsState.currentSchemaVersion
        return next
    }
}

public struct WorkflowPackResult: Equatable, Sendable {
    public let pack: JapaneseWorkflowPack
    public let original: String
    public let rewritten: String
    public let preservedEntities: [String]
    public let sourceDisclosure: String
    public let fieldFingerprint: String

    public init(pack: JapaneseWorkflowPack, original: String, rewritten: String, preservedEntities: [String], sourceDisclosure: String, fieldFingerprint: String) {
        self.pack = pack
        self.original = original
        self.rewritten = rewritten
        self.preservedEntities = preservedEntities
        self.sourceDisclosure = sourceDisclosure
        self.fieldFingerprint = fieldFingerprint
    }
}

/// Japanese workflow packs are deterministic local fixtures, not IME conversion
/// and not an LLM. Every transform masks/restores high-confidence entities.
public struct JapaneseWorkflowEngine: Sendable {
    private let locking: EntityLocking
    private let rewrite: LocalRewriteEngine

    public init(locking: EntityLocking = EntityLocking()) {
        self.locking = locking
        rewrite = LocalRewriteEngine(locking: locking)
    }

    public func transform(_ input: String, pack: JapaneseWorkflowPack, referenceDate: Date = Date()) -> WorkflowPackResult? {
        let original = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return nil }
        let entities = locking.entities(in: original)
        let transformed: String
        switch pack {
        case .polite:
            transformed = rewrite.politeRewrite(original)?.rewritten ?? original
        case .concise:
            transformed = locking.maskAndRestore(original) { value in
                value.replacingOccurrences(of: "よろしくお願いいたします", with: "よろしくお願いします")
                    .replacingOccurrences(of: "お願いいたします", with: "お願いします")
                    .replacingOccurrences(of: "させていただきます", with: "します")
                    .replacingOccurrences(of: "可能でしょうか", with: "できますか")
            }
        case .keyPoints:
            transformed = locking.maskAndRestore(original) { value in
                let parts = value.split(whereSeparator: { "。！？!?\n".contains($0) }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                return parts.isEmpty ? value : parts.map { "・\($0)" }.joined(separator: "\n")
            }
        case .absoluteDate:
            transformed = locking.maskAndRestore(original) { value in
                replaceRelativeDates(in: value, referenceDate: referenceDate)
            }
        }
        // Never surface a result if a protected token was dropped or altered.
        guard preservesEntities(original: original, rewritten: transformed) else { return nil }
        return WorkflowPackResult(pack: pack, original: original, rewritten: transformed, preservedEntities: entities, sourceDisclosure: "端末内の決定的fixture。IME変換・LLM・外部送信は実装していません。", fieldFingerprint: locking.fingerprint(original))
    }

    /// Public for adversarial tests and UI adapters that need a fail-closed check.
    public func preservesEntities(original: String, rewritten: String) -> Bool {
        let sourceEntities = locking.entities(in: original)
        guard !rewritten.isEmpty else { return sourceEntities.isEmpty }
        return sourceEntities.allSatisfy { entity in
            occurrenceCount(of: entity, in: rewritten) >= occurrenceCount(of: entity, in: original)
        }
    }

    private func occurrenceCount(of value: String, in text: String) -> Int {
        guard !value.isEmpty else { return 0 }
        var count = 0
        var searchStart = text.startIndex
        while let range = text.range(of: value, range: searchStart..<text.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    private func replaceRelativeDates(in value: String, referenceDate: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日"
        let replacements: [(String, Date?)] = [
            ("今日", referenceDate),
            ("明日", calendar.date(byAdding: .day, value: 1, to: referenceDate)),
            ("昨日", calendar.date(byAdding: .day, value: -1, to: referenceDate))
        ]
        return replacements.reduce(value) { partial, replacement in
            guard let date = replacement.1 else { return partial }
            return partial.replacingOccurrences(of: replacement.0, with: formatter.string(from: date))
        }
    }
}

public enum QualificationPhysicalStatus: String, Equatable, Sendable {
    case notProven = "not_proven: physical device"
}

public struct QualificationBudget: Equatable, Sendable {
    public let coldStartP50Milliseconds: Int
    public let coldStartP95Milliseconds: Int
    public let warmStartP95Milliseconds: Int
    public let keyLatencyP95Milliseconds: Int
    public let betaMinimumCrashFreeBasisPoints: Int
    public let broadMinimumCrashFreeBasisPoints: Int

    public init(coldStartP50Milliseconds: Int = 250, coldStartP95Milliseconds: Int = 400, warmStartP95Milliseconds: Int = 150, keyLatencyP95Milliseconds: Int = 50, betaMinimumCrashFreeBasisPoints: Int = 9_980, broadMinimumCrashFreeBasisPoints: Int = 9_995) {
        self.coldStartP50Milliseconds = coldStartP50Milliseconds
        self.coldStartP95Milliseconds = coldStartP95Milliseconds
        self.warmStartP95Milliseconds = warmStartP95Milliseconds
        self.keyLatencyP95Milliseconds = keyLatencyP95Milliseconds
        self.betaMinimumCrashFreeBasisPoints = betaMinimumCrashFreeBasisPoints
        self.broadMinimumCrashFreeBasisPoints = broadMinimumCrashFreeBasisPoints
    }
}

public struct QualificationMeasurement: Equatable, Sendable {
    public let coldStartP50Milliseconds: Int
    public let coldStartP95Milliseconds: Int
    public let warmStartP95Milliseconds: Int
    public let keyLatencyP95Milliseconds: Int
    public let sessions: Int
    public let crashes: Int
    public let contentFree: Bool

    public init(coldStartP50Milliseconds: Int, coldStartP95Milliseconds: Int, warmStartP95Milliseconds: Int, keyLatencyP95Milliseconds: Int, sessions: Int, crashes: Int, contentFree: Bool = true) {
        self.coldStartP50Milliseconds = coldStartP50Milliseconds
        self.coldStartP95Milliseconds = coldStartP95Milliseconds
        self.warmStartP95Milliseconds = warmStartP95Milliseconds
        self.keyLatencyP95Milliseconds = keyLatencyP95Milliseconds
        self.sessions = sessions
        self.crashes = crashes
        self.contentFree = contentFree
    }

    public var crashFreeBasisPoints: Int? {
        guard sessions > 0, crashes >= 0, crashes <= sessions else { return nil }
        return ((sessions - crashes) * 10_000) / sessions
    }
}

public struct QualificationEvaluation: Equatable, Sendable {
    public let valid: Bool
    public let passed: Bool
    public let issues: [String]

    public init(valid: Bool, passed: Bool, issues: [String]) {
        self.valid = valid
        self.passed = passed
        self.issues = issues
    }
}

public struct QualificationEvaluator: Sendable {
    public init() {}

    public func evaluate(_ measurement: QualificationMeasurement, budget: QualificationBudget) -> QualificationEvaluation {
        var issues: [String] = []
        guard measurement.coldStartP50Milliseconds >= 0,
              measurement.coldStartP95Milliseconds >= 0,
              measurement.warmStartP95Milliseconds >= 0,
              measurement.keyLatencyP95Milliseconds >= 0,
              measurement.sessions > 0,
              measurement.crashes >= 0,
              measurement.crashes <= measurement.sessions else {
            return QualificationEvaluation(valid: false, passed: false, issues: ["invalid measurement"])
        }
        guard measurement.coldStartP50Milliseconds <= measurement.coldStartP95Milliseconds else {
            return QualificationEvaluation(valid: false, passed: false, issues: ["cold percentile order invalid"])
        }
        if measurement.coldStartP50Milliseconds > budget.coldStartP50Milliseconds { issues.append("cold P50 over budget") }
        if measurement.coldStartP95Milliseconds > budget.coldStartP95Milliseconds { issues.append("cold P95 over budget") }
        if measurement.warmStartP95Milliseconds > budget.warmStartP95Milliseconds { issues.append("warm P95 over budget") }
        if measurement.keyLatencyP95Milliseconds > budget.keyLatencyP95Milliseconds { issues.append("key P95 over budget") }
        if !measurement.contentFree { issues.append("content is not free") }
        if let rate = measurement.crashFreeBasisPoints {
            if rate < budget.betaMinimumCrashFreeBasisPoints { issues.append("crash-free below beta budget") }
            if rate < budget.broadMinimumCrashFreeBasisPoints { issues.append("crash-free below broad budget") }
        }
        return QualificationEvaluation(valid: true, passed: issues.isEmpty, issues: issues)
    }
}

public struct QualificationState: Equatable, Sendable {
    public var budget: QualificationBudget
    public var measurement: QualificationMeasurement?
    public var fixturePassed: Bool
    public var physicalStatus: QualificationPhysicalStatus

    public init(budget: QualificationBudget = QualificationBudget(), measurement: QualificationMeasurement? = nil, fixturePassed: Bool = false, physicalStatus: QualificationPhysicalStatus = .notProven) {
        self.budget = budget
        self.measurement = measurement
        self.fixturePassed = fixturePassed
        self.physicalStatus = physicalStatus
    }
}

public enum QualificationAction: Equatable, Sendable {
    case runFixture
    case runFixtureForSession(ownerSubject: String, now: Date, expiresAt: Date)
    case clearBoundary
}

public struct QualificationReducer: Sendable {
    public init() {}

    public func reduce(_ state: QualificationState, _ action: QualificationAction) -> QualificationState {
        switch action {
        case .clearBoundary: return QualificationState(budget: state.budget)
        case .runFixture: return state
        case .runFixtureForSession(_, let now, let expiresAt):
            guard now < expiresAt else { return state }
            let measurement = QualificationMeasurement(coldStartP50Milliseconds: 120, coldStartP95Milliseconds: 180, warmStartP95Milliseconds: 80, keyLatencyP95Milliseconds: 18, sessions: 1_000, crashes: 0)
            let evaluation = QualificationEvaluator().evaluate(measurement, budget: state.budget)
            return QualificationState(budget: state.budget, measurement: measurement, fixturePassed: evaluation.passed)
        }
    }
}

public struct LaunchReadinessFixture: Equatable, Sendable {
    public let fullAccessEnabled: Bool
    public let collectedDataTypes: [String]
    public let networkConnected: Bool
    public let privacyManifestSourceDeclared: Bool
    public let privacyManifestArchivedVerified: Bool
    public let supportEntry: String
    public let incidentEntry: String

    public init(fullAccessEnabled: Bool = false, collectedDataTypes: [String] = [], networkConnected: Bool = false, privacyManifestSourceDeclared: Bool = true, privacyManifestArchivedVerified: Bool = false, supportEntry: String = "local-fixture support-entry (no endpoint)", incidentEntry: String = "local-fixture incident-entry (no endpoint)") {
        self.fullAccessEnabled = fullAccessEnabled
        self.collectedDataTypes = collectedDataTypes
        self.networkConnected = networkConnected
        self.privacyManifestSourceDeclared = privacyManifestSourceDeclared
        self.privacyManifestArchivedVerified = privacyManifestArchivedVerified
        self.supportEntry = supportEntry
        self.incidentEntry = incidentEntry
    }
}
