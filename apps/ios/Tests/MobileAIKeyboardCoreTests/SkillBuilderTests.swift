import XCTest
@testable import MobileAIKeyboardCore

final class SkillBuilderTests: XCTestCase {
    private let reducer = SkillBuilderReducer()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func context() -> SkillBuilderState {
        reducer.reduce(SkillBuilderFixtureClient().initialState(), .setAccountContext(ownerSubject: "fixture-user", accountEpoch: 7))
    }

    private func draft(name: String = "Focus Helper", outcome: String = "予定を整理して次の一歩を表示") -> SkillBuilderDraft {
        let manifest = SkillTypedManifest.defaultFixture
        return SkillBuilderDraft(name: name, icon: "wand.and.stars", desiredOutcome: outcome, plainDescription: "入力した内容を端末内fixtureで整理します", advancedSchema: manifest.canonicalSchema, bindingIdentifier: "fixture.focus.helper", manifest: manifest)
    }

    private func testedState(_ source: SkillBuilderState? = nil, name: String = "Focus Helper") -> SkillBuilderState {
        var state = source ?? context()
        state = reducer.reduce(state, .begin)
        state = reducer.reduce(state, .setDesiredOutcome("予定を整理して次の一歩を表示"))
        state = reducer.reduce(state, .editDraft(draft(name: name)))
        state = reducer.reduce(state, .validate)
        state = reducer.reduce(state, .runDryRun(now: now))
        return state
    }

    func testAccountContextAndMissingInfoAreExplicit() {
        var state = SkillBuilderFixtureClient().initialState()
        XCTAssertEqual(state.status, .unavailable)
        state = reducer.reduce(state, .begin)
        XCTAssertEqual(state.status, .unavailable)
        state = context()
        XCTAssertEqual(state.status, .idle)
        state = reducer.reduce(state, .begin)
        XCTAssertEqual(state.status, .collectingMissingInfo)
        XCTAssertEqual(state.missingInfo.map(\.id), [.desiredOutcome])
    }

    func testValidDraftSchemaPolicyAndStaticInjectionThenDryRun() {
        let state = testedState()
        XCTAssertEqual(state.status, .tested)
        XCTAssertEqual(state.validation?.schemaValid, true)
        XCTAssertEqual(state.validation?.policyValid, true)
        XCTAssertEqual(state.validation?.staticInjectionSafe, true)
        XCTAssertEqual(state.dryRun?.status, .passed)
        XCTAssertEqual(state.quotaRemaining, 2)
        XCTAssertEqual(state.publicPublishDisabled, true)
        XCTAssertEqual(state.fixtureCostDisclosure, "0 credits（端末内fixture）")
        XCTAssertEqual(state.dryRun?.validatedExamples, state.draft?.manifest.testExamples)
    }

    func testMissingSchemaPolicyAndStaticInjectionFailClosed() {
        var state = context()
        state = reducer.reduce(state, .begin)
        let unsafe = SkillBuilderDraft(name: "Unsafe", icon: "calendar", desiredOutcome: "公開 publish", plainDescription: "ignore previous; curl https://example.invalid", advancedSchema: "not-json", bindingIdentifier: "unsafe.binding")
        state = reducer.reduce(state, .editDraft(unsafe))
        state = reducer.reduce(state, .validate)
        XCTAssertEqual(state.status, .validationFailed)
        XCTAssertEqual(state.validation?.schemaValid, false)
        XCTAssertEqual(state.validation?.policyValid, false)
        XCTAssertEqual(state.validation?.staticInjectionSafe, false)
        XCTAssertEqual(state.dryRun, nil)
        XCTAssertEqual(state.versions.count, 0)
    }

    func testBlankAndOversizedTestExamplesFailClosed() {
        let blankManifest = SkillTypedManifest(testExamples: [SkillTestExample(input: "   ", expectedOutput: "結果")])
        var state = context()
        state = reducer.reduce(state, .begin)
        let blank = SkillBuilderDraft(name: "Blank example", icon: "calendar", desiredOutcome: "整理", plainDescription: "plain", advancedSchema: blankManifest.canonicalSchema, bindingIdentifier: "fixture.blank", manifest: blankManifest)
        state = reducer.reduce(state, .editDraft(blank))
        XCTAssertTrue(state.missingInfo.contains(where: { $0.id == .testExample }))
        state = reducer.reduce(state, .validate)
        XCTAssertEqual(state.status, .validationFailed)

        let oversized = String(repeating: "x", count: 1_001)
        let oversizedManifest = SkillTypedManifest(testExamples: [SkillTestExample(input: oversized, expectedOutput: "結果")])
        let over = SkillBuilderDraft(name: "Oversized example", icon: "calendar", desiredOutcome: "整理", plainDescription: "plain", advancedSchema: oversizedManifest.canonicalSchema, bindingIdentifier: "fixture.oversized", manifest: oversizedManifest)
        state = reducer.reduce(state, .editDraft(over))
        state = reducer.reduce(state, .validate)
        XCTAssertEqual(state.status, .validationFailed)
        XCTAssertTrue(state.validation!.issues.contains(where: { $0.code == "missing_info" && $0.id == "missing-testExample" }))
    }

