import Foundation
import Combine
import MobileAIKeyboardCore

/// Local W3 fixture store. It intentionally has no identity provider or backend connection.
@MainActor
final class AccountActivityStore: ObservableObject {
    @Published private(set) var state: AccountActivityState
    @Published private(set) var connections: ConnectionsState
    private let reducer = AccountActivityReducer()
    private let fixture = AccountActivityFixtureClient()
    private let connectionsReducer = ConnectionsReducer()

    init() {
        state = fixture.initialState()
        connections = ConnectionsFixtureClient().initialState()
    }

    func send(_ action: AccountActivityAction) {
        state = reducer.reduce(state, action)
    }

    func send(_ action: ConnectionsAction) {
        let previousReceiptCount = connections.receipts.count
        connections = connectionsReducer.reduce(connections, action)
        if connections.receipts.count > previousReceiptCount {
            for receipt in connections.receipts.dropFirst(previousReceiptCount) {
                state = reducer.reduce(state, .appendActivity(receipt.activityRecord()))
            }
        }
    }
}
