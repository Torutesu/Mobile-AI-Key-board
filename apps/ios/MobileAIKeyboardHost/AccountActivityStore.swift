import Foundation
import Combine
import MobileAIKeyboardCore

/// Local W3 fixture store. It intentionally has no identity provider or backend connection.
@MainActor
final class AccountActivityStore: ObservableObject {
    @Published private(set) var state: AccountActivityState
    @Published private(set) var connections: ConnectionsState
    @Published private(set) var calendarWrite: CalendarWriteState
    @Published private(set) var skillBuilder: SkillBuilderState
    @Published private(set) var settings: KeyboardSettingsState
    @Published private(set) var qualification: QualificationState
    private var qualificationOwnerSubject: String?
    private var qualificationSessionExpiresAt: Date?
    private let reducer = AccountActivityReducer()
    private let fixture = AccountActivityFixtureClient()
    private let connectionsReducer = ConnectionsReducer()
    private let calendarWriteReducer = CalendarWriteReducer()
    private let skillBuilderReducer = SkillBuilderReducer()
    private let settingsReducer = KeyboardSettingsReducer()
    private let qualificationReducer = QualificationReducer()

    init() {
        state = fixture.initialState()
        connections = ConnectionsFixtureClient().initialState()
        calendarWrite = CalendarWriteFixtureClient().initialState()
        skillBuilder = SkillBuilderFixtureClient().initialState()
        settings = .defaultFixture
        qualification = QualificationState()
        qualificationOwnerSubject = nil
        qualificationSessionExpiresAt = nil
    }

    func send(_ action: AccountActivityAction) {
        let wasAuthenticated = state.account.canUseAuthenticatedFeatures
        state = reducer.reduce(state, action)
        if case .signInFixture(let label) = action {
            // A new fixture subject must not inherit protected settings or qualification state.
            if wasAuthenticated {
                calendarWrite = calendarWriteReducer.reduce(calendarWrite, .clearBoundary)
                skillBuilder = skillBuilderReducer.reduce(skillBuilder, .clearBoundary)
                settings = settingsReducer.reduce(settings, .clearBoundary)
                qualification = qualificationReducer.reduce(qualification, .clearBoundary)
                qualificationOwnerSubject = nil
                qualificationSessionExpiresAt = nil
            }
            skillBuilder = skillBuilderReducer.reduce(skillBuilder, .setAccountContext(ownerSubject: "fixture-user:\(label)", accountEpoch: 1))
            qualificationOwnerSubject = "fixture-user:\(label)"
            qualificationSessionExpiresAt = Date().addingTimeInterval(3_600)
        }
        if wasAuthenticated, !state.account.canUseAuthenticatedFeatures {
            calendarWrite = calendarWriteReducer.reduce(calendarWrite, .clearBoundary)
            skillBuilder = skillBuilderReducer.reduce(skillBuilder, .clearBoundary)
            if case .completeDeletion = action, state.deletion == .completed {
                settings = settingsReducer.reduce(settings, .reset)
            } else {
                settings = settingsReducer.reduce(settings, .clearBoundary)
            }
            qualification = qualificationReducer.reduce(qualification, .clearBoundary)
            qualificationOwnerSubject = nil
            qualificationSessionExpiresAt = nil
        } else if case .completeDeletion = action {
            calendarWrite = calendarWriteReducer.reduce(calendarWrite, .clearBoundary)
            skillBuilder = skillBuilderReducer.reduce(skillBuilder, .clearBoundary)
            settings = settingsReducer.reduce(settings, .reset)
            qualification = qualificationReducer.reduce(qualification, .clearBoundary)
            qualificationOwnerSubject = nil
            qualificationSessionExpiresAt = nil
        } else if case .revokeSession = action {
            qualification = qualificationReducer.reduce(qualification, .clearBoundary)
            qualificationOwnerSubject = nil
            qualificationSessionExpiresAt = nil
        } else if case .requestDeletion = action {
            // Deletion request is itself a protected-data boundary; do not retain local qualification/settings while it is pending.
            calendarWrite = calendarWriteReducer.reduce(calendarWrite, .clearBoundary)
            skillBuilder = skillBuilderReducer.reduce(skillBuilder, .clearBoundary)
            qualification = qualificationReducer.reduce(qualification, .clearBoundary)
            qualificationOwnerSubject = nil
            qualificationSessionExpiresAt = nil
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

    func send(_ action: SkillBuilderAction) {
        skillBuilder = skillBuilderReducer.reduce(skillBuilder, action)
    }

    func send(_ action: KeyboardSettingsAction) {
        settings = settingsReducer.reduce(settings, action)
    }

    func send(_ action: QualificationAction) {
        switch action {
        case .runFixture:
            guard state.account.canUseAuthenticatedFeatures,
                  let owner = qualificationOwnerSubject,
                  let expiresAt = qualificationSessionExpiresAt,
                  Date() < expiresAt else { return }
            qualification = qualificationReducer.reduce(qualification, .runFixtureForSession(ownerSubject: owner, now: Date(), expiresAt: expiresAt))
        case .runFixtureForSession(let owner, let now, let expiresAt):
            guard state.account.canUseAuthenticatedFeatures,
                  qualificationOwnerSubject == owner,
                  Date() < expiresAt,
                  now < expiresAt else { return }
            qualification = qualificationReducer.reduce(qualification, action)
        case .clearBoundary:
            qualification = qualificationReducer.reduce(qualification, action)
        }
    }
}
