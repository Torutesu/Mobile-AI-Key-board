import XCTest
@testable import MobileAIKeyboardCore

final class AccountActivityTests: XCTestCase {
    private let reducer = AccountActivityReducer()

    func testAnonymousModeExplainsSignInBoundary() {
        let fixture = AccountActivityFixtureClient().initialState(now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(fixture.account, .anonymous)
        XCTAssertFalse(fixture.account.canUseAuthenticatedFeatures)
        let required = reducer.reduce(fixture, .requireSignIn)
        XCTAssertEqual(required.account, .signInRequired)
        let signedIn = reducer.reduce(required, .signInFixture(label: "fixture@example.invalid"))
        XCTAssertEqual(signedIn.account, .signedIn(label: "fixture@example.invalid"))
    }

    func testCurrentDeviceRevocationRevokesSession() {
        let fixture = AccountActivityFixtureClient().initialState()
        let signedIn = reducer.reduce(fixture, .signInFixture(label: "Fixture User"))
        let revoked = reducer.reduce(signedIn, .revokeDevice(id: "fixture-current"))
        XCTAssertEqual(revoked.account, .revoked)
        XCTAssertEqual(revoked.devices.first(where: { $0.id == "fixture-current" })?.state, .revoked)
    }

    func testSessionExpiryAndRetentionAreExplicit() {
        let fixture = AccountActivityFixtureClient().initialState()
        let signedIn = reducer.reduce(fixture, .signInFixture(label: "Fixture User"))
        XCTAssertEqual(reducer.reduce(signedIn, .expireSession).account, .sessionExpired)
        XCTAssertEqual(reducer.reduce(fixture, .setRetention(.deleteImmediately)).retention, .deleteImmediately)
    }

    func testDeletionProgressClearsLocalFixtureOnlyOnCompletion() {
        let fixture = AccountActivityFixtureClient().initialState()
        let requested = reducer.reduce(fixture, .requestDeletion)
        XCTAssertEqual(requested.deletion, .requested)
        XCTAssertEqual(reducer.reduce(fixture, .completeDeletion), fixture)
        let inProgress = reducer.reduce(requested, .advanceDeletion)
        XCTAssertEqual(inProgress.deletion, .inProgress(progress: 50))
        XCTAssertFalse(inProgress.activities.isEmpty)
        let completed = reducer.reduce(inProgress, .completeDeletion)
        XCTAssertEqual(completed.deletion, .completed)
        XCTAssertTrue(completed.activities.isEmpty)
        XCTAssertTrue(completed.devices.isEmpty)
        XCTAssertEqual(completed.account, .anonymous)
    }

    func testActivityDetailIsContentFreeAndPlanVersionIsImmutable() {
        let activity = try! XCTUnwrap(AccountActivityFixtureClient().initialState().activities.first)
        XCTAssertEqual(activity.immutablePlanVersion, "text-rewrite.v1")
        XCTAssertEqual(activity.planDigest, "sha256:fixture-plan-v1")
        XCTAssertFalse(activity.safeReceipt.contains("よろしく"))
        XCTAssertTrue(activity.steps.allSatisfy { !$0.safeSummary.isEmpty })
    }
}
