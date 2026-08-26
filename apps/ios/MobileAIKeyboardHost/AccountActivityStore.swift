import Foundation
import Combine
import MobileAIKeyboardCore

/// Local W3 fixture store. It intentionally has no identity provider or backend connection.
@MainActor
final class AccountActivityStore: ObservableObject {
    @Published private(set) var state: AccountActivityState
    @Published private(set) var connections: ConnectionsState
    @Published private(set) var calendarWrite: CalendarWriteState
    private let reducer = AccountActivityReducer()
    private let fixture = AccountActivityFixtureClient()
    private let connectionsReducer = ConnectionsReducer()
    private let calendarWriteReducer = CalendarWriteReducer()

    init() {
        state = fixture.initialState()
        connections = ConnectionsFixtureClient().initialState()
        calendarWrite = CalendarWriteFixtureClient().initialState()
    }

    func send(_ action: AccountActivityAction) {
        let wasAuthenticated = state.account.canUseAuthenticatedFeatures
        state = reducer.reduce(state, action)
        if wasAuthenticated, !state.account.canUseAuthenticatedFeatures {
            calendarWrite = calendarWriteReducer.reduce(calendarWrite, .clearBoundary)
        }
    }

    func send(_ action: ConnectionsAction) {
        let previousReceiptCount = connections.receipts.count
        connections = connectionsReducer.reduce(connections, action)
        if case .disconnect(.calendar) = action {
            calendarWrite = calendarWriteReducer.reduce(calendarWrite, .clearBoundary)
        } else if case .reconnect(.calendar) = action {
            calendarWrite = calendarWriteReducer.reduce(calendarWrite, .clearBoundary)
        } else if case .rebind(.calendar) = action {
            calendarWrite = calendarWriteReducer.reduce(calendarWrite, .clearBoundary)
        }
        if connections.receipts.count > previousReceiptCount {
            for receipt in connections.receipts.dropFirst(previousReceiptCount) {
                state = reducer.reduce(state, .appendActivity(receipt.activityRecord()))
            }
        }
    }

    func send(_ action: CalendarWriteAction) {
        if case .enableFixtureCapability = action, !canEnableCalendarWriteFixture { return }
        let previousReceipt = calendarWrite.receipt
        calendarWrite = calendarWriteReducer.reduce(calendarWrite, action)
        if calendarWrite.receipt != previousReceipt, let receipt = calendarWrite.receipt {
            state = reducer.reduce(state, .appendActivity(receipt.activityRecord()))
        }
    }

    var canEnableCalendarWriteFixture: Bool {
        state.account.canUseAuthenticatedFeatures
            && connections.connections.contains { $0.provider == .calendar && $0.status == .connected }
    }
}
