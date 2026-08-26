import CryptoKit
import Foundation

private func fixturePlanDigest(_ seed: String) -> String {
    let digest = SHA256.hash(data: Data(seed.utf8))
    return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
}

public enum AccountState: Equatable, Sendable {
    case anonymous
    case signInRequired
    case signedIn(label: String)
    case sessionExpired
    case revoked

    public var title: String {
        switch self {
        case .anonymous: return "匿名・端末内モード"
        case .signInRequired: return "サインインが必要です"
        case .signedIn(let label): return "サインイン中: \(label)"
        case .sessionExpired: return "セッションの有効期限が切れました"
        case .revoked: return "この端末のセッションは失効しています"
        }
    }

    public var canUseAuthenticatedFeatures: Bool {
        if case .signedIn = self { return true }
        return false
    }
}

public enum DevicePlatform: String, Equatable, Sendable {
    case iPhone
    case iPad
    case mac
    case unknown
}

public enum DeviceState: String, Equatable, Sendable {
    case active
    case revoked
}

public struct DeviceRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let platform: DevicePlatform
    public let lastSeen: Date
    public let isCurrent: Bool
    public var state: DeviceState

    public init(id: String, label: String, platform: DevicePlatform, lastSeen: Date, isCurrent: Bool, state: DeviceState = .active) {
        self.id = id
        self.label = label
        self.platform = platform
        self.lastSeen = lastSeen
        self.isCurrent = isCurrent
        self.state = state
    }
}

public enum ActivityStatus: String, Equatable, Sendable {
    case running
    case succeeded
    case failed
    case partial
    case unknown
}

public struct ActivityStep: Identifiable, Equatable, Sendable {
    public let id: String
    public let operation: String
    public let status: ActivityStatus
    public let safeSummary: String

    public init(id: String, operation: String, status: ActivityStatus, safeSummary: String) {
        self.id = id
        self.operation = operation
        self.status = status
        self.safeSummary = safeSummary
    }
}

public struct ActivityRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let immutablePlanVersion: String
    public let riskClass: String
    public let status: ActivityStatus
    public let createdAt: Date
    public let updatedAt: Date
    public let safeReceipt: String
    public let safeFailure: String?
    public let steps: [ActivityStep]
    public let planDigest: String

    public init(id: String, immutablePlanVersion: String, riskClass: String, status: ActivityStatus, createdAt: Date, updatedAt: Date, safeReceipt: String, safeFailure: String? = nil, steps: [ActivityStep] = [], planDigest: String) {
        self.id = id
        self.immutablePlanVersion = immutablePlanVersion
        self.riskClass = riskClass
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.safeReceipt = safeReceipt
        self.safeFailure = safeFailure
        self.steps = steps
        self.planDigest = planDigest
    }
}

public enum RetentionPolicy: String, CaseIterable, Equatable, Sendable {
    case transient24Hours = "24時間（処理情報）"
    case receipts90Days = "90日（レシート）"
    case deleteImmediately = "すぐに削除"
}

public enum DeletionState: Equatable, Sendable {
    case idle
    case requested
    case inProgress(progress: Int)
    case completed
    case failed(reason: String)
}

public struct AccountActivityState: Equatable, Sendable {
    public var account: AccountState
    public var devices: [DeviceRecord]
    public var activities: [ActivityRecord]
    public var retention: RetentionPolicy
    public var deletion: DeletionState

    public init(account: AccountState, devices: [DeviceRecord], activities: [ActivityRecord], retention: RetentionPolicy, deletion: DeletionState = .idle) {
        self.account = account
        self.devices = devices
        self.activities = activities
        self.retention = retention
        self.deletion = deletion
    }
}

public enum AccountActivityAction: Equatable, Sendable {
    case requireSignIn
    case signInFixture(label: String)
    case expireSession
    case revokeSession
    case revokeDevice(id: String)
    case setRetention(RetentionPolicy)
    case requestDeletion
    case advanceDeletion
    case completeDeletion
    case failDeletion(reason: String)
    case appendActivity(ActivityRecord)
}

public struct AccountActivityReducer: Sendable {
    public init() {}