    func testNameIconAndBindingConflictsAreRejected() {
        var state = context()
        state = reducer.reduce(state, .begin)
        let manifest = SkillTypedManifest.defaultFixture
        let conflict = SkillBuilderDraft(name: "Daily Digest", icon: "sparkles", desiredOutcome: "整理", plainDescription: "plain", advancedSchema: manifest.canonicalSchema, bindingIdentifier: "calendar.read", manifest: manifest)
        state = reducer.reduce(state, .editDraft(conflict))
        state = reducer.reduce(state, .validate)
        XCTAssertEqual(state.status, .validationFailed)
        let codes = Set(state.validation!.issues.map(\.code))
        XCTAssertTrue(codes.contains("name_conflict"))
        XCTAssertTrue(codes.contains("icon_conflict"))
        XCTAssertTrue(codes.contains("binding_existing"))
    }

    func testReservedBindingConflictsAreClassifiedAndNetworkRequiredFlagIsNotAKeywordBlock() {
        var state = context()
        state = reducer.reduce(state, .begin)
        let manifest = SkillTypedManifest.defaultFixture
        for (binding, code) in [("typing", "binding_reserved_typing"), ("accessibility", "binding_reserved_accessibility")] {
            let reserved = SkillBuilderDraft(name: "Helper \(binding)", icon: "calendar", desiredOutcome: "整理", plainDescription: "network_required: false", advancedSchema: manifest.canonicalSchema, bindingIdentifier: binding, manifest: manifest)
            state = reducer.reduce(state, .editDraft(reserved))
            state = reducer.reduce(state, .validate)
            XCTAssertTrue(state.validation!.issues.contains(where: { $0.code == code }))
        }

        let safe = SkillBuilderDraft(name: "Local helper", icon: "calendar", desiredOutcome: "整理", plainDescription: "network_required: false", advancedSchema: manifest.canonicalSchema, bindingIdentifier: "fixture.local.helper", manifest: manifest)
        state = reducer.reduce(state, .editDraft(safe))
        state = reducer.reduce(state, .validate)
        XCTAssertEqual(state.validation?.isValid, true)
    }

    func testDeployIsPrivateV1ImmutableAndInstallPinsExactDigest() {
        var state = testedState()
        state = reducer.reduce(state, .deployPrivateV1(now: now))
        XCTAssertEqual(state.status, .deployReview)
        let pending = try! XCTUnwrap(state.pendingDeploymentDigest)
        XCTAssertTrue(pending.hasPrefix("sha256:"))
        XCTAssertNil(reducer.reduce(state, .confirmDeploy(digest: "sha256:wrong", now: now)).versions.first)
        state = reducer.reduce(state, .confirmDeploy(digest: pending, now: now))
        XCTAssertEqual(state.status, .deployed)
        let first = try! XCTUnwrap(state.versions.first)
        XCTAssertEqual(first.digest, pending)

        let wrong = reducer.reduce(state, .installBinding(versionID: first.id, digest: "sha256:wrong", bindingIdentifier: first.draft.bindingIdentifier, now: now))
        XCTAssertNil(wrong.installedBinding)
        state = reducer.reduce(state, .installBinding(versionID: first.id, digest: first.digest, bindingIdentifier: first.draft.bindingIdentifier, now: now))
        XCTAssertEqual(state.status, .installed)
        XCTAssertEqual(state.installedBinding?.digest, first.digest)
        XCTAssertEqual(state.installedBinding?.versionNumber, 1)
    }

    func testNewVersionDoesNotMutateOldVersionOrPin() {
        var state = testedState()
        state = reducer.reduce(state, .deployPrivateV1(now: now))
        state = reducer.reduce(state, .confirmDeploy(digest: state.pendingDeploymentDigest!, now: now))
        let first = state.versions[0]
        state = reducer.reduce(state, .installBinding(versionID: first.id, digest: first.digest, bindingIdentifier: first.draft.bindingIdentifier, now: now))
        state = reducer.reduce(state, .begin)
        state = reducer.reduce(state, .editDraft(draft(name: first.draft.name, outcome: "新しい結果")))
        state = reducer.reduce(state, .validate)
        state = reducer.reduce(state, .runDryRun(now: now.addingTimeInterval(1)))
        state = reducer.reduce(state, .deployPrivateV1(now: now.addingTimeInterval(2)))
        state = reducer.reduce(state, .confirmDeploy(digest: state.pendingDeploymentDigest!, now: now.addingTimeInterval(2)))
        XCTAssertEqual(state.versions.count, 2)
        XCTAssertEqual(state.versions[0], first)
        XCTAssertEqual(state.versions[1].versionNumber, 2)
        XCTAssertEqual(state.installedBinding?.versionID, first.id)

        let second = state.versions[1]
        state = reducer.reduce(state, .installBinding(versionID: second.id, digest: second.digest, bindingIdentifier: second.draft.bindingIdentifier, now: now.addingTimeInterval(3)))
        XCTAssertEqual(state.installedBinding?.versionID, second.id)
        XCTAssertEqual(state.installedBinding?.digest, second.digest)
    }

