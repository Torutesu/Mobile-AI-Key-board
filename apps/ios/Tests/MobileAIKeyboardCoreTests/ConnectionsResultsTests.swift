import XCTest
@testable import MobileAIKeyboardCore

final class ConnectionsResultsTests: XCTestCase {
    private let reducer = ConnectionsReducer()

    func testCalendarConnectionRequiresExplicitScopeReviewAndIsReadOnly() {
        var state = ConnectionsFixtureClient().initialState()
        XCTAssertEqual(state.connections.first(where: { $0.provider == .calendar })?.status, .disconnected)
        state = reducer.reduce(state, .reviewScopes(.calendar))
        XCTAssertEqual(state.connections.first(where: { $0.provider == .calendar })?.status, .scopeReview)
        XCTAssertTrue(state.connections.first(where: { $0.provider == .calendar })!.requestedScopes.allSatisfy { $0.readOnly && $0.incremental })
        state = reducer.reduce(state, .beginConnection(.calendar))
        XCTAssertEqual(state.connections.first(where: { $0.provider == .calendar })?.status, .connecting)
        state = reducer.reduce(state, .finishConnection(.calendar, accountLabel: "Fixture Calendar"))
        XCTAssertEqual(state.connections.first(where: { $0.provider == .calendar })?.status, .connected)
    }

    func testReconnectRebindAndDisconnectStatesAreDistinct() {
        var state = connected(.notion)
        state = reducer.reduce(state, .reconnect(.notion))
        XCTAssertEqual(state.connections.first(where: { $0.provider == .notion })?.status, .reconnectRequired)
        state = reducer.reduce(state, .beginConnection(.notion))
        state = reducer.reduce(state, .finishConnection(.notion, accountLabel: "Fixture Notion"))
        state = reducer.reduce(state, .rebind(.notion))
        XCTAssertEqual(state.connections.first(where: { $0.provider == .notion })?.status, .rebindRequired)
        state = reducer.reduce(state, .beginConnection(.notion))
        state = reducer.reduce(state, .finishConnection(.notion, accountLabel: "Fixture Notion 2"))
        XCTAssertEqual(state.connections.first(where: { $0.provider == .notion })?.connectionEpoch, 3)
        state = reducer.reduce(state, .disconnect(.notion))
        XCTAssertEqual(state.connections.first(where: { $0.provider == .notion })?.status, .disconnected)
    }

    func testInvalidConnectionTransitionsFailClosed() {
        var state = ConnectionsFixtureClient().initialState()
        state = reducer.reduce(state, .beginConnection(.calendar))
        state = reducer.reduce(state, .finishConnection(.calendar, accountLabel: "bypass"))
        state = reducer.reduce(state, .reconnect(.calendar))
        state = reducer.reduce(state, .rebind(.calendar))
        state = reducer.reduce(state, .disconnect(.calendar))
        let connection = state.connections.first { $0.provider == .calendar }!
        XCTAssertEqual(connection.status, .disconnected)
        XCTAssertEqual(connection.connectionEpoch, 0)
        XCTAssertTrue(connection.grantedScopes.isEmpty)
    }

    func testFixtureScopesMatchSharedAuthorityExactly() {
        let state = ConnectionsFixtureClient().initialState()
        XCTAssertEqual(state.connections.first { $0.provider == .calendar }?.requestedScopes.map(\.identifier), ["calendar.availability.read"])
        XCTAssertEqual(state.connections.first { $0.provider == .notion }?.requestedScopes.map(\.identifier), ["notion.pages.search"])
        XCTAssertEqual(state.connections.first { $0.provider == .maps }?.requestedScopes.map(\.identifier), ["maps.places.search"])
    }

    func testResultsAreSourceLinkedUntrustedAndReadOnlyReceiptIsEmitted() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var state = connected(.maps)
        state = reducer.reduce(state, .execute(ReadOnlyQuery(provider: .maps, text: String(repeating: "x", count: 500), pageSize: 100)), now: now)
        XCTAssertEqual(state.results.count, 1)
        let result = state.results[0]
        XCTAssertEqual(result.source.provider, .maps)
        XCTAssertEqual(result.fetchedAt, now)
        XCTAssertTrue(result.untrustedContentWarning)
        XCTAssertTrue(result.isPartial)
        XCTAssertEqual(result.failure, "営業時間は取得できませんでした")
        XCTAssertEqual(state.receipts.count, 1)
        XCTAssertEqual(state.receipts[0].status, .partial)
        XCTAssertEqual(state.receipts[0].operation, "maps.places.search")
        XCTAssertTrue(state.receipts[0].planDigest.range(of: #"^sha256:[0-9a-f]{64}$"#, options: .regularExpression) != nil)
    }

    func testPaginationIsBoundedAndOnlyConnectedProviderExecutes() {
        var state = ConnectionsFixtureClient().initialState()
        state = reducer.reduce(state, .execute(ReadOnlyQuery(provider: .calendar, text: "fixture", page: 99, pageSize: 99)))
        XCTAssertTrue(state.results.isEmpty)
        state = connected(.calendar)
        state = reducer.reduce(state, .execute(ReadOnlyQuery(provider: .calendar, text: "original query", pageSize: 20)))
        XCTAssertTrue(state.hasMore)
        state = reducer.reduce(state, .loadNextPage)
        XCTAssertEqual(state.currentPage, 2)
        XCTAssertEqual(state.results.count, 2)
        XCTAssertEqual(state.activeQuery?.text, "original query")
        XCTAssertEqual(state.activeQuery?.pageSize, 20)
    }

    func testDisconnectClearsActiveProviderResultsAndPagination() {
        var state = connected(.calendar)
        state = reducer.reduce(state, .execute(ReadOnlyQuery(provider: .calendar, text: "fixture")))
        XCTAssertFalse(state.results.isEmpty)
        state = reducer.reduce(state, .disconnect(.calendar))
        XCTAssertTrue(state.results.isEmpty)
        XCTAssertNil(state.activeProvider)
        XCTAssertNil(state.activeQuery)
        XCTAssertFalse(state.hasMore)
    }

    private func connected(_ provider: ReadOnlyProvider) -> ConnectionsState {
        var state = ConnectionsFixtureClient().initialState()
        state = reducer.reduce(state, .reviewScopes(provider))
        state = reducer.reduce(state, .beginConnection(provider))
        return reducer.reduce(state, .finishConnection(provider, accountLabel: "Fixture"))
    }
}
