import CryptoKit
import Foundation

public enum ReadOnlyProvider: String, CaseIterable, Identifiable, Sendable {
    case calendar = "Calendar"
    case notion = "Notion"
    case maps = "Maps"

    public var id: String { rawValue }
    public var operation: String {
        switch self {
        case .calendar: return "calendar.availability.read"
        case .notion: return "notion.pages.search"
        case .maps: return "maps.places.search"
        }
    }
    public var scope: String { operation }
    public var icon: String {
        switch self {
        case .calendar: return "calendar"
        case .notion: return "doc.text"
        case .maps: return "map"
        }
    }
}

public enum ConnectionStatus: String, Equatable, Sendable {
    case disconnected
    case scopeReview
    case connecting
    case connected
    case reconnectRequired
    case rebindRequired
    case revoked

    public var title: String {
        switch self {
        case .disconnected: return "未接続"
        case .scopeReview: return "権限を確認"
        case .connecting: return "接続中"
        case .connected: return "接続済み（読み取り専用）"
        case .reconnectRequired: return "再接続が必要"
        case .rebindRequired: return "アカウント再紐付けが必要"
        case .revoked: return "切断済み"
        }
    }
}

public struct ScopeRequest: Equatable, Sendable {
    public let identifier: String
    public let purpose: String
    public let readOnly: Bool
    public let incremental: Bool

    public init(identifier: String, purpose: String, readOnly: Bool = true, incremental: Bool = true) {
        self.identifier = identifier
        self.purpose = purpose
        self.readOnly = readOnly
        self.incremental = incremental
    }
}

public struct ConnectionRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let provider: ReadOnlyProvider
    public var status: ConnectionStatus
    public var accountLabel: String?
    public var grantedScopes: [String]
    public var connectionEpoch: Int
    public let requestedScopes: [ScopeRequest]

    public init(provider: ReadOnlyProvider, status: ConnectionStatus = .disconnected, accountLabel: String? = nil, grantedScopes: [String] = [], connectionEpoch: Int = 0, requestedScopes: [ScopeRequest]) {
        self.id = provider.rawValue
        self.provider = provider
        self.status = status
        self.accountLabel = accountLabel
        self.grantedScopes = grantedScopes
        self.connectionEpoch = connectionEpoch
        self.requestedScopes = requestedScopes
    }
}

public enum ResultFreshness: String, Equatable, Sendable {
    case fresh
    case stale
    case unknown
}

public struct SourceReference: Equatable, Sendable {
    public let provider: ReadOnlyProvider
    public let reference: String
    public let canonicalURL: String?

    public init(provider: ReadOnlyProvider, reference: String, canonicalURL: String? = nil) {
        self.provider = provider
        self.reference = reference
        self.canonicalURL = canonicalURL
    }
}

public struct ReadOnlyResult: Identifiable, Equatable, Sendable {
    public let id: String
    public let provider: ReadOnlyProvider
    public let title: String
    public let safeSummary: String
    public let source: SourceReference
    public let fetchedAt: Date
    public let freshness: ResultFreshness
    public let isPartial: Bool
    public let failure: String?
    public let untrustedContentWarning: Bool
    public let page: Int

    public init(id: String, provider: ReadOnlyProvider, title: String, safeSummary: String, source: SourceReference, fetchedAt: Date, freshness: ResultFreshness, isPartial: Bool = false, failure: String? = nil, untrustedContentWarning: Bool = true, page: Int = 1) {
        self.id = id
        self.provider = provider
        self.title = title
        self.safeSummary = safeSummary
        self.source = source
        self.fetchedAt = fetchedAt
        self.freshness = freshness
        self.isPartial = isPartial
        self.failure = failure
        self.untrustedContentWarning = untrustedContentWarning
        self.page = page
    }
}

public struct ReadOnlyReceipt: Identifiable, Equatable, Sendable {
    public let id: String
    public let provider: ReadOnlyProvider
    public let operation: String
    public let status: ActivityStatus
    public let createdAt: Date
    public let safeSummary: String
    public let failure: String?
    public let planVersion: String
    public let planDigest: String