    @discardableResult
    public func reduce(_ state: AccountActivityState, _ action: AccountActivityAction, now: Date = Date()) -> AccountActivityState {
        var next = state
        switch action {
        case .requireSignIn:
            if case .anonymous = next.account { next.account = .signInRequired }
        case .signInFixture(let label):
            next.account = .signedIn(label: label)
        case .expireSession:
            if next.account.canUseAuthenticatedFeatures { next.account = .sessionExpired }
        case .revokeSession:
            next.account = .revoked
        case .revokeDevice(let id):
            next.devices = next.devices.map { device in
                guard device.id == id, device.state == .active else { return device }
                var copy = device; copy.state = .revoked; return copy
            }
            if next.devices.first(where: { $0.id == id })?.isCurrent == true { next.account = .revoked }
        case .setRetention(let policy):
            next.retention = policy
        case .requestDeletion:
            if next.deletion == .idle { next.deletion = .requested }
        case .advanceDeletion:
            switch next.deletion {
            case .requested: next.deletion = .inProgress(progress: 50)
            case .inProgress: next.deletion = .inProgress(progress: 90)
            default: break
            }
        case .completeDeletion:
            if case .inProgress = next.deletion {
                next.deletion = .completed
                next.account = .anonymous
                next.activities = []
                next.devices = []
            }
        case .failDeletion(let reason):
            switch next.deletion {
            case .requested, .inProgress: next.deletion = .failed(reason: reason)
            default: break
            }
        case .appendActivity(let activity):
            next.activities.insert(activity, at: 0)
        }
        _ = now
        return next
    }
}

/// Deterministic local-only fixture. It has no URLSession, identity SDK, or backend dependency.
public struct AccountActivityFixtureClient: Sendable {
    public init() {}

    public func initialState(now: Date = Date()) -> AccountActivityState {
        let current = DeviceRecord(id: "fixture-current", label: "このiPhone", platform: .iPhone, lastSeen: now, isCurrent: true)
        let other = DeviceRecord(id: "fixture-ipad", label: "テスト用iPad", platform: .iPad, lastSeen: now.addingTimeInterval(-86_400), isCurrent: false)
        let steps = [
            ActivityStep(id: "step-1", operation: "text.rewrite.local", status: .succeeded, safeSummary: "端末内で結果を生成"),
            ActivityStep(id: "step-2", operation: "text.apply", status: .succeeded, safeSummary: "入力欄へ適用")
        ]
        let activity = ActivityRecord(id: "run-fixture-1", immutablePlanVersion: "text-rewrite.v1", riskClass: "R1 / text transformation", status: .succeeded, createdAt: now.addingTimeInterval(-300), updatedAt: now.addingTimeInterval(-240), safeReceipt: "結果を入力欄へ適用しました（端末内）", steps: steps, planDigest: fixturePlanDigest("fixture-plan-v1"))
        let partial = ActivityRecord(id: "run-fixture-2", immutablePlanVersion: "calendar.read.v1", riskClass: "R2 / read-only", status: .partial, createdAt: now.addingTimeInterval(-7_200), updatedAt: now.addingTimeInterval(-7_100), safeReceipt: "一部の読み取り結果を確認しました", safeFailure: "接続が切れたため、残りの結果は未確定です", steps: [ActivityStep(id: "step-3", operation: "calendar.availability.read", status: .partial, safeSummary: "一部の応答のみ" )], planDigest: fixturePlanDigest("fixture-plan-v2"))
        let failed = ActivityRecord(id: "run-fixture-3", immutablePlanVersion: "notion.search.v1", riskClass: "R2 / read-only", status: .failed, createdAt: now.addingTimeInterval(-86_400), updatedAt: now.addingTimeInterval(-86_300), safeReceipt: "検索は実行されませんでした", safeFailure: "接続が設定されていません", steps: [ActivityStep(id: "step-4", operation: "notion.pages.search", status: .failed, safeSummary: "認証前に停止" )], planDigest: fixturePlanDigest("fixture-plan-v3"))
        return AccountActivityState(account: .anonymous, devices: [current, other], activities: [activity, partial, failed], retention: .receipts90Days)
    }
}