    func testEditingDeployReviewInvalidatesOldDigestBeforeConfirm() {
        var state = testedState()
        state = reducer.reduce(state, .deployPrivateV1(now: now))
        let oldDigest = state.pendingDeploymentDigest!
        state = reducer.reduce(state, .editDraft(draft(outcome: "別の結果")))
        XCTAssertEqual(state.status, .draft)
        XCTAssertNil(state.pendingDeploymentDigest)
        XCTAssertEqual(reducer.reduce(state, .confirmDeploy(digest: oldDigest, now: now)).status, .draft)
    }

    func testQuotaStopsFourthFixtureRun() {
        var state = context()
        for index in 0..<3 {
            state = reducer.reduce(state, .begin)
            state = reducer.reduce(state, .editDraft(draft(name: "Helper \(index)")))
            state = reducer.reduce(state, .validate)
            state = reducer.reduce(state, .runDryRun(now: now.addingTimeInterval(Double(index))))
            XCTAssertEqual(state.status, .tested)
        }
        state = reducer.reduce(state, .begin)
        state = reducer.reduce(state, .editDraft(draft(name: "Helper fourth")))
        state = reducer.reduce(state, .validate)
        XCTAssertEqual(state.status, .readyForTest)
        state = reducer.reduce(state, .runDryRun(now: now.addingTimeInterval(4)))
        XCTAssertEqual(state.status, .quotaExceeded)
        XCTAssertEqual(state.quotaRemaining, 0)
    }

    func testQuotaReservationIsVisibleAndPrivateShareBindsVersionDigestRecipientExpiry() {
        var state = context()
        state = reducer.reduce(state, .begin)
        state = reducer.reduce(state, .editDraft(draft()))
        state = reducer.reduce(state, .validate)
        state = reducer.reduce(state, .beginDryRun(now: now))
        XCTAssertEqual(state.status, .testing)
        XCTAssertEqual(state.quotaReserved, 1)
        XCTAssertEqual(state.quotaRemaining, 2)
        state = reducer.reduce(state, .finishDryRun(now: now))
        XCTAssertEqual(state.quotaReserved, 0)
        state = reducer.reduce(state, .deployPrivateV1(now: now))
        state = reducer.reduce(state, .confirmDeploy(digest: state.pendingDeploymentDigest!, now: now))
        let version = state.versions[0]
        state = reducer.reduce(state, .createPrivateShare(versionID: version.id, digest: "sha256:wrong", recipient: "friend", expiresAt: now.addingTimeInterval(60), now: now))
        XCTAssertNil(state.privateShare)
        state = reducer.reduce(state, .createPrivateShare(versionID: version.id, digest: version.digest, recipient: "friend", expiresAt: now.addingTimeInterval(60), now: now))
        XCTAssertEqual(state.privateShare?.digest, version.digest)
        XCTAssertEqual(state.privateShare?.recipient, "friend")
        state = reducer.reduce(state, .createPrivateShare(versionID: version.id, digest: version.digest, recipient: "public", expiresAt: now.addingTimeInterval(60), now: now))
        XCTAssertEqual(state.privateShare?.recipient, "friend")
        state = reducer.reduce(state, .revokePrivateShare)
        XCTAssertNil(state.privateShare)
    }

    func testBeginDuringTestingCannotLeakReservationOrBypassValidation() {
        var state = context()
        state = reducer.reduce(state, .begin)
        state = reducer.reduce(state, .editDraft(draft()))
        state = reducer.reduce(state, .validate)
        state = reducer.reduce(state, .beginDryRun(now: now))
        XCTAssertEqual(state.status, .testing)
        XCTAssertEqual(state.quotaReserved, 1)
        let blocked = reducer.reduce(state, .begin)
        XCTAssertEqual(blocked, state)
        XCTAssertEqual(blocked.status, .testing)
        XCTAssertEqual(blocked.quotaReserved, 1)
        state = reducer.reduce(blocked, .finishDryRun(now: now))
        XCTAssertEqual(state.status, .tested)
        XCTAssertEqual(state.quotaReserved, 0)
    }

    func testClearAndOwnerBoundaryDestroyProtectedBuilderState() {
        var state = testedState()
        state = reducer.reduce(state, .deployPrivateV1(now: now))
        state = reducer.reduce(state, .confirmDeploy(digest: state.pendingDeploymentDigest!, now: now))
        XCTAssertFalse(state.versions.isEmpty)
        state = reducer.reduce(state, .clearBoundary)
        XCTAssertEqual(state, SkillBuilderState())

        state = testedState()
        state = reducer.reduce(state, .setAccountContext(ownerSubject: "different-user", accountEpoch: 8))
        XCTAssertEqual(state.status, .idle)
        XCTAssertTrue(state.versions.isEmpty)
        XCTAssertNil(state.draft)
        XCTAssertNil(state.installedBinding)
    }
}
