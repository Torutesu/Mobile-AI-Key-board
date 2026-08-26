import CryptoKit
import Foundation

public struct PrivateCalendarEventDraft: Equatable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date
    public let timezoneIdentifier: String
    public let calendarIdentifier: String

    public init(title: String, start: Date, end: Date, timezoneIdentifier: String, calendarIdentifier: String) {
        self.title = String(title.prefix(200))
        self.start = start
        self.end = end
        self.timezoneIdentifier = String(timezoneIdentifier.prefix(100))
        self.calendarIdentifier = String(calendarIdentifier.prefix(200))
    }

    public var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && end > start
            && !timezoneIdentifier.isEmpty
            && calendarIdentifier == "fixture-private"
    }
}

public struct CalendarWriteCapability: Equatable, Sendable {
    public let accountLabel: String
    /// Stable local subject binding for this fixture capability. It is kept
    /// separate from the display label so an owner swap cannot reuse a plan.
    public let ownerSubject: String
    public let connectionEpoch: Int
    public let canCreatePrivateNoInvite: Bool
    public let fixtureOnly: Bool

    public init(accountLabel: String, ownerSubject: String? = nil, connectionEpoch: Int, canCreatePrivateNoInvite: Bool, fixtureOnly: Bool = true) {
        self.accountLabel = accountLabel
        self.ownerSubject = String((ownerSubject ?? accountLabel).prefix(200))
        self.connectionEpoch = connectionEpoch
        self.canCreatePrivateNoInvite = canCreatePrivateNoInvite
        self.fixtureOnly = fixtureOnly
    }
}

public struct CalendarWritePlan: Equatable, Sendable {
    public let draft: PrivateCalendarEventDraft
    public let canonicalPayload: String
    public let confirmationDigest: String
    public let expiresAt: Date
    public let connectionEpoch: Int
    public let ownerSubject: String

    public init(draft: PrivateCalendarEventDraft, canonicalPayload: String, confirmationDigest: String, expiresAt: Date, connectionEpoch: Int, ownerSubject: String = "") {
        self.draft = draft
        self.canonicalPayload = canonicalPayload
        self.confirmationDigest = confirmationDigest
        self.expiresAt = expiresAt
        self.connectionEpoch = connectionEpoch
        self.ownerSubject = ownerSubject
    }
}

public struct CalendarResourceReference: Equatable, Sendable {
    public let provider: ReadOnlyProvider
    public let resourceIdentifier: String
    public let sourceReference: String

    public init(provider: ReadOnlyProvider = .calendar, resourceIdentifier: String, sourceReference: String) {
        self.provider = provider
        self.resourceIdentifier = resourceIdentifier
        self.sourceReference = sourceReference
    }
}

public enum CalendarWriteReceiptStatus: String, Equatable, Sendable {
    case succeeded
    case failed
    case partial
    case unknown
    case undone
}

public struct CalendarWriteReceipt: Equatable, Sendable {
    public let id: String
    public let status: CalendarWriteReceiptStatus
    public let createdAt: Date
    public let safeSummary: String
    public let failure: String?
    public let resource: CalendarResourceReference?
    public let planDigest: String

    public init(id: String, status: CalendarWriteReceiptStatus, createdAt: Date, safeSummary: String, failure: String? = nil, resource: CalendarResourceReference? = nil, planDigest: String) {
        self.id = id
        self.status = status
        self.createdAt = createdAt
        self.safeSummary = safeSummary
        self.failure = failure
        self.resource = resource
        self.planDigest = planDigest
    }

    public func activityRecord() -> ActivityRecord {
        let status: ActivityStatus
        switch self.status {
        case .succeeded, .undone: status = .succeeded
        case .failed: status = .failed
        case .partial: status = .partial
        case .unknown: status = .unknown
        }
        let operation = self.status == .undone ? "calendar.event.delete_own" : "calendar.event.create_private"
        return ActivityRecord(id: id, immutablePlanVersion: "\(operation).v1", riskClass: "R3 / confirmed private write", status: status, createdAt: createdAt, updatedAt: createdAt, safeReceipt: safeSummary, safeFailure: failure, steps: [ActivityStep(id: "\(id)-step", operation: operation, status: status, safeSummary: safeSummary)], planDigest: planDigest)
    }
}

public struct CalendarUndoTicket: Equatable, Sendable {
    public let resource: CalendarResourceReference
    public let expiresAt: Date
    public let oneShot: Bool

    public init(resource: CalendarResourceReference, expiresAt: Date, oneShot: Bool = true) {
        self.resource = resource
        self.expiresAt = expiresAt
        self.oneShot = oneShot
    }
}

public enum CalendarWriteStatus: Equatable, Sendable {
    case unavailable
    case idle
    case draft
    case review
    case confirmed
    case executing
    case succeeded
    case failed
    case partial
    case unknown
    case reconciling
    case undone
    case expired

