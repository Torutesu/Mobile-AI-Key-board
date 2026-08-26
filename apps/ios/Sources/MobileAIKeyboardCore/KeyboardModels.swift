import Foundation

public enum KeyboardScreen: Equatable, Sendable {
    case typing
    case command
    case captureReview(CaptureDraft)
    case planning
    case resultReview(RewriteResult)
    case actionReview
    case executing
    case receipt(Receipt)
    case locked(LockReason)
    case error(KeyboardError)
}

public struct CaptureDraft: Equatable, Sendable {
    public let text: String
    public let source: CaptureSource
    public let acknowledged: Bool
    public let fieldFingerprint: String

    public init(text: String, source: CaptureSource = .selection, acknowledged: Bool = false, fieldFingerprint: String) {
        self.text = text
        self.source = source
        self.acknowledged = acknowledged
        self.fieldFingerprint = fieldFingerprint
    }

    public func acknowledging() -> CaptureDraft {
        CaptureDraft(text: text, source: source, acknowledged: true, fieldFingerprint: fieldFingerprint)
    }
}

public enum CaptureSource: String, Equatable, Sendable {
    case command
    case selection
    case surroundingContext
}

public struct RewriteResult: Equatable, Sendable {
    public let original: String
    public let rewritten: String
    public let preservedEntities: [String]
    public let fieldFingerprint: String

    public init(original: String, rewritten: String, preservedEntities: [String], fieldFingerprint: String) {
        self.original = original
        self.rewritten = rewritten
        self.preservedEntities = preservedEntities
        self.fieldFingerprint = fieldFingerprint
    }
}

public struct Receipt: Equatable, Sendable {
    public let status: ReceiptStatus
    public let operation: String
    public let canUndo: Bool

    public init(status: ReceiptStatus, operation: String, canUndo: Bool = false) {
        self.status = status
        self.operation = operation
        self.canUndo = canUndo
    }
}

public enum ReceiptStatus: String, Equatable, Sendable {
    case succeeded
    case failed
    case partial
    case unknown
}

public enum LockReason: String, Equatable, Sendable {
    case secureField
    case unsupportedField
    case fullAccessRequired

    public var accessibilityLabel: String {
        switch self {
        case .secureField: return "安全な入力欄ではAI機能を利用できません"
        case .unsupportedField: return "この入力欄ではAI機能を利用できません"
        case .fullAccessRequired: return "AI機能にはフルアクセスの許可が必要です"
        }
    }
}

public enum KeyboardError: String, Equatable, Sendable {
    case missingDisclosure
    case staleField
    case emptyInput
    case offline
    case cancelled
    case unavailable

    public var recoveryMessage: String {
        switch self {
        case .missingDisclosure: return "送信する内容を確認してから続けてください。"
        case .staleField: return "入力欄の内容が変更されたため、自動置換を止めました。"
        case .emptyInput: return "処理する文章を入力してください。"
        case .offline: return "オフラインです。通常入力は引き続き利用できます。"
        case .cancelled: return "処理をキャンセルしました。"
        case .unavailable: return "この機能は現在利用できません。"
        }
    }
}

public enum KeyboardAction: Equatable, Sendable {
    case invokeCommand
    case cancel
    case beginCapture(CaptureDraft)
    case acknowledgeCapture
    case beginPlanning
    case showRewrite(RewriteResult)
    case applyResult(currentFieldFingerprint: String)
    case showActionReview
    case confirmExecution
    case settle(Receipt)
    case fail(KeyboardError)
    case lock(LockReason)
    case unlock
}