    public init(id: String, provider: ReadOnlyProvider, operation: String, status: ActivityStatus, createdAt: Date, safeSummary: String, failure: String? = nil, planVersion: String, planDigest: String) {
        self.id = id
        self.provider = provider
        self.operation = operation
        self.status = status
        self.createdAt = createdAt
        self.safeSummary = safeSummary
        self.failure = failure
        self.planVersion = planVersion
        self.planDigest = planDigest
    }

    public func activityRecord() -> ActivityRecord {
        ActivityRecord(id: id, immutablePlanVersion: planVersion, riskClass: "R2 / read-only", status: status, createdAt: createdAt, updatedAt: createdAt, safeReceipt: safeSummary, safeFailure: failure, steps: [ActivityStep(id: "\(id)-step", operation: operation, status: status, safeSummary: safeSummary)], planDigest: planDigest)
    }
}

public struct ReadOnlyQuery: Equatable, Sendable {
    public let provider: ReadOnlyProvider
    public let text: String
    public let page: Int
    public let pageSize: Int

    public init(provider: ReadOnlyProvider, text: String, page: Int = 1, pageSize: Int = 10) {
        self.provider = provider
        self.text = String(text.prefix(200))
        self.page = max(1, page)
        self.pageSize = min(max(1, pageSize), 20)
    }
}

public struct ConnectionsState: Equatable, Sendable {
    public var connections: [ConnectionRecord]
    public var results: [ReadOnlyResult]
    public var receipts: [ReadOnlyReceipt]
    public var activeProvider: ReadOnlyProvider?
    public var currentPage: Int
    public var hasMore: Bool
    public var activeQuery: ReadOnlyQuery?

    public init(connections: [ConnectionRecord], results: [ReadOnlyResult] = [], receipts: [ReadOnlyReceipt] = [], activeProvider: ReadOnlyProvider? = nil, currentPage: Int = 1, hasMore: Bool = false, activeQuery: ReadOnlyQuery? = nil) {
        self.connections = connections
        self.results = results
        self.receipts = receipts
        self.activeProvider = activeProvider
        self.currentPage = currentPage
        self.hasMore = hasMore
        self.activeQuery = activeQuery
    }
}

public enum ConnectionsAction: Equatable, Sendable {
    case reviewScopes(ReadOnlyProvider)
    case beginConnection(ReadOnlyProvider)
    case finishConnection(ReadOnlyProvider, accountLabel: String)
    case reconnect(ReadOnlyProvider)
    case rebind(ReadOnlyProvider)
    case disconnect(ReadOnlyProvider)
    case execute(ReadOnlyQuery)
    case loadNextPage
}

public struct ConnectionsReducer: Sendable {
    public init() {}

    public func reduce(_ state: ConnectionsState, _ action: ConnectionsAction, now: Date = Date()) -> ConnectionsState {
        var next = state
        switch action {
        case .reviewScopes(let provider): update(&next, provider: provider) {
            guard $0.status == .disconnected || $0.status == .revoked else { return }
            $0.status = .scopeReview
        }
        case .beginConnection(let provider): update(&next, provider: provider) {
            guard $0.status == .scopeReview || $0.status == .reconnectRequired || $0.status == .rebindRequired else { return }
            $0.status = .connecting
        }
        case .finishConnection(let provider, let label): update(&next, provider: provider) { record in
            guard record.status == .connecting else { return }
            record.status = .connected; record.accountLabel = label; record.grantedScopes = record.requestedScopes.map(\.identifier); record.connectionEpoch += 1
        }
        case .reconnect(let provider): update(&next, provider: provider) {
            guard $0.status == .connected else { return }
            $0.status = .reconnectRequired
        }
        case .rebind(let provider): update(&next, provider: provider) {
            guard $0.status == .connected else { return }
            $0.status = .rebindRequired
        }
        case .disconnect(let provider):
            var disconnected = false
            update(&next, provider: provider) { record in
                guard [.connected, .reconnectRequired, .rebindRequired].contains(record.status) else { return }
                record.status = .disconnected; record.accountLabel = nil; record.grantedScopes = []; record.connectionEpoch += 1
                disconnected = true
            }
            if disconnected, next.activeProvider == provider {
                next.results = []; next.activeProvider = nil; next.activeQuery = nil; next.currentPage = 1; next.hasMore = false
            }
        case .execute(let query): execute(query, state: &next, now: now)
        case .loadNextPage:
            guard let query = next.activeQuery, next.hasMore else { break }
            execute(ReadOnlyQuery(provider: query.provider, text: query.text, page: next.currentPage + 1, pageSize: query.pageSize), state: &next, now: now)
        }
        return next
    }