    public var title: String {
        switch self {
        case .unavailable: return "write capability未接続"
        case .idle: return "private write待機中"
        case .draft: return "下書き"
        case .review: return "確認待ち"
        case .confirmed: return "確認済み"
        case .executing: return "実行中"
        case .succeeded: return "作成済み"
        case .failed: return "失敗"
        case .partial: return "部分成功"
        case .unknown: return "結果不明（再試行禁止）"
        case .reconciling: return "結果を照合中"
        case .undone: return "Undo済み"
        case .expired: return "期限切れ"
        }
    }
}

public struct CalendarWriteState: Equatable, Sendable {
    public var capability: CalendarWriteCapability?
    public var status: CalendarWriteStatus
    public var draft: PrivateCalendarEventDraft?
    public var plan: CalendarWritePlan?
    public var receipt: CalendarWriteReceipt?
    public var undoTicket: CalendarUndoTicket?
    public var hasReconciledUnknown: Bool

    public init(capability: CalendarWriteCapability? = nil, status: CalendarWriteStatus = .unavailable, draft: PrivateCalendarEventDraft? = nil, plan: CalendarWritePlan? = nil, receipt: CalendarWriteReceipt? = nil, undoTicket: CalendarUndoTicket? = nil, hasReconciledUnknown: Bool = false) {
        self.capability = capability
        self.status = status
        self.draft = draft
        self.plan = plan
        self.receipt = receipt
        self.undoTicket = undoTicket
        self.hasReconciledUnknown = hasReconciledUnknown
    }
}

public enum CalendarWriteOutcome: Equatable, Sendable {
    case succeeded(resource: CalendarResourceReference)
    case failed(reason: String)
    case partial(reason: String)
    case unknown(reason: String)
}

public enum CalendarWriteAction: Equatable, Sendable {
    case enableFixtureCapability(accountLabel: String, connectionEpoch: Int)
    case disableCapability
    case beginDraft(PrivateCalendarEventDraft)
    case review(now: Date)
    case editDraft(PrivateCalendarEventDraft)
    case confirm(digest: String, now: Date)
    case beginExecution(now: Date)
    case settle(CalendarWriteOutcome, now: Date)
    case reconcile(CalendarWriteOutcome, now: Date)
    case undo(resource: CalendarResourceReference, now: Date)
    case clearBoundary
}

public struct CalendarWriteReducer: Sendable {
    public init() {}

    public func reduce(_ state: CalendarWriteState, _ action: CalendarWriteAction) -> CalendarWriteState {
        var next = state
        switch action {
        case .enableFixtureCapability(let label, let epoch):
            next.capability = CalendarWriteCapability(accountLabel: label, connectionEpoch: epoch, canCreatePrivateNoInvite: true)
            next.status = .idle; next.draft = nil; next.plan = nil; next.receipt = nil; next.undoTicket = nil; next.hasReconciledUnknown = false
        case .disableCapability, .clearBoundary:
            next = CalendarWriteState()
        case .beginDraft(let draft):
            guard let capability = next.capability, capability.canCreatePrivateNoInvite, draft.isValid, next.status == .idle || next.status == .draft || next.status == .review else { return next }
            next.draft = draft; next.plan = nil; next.receipt = nil; next.undoTicket = nil; next.status = .draft; next.hasReconciledUnknown = false
        case .review(let now):
            guard let capability = next.capability, capability.canCreatePrivateNoInvite, let draft = next.draft, draft.isValid, [.draft, .review].contains(next.status) else { return next }
            let expiresAt = now.addingTimeInterval(60)
            let payload = canonicalPayload(draft: draft, epoch: capability.connectionEpoch, ownerSubject: capability.ownerSubject, expiresAt: expiresAt)
            next.plan = CalendarWritePlan(draft: draft, canonicalPayload: payload, confirmationDigest: digest(payload), expiresAt: expiresAt, connectionEpoch: capability.connectionEpoch, ownerSubject: capability.ownerSubject)
            next.status = .review
        case .editDraft(let draft):
            // Editing after confirmation invalidates the prior digest. Once execution
            // starts or a receipt exists, editing is fail-closed and ignored.
            guard draft.isValid, [.draft, .review, .confirmed].contains(next.status) else { return next }
            next.draft = draft; next.plan = nil; next.status = .draft
        case .confirm(let digestValue, let now):
            guard let plan = next.plan, next.status == .review, now <= plan.expiresAt, digestValue == plan.confirmationDigest,
                  next.capability?.connectionEpoch == plan.connectionEpoch,
                  next.capability?.ownerSubject == plan.ownerSubject else { return next }
            next.status = .confirmed
        case .beginExecution(let now):
            guard next.status == .confirmed, let plan = next.plan, let capability = next.capability else { return next }
            if now > plan.expiresAt {
                next.status = .expired
                return next
            }
            guard capability.canCreatePrivateNoInvite,
                  capability.connectionEpoch == plan.connectionEpoch,
                  capability.ownerSubject == plan.ownerSubject else { return next }
            next.status = .executing
        case .settle(let outcome, let now):
            guard next.status == .executing, let plan = next.plan else { return next }
            guard isAllowedOutcome(outcome) else { return next }
            applyOutcome(&next, outcome: outcome, plan: plan, now: now)
        case .reconcile(let outcome, let now):
            guard next.status == .unknown, !next.hasReconciledUnknown, let plan = next.plan else { return next }
            guard case .succeeded = outcome else {
                guard case .failed = outcome else { return next }
                applyOutcome(&next, outcome: outcome, plan: plan, now: now)
                next.hasReconciledUnknown = true
                return next
            }
            guard isAllowedOutcome(outcome) else { return next }
            next.status = .reconciling
            applyOutcome(&next, outcome: outcome, plan: plan, now: now)
            next.hasReconciledUnknown = true
        case .undo(let resource, let now):
            guard isAllowedOutcome(.succeeded(resource: resource)), next.status == .succeeded, let ticket = next.undoTicket, ticket.resource == resource, now <= ticket.expiresAt, ticket.oneShot, let receipt = next.receipt, receipt.resource == resource else { return next }
            next.status = .undone
            next.undoTicket = nil
            next.receipt = CalendarWriteReceipt(id: "undo-\(receipt.id)", status: .undone, createdAt: now, safeSummary: "作成したprivate予定をUndoしました（fixture）", resource: resource, planDigest: receipt.planDigest)
        }
        return next
    }

