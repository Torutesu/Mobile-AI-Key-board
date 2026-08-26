import CryptoKit
import Foundation

/// The W6 builder is deliberately provider-neutral. It stores only a local
/// draft and a content-free deployment receipt; there is no LLM, URLSession, or
/// public publishing implementation behind these contracts.
public enum SkillBuilderStatus: String, Equatable, Sendable {
    case unavailable
    case idle
    case collectingMissingInfo
    case draft
    case validationFailed
    case readyForTest
    case testing
    case tested
    case quotaExceeded
    case deployReview
    case deployed
    case installed

    public var title: String {
        switch self {
        case .unavailable: return "認証が必要です"
        case .idle: return "Skill作成を開始できます"
        case .collectingMissingInfo: return "不足情報を確認中"
        case .draft: return "下書き"
        case .validationFailed: return "検証に失敗"
        case .readyForTest: return "テスト準備完了"
        case .testing: return "fixtureテスト中"
        case .tested: return "テスト済み"
        case .quotaExceeded: return "quota上限"
        case .deployReview: return "deploy確認待ち"
        case .deployed: return "private v1 deploy済み"
        case .installed: return "binding pin済み"
        }
    }
}

public enum SkillBuilderMissingField: String, CaseIterable, Equatable, Sendable {
    case desiredOutcome
    case name
    case icon
    case binding
    case testExample

    public var title: String {
        switch self {
        case .desiredOutcome: return "達成したい結果"
        case .name: return "Skill名"
        case .icon: return "アイコン"
        case .binding: return "binding名"
        case .testExample: return "テスト例"
        }
    }
}

public struct SkillBuilderMissingInfo: Identifiable, Equatable, Sendable {
    public let id: SkillBuilderMissingField
    public let explanation: String

    public init(_ field: SkillBuilderMissingField, explanation: String) {
        id = field
        self.explanation = explanation
    }
}

public enum SkillTrigger: String, CaseIterable, Equatable, Sendable {
    case manual
    case keyboardCommand
}

public enum SkillInputKind: String, CaseIterable, Equatable, Sendable {
    case selectedText
    case typedText
    case structuredText
}

public enum SkillOutputKind: String, CaseIterable, Equatable, Sendable {
    case rewrittenText
    case structuredSummary
}

public enum SkillAllowedTool: String, CaseIterable, Equatable, Sendable {
    case none
    case localTextTransform
}

public enum SkillRiskCeiling: String, CaseIterable, Equatable, Sendable {
    case r1LocalTransform = "R1-local-transform"
}

public enum SkillConfirmationMode: String, CaseIterable, Equatable, Sendable {
    case always
}

public enum SkillRetentionMode: String, CaseIterable, Equatable, Sendable {
    case ephemeral
    case untilDeleted
}

public struct SkillTestExample: Equatable, Sendable {
    public let input: String
    public let expectedOutput: String

    public init(input: String, expectedOutput: String) {
        // Keep one byte over the limit so validation can reject it without
        // retaining unbounded fixture input.
        self.input = String(input.prefix(1_001))
        self.expectedOutput = String(expectedOutput.prefix(1_001))
    }
}

public struct SkillTypedManifest: Equatable, Sendable {
    public let trigger: SkillTrigger
    public let input: SkillInputKind
    public let output: SkillOutputKind
    public let allowedTools: [SkillAllowedTool]
    public let riskCeiling: SkillRiskCeiling
    public let confirmation: SkillConfirmationMode
    public let retention: SkillRetentionMode
    public let testExamples: [SkillTestExample]

    public init(trigger: SkillTrigger = .manual, input: SkillInputKind = .typedText, output: SkillOutputKind = .rewrittenText, allowedTools: [SkillAllowedTool] = [.localTextTransform], riskCeiling: SkillRiskCeiling = .r1LocalTransform, confirmation: SkillConfirmationMode = .always, retention: SkillRetentionMode = .ephemeral, testExamples: [SkillTestExample] = [SkillTestExample(input: "fixture input", expectedOutput: "fixture expected output")]) {
        self.trigger = trigger
        self.input = input
        self.output = output
        self.allowedTools = allowedTools
        self.riskCeiling = riskCeiling
        self.confirmation = confirmation
        self.retention = retention
        self.testExamples = Array(testExamples.prefix(5))
    }