    private func update(_ state: inout ConnectionsState, provider: ReadOnlyProvider, _ body: (inout ConnectionRecord) -> Void) {
        guard let index = state.connections.firstIndex(where: { $0.provider == provider }) else { return }
        body(&state.connections[index])
    }

    private func execute(_ query: ReadOnlyQuery, state: inout ConnectionsState, now: Date) {
        guard let connection = state.connections.first(where: { $0.provider == query.provider }), connection.status == .connected else { return }
        let page = query.page
        state.activeProvider = query.provider
        state.activeQuery = query
        state.currentPage = page
        state.hasMore = page == 1
        if page == 1 { state.results.removeAll() }
        state.results.append(contentsOf: fixtureResults(query: query, now: now))
        let receiptStatus: ActivityStatus = state.results.contains(where: { $0.failure != nil }) ? .partial : .succeeded
        let receipt = ReadOnlyReceipt(id: "receipt-\(query.provider.rawValue)-\(page)-\(Int(now.timeIntervalSince1970))", provider: query.provider, operation: query.provider.operation, status: receiptStatus, createdAt: now, safeSummary: "\(query.provider.rawValue)の読み取り結果を取得しました（外部変更なし）", failure: receiptStatus == .partial ? "一部の結果は取得できませんでした" : nil, planVersion: "\(query.provider.rawValue.lowercased()).read.v1", planDigest: planDigest("\(query.provider.operation)|\(query.text)|\(query.page)|\(query.pageSize)"))
        state.receipts.append(receipt)
    }

    private func planDigest(_ seed: String) -> String {
        let digest = SHA256.hash(data: Data(seed.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private func fixtureResults(query: ReadOnlyQuery, now: Date) -> [ReadOnlyResult] {
        switch query.provider {
        case .calendar:
            return [ReadOnlyResult(id: "calendar-\(query.page)-1", provider: .calendar, title: "空き時間候補", safeSummary: "2026-08-27 15:00（端末タイムゾーン）", source: SourceReference(provider: .calendar, reference: "calendar://fixture/availability/1"), fetchedAt: now, freshness: .fresh, page: query.page)]
        case .notion:
            return [ReadOnlyResult(id: "notion-\(query.page)-1", provider: .notion, title: "W4 Read-only notes", safeSummary: "Fixture workspace / 更新日時はサンプルです", source: SourceReference(provider: .notion, reference: "notion://fixture/page/1", canonicalURL: "https://notion.example.invalid/fixture/1"), fetchedAt: now, freshness: .fresh, page: query.page)]
        case .maps:
            return [ReadOnlyResult(id: "maps-\(query.page)-1", provider: .maps, title: "Fixture Cafe", safeSummary: "東京都渋谷区（サンプル）", source: SourceReference(provider: .maps, reference: "maps://fixture/place/1"), fetchedAt: now, freshness: .unknown, isPartial: true, failure: "営業時間は取得できませんでした", page: query.page)]
        }
    }
}

public struct ConnectionsFixtureClient: Sendable {
    public init() {}

    public func initialState() -> ConnectionsState {
        let connections = ReadOnlyProvider.allCases.map { provider in
            ConnectionRecord(provider: provider, requestedScopes: [ScopeRequest(identifier: provider.scope, purpose: "\(provider.rawValue)を検索・読み取るため", readOnly: true, incremental: true)])
        }
        return ConnectionsState(connections: connections)
    }
}
