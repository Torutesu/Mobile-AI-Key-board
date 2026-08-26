import CryptoKit
import Foundation

// MARK: - Contextual suggestions

public enum ContextualSuggestionKind: String, CaseIterable, Equatable, Sendable {
    case politeRewrite = "丁寧化"
    case conciseRewrite = "短縮"
    case keyPoints = "要点"
}

public struct ContextualSuggestionContext: Equatable, Sendable {
    /// Opaque, locally-owned editor boundary. It is never derived from text or an editor fingerprint.
    public let editorBoundaryID: String
    public let characterCountBucket: String
    public let locale: String
    public let secureField: Bool

    public init(editorBoundaryID: String, characterCountBucket: String, locale: String, secureField: Bool = false) {
        self.editorBoundaryID = editorBoundaryID
        self.characterCountBucket = characterCountBucket
        self.locale = locale
        self.secureField = secureField
    }

    public var isValid: Bool {
        let bytes = Array(editorBoundaryID.utf8)
        guard (1...64).contains(bytes.count) else { return false }
        return bytes.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45 || $0 == 46 || $0 == 95 }
    }
}

public struct ContextualSuggestion: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: ContextualSuggestionKind
    public let title: String
    public let sourceDisclosure: String
    public let riskClass: String
    public let autoApplyAllowed: Bool
    public let rawContentRetained: Bool

    public init(id: String, kind: ContextualSuggestionKind, title: String, sourceDisclosure: String = "端末内の型付きfixture。raw textは保持せず、外部送信しません。", riskClass: String = "R1", autoApplyAllowed: Bool = false, rawContentRetained: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.sourceDisclosure = sourceDisclosure
        self.riskClass = riskClass
        self.autoApplyAllowed = autoApplyAllowed
        self.rawContentRetained = rawContentRetained
    }
}

public enum ContextualSuggestionDecision: Equatable, Sendable {
    case none
    case refreshed
    case previewed(id: String)
    case rejectedAutoApply
    case disabledForSecureField
}

public struct ContextualSuggestionState: Equatable, Sendable {
    public var context: ContextualSuggestionContext?
    public var suggestions: [ContextualSuggestion]
    public var selectedSuggestionID: String?
    public var lastDecision: ContextualSuggestionDecision

    public init(context: ContextualSuggestionContext? = nil, suggestions: [ContextualSuggestion] = [], selectedSuggestionID: String? = nil, lastDecision: ContextualSuggestionDecision = .none) {
        self.context = context
        self.suggestions = suggestions
        self.selectedSuggestionID = selectedSuggestionID
        self.lastDecision = lastDecision
    }
}

public enum ContextualSuggestionAction: Equatable, Sendable {
    case refresh(ContextualSuggestionContext)
    case preview(id: String)
    case attemptAutoApply(id: String)
    case clearBoundary
}

public struct ContextualSuggestionReducer: Sendable {
    public init() {}

    public func reduce(_ state: ContextualSuggestionState, _ action: ContextualSuggestionAction) -> ContextualSuggestionState {
        var next = state
        switch action {
        case .refresh(let context):
            guard context.isValid else { return ContextualSuggestionState(lastDecision: .none) }
            guard !context.secureField else { return ContextualSuggestionState(context: context, lastDecision: .disabledForSecureField) }
            next.context = context
            next.suggestions = [
                ContextualSuggestion(id: "local-polite", kind: .politeRewrite, title: "丁寧に整える"),
                ContextualSuggestion(id: "local-concise", kind: .conciseRewrite, title: "短く整える"),
                ContextualSuggestion(id: "local-points", kind: .keyPoints, title: "要点にまとめる")
            ]
            next.selectedSuggestionID = nil
            next.lastDecision = .refreshed
        case .preview(let id):
            guard next.suggestions.contains(where: { $0.id == id }) else { return next }
            next.selectedSuggestionID = id
            next.lastDecision = .previewed(id: id)
        case .attemptAutoApply:
            // Suggestions are never an execution authority. There is no apply mutation here.
            next.lastDecision = .rejectedAutoApply
        case .clearBoundary:
            return ContextualSuggestionState()
        }
        return next
    }
}