    public static var defaultFixture: SkillTypedManifest { SkillTypedManifest() }

    public var testExamplesValid: Bool {
        !testExamples.isEmpty && testExamples.allSatisfy {
            let input = $0.input.trimmingCharacters(in: .whitespacesAndNewlines)
            let expected = $0.expectedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            return !input.isEmpty && !expected.isEmpty && input.count <= 1_000 && expected.count <= 1_000
        }
    }

    fileprivate var canonicalObject: [String: Any] {
        [
            "allowedTools": allowedTools.map(\.rawValue),
            "confirmation": confirmation.rawValue,
            "input": input.rawValue,
            "output": output.rawValue,
            "retention": retention.rawValue,
            "riskCeiling": riskCeiling.rawValue,
            "testExamples": testExamples.map { ["input": $0.input, "expectedOutput": $0.expectedOutput] },
            "trigger": trigger.rawValue
        ]
    }

    public var canonicalSchema: String {
        guard let data = try? JSONSerialization.data(withJSONObject: canonicalObject, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

public enum SkillBuilderIssueSeverity: String, Equatable, Sendable {
    case error
    case warning
}

public struct SkillBuilderValidationIssue: Identifiable, Equatable, Sendable {
    public let id: String
    public let code: String
    public let severity: SkillBuilderIssueSeverity
    public let message: String

    public init(id: String, code: String, severity: SkillBuilderIssueSeverity, message: String) {
        self.id = id
        self.code = code
        self.severity = severity
        self.message = message
    }
}

public struct SkillBuilderDraft: Equatable, Sendable {
    public let name: String
    public let icon: String
    public let desiredOutcome: String
    public let plainDescription: String
    public let advancedSchema: String
    public let bindingIdentifier: String
    public let manifest: SkillTypedManifest

    public init(name: String, icon: String, desiredOutcome: String, plainDescription: String, advancedSchema: String, bindingIdentifier: String, manifest: SkillTypedManifest = .defaultFixture) {
        self.name = String(name.prefix(80))
        self.icon = String(icon.prefix(80))
        self.desiredOutcome = String(desiredOutcome.prefix(2_000))
        self.plainDescription = String(plainDescription.prefix(2_000))
        self.advancedSchema = String(advancedSchema.prefix(4_000))
        self.bindingIdentifier = String(bindingIdentifier.prefix(120))
        self.manifest = manifest
    }

    public var missingFields: [SkillBuilderMissingField] {
        SkillBuilderMissingField.allCases.filter { field in
            switch field {
            case .desiredOutcome: return desiredOutcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .name: return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .icon: return icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .binding: return bindingIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .testExample: return !manifest.testExamplesValid
            }
        }
    }
}

public struct SkillBuilderValidation: Equatable, Sendable {
    public let issues: [SkillBuilderValidationIssue]
    public let schemaValid: Bool
    public let policyValid: Bool
    public let staticInjectionSafe: Bool

    public init(issues: [SkillBuilderValidationIssue] = [], schemaValid: Bool = false, policyValid: Bool = false, staticInjectionSafe: Bool = false) {
        self.issues = issues
        self.schemaValid = schemaValid
        self.policyValid = policyValid
        self.staticInjectionSafe = staticInjectionSafe
    }

    public var isValid: Bool {
        schemaValid && policyValid && staticInjectionSafe && !issues.contains(where: { $0.severity == .error })
    }
}

public enum SkillDryRunStatus: String, Equatable, Sendable {
    case passed
    case failed
}

public struct SkillDryRunResult: Equatable, Sendable {
    public let status: SkillDryRunStatus
    public let createdAt: Date
    public let safeSummary: String
    public let checkedContracts: [String]
    public let warnings: [String]
    public let validatedExamples: [SkillTestExample]

    public init(status: SkillDryRunStatus, createdAt: Date, safeSummary: String, checkedContracts: [String], warnings: [String] = [], validatedExamples: [SkillTestExample] = []) {
        self.status = status
        self.createdAt = createdAt
        self.safeSummary = safeSummary
        self.checkedContracts = checkedContracts
        self.warnings = warnings
        self.validatedExamples = validatedExamples
    }
}

public struct PrivateSkillShare: Equatable, Sendable {
    public let versionID: String
    public let versionNumber: Int
    public let digest: String
    public let recipient: String
    public let expiresAt: Date

    public init(versionID: String, versionNumber: Int, digest: String, recipient: String, expiresAt: Date) {
        self.versionID = versionID
        self.versionNumber = versionNumber
        self.digest = digest
        self.recipient = recipient
        self.expiresAt = expiresAt
    }
}

public struct PrivateSkillVersion: Identifiable, Equatable, Sendable {
    public let id: String
    /// Stable Skill identity shared by every immutable version of this private Skill.
    public let skillID: String
    public let versionNumber: Int
    public let digest: String
    public let createdAt: Date
    public let draft: SkillBuilderDraft

    public init(id: String, skillID: String? = nil, versionNumber: Int, digest: String, createdAt: Date, draft: SkillBuilderDraft) {
        self.id = id
        self.skillID = skillID ?? Self.skillID(for: draft.bindingIdentifier)
        self.versionNumber = versionNumber
        self.digest = digest
        self.createdAt = createdAt
        self.draft = draft
    }

    public static func skillID(for binding: String) -> String {
        // Do not normalize punctuation into a lossy slug: distinct binding
        // identifiers such as `private.a.b` and `private.a_b` must never become
        // the same Skill identity. A truncated SHA-256 remains opaque, stable,
        // content-free and comfortably inside snapshot ID limits.
        let normalized = binding.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digest = ShortcutDigest.sha256(normalized).dropFirst("sha256:".count)
        return "skill_private_\(digest.prefix(32))"
    }
}

public struct InstalledSkillBinding: Equatable, Sendable {
    public let versionID: String
    public let versionNumber: Int
    public let digest: String
    public let bindingIdentifier: String
    public let pinnedAt: Date

    public init(versionID: String, versionNumber: Int, digest: String, bindingIdentifier: String, pinnedAt: Date) {
        self.versionID = versionID
        self.versionNumber = versionNumber
        self.digest = digest
        self.bindingIdentifier = bindingIdentifier
        self.pinnedAt = pinnedAt
    }
}

public struct SkillBuilderState: Equatable, Sendable {
    public var ownerSubject: String?
    public var accountEpoch: Int?
    public var status: SkillBuilderStatus
    public var desiredOutcome: String
    public var missingInfo: [SkillBuilderMissingInfo]
    public var draft: SkillBuilderDraft?
    public var validation: SkillBuilderValidation?
    public var dryRun: SkillDryRunResult?
    public var versions: [PrivateSkillVersion]
    public var installedBinding: InstalledSkillBinding?
    public var privateShare: PrivateSkillShare?
    public var pendingDeploymentDigest: String?
    public var pendingDeploymentVersionNumber: Int?
    public var pendingDeploymentExpiresAt: Date?
    public var quotaLimit: Int
    public var quotaUsed: Int
    public var quotaReserved: Int
    public let publicPublishDisabled: Bool

    public init(ownerSubject: String? = nil, accountEpoch: Int? = nil, status: SkillBuilderStatus = .unavailable, desiredOutcome: String = "", missingInfo: [SkillBuilderMissingInfo] = [], draft: SkillBuilderDraft? = nil, validation: SkillBuilderValidation? = nil, dryRun: SkillDryRunResult? = nil, versions: [PrivateSkillVersion] = [], installedBinding: InstalledSkillBinding? = nil, privateShare: PrivateSkillShare? = nil, pendingDeploymentDigest: String? = nil, pendingDeploymentVersionNumber: Int? = nil, pendingDeploymentExpiresAt: Date? = nil, quotaLimit: Int = 3, quotaUsed: Int = 0, quotaReserved: Int = 0, publicPublishDisabled: Bool = true) {
        self.ownerSubject = ownerSubject
        self.accountEpoch = accountEpoch
        self.status = status
        self.desiredOutcome = desiredOutcome
        self.missingInfo = missingInfo
        self.draft = draft
        self.validation = validation
        self.dryRun = dryRun
        self.versions = versions
        self.installedBinding = installedBinding
        self.privateShare = privateShare
        self.pendingDeploymentDigest = pendingDeploymentDigest
        self.pendingDeploymentVersionNumber = pendingDeploymentVersionNumber
        self.pendingDeploymentExpiresAt = pendingDeploymentExpiresAt
        self.quotaLimit = quotaLimit
        self.quotaUsed = quotaUsed
        self.quotaReserved = quotaReserved
        self.publicPublishDisabled = publicPublishDisabled
    }

    public var quotaRemaining: Int { max(0, quotaLimit - quotaUsed - quotaReserved) }
    public var fixtureCostDisclosure: String { "0 credits（端末内fixture）" }
    public var externalCostDisclosure: String { "外部LLM/provider未接続・未証明" }
}

public enum SkillBuilderAction: Equatable, Sendable {
    case setAccountContext(ownerSubject: String, accountEpoch: Int)
    case begin
    case setDesiredOutcome(String)
    case editDraft(SkillBuilderDraft)
    case validate
    case beginDryRun(now: Date)
    case finishDryRun(now: Date)
    case runDryRun(now: Date)
    case deployPrivateV1(now: Date)
    case confirmDeploy(digest: String, now: Date)
    case installBinding(versionID: String, digest: String, bindingIdentifier: String, now: Date)
    case createPrivateShare(versionID: String, digest: String, recipient: String, expiresAt: Date, now: Date)
    case revokePrivateShare
    case clearBoundary
}

public struct SkillBuilderReducer: Sendable {
    public init() {}

    public func reduce(_ state: SkillBuilderState, _ action: SkillBuilderAction) -> SkillBuilderState {
        var next = state
        switch action {
        case .setAccountContext(let owner, let epoch):
            guard !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, epoch > 0 else { return next }
            if state.ownerSubject != owner || state.accountEpoch != epoch {
                next = SkillBuilderState(ownerSubject: owner, accountEpoch: epoch, status: .idle, quotaLimit: state.quotaLimit)
            } else if state.status == .unavailable {
                next.status = .idle
            }
        case .begin:
            guard hasCapability(next), [.idle, .tested, .deployed, .installed].contains(next.status) else { return next }
            next.status = .collectingMissingInfo
            next.desiredOutcome = ""
            next.missingInfo = [SkillBuilderMissingInfo(.desiredOutcome, explanation: "どんな結果にしたいかを一文で入力してください")]
            next.draft = nil
            next.validation = nil
            next.dryRun = nil
        case .setDesiredOutcome(let raw):
            guard hasCapability(next), [.collectingMissingInfo, .draft, .validationFailed].contains(next.status) else { return next }
            next.desiredOutcome = String(raw.prefix(2_000))
            next.missingInfo = next.missingInfo.filter { $0.id != .desiredOutcome }
            if next.desiredOutcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                next.missingInfo.append(SkillBuilderMissingInfo(.desiredOutcome, explanation: "達成したい結果が必要です"))
            }
            next.status = .collectingMissingInfo
        case .editDraft(let draft):
            guard hasCapability(next), [.collectingMissingInfo, .draft, .validationFailed, .readyForTest, .tested, .deployReview].contains(next.status) else { return next }
            next.draft = draft
            next.desiredOutcome = draft.desiredOutcome
            next.missingInfo = missingInfo(for: draft)
            next.validation = nil
            next.dryRun = nil
            next.pendingDeploymentDigest = nil
            next.pendingDeploymentVersionNumber = nil
            next.pendingDeploymentExpiresAt = nil
            next.status = next.missingInfo.isEmpty ? .draft : .collectingMissingInfo
        case .validate:
            guard hasCapability(next), let draft = next.draft, [.collectingMissingInfo, .draft, .validationFailed].contains(next.status) else { return next }
            let result = validate(draft: draft, state: next)
            next.validation = result
            next.status = result.isValid ? .readyForTest : .validationFailed
        case .beginDryRun:
            guard hasCapability(next), next.status == .readyForTest, let validation = next.validation, validation.isValid else { return next }
            guard next.quotaUsed + next.quotaReserved < next.quotaLimit else {
                next.status = .quotaExceeded
                return next
            }
            next.status = .testing
            next.quotaReserved += 1
        case .finishDryRun(let now):
            guard hasCapability(next), next.status == .testing, let draft = next.draft else { return next }
            next.quotaReserved = max(0, next.quotaReserved - 1)
            next.quotaUsed += 1
            next.dryRun = SkillDryRunResult(status: .passed, createdAt: now, safeSummary: "fixture入力だけで契約を確認しました。外部サービスは呼び出していません。", checkedContracts: ["typed manifest", "schema", "private policy", "static injection", "binding safety", "no public publish"], warnings: [], validatedExamples: draft.manifest.testExamples)
            next.status = .tested
        case .runDryRun(let now):
            let reserved = reduce(next, .beginDryRun(now: now))
            next = reduce(reserved, .finishDryRun(now: now))
        case .deployPrivateV1(let now):
            guard hasCapability(next), next.status == .tested, let draft = next.draft, next.validation?.isValid == true, next.dryRun?.status == .passed else { return next }
            let versionNumber = (next.versions.map(\.versionNumber).max() ?? 0) + 1
            let payload = canonicalManifest(draft: draft, ownerSubject: next.ownerSubject ?? "", accountEpoch: next.accountEpoch ?? 0, versionNumber: versionNumber, createdAt: now)
            let digest = sha256(payload)
            next.pendingDeploymentDigest = digest
            next.pendingDeploymentVersionNumber = versionNumber
            next.pendingDeploymentExpiresAt = now.addingTimeInterval(60)
            next.status = .deployReview
        case .confirmDeploy(let digest, let now):
            guard hasCapability(next), next.status == .deployReview, let draft = next.draft, let pendingDigest = next.pendingDeploymentDigest, pendingDigest == digest, let versionNumber = next.pendingDeploymentVersionNumber, let expiresAt = next.pendingDeploymentExpiresAt, now <= expiresAt else { return next }
            let stableSkillID = next.versions.first(where: { $0.draft.bindingIdentifier == draft.bindingIdentifier })?.skillID ?? PrivateSkillVersion.skillID(for: draft.bindingIdentifier)
            let version = PrivateSkillVersion(id: "sv_\(digest.dropFirst(7).prefix(24))", skillID: stableSkillID, versionNumber: versionNumber, digest: digest, createdAt: now, draft: draft)
            next.versions.append(version)
            next.pendingDeploymentDigest = nil
            next.pendingDeploymentVersionNumber = nil
            next.pendingDeploymentExpiresAt = nil
            next.status = .deployed
        case .installBinding(let versionID, let digest, let binding, let now):
            guard hasCapability(next), [.deployed, .installed].contains(next.status), let version = next.versions.first(where: { $0.id == versionID }), version.digest == digest, version.draft.bindingIdentifier == binding else { return next }
            next.installedBinding = InstalledSkillBinding(versionID: version.id, versionNumber: version.versionNumber, digest: version.digest, bindingIdentifier: binding, pinnedAt: now)
            next.status = .installed
        case .createPrivateShare(let versionID, let digest, let recipient, let expiresAt, let now):
            guard hasCapability(next), next.publicPublishDisabled, let version = next.versions.first(where: { $0.id == versionID }), version.digest == digest, !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, recipient.lowercased() != "public", expiresAt > now else { return next }
            next.privateShare = PrivateSkillShare(versionID: version.id, versionNumber: version.versionNumber, digest: version.digest, recipient: recipient, expiresAt: expiresAt)
        case .revokePrivateShare:
            next.privateShare = nil
        case .clearBoundary:
            next = SkillBuilderState()
        }
        return next
    }

    private func hasCapability(_ state: SkillBuilderState) -> Bool {
        guard let owner = state.ownerSubject, !owner.isEmpty, let epoch = state.accountEpoch else { return false }
        return epoch > 0 && state.publicPublishDisabled
    }

    private func missingInfo(for draft: SkillBuilderDraft) -> [SkillBuilderMissingInfo] {
        draft.missingFields.map { field in
            SkillBuilderMissingInfo(field, explanation: "\(field.title)を入力してください")
        }
    }

    private func validate(draft: SkillBuilderDraft, state: SkillBuilderState) -> SkillBuilderValidation {
        var issues: [SkillBuilderValidationIssue] = []
        let missing = missingInfo(for: draft)
        for field in missing {
            issues.append(issue("missing-\(field.id.rawValue)", "missing_info", .error, field.explanation))
        }
        let schemaValid: Bool
        if let data = draft.advancedSchema.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data), let dictionary = object as? [String: Any], let canonicalData = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys, .withoutEscapingSlashes]), let typedData = draft.manifest.canonicalSchema.data(using: .utf8), canonicalData == typedData {
            schemaValid = true
        } else {
            schemaValid = false
            issues.append(issue("schema", "schema_invalid", .error, "advanced schemaはallowlisted typed manifestのcanonical JSONと一致させてください"))
        }