    private func applyOutcome(_ state: inout CalendarWriteState, outcome: CalendarWriteOutcome, plan: CalendarWritePlan, now: Date) {
        switch outcome {
        case .succeeded(let resource):
            state.status = .succeeded
            state.receipt = CalendarWriteReceipt(id: "write-\(plan.confirmationDigest.prefix(12))", status: .succeeded, createdAt: now, safeSummary: "招待なしのprivate予定を作成しました（fixture）", resource: resource, planDigest: plan.confirmationDigest)
            state.undoTicket = CalendarUndoTicket(resource: resource, expiresAt: now.addingTimeInterval(300))
        case .failed(let reason):
            state.status = .failed; state.receipt = CalendarWriteReceipt(id: "write-failed-\(plan.confirmationDigest.prefix(12))", status: .failed, createdAt: now, safeSummary: "予定は作成されていません", failure: reason, planDigest: plan.confirmationDigest)
        case .partial(let reason):
            state.status = .partial; state.receipt = CalendarWriteReceipt(id: "write-partial-\(plan.confirmationDigest.prefix(12))", status: .partial, createdAt: now, safeSummary: "予定作成の一部結果を確認してください", failure: reason, planDigest: plan.confirmationDigest)
        case .unknown(let reason):
            state.status = .unknown; state.receipt = CalendarWriteReceipt(id: "write-unknown-\(plan.confirmationDigest.prefix(12))", status: .unknown, createdAt: now, safeSummary: "作成結果が不明です。盲目的な再試行は停止しました", failure: reason, planDigest: plan.confirmationDigest)
        }
    }

    private func canonicalPayload(draft: PrivateCalendarEventDraft, epoch: Int, ownerSubject: String, expiresAt: Date) -> String {
        let fields: [String: String] = [
            "attendees": "none",
            "calendar": "private",
            "calendarID": draft.calendarIdentifier,
            "connectionEpoch": String(epoch),
            "end": canonicalDate(draft.end),
            "expiresAt": canonicalDate(expiresAt),
            "externalEffect": "create exactly one private Calendar event",
            "invite": "false",
            "operation": "calendar.event.create_private.v1",
            "ownerSubject": ownerSubject,
            "riskClass": "R3",
            "sendUpdates": "none",
            "start": canonicalDate(draft.start),
            "timezone": draft.timezoneIdentifier,
            "title": draft.title
        ]
        // sortedKeys gives one canonical representation while JSON escaping
        // keeps pipes, newlines, and delimiter-like user input unambiguous.
        if let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes]) {
            return String(decoding: data, as: UTF8.self)
        }
        // All values above are strings, so this is only a defensive fallback.
        return fields.keys.sorted().map { key in
            let value = fields[key] ?? ""
            return "\(key.utf8.count):\(key)\(value.utf8.count):\(value)"
        }.joined()
    }

    private func isAllowedOutcome(_ outcome: CalendarWriteOutcome) -> Bool {
        guard case .succeeded(let resource) = outcome else { return true }
        return resource.provider == .calendar
            && resource.sourceReference.hasPrefix("calendar://fixture/private-event/")
            && resource.resourceIdentifier.hasPrefix("fixture-event-")
    }

    private func canonicalDate(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private func digest(_ payload: String) -> String { "sha256:" + SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined() }
}

public struct CalendarWriteFixtureClient: Sendable {
    public init() {}

    public func initialState() -> CalendarWriteState { CalendarWriteState() }
    public func successResource() -> CalendarResourceReference { CalendarResourceReference(resourceIdentifier: "fixture-event-1", sourceReference: "calendar://fixture/private-event/1") }
}
