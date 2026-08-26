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
    case applied(UndoToken)
    case locked(LockReason)
    case error(KeyboardError)
}

public struct EditorSnapshot: Equatable, Sendable {
    public let documentIdentifier: String
    public let fieldFingerprint: String
    public let expectedAppliedFingerprint: String?

    public init(documentIdentifier: String, fieldFingerprint: String, expectedAppliedFingerprint: String? = nil) {
        self.documentIdentifier = documentIdentifier
        self.fieldFingerprint = fieldFingerprint
        self.expectedAppliedFingerprint = expectedAppliedFingerprint
    }
}

public struct CaptureDraft: Equatable, Sendable {
    public let text: String
    public let source: CaptureSource
    public let acknowledged: Bool
    public let fieldFingerprint: String
    public let redactedText: String
    public let characterCount: Int
    public let externalTransmissionAllowed: Bool
    public let fallbackMessage: String?
    public let documentIdentifier: String?

    public init(text: String, source: CaptureSource = .selection, acknowledged: Bool = false, fieldFingerprint: String, redactedText: String? = nil, externalTransmissionAllowed: Bool = false, fallbackMessage: String? = nil, documentIdentifier: String? = nil) {
        self.text = text
        self.source = source
        self.acknowledged = acknowledged
        self.fieldFingerprint = fieldFingerprint
        self.redactedText = redactedText ?? text
        self.characterCount = text.count
        self.externalTransmissionAllowed = externalTransmissionAllowed
        self.fallbackMessage = fallbackMessage
        self.documentIdentifier = documentIdentifier
    }

    public func acknowledging() -> CaptureDraft {
        CaptureDraft(text: text, source: source, acknowledged: true, fieldFingerprint: fieldFingerprint, redactedText: redactedText, externalTransmissionAllowed: externalTransmissionAllowed, fallbackMessage: fallbackMessage, documentIdentifier: documentIdentifier)
    }
}

public enum CaptureSource: String, Hashable, Equatable, Sendable {
    case command
    case selection
    case surroundingContext
}

public enum LocalTextLimits {
    public static let commandCharacters = 500
    public static let selectionCharacters = 4_000
    public static let surroundingBeforeCharacters = 1_000
    public static let surroundingAfterCharacters = 500
    public static let resultCharacters = 10_000
}

public struct RedactionResult: Equatable, Sendable {
    public let redacted: String
    public let detected: [String]
    public let blocked: Bool

    public init(redacted: String, detected: [String], blocked: Bool) {
        self.redacted = redacted
        self.detected = detected
        self.blocked = blocked
    }
}

public struct RewriteResult: Equatable, Sendable {
    public let original: String
    public let rewritten: String
    public let preservedEntities: [String]
    public let fieldFingerprint: String
    public let documentIdentifier: String?

    public init(original: String, rewritten: String, preservedEntities: [String], fieldFingerprint: String, documentIdentifier: String? = nil) {
        self.original = original
        self.rewritten = rewritten
        self.preservedEntities = preservedEntities
        self.fieldFingerprint = fieldFingerprint
        self.documentIdentifier = documentIdentifier
    }
}

public struct UndoToken: Equatable, Sendable {
    public let original: String
    public let rewritten: String
    public let originalFingerprint: String
    public let appliedFingerprint: String
    public let documentIdentifier: String?

    public init(original: String, rewritten: String, originalFingerprint: String, appliedFingerprint: String, documentIdentifier: String? = nil) {
        self.original = original
        self.rewritten = rewritten
        self.originalFingerprint = originalFingerprint
        self.appliedFingerprint = appliedFingerprint
        self.documentIdentifier = documentIdentifier
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
    case captureTooLarge
    case resultTooLarge
    case protectedEntityChanged
    case activeSelectionNotApproved
    case surroundingContextApplyUnavailable

    public var recoveryMessage: String {
        switch self {
        case .missingDisclosure: return "送信する内容を確認してから続けてください。"
        case .staleField: return "入力欄の内容が変更されたため、自動置換を止めました。"
        case .emptyInput: return "処理する文章を入力してください。"
        case .offline: return "オフラインです。通常入力は引き続き利用できます。"
        case .cancelled: return "処理をキャンセルしました。"
        case .unavailable: return "この機能は現在利用できません。"
        case .captureTooLarge: return "入力が上限を超えています。範囲を短くしてから再試行してください。"
        case .resultTooLarge: return "結果が10,000文字を超えているため適用できません。"
        case .protectedEntityChanged: return "保護対象の名前・日時・数値・URLなどが変更されたため適用を停止しました。"
        case .activeSelectionNotApproved: return "未承認の選択範囲を置換する可能性があるため適用を停止しました。選択範囲を入力ソースに指定してください。"
        case .surroundingContextApplyUnavailable: return "前後の文章は安全に範囲置換できないため、自動適用を停止しました。結果をコピーしてください。"
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
    case updateRewrite(RewriteResult)
    case applyResult(currentFieldFingerprint: String)
    case applyResultWithSnapshot(EditorSnapshot)
    case undo(currentFieldFingerprint: String)
    case undoWithSnapshot(EditorSnapshot)
    case editResult
    case regenerateResult
    case copyResult
    case showActionReview
    case confirmExecution
    case settle(Receipt)
    case fail(KeyboardError)
    case lock(LockReason)
    case unlock
}