        if draft.name == "Daily Digest" {
            issues.append(issue("fixture-name-conflict", "name_conflict", .error, "fixture catalog内のSkill名と競合しています"))
        }
        if draft.icon == "sparkles" {
            issues.append(issue("icon-conflict", "icon_conflict", .error, "このアイコンはfixture catalogで使用済みです"))
        }
        let allowedIcons = ["wand.and.stars", "calendar", "list.bullet.rectangle", "text.badge.checkmark", "checkmark.seal"]
        if !allowedIcons.contains(draft.icon) {
            issues.append(issue("icon-allowlist", "icon_invalid", .error, "アイコンはallowlisted SF Symbolから選択してください。emojiは使えません"))
        }
        if draft.bindingIdentifier == "typing" {
            issues.append(issue("binding-typing", "binding_reserved_typing", .error, "typingは予約bindingです"))
        } else if draft.bindingIdentifier == "accessibility" {
            issues.append(issue("binding-accessibility", "binding_reserved_accessibility", .error, "accessibilityは予約bindingです"))
        } else if draft.bindingIdentifier == "calendar.read" {
            issues.append(issue("binding-existing", "binding_existing", .error, "既存read-only bindingと競合しています"))
        }
        if !allowedName(draft.name) || !allowedBinding(draft.bindingIdentifier) {
            issues.append(issue("identifier", "identifier_invalid", .error, "名前とbindingには制御文字や空白を使えません"))
        }

