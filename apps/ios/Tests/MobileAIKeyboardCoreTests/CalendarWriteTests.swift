import XCTest
@testable import MobileAIKeyboardCore

final class CalendarWriteTests: XCTestCase {
    private let reducer = CalendarWriteReducer()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func readyState() -> CalendarWriteState {
        var state = CalendarWriteFixtureClient().initialState()
        state = reducer.reduce(state, .enableFixtureCapability(accountLabel: "Fixture Calendar", connectionEpoch: 4))
        return state
    }

    private func draft(title: String = "設計レビュー") -> PrivateCalendarEventDraft {
        PrivateCalendarEventDraft(title: title, start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200), timezoneIdentifier: "Asia/Tokyo", calendarIdentifier: "fixture-private")
    }

    func testPrivateDraftHasNoAttendeeOrInviteSurfaceAndRequiresReview() {
        var state = readyState()
        state = reducer.reduce(state, .beginDraft(draft()))
        XCTAssertEqual(state.status, .draft)
        XCTAssertNil(state.plan)
        state = reducer.reduce(state, .review(now: now))
        XCTAssertEqual(state.status, .review)
        XCTAssertTrue(state.plan!.canonicalPayload.contains("\"attendees\":\"none\""))
        XCTAssertTrue(state.plan!.canonicalPayload.contains("\"invite\":\"false\""))
        XCTAssertTrue(state.plan!.confirmationDigest.hasPrefix("sha256:"))
        XCTAssertFalse(PrivateCalendarEventDraft(title: "x", start: now, end: now.addingTimeInterval(60), timezoneIdentifier: "UTC", calendarIdentifier: "another-calendar").isValid)
    }

    func testDigestChangesWhenMaterialDraftIsEditedAndOldConfirmFails() {
        var state = readyState()
        state = reducer.reduce(state, .beginDraft(draft()))
        state = reducer.reduce(state, .review(now: now))
        let oldDigest = try! XCTUnwrap(state.plan?.confirmationDigest)
        state = reducer.reduce(state, .editDraft(draft(title: "変更された予定")))
        XCTAssertEqual(state.status, .draft)
        XCTAssertNil(state.plan)
        state = reducer.reduce(state, .review(now: now))
        XCTAssertNotEqual(state.plan?.confirmationDigest, oldDigest)
        XCTAssertEqual(state.status, .review)
        state = reducer.reduce(state, .confirm(digest: oldDigest, now: now))
        XCTAssertEqual(state.status, .review)
    }

    func testEditAfterConfirmationInvalidatesConfirmedDigest() {
        var state = confirmedState()
        let edited = draft(title: "確認後に変更された予定")
        state = reducer.reduce(state, .editDraft(edited))
        XCTAssertEqual(state.status, .draft)
        XCTAssertNil(state.plan)
        XCTAssertEqual(state.draft?.title, edited.title)
    }

    func testConfirmRequiresExactDigestAndExpiry() {
        var state = readyState()
        state = reducer.reduce(state, .beginDraft(draft()))
        state = reducer.reduce(state, .review(now: now))
        let digest = state.plan!.confirmationDigest
        XCTAssertEqual(reducer.reduce(state, .confirm(digest: "sha256:wrong", now: now)).status, .review)
        XCTAssertEqual(reducer.reduce(state, .confirm(digest: digest, now: now.addingTimeInterval(61))).status, .review)
        state = reducer.reduce(state, .confirm(digest: digest, now: now))
        XCTAssertEqual(state.status, .confirmed)
    }

    func testExecutionRechecksExpiryEpochAndOwnerBinding() {
        var state = confirmedState()
        let plan = state.plan!
        XCTAssertEqual(reducer.reduce(state, .beginExecution(now: plan.expiresAt.addingTimeInterval(1))).status, .expired)

        state = confirmedState()
        state.capability = CalendarWriteCapability(accountLabel: "Fixture Calendar", ownerSubject: "different-owner", connectionEpoch: plan.connectionEpoch, canCreatePrivateNoInvite: true)
        XCTAssertEqual(reducer.reduce(state, .beginExecution(now: now)).status, .confirmed)

        state = confirmedState()
        state.capability = CalendarWriteCapability(accountLabel: "Fixture Calendar", ownerSubject: plan.ownerSubject, connectionEpoch: plan.connectionEpoch + 1, canCreatePrivateNoInvite: true)
        XCTAssertEqual(reducer.reduce(state, .beginExecution(now: now)).status, .confirmed)
    }

    func testDigestBindsOwnerEpochAndExpiryAuthority() {
        var state = readyState()
        state = reducer.reduce(state, .beginDraft(draft()))
        state = reducer.reduce(state, .review(now: now))
        let original = state.plan!
        XCTAssertTrue(original.canonicalPayload.contains("ownerSubject"))
        XCTAssertTrue(original.canonicalPayload.contains("expiresAt"))

        var ownerChanged = state
        ownerChanged.capability = CalendarWriteCapability(accountLabel: "Fixture Calendar", ownerSubject: "different-owner", connectionEpoch: original.connectionEpoch, canCreatePrivateNoInvite: true)
        XCTAssertEqual(reducer.reduce(ownerChanged, .confirm(digest: original.confirmationDigest, now: now)).status, .review)

        var epochChanged = state
        epochChanged.capability = CalendarWriteCapability(accountLabel: "Fixture Calendar", ownerSubject: original.ownerSubject, connectionEpoch: original.connectionEpoch + 1, canCreatePrivateNoInvite: true)
        XCTAssertEqual(reducer.reduce(epochChanged, .confirm(digest: original.confirmationDigest, now: now)).status, .review)

        var laterReview = readyState()
        laterReview = reducer.reduce(laterReview, .beginDraft(draft()))
        laterReview = reducer.reduce(laterReview, .review(now: now.addingTimeInterval(1)))
        XCTAssertNotEqual(original.confirmationDigest, laterReview.plan?.confirmationDigest)
    }

    func testOnlyFixtureCalendarResourcesCanSettleOrReconcile() {
        var state = confirmedState()
        state = reducer.reduce(state, .beginExecution(now: now))
        let wrongProvider = CalendarResourceReference(provider: .notion, resourceIdentifier: "fixture-event-1", sourceReference: "calendar://fixture/private-event/1")
        XCTAssertEqual(reducer.reduce(state, .settle(.succeeded(resource: wrongProvider), now: now.addingTimeInterval(1))).status, .executing)
        let wrongNamespace = CalendarResourceReference(resourceIdentifier: "event-1", sourceReference: "calendar://provider/real-event/1")
        XCTAssertEqual(reducer.reduce(state, .settle(.succeeded(resource: wrongNamespace), now: now.addingTimeInterval(1))).status, .executing)

        state = reducer.reduce(state, .settle(.unknown(reason: "timeout"), now: now.addingTimeInterval(1)))
        XCTAssertEqual(reducer.reduce(state, .reconcile(.succeeded(resource: wrongNamespace), now: now.addingTimeInterval(2))).status, .unknown)
    }

    func testCanonicalPayloadDoesNotTreatDelimiterLikeTitleAsStructure() {
        var state = readyState()
        state = reducer.reduce(state, .beginDraft(draft(title: "A|B=\nC")))
        state = reducer.reduce(state, .review(now: now))
        XCTAssertTrue(state.plan!.canonicalPayload.contains("A|B=\\nC"))
        XCTAssertNotEqual(state.plan!.confirmationDigest, reducer.reduce(reducer.reduce(readyState(), .beginDraft(draft(title: "AB"))), .review(now: now)).plan?.confirmationDigest)
    }

    func testSuccessReceiptCreatesOneShotBoundedUndo() {
        var state = confirmedState()
        state = reducer.reduce(state, .beginExecution(now: now))
        XCTAssertEqual(state.status, .executing)
        let resource = CalendarWriteFixtureClient().successResource()
        state = reducer.reduce(state, .settle(.succeeded(resource: resource), now: now.addingTimeInterval(1)))
        XCTAssertEqual(state.status, .succeeded)
        XCTAssertEqual(state.receipt?.resource, resource)
        XCTAssertEqual(state.undoTicket?.oneShot, true)
        state = reducer.reduce(state, .undo(resource: resource, now: now.addingTimeInterval(2)))
        XCTAssertEqual(state.status, .undone)
        XCTAssertTrue(state.receipt!.id.hasPrefix("undo-"))
        XCTAssertEqual(state.receipt!.activityRecord().steps.first?.operation, "calendar.event.delete_own")
        let once = state
        state = reducer.reduce(state, .undo(resource: resource, now: now.addingTimeInterval(3)))
        XCTAssertEqual(state, once)
    }

    func testUnknownBlocksBlindRetryAndOnlyReconciliationCanSettleIt() {
        var state = confirmedState()
        state = reducer.reduce(state, .beginExecution(now: now))
        state = reducer.reduce(state, .settle(.unknown(reason: "provider timeout"), now: now.addingTimeInterval(1)))
        XCTAssertEqual(state.status, .unknown)
        let blocked = reducer.reduce(state, .beginExecution(now: now.addingTimeInterval(2)))
        XCTAssertEqual(blocked.status, .unknown)
        let resource = CalendarWriteFixtureClient().successResource()
        state = reducer.reduce(state, .reconcile(.succeeded(resource: resource), now: now.addingTimeInterval(3)))
        XCTAssertEqual(state.status, .succeeded)
        XCTAssertTrue(state.hasReconciledUnknown)
    }

    func testReconciliationCannotReturnPartialOrUnknown() {
        var state = confirmedState()
        state = reducer.reduce(state, .beginExecution(now: now))
        state = reducer.reduce(state, .settle(.unknown(reason: "provider timeout"), now: now.addingTimeInterval(1)))
        XCTAssertEqual(reducer.reduce(state, .reconcile(.partial(reason: "ambiguous lookup"), now: now.addingTimeInterval(2))), state)
        XCTAssertEqual(reducer.reduce(state, .reconcile(.unknown(reason: "lookup timeout"), now: now.addingTimeInterval(2))), state)
        state = reducer.reduce(state, .reconcile(.failed(reason: "not found"), now: now.addingTimeInterval(3)))
        XCTAssertEqual(state.status, .failed)
        XCTAssertTrue(state.hasReconciledUnknown)
    }

    func testPartialFailureAndCrossResourceOrExpiredUndoAreRejected() {
        var state = confirmedState()
        state = reducer.reduce(state, .beginExecution(now: now))
        state = reducer.reduce(state, .settle(.partial(reason: "provider accepted only part"), now: now.addingTimeInterval(1)))
        XCTAssertEqual(state.status, .partial)
        let other = CalendarResourceReference(resourceIdentifier: "other", sourceReference: "calendar://fixture/other")
        XCTAssertEqual(reducer.reduce(state, .undo(resource: other, now: now.addingTimeInterval(2))), state)

        state = confirmedState()
        state = reducer.reduce(state, .beginExecution(now: now))
        let resource = CalendarWriteFixtureClient().successResource()
        state = reducer.reduce(state, .settle(.succeeded(resource: resource), now: now))
        let expired = reducer.reduce(state, .undo(resource: resource, now: now.addingTimeInterval(301)))
        XCTAssertEqual(expired.status, .succeeded)
    }

    func testDisconnectBoundaryClearsDraftPlanReceiptAndCapability() {
        var state = confirmedState()
        state = reducer.reduce(state, .clearBoundary)
        XCTAssertEqual(state, CalendarWriteState())
        state = readyState()
        state = reducer.reduce(state, .disableCapability)
        XCTAssertEqual(state.status, .unavailable)
        XCTAssertNil(state.capability)
    }

    private func confirmedState() -> CalendarWriteState {
        var state = readyState()
        state = reducer.reduce(state, .beginDraft(draft()))
        state = reducer.reduce(state, .review(now: now))
        state = reducer.reduce(state, .confirm(digest: state.plan!.confirmationDigest, now: now))
        return state
    }
}
