import Foundation
import Combine
import MobileAIKeyboardCore

/// Local W3 fixture store. It intentionally has no identity provider or backend connection.
@MainActor
final class AccountActivityStore: ObservableObject {
    @Published private(set) var state: AccountActivityState
    private let reducer = AccountActivityReducer()
    private let fixture = AccountActivityFixtureClient()

    init() {
        state = fixture.initialState()
    }

    func send(_ action: AccountActivityAction) {
        state = reducer.reduce(state, action)
    }
}