// MARK: - Trust Preview and community catalog (SK-006)

public enum SkillPublisherTrust: String, Equatable, Sendable {
    case notVerified = "not_proven: publisher"
}

public enum SkillPackageTrust: String, Equatable, Sendable {
    case notVerified = "not_proven: package signature"
}

public struct SkillProvenance: Equatable, Sendable {
    public let source: String
    public let publisher: SkillPublisherTrust
    public let package: SkillPackageTrust
    public let runtimeSync: String

    public init(source: String = "local-fixture", publisher: SkillPublisherTrust = .notVerified, package: SkillPackageTrust = .notVerified, runtimeSync: String = "not_proven: runtime sync") {
        self.source = source
        self.publisher = publisher
        self.package = package
        self.runtimeSync = runtimeSync
    }
}

public enum SkillIssueCategory: String, CaseIterable, Equatable, Sendable {
    case correctness
    case safety
    case privacy
    case availability
    case other
}

/// Bounded, content-free issue telemetry. There is intentionally no free-text field.
public struct SkillIssueCounts: Equatable, Sendable {
    public static let maximumPerCategory = 10_000
    public let correctness: Int
    public let safety: Int
    public let privacy: Int
    public let availability: Int
    public let other: Int

    public init(correctness: Int = 0, safety: Int = 0, privacy: Int = 0, availability: Int = 0, other: Int = 0) {
        self.correctness = correctness
        self.safety = safety
        self.privacy = privacy
        self.availability = availability
        self.other = other
    }

    public var total: Int { correctness + safety + privacy + availability + other }
    public var isValid: Bool {
        [correctness, safety, privacy, availability, other].allSatisfy { (0...Self.maximumPerCategory).contains($0) }
    }
    public var canonical: [String: Int] {
        ["availability": availability, "correctness": correctness, "other": other, "privacy": privacy, "safety": safety]
    }
}

public struct CommunitySkillMetadata: Identifiable, Equatable, Sendable {
    public static let lowConfidenceAttemptThreshold = 100
    public let id: String
    public let publisher: String
    public let requestedOperations: [String]
    public let requestedConnectorsScopes: [String]
    public let dataInputs: [String]
    public let riskClass: String
    public let confirmationPolicy: String
    public let version: String
    public let lastReviewDate: String
    public let installs: Int
    public let completionCompleted: Int
    public let completionAttempted: Int
    public let reportedIssueCounts: SkillIssueCounts
    public let declaredMetadataDigest: String
    public let provenance: SkillProvenance

    public init(id: String, publisher: String, requestedOperations: [String] = ["local.text.transform"], requestedConnectorsScopes: [String], dataInputs: [String], riskClass: String, confirmationPolicy: String = "always", version: String, lastReviewDate: String, installs: Int, completionCompleted: Int, completionAttempted: Int, reportedIssueCounts: SkillIssueCounts = SkillIssueCounts(), declaredMetadataDigest: String = "", provenance: SkillProvenance = SkillProvenance()) {
        self.id = id
        self.publisher = publisher
        self.requestedOperations = requestedOperations
        self.requestedConnectorsScopes = requestedConnectorsScopes
        self.dataInputs = dataInputs
        self.riskClass = riskClass
        self.confirmationPolicy = confirmationPolicy
        self.version = version
        self.lastReviewDate = lastReviewDate
        self.installs = installs
        self.completionCompleted = completionCompleted
        self.completionAttempted = completionAttempted
        self.reportedIssueCounts = reportedIssueCounts
        self.declaredMetadataDigest = declaredMetadataDigest
        self.provenance = provenance
    }

    public var completionRateBasisPoints: Int? {
        guard completionAttempted > 0, completionCompleted >= 0, completionCompleted <= completionAttempted else { return nil }
        return (completionCompleted * 10_000) / completionAttempted
    }