        let combined = [draft.name, draft.desiredOutcome, draft.plainDescription, draft.advancedSchema].joined(separator: "\n").lowercased()
        let injectionTokens = ["ignore previous", "<script", "javascript:", "curl ", "http://", "https://", "${", "system(", "shell", "eval("]
        let injectionSafe = !injectionTokens.contains(where: combined.contains)
        if !injectionSafe {
            issues.append(issue("static-injection", "static_injection", .error, "静的検査で命令注入または外部実行らしい入力を拒否しました"))
        }
        let policyTokens = ["public publish", "公開", "send email", "メール送信", "invite", "招待"]
        let policyValid = !policyTokens.contains(where: combined.contains)
            && draft.manifest.allowedTools.allSatisfy { $0 == .none || $0 == .localTextTransform }
            && draft.manifest.riskCeiling == .r1LocalTransform
            && draft.manifest.confirmation == .always
        if !policyValid {
            issues.append(issue("policy", "private_policy", .error, "private Skillのtyped policy/risk/confirmation許可範囲外です"))
        }
        return SkillBuilderValidation(issues: issues, schemaValid: schemaValid, policyValid: policyValid, staticInjectionSafe: injectionSafe)
    }

    private func allowedName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !containsControl(trimmed)
    }

    private func allowedBinding(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }) && !containsControl(trimmed)
    }

    private func containsControl(_ value: String) -> Bool {
        value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private func issue(_ id: String, _ code: String, _ severity: SkillBuilderIssueSeverity, _ message: String) -> SkillBuilderValidationIssue {
        SkillBuilderValidationIssue(id: id, code: code, severity: severity, message: message)
    }

    private func canonicalManifest(draft: SkillBuilderDraft, ownerSubject: String, accountEpoch: Int, versionNumber: Int, createdAt: Date) -> String {
        let fields: [String: String] = [
            "accountEpoch": String(accountEpoch),
            "advancedSchema": draft.advancedSchema,
            "binding": draft.bindingIdentifier,
            "createdAt": ISO8601DateFormatter().string(from: createdAt),
            "desiredOutcome": draft.desiredOutcome,
            "icon": draft.icon,
            "name": draft.name,
            "ownerSubject": ownerSubject,
            "plainDescription": draft.plainDescription,
            "publicPublish": "disabled",
            "skillPlan": "private.v1",
            "version": String(versionNumber)
        ]
        if let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes]) {
            return String(decoding: data, as: UTF8.self)
        }
        return fields.keys.sorted().map { key in
            let value = fields[key] ?? ""
            return "\(key.utf8.count):\(key)\(value.utf8.count):\(value)"
        }.joined()
    }

    private func sha256(_ value: String) -> String {
        "sha256:" + SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public struct SkillBuilderFixtureClient: Sendable {
    public init() {}

    public func initialState() -> SkillBuilderState { SkillBuilderState() }
}