    public var completionRateDisplay: String {
        guard let rate = completionRateBasisPoints else { return "not_proven: invalid or no attempts" }
        guard completionAttempted >= Self.lowConfidenceAttemptThreshold else { return "not_proven: low confidence (<\(Self.lowConfidenceAttemptThreshold) attempts)" }
        return "\(rate / 100).\(String(format: "%02d", rate % 100))% (\(completionCompleted)/\(completionAttempted))"
    }

    public var canonicalMetadata: String {
        let object: [String: Any] = [
            "completionAttempted": completionAttempted,
            "completionCompleted": completionCompleted,
            "confirmationPolicy": confirmationPolicy,
            "dataInputs": dataInputs,
            "id": id,
            "installs": installs,
            "lastReviewDate": lastReviewDate,
            "publisher": publisher,
            "reportedIssueCounts": reportedIssueCounts.canonical,
            "requestedConnectorsScopes": requestedConnectorsScopes,
            "requestedOperations": requestedOperations,
            "riskClass": riskClass,
            "version": version
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    public var computedMetadataDigest: String {
        "sha256:" + SHA256.hash(data: Data(canonicalMetadata.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public var digestMatches: Bool { !declaredMetadataDigest.isEmpty && declaredMetadataDigest == computedMetadataDigest }

    public func withDeclaredDigest(_ digest: String) -> CommunitySkillMetadata {
        CommunitySkillMetadata(id: id, publisher: publisher, requestedOperations: requestedOperations, requestedConnectorsScopes: requestedConnectorsScopes, dataInputs: dataInputs, riskClass: riskClass, confirmationPolicy: confirmationPolicy, version: version, lastReviewDate: lastReviewDate, installs: installs, completionCompleted: completionCompleted, completionAttempted: completionAttempted, reportedIssueCounts: reportedIssueCounts, declaredMetadataDigest: digest, provenance: provenance)
    }
}

public struct CommunitySkillCatalogFixture: Sendable {
    public init() {}

    public static var metadata: CommunitySkillMetadata {
        let draft = CommunitySkillMetadata(id: "fixture.polite.reply", publisher: "Fixture Community Publisher", requestedConnectorsScopes: ["none"], dataInputs: ["typed text (preview only)"], riskClass: "R1", version: "1.0.0", lastReviewDate: "2026-08-26T00:00:00Z", installs: 128, completionCompleted: 98, completionAttempted: 100, reportedIssueCounts: SkillIssueCounts(other: 1))
        return draft.withDeclaredDigest(draft.computedMetadataDigest)
    }
}

public struct TrustPreviewValidation: Equatable, Sendable {
    public let allowed: Bool
    public let issues: [String]
    public let fixtureMetadataConsistent: Bool

    public init(allowed: Bool, issues: [String], fixtureMetadataConsistent: Bool = true) {
        self.allowed = allowed
        self.issues = issues
        self.fixtureMetadataConsistent = fixtureMetadataConsistent
    }
}

public struct TrustPreviewValidator: Sendable {
    public init() {}

    public func validate(_ metadata: CommunitySkillMetadata, now: Date = Date(), maximumReviewAge: TimeInterval = 180 * 24 * 60 * 60, expectedVersion: String? = nil, expectedDigest: String? = nil) -> TrustPreviewValidation {
        var issues: [String] = []
        if metadata.publisher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("publisher missing") }
        if metadata.installs < 0 || metadata.completionAttempted < 0 || metadata.completionCompleted < 0 || metadata.completionCompleted > metadata.completionAttempted || !metadata.reportedIssueCounts.isValid { issues.append("SK-006 numeric metadata invalid") }
        if ISO8601DateFormatter().date(from: metadata.lastReviewDate) == nil { issues.append("last review timestamp invalid") }
        if let reviewDate = ISO8601DateFormatter().date(from: metadata.lastReviewDate) {
            if reviewDate > now || now.timeIntervalSince(reviewDate) > maximumReviewAge { issues.append("last review timestamp stale") }
        }
        if !metadata.digestMatches { issues.append("metadata digest mismatch") }
        if let expectedVersion, expectedVersion != metadata.version { issues.append("stale version") }
        if let expectedDigest, expectedDigest != metadata.declaredMetadataDigest { issues.append("stale digest") }
        return TrustPreviewValidation(allowed: issues.isEmpty, issues: issues, fixtureMetadataConsistent: issues.isEmpty)
    }
}

// MARK: - Team policy and explicit version lifecycle

public enum TeamPolicyDecision: Equatable, Sendable {
    case none
    case previewed
    case installed
    case upgraded
    case upgradeRequired
    case revoked
    case deniedOwnerConfusion
    case deniedMetadata
    case deniedConfirmation
    case deniedPolicy
    case deniedRevoked
    case deniedVersion
}

public struct TeamPolicyRules: Equatable, Sendable {
    public let teamID: String
    public let ownerSubject: String
    public let policyVersion: String
    public let policyEpoch: Int
    public let allowedOperations: [String]
    public let allowedScopes: [String]
    public let riskCeiling: String
    public let confirmationFloor: String

    public init(teamID: String = "fixture-team", ownerSubject: String = "", policyVersion: String = "team-policy.v1", policyEpoch: Int = 1, allowedOperations: [String] = ["local.text.transform"], allowedScopes: [String] = ["none"], riskCeiling: String = "R1", confirmationFloor: String = "always") {
        self.teamID = teamID
        self.ownerSubject = ownerSubject
        self.policyVersion = policyVersion
        self.policyEpoch = policyEpoch
        self.allowedOperations = allowedOperations
        self.allowedScopes = allowedScopes
        self.riskCeiling = riskCeiling
        self.confirmationFloor = confirmationFloor
    }

    public var canonicalPayload: String {
        let object: [String: Any] = ["allowedOperations": allowedOperations.sorted(), "allowedScopes": allowedScopes.sorted(), "confirmationFloor": confirmationFloor, "ownerSubject": ownerSubject, "policyEpoch": policyEpoch, "policyVersion": policyVersion, "riskCeiling": riskCeiling, "teamID": teamID]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    public var canonicalDigest: String {
        "sha256:" + SHA256.hash(data: Data(canonicalPayload.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private var riskRank: Int { Int(riskCeiling.dropFirst()).flatMap { riskCeiling.first == "R" ? $0 : nil } ?? -1 }
    public func allows(_ metadata: CommunitySkillMetadata) -> Bool {
        let metadataRisk = Int(metadata.riskClass.dropFirst()).flatMap { metadata.riskClass.first == "R" ? $0 : nil } ?? -1
        let confirmationRank = ["none": 0, "on-risk": 1, "always": 2]
        guard metadataRisk >= 0, riskRank >= metadataRisk else { return false }
        guard metadata.requestedOperations.allSatisfy({ allowedOperations.contains($0) }) else { return false }
        guard metadata.requestedConnectorsScopes.allSatisfy({ allowedScopes.contains($0) }) else { return false }
        return (confirmationRank[metadata.confirmationPolicy] ?? -1) >= (confirmationRank[confirmationFloor] ?? Int.max)
    }

    /// Fixture contract: exactly one SemVer component may advance by one.
    /// This permits 1.0.0→2.0.0 and 1.0.0→1.1.0/1.0.1, but rejects skips such as 1.0.0→3.0.0.
    public static func isSequentialUpgrade(from current: String, to candidate: String) -> Bool {
        let lhs = current.split(separator: ".").map { Int($0) ?? -1 }
        let rhs = candidate.split(separator: ".").map { Int($0) ?? -1 }
        guard lhs.count == 3, rhs.count == 3, lhs.allSatisfy({ $0 >= 0 }), rhs.allSatisfy({ $0 >= 0 }) else { return false }
        return (rhs[0] == lhs[0] + 1 && rhs[1] == 0 && rhs[2] == 0)
            || (rhs[0] == lhs[0] && rhs[1] == lhs[1] + 1 && rhs[2] == 0)
            || (rhs[0] == lhs[0] && rhs[1] == lhs[1] && rhs[2] == lhs[2] + 1)
    }

    public static let fixture = TeamPolicyRules()
}

public struct TeamPolicyBinding: Equatable, Sendable {
    public let teamID: String
    public let ownerSubject: String
    public let skillID: String
    public let version: String
    public let digest: String
    public let policyEpoch: Int
    public let policyDigest: String
}

public struct TeamPolicyState: Equatable, Sendable {
    public var teamID: String
    public var ownerSubject: String?
    public var policyVersion: String
    public var policyEpoch: Int
    public var policyCanonicalDigest: String
    public var allowedOperations: [String]
    public var allowedScopes: [String]
    public var riskCeiling: String
    public var confirmationFloor: String
    public var binding: TeamPolicyBinding?
    public var decision: TeamPolicyDecision
    public var revoked: Bool
    public var revokedDigests: Set<String>
    public var revokedPolicyDigests: Set<String>

    public init(teamID: String = TeamPolicyRules.fixture.teamID, ownerSubject: String? = nil, policyVersion: String = "team-policy.v1", rules: TeamPolicyRules = .fixture, binding: TeamPolicyBinding? = nil, decision: TeamPolicyDecision = .none, revoked: Bool = false, revokedDigests: Set<String> = [], revokedPolicyDigests: Set<String> = []) {
        self.teamID = teamID
        self.ownerSubject = ownerSubject ?? (rules.ownerSubject.isEmpty ? nil : rules.ownerSubject)
        self.policyVersion = policyVersion
        self.policyEpoch = rules.policyEpoch
        self.policyCanonicalDigest = rules.canonicalDigest
        self.allowedOperations = rules.allowedOperations
        self.allowedScopes = rules.allowedScopes
        self.riskCeiling = rules.riskCeiling
        self.confirmationFloor = rules.confirmationFloor
        self.binding = binding
        self.decision = decision
        self.revoked = revoked
        self.revokedDigests = revokedDigests
        self.revokedPolicyDigests = revokedPolicyDigests
    }

    public var rules: TeamPolicyRules { TeamPolicyRules(teamID: teamID, ownerSubject: ownerSubject ?? "", policyVersion: policyVersion, policyEpoch: policyEpoch, allowedOperations: allowedOperations, allowedScopes: allowedScopes, riskCeiling: riskCeiling, confirmationFloor: confirmationFloor) }
}

public enum TeamPolicyAction: Equatable, Sendable {
    case preview(ownerSubject: String)
    case install(metadata: CommunitySkillMetadata, policy: TeamPolicyRules, ownerSubject: String, explicitConfirm: Bool)
    case upgrade(metadata: CommunitySkillMetadata, policy: TeamPolicyRules, ownerSubject: String, explicitConfirm: Bool)
    case revoke
    case clearBoundary
}

public struct TeamPolicyReducer: Sendable {
    private let validator = TrustPreviewValidator()
    private let now: Date

    public init(now: Date = Date()) { self.now = now }

    public func reduce(_ state: TeamPolicyState, _ action: TeamPolicyAction) -> TeamPolicyState {
        var next = state
        switch action {
        case .preview(let owner):
            guard !owner.isEmpty else { return next }
            next.ownerSubject = owner
            next.policyCanonicalDigest = next.rules.canonicalDigest
            next.decision = .previewed
        case .install(let metadata, let policy, let owner, let explicit):
            guard explicit else { next.decision = .deniedConfirmation; return next }
            guard state.policyCanonicalDigest == state.rules.canonicalDigest else { next.decision = .deniedPolicy; return next }
            guard policy.teamID == state.teamID, policy.ownerSubject == owner, policy.policyVersion == state.policyVersion, policy.policyEpoch == state.policyEpoch, policy.canonicalDigest == state.policyCanonicalDigest, state.ownerSubject == owner else { next.decision = .deniedOwnerConfusion; return next }
            guard !state.revokedPolicyDigests.contains(policy.canonicalDigest) else { next.decision = .deniedRevoked; return next }
            guard !state.revokedDigests.contains(metadata.declaredMetadataDigest) else { next.decision = .deniedRevoked; return next }
            guard validator.validate(metadata, now: now).allowed, state.rules.allows(metadata) else { next.decision = .deniedPolicy; return next }
            if let binding = state.binding, binding.skillID == metadata.id { next.decision = .upgradeRequired; return next }
            next.ownerSubject = owner
            next.binding = TeamPolicyBinding(teamID: state.teamID, ownerSubject: owner, skillID: metadata.id, version: metadata.version, digest: metadata.declaredMetadataDigest, policyEpoch: state.policyEpoch, policyDigest: state.policyCanonicalDigest)
            next.revoked = false
            next.decision = .installed
        case .upgrade(let metadata, let policy, let owner, let explicit):
            guard explicit else { next.decision = .deniedConfirmation; return next }
            guard state.policyCanonicalDigest == state.rules.canonicalDigest else { next.decision = .deniedPolicy; return next }
            guard policy.teamID == state.teamID, policy.ownerSubject == owner, policy.policyVersion == state.policyVersion, policy.policyEpoch == state.policyEpoch, policy.canonicalDigest == state.policyCanonicalDigest, let current = state.binding, current.skillID == metadata.id, current.ownerSubject == owner, current.teamID == state.teamID, current.policyEpoch == state.policyEpoch, current.policyDigest == state.policyCanonicalDigest else { next.decision = .deniedOwnerConfusion; return next }
            guard !state.revokedPolicyDigests.contains(policy.canonicalDigest), !state.revokedDigests.contains(metadata.declaredMetadataDigest) else { next.decision = .deniedRevoked; return next }
            guard validator.validate(metadata, now: now).allowed, state.rules.allows(metadata) else { next.decision = .deniedPolicy; return next }
            guard TeamPolicyRules.isSequentialUpgrade(from: current.version, to: metadata.version) else { next.decision = .deniedVersion; return next }
            next.binding = TeamPolicyBinding(teamID: state.teamID, ownerSubject: owner, skillID: metadata.id, version: metadata.version, digest: metadata.declaredMetadataDigest, policyEpoch: state.policyEpoch, policyDigest: state.policyCanonicalDigest)
            next.revoked = false
            next.decision = .upgraded
        case .revoke:
            if let digest = state.binding?.digest { next.revokedDigests.insert(digest) }
            next.revokedPolicyDigests.insert(state.policyCanonicalDigest)
            next.revoked = true
            next.decision = .revoked
            next.binding = nil
        case .clearBoundary:
            return TeamPolicyState(teamID: state.teamID)
        }
        return next
    }
}

// MARK: - R4 connector gate

public struct R4ConnectorGateState: Equatable, Sendable {
    public let connector: String
    public let riskClass: String
    public var enabled: Bool
    public var approvalEvidencePresent: Bool
    public var decision: String

    public init(connector: String = "external communication", riskClass: String = "R4", enabled: Bool = false, approvalEvidencePresent: Bool = false, decision: String = "not_proven: separate approval and evidence required") {
        self.connector = connector
        self.riskClass = riskClass
        self.enabled = enabled
        self.approvalEvidencePresent = approvalEvidencePresent
        self.decision = decision
    }
}

public enum R4ConnectorGateAction: Equatable, Sendable {
    case requestApproval
    case attemptEnable
    case clearBoundary
}

public struct R4ConnectorGateReducer: Sendable {
    public init() {}

    public func reduce(_ state: R4ConnectorGateState, _ action: R4ConnectorGateAction) -> R4ConnectorGateState {
        var next = state
        switch action {
        case .requestApproval:
            next.enabled = false
            next.decision = "denied: approval evidence is absent"
        case .attemptEnable:
            next.enabled = false
            next.decision = "denied: R4 is disabled pending separate approval/evidence"
        case .clearBoundary:
            return R4ConnectorGateState()
        }
        return next
    }
}
