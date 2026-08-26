import XCTest
@testable import MobileAIKeyboardCore

final class TrustContextTests: XCTestCase {
    private let reviewNow = ISO8601DateFormatter().date(from: "2026-08-26T12:00:00Z")!

    func testContextualSuggestionsNeverRetainRawTextOrAutoApply() {
        let reducer = ContextualSuggestionReducer()
        let context = ContextualSuggestionContext(editorBoundaryID: "local-boundary-1", characterCountBucket: "20-49", locale: "ja-JP")
        var state = reducer.reduce(ContextualSuggestionState(), .refresh(context))
        XCTAssertEqual(state.suggestions.count, 3)
        XCTAssertTrue(state.suggestions.allSatisfy { !$0.autoApplyAllowed && !$0.rawContentRetained })
        state = reducer.reduce(state, .attemptAutoApply(id: "local-polite"))
        XCTAssertEqual(state.lastDecision, .rejectedAutoApply)
    }

    func testSecureFieldDisablesSuggestionsAndBoundaryClearsThem() {
        let reducer = ContextualSuggestionReducer()
        let secure = ContextualSuggestionContext(editorBoundaryID: "local-boundary-2", characterCountBucket: "20-49", locale: "ja-JP", secureField: true)
        var state = reducer.reduce(ContextualSuggestionState(), .refresh(secure))
        XCTAssertTrue(state.suggestions.isEmpty)
        XCTAssertEqual(state.lastDecision, .disabledForSecureField)
        state = reducer.reduce(state, .clearBoundary)
        XCTAssertNil(state.context)
    }

    func testInvalidOpaqueEditorBoundaryFailsClosedAndDoesNotStoreContext() {
        let reducer = ContextualSuggestionReducer()
        let invalid = ContextualSuggestionContext(editorBoundaryID: "contains space", characterCountBucket: "20-49", locale: "ja-JP")
        XCTAssertFalse(invalid.isValid)
        let state = reducer.reduce(ContextualSuggestionState(), .refresh(invalid))
        XCTAssertNil(state.context)
        XCTAssertTrue(state.suggestions.isEmpty)
        let oversized = ContextualSuggestionContext(editorBoundaryID: String(repeating: "a", count: 65), characterCountBucket: "20-49", locale: "ja-JP")
        XCTAssertFalse(oversized.isValid)
        XCTAssertNil(reducer.reduce(ContextualSuggestionState(), .refresh(oversized)).context)
    }

    func testSK006UsesDerivedCountsTypedIssuesAndFixtureOnlyTrust() {
        let metadata = CommunitySkillCatalogFixture.metadata
        XCTAssertEqual(metadata.lastReviewDate, "2026-08-26T00:00:00Z")
        XCTAssertEqual(metadata.completionCompleted, 98)
        XCTAssertEqual(metadata.completionAttempted, 100)
        XCTAssertEqual(metadata.completionRateBasisPoints, 9800)
        XCTAssertEqual(metadata.completionRateDisplay, "98.00% (98/100)")
        XCTAssertEqual(metadata.reportedIssueCounts.total, 1)
        XCTAssertTrue(metadata.digestMatches)
        let validation = TrustPreviewValidator().validate(metadata, now: reviewNow)
        XCTAssertTrue(validation.allowed)
        XCTAssertTrue(validation.fixtureMetadataConsistent)
        XCTAssertEqual(metadata.provenance.publisher, .notVerified)
        XCTAssertEqual(metadata.provenance.package, .notVerified)
    }

    func testCountsAreIntegerDerivedBoundedAndLowConfidenceIsVisible() {
        let zero = CommunitySkillMetadata(id: "zero", publisher: "fixture", requestedConnectorsScopes: ["none"], dataInputs: ["typed"], riskClass: "R1", version: "1.0.0", lastReviewDate: "2026-08-26T00:00:00Z", installs: 0, completionCompleted: 0, completionAttempted: 0)
        XCTAssertNil(zero.completionRateBasisPoints)
        XCTAssertTrue(zero.completionRateDisplay.contains("no attempts"))
        let low = CommunitySkillMetadata(id: "low", publisher: "fixture", requestedConnectorsScopes: ["none"], dataInputs: ["typed"], riskClass: "R1", version: "1.0.0", lastReviewDate: "2026-08-26T00:00:00Z", installs: 0, completionCompleted: 1, completionAttempted: 2)
        XCTAssertTrue(low.completionRateDisplay.contains("low confidence"))
        let invalid = CommunitySkillMetadata(id: "invalid", publisher: "fixture", requestedConnectorsScopes: ["none"], dataInputs: ["typed"], riskClass: "R1", version: "1.0.0", lastReviewDate: "2026-08-26T00:00:00Z", installs: 0, completionCompleted: 3, completionAttempted: 2, reportedIssueCounts: SkillIssueCounts(privacy: -1))
        let result = TrustPreviewValidator().validate(invalid, now: reviewNow)
        XCTAssertFalse(result.allowed)
        XCTAssertTrue(result.issues.contains("SK-006 numeric metadata invalid"))
        XCTAssertFalse(SkillIssueCounts(correctness: SkillIssueCounts.maximumPerCategory + 1).isValid)
    }

    func testReviewTimestampIsInjectedFreshnessBoundAndDigestBound() {
        let base = CommunitySkillCatalogFixture.metadata
        XCTAssertFalse(TrustPreviewValidator().validate(base, now: reviewNow.addingTimeInterval(-86_401)).allowed)
        XCTAssertFalse(TrustPreviewValidator().validate(base, now: reviewNow, maximumReviewAge: 1).allowed)
        let malformed = CommunitySkillMetadata(id: base.id, publisher: base.publisher, requestedOperations: base.requestedOperations, requestedConnectorsScopes: base.requestedConnectorsScopes, dataInputs: base.dataInputs, riskClass: base.riskClass, version: base.version, lastReviewDate: "yesterday", installs: base.installs, completionCompleted: base.completionCompleted, completionAttempted: base.completionAttempted, reportedIssueCounts: base.reportedIssueCounts)
        XCTAssertTrue(TrustPreviewValidator().validate(malformed, now: reviewNow).issues.contains("last review timestamp invalid"))
        let tampered = CommunitySkillMetadata(id: base.id, publisher: base.publisher, requestedOperations: base.requestedOperations, requestedConnectorsScopes: base.requestedConnectorsScopes, dataInputs: base.dataInputs, riskClass: base.riskClass, version: base.version, lastReviewDate: base.lastReviewDate, installs: base.installs, completionCompleted: 97, completionAttempted: base.completionAttempted, reportedIssueCounts: base.reportedIssueCounts, declaredMetadataDigest: base.declaredMetadataDigest)
        XCTAssertFalse(TrustPreviewValidator().validate(tampered, now: reviewNow).allowed)
    }

    func testTrustPreviewRejectsStaleAndTamperedMetadataAndDoesNotVerifyPublisher() {
        let base = CommunitySkillCatalogFixture.metadata
        let validator = TrustPreviewValidator()
        XCTAssertFalse(validator.validate(base, now: reviewNow, expectedVersion: "2.0.0").allowed)
        XCTAssertFalse(validator.validate(base, now: reviewNow, expectedDigest: "sha256:stale").allowed)
        XCTAssertTrue(validator.validate(base, now: reviewNow).fixtureMetadataConsistent)
        XCTAssertEqual(base.provenance.publisher, .notVerified)
    }

    func testTeamPolicyRequiresPolicyBindingExplicitConfirmationAndMonotonicUpgrade() {
        let metadata = CommunitySkillCatalogFixture.metadata
        let reducer = TeamPolicyReducer(now: reviewNow)
        var state = reducer.reduce(TeamPolicyState(), .preview(ownerSubject: "owner-a"))
        let ownerPolicy = state.rules
        state = reducer.reduce(state, .install(metadata: metadata, policy: ownerPolicy, ownerSubject: "owner-a", explicitConfirm: false))
        XCTAssertEqual(state.decision, .deniedConfirmation)
        state = reducer.reduce(state, .install(metadata: metadata, policy: ownerPolicy, ownerSubject: "owner-a", explicitConfirm: true))
        XCTAssertEqual(state.decision, .installed)
        XCTAssertEqual(state.binding?.policyDigest, ownerPolicy.canonicalDigest)
        state = reducer.reduce(state, .install(metadata: metadata, policy: ownerPolicy, ownerSubject: "owner-a", explicitConfirm: true))
        XCTAssertEqual(state.decision, .upgradeRequired)
        state = reducer.reduce(state, .upgrade(metadata: metadata, policy: ownerPolicy, ownerSubject: "owner-a", explicitConfirm: true))
        XCTAssertEqual(state.decision, .deniedVersion)
        let v3Draft = CommunitySkillMetadata(id: metadata.id, publisher: metadata.publisher, requestedOperations: metadata.requestedOperations, requestedConnectorsScopes: metadata.requestedConnectorsScopes, dataInputs: metadata.dataInputs, riskClass: metadata.riskClass, confirmationPolicy: metadata.confirmationPolicy, version: "3.0.0", lastReviewDate: metadata.lastReviewDate, installs: metadata.installs, completionCompleted: metadata.completionCompleted, completionAttempted: metadata.completionAttempted, reportedIssueCounts: metadata.reportedIssueCounts)
        let v3 = v3Draft.withDeclaredDigest(v3Draft.computedMetadataDigest)
        state = reducer.reduce(state, .upgrade(metadata: v3, policy: ownerPolicy, ownerSubject: "owner-a", explicitConfirm: true))
        XCTAssertEqual(state.decision, .deniedVersion)
        state = reducer.reduce(state, .upgrade(metadata: metadata, policy: TeamPolicyRules(ownerSubject: "owner-a", policyEpoch: 2), ownerSubject: "owner-a", explicitConfirm: true))
        XCTAssertEqual(state.decision, .deniedOwnerConfusion)
        let v2Draft = CommunitySkillMetadata(id: metadata.id, publisher: metadata.publisher, requestedOperations: metadata.requestedOperations, requestedConnectorsScopes: metadata.requestedConnectorsScopes, dataInputs: metadata.dataInputs, riskClass: metadata.riskClass, confirmationPolicy: metadata.confirmationPolicy, version: "2.0.0", lastReviewDate: metadata.lastReviewDate, installs: metadata.installs, completionCompleted: metadata.completionCompleted, completionAttempted: metadata.completionAttempted, reportedIssueCounts: metadata.reportedIssueCounts)
        let v2 = v2Draft.withDeclaredDigest(v2Draft.computedMetadataDigest)
        state = reducer.reduce(state, .upgrade(metadata: v2, policy: ownerPolicy, ownerSubject: "owner-b", explicitConfirm: true))
        XCTAssertEqual(state.decision, .deniedOwnerConfusion)
        state = reducer.reduce(state, .upgrade(metadata: v2, policy: ownerPolicy, ownerSubject: "owner-a", explicitConfirm: false))
        XCTAssertEqual(state.decision, .deniedConfirmation)
        state = reducer.reduce(state, .upgrade(metadata: v2, policy: ownerPolicy, ownerSubject: "owner-a", explicitConfirm: true))
        XCTAssertEqual(state.decision, .upgraded)
        state = reducer.reduce(state, .revoke)
        XCTAssertEqual(state.decision, .revoked)
        XCTAssertTrue(state.revoked)
        XCTAssertNil(state.binding)
        XCTAssertTrue(state.revokedPolicyDigests.contains(ownerPolicy.canonicalDigest))
        state = reducer.reduce(state, .install(metadata: v2, policy: ownerPolicy, ownerSubject: "owner-a", explicitConfirm: true))
        XCTAssertEqual(state.decision, .deniedRevoked)
    }

    func testTeamPolicyRejectsScopeRiskOperationAndConfirmationConfusion() {
        let base = CommunitySkillCatalogFixture.metadata
        let reducer = TeamPolicyReducer(now: reviewNow)
        var state = reducer.reduce(TeamPolicyState(), .preview(ownerSubject: "owner"))
        let ownerPolicy = state.rules
        let scopeDraft = CommunitySkillMetadata(id: base.id, publisher: base.publisher, requestedConnectorsScopes: ["calendar.write"], dataInputs: base.dataInputs, riskClass: base.riskClass, version: base.version, lastReviewDate: base.lastReviewDate, installs: base.installs, completionCompleted: base.completionCompleted, completionAttempted: base.completionAttempted, reportedIssueCounts: base.reportedIssueCounts)
        state = reducer.reduce(state, .install(metadata: scopeDraft.withDeclaredDigest(scopeDraft.computedMetadataDigest), policy: ownerPolicy, ownerSubject: "owner", explicitConfirm: true))
        XCTAssertEqual(state.decision, .deniedPolicy)
        let highRisk = CommunitySkillMetadata(id: base.id, publisher: base.publisher, requestedConnectorsScopes: base.requestedConnectorsScopes, dataInputs: base.dataInputs, riskClass: "R4", version: base.version, lastReviewDate: base.lastReviewDate, installs: base.installs, completionCompleted: base.completionCompleted, completionAttempted: base.completionAttempted, reportedIssueCounts: base.reportedIssueCounts)
        state = reducer.reduce(state, .install(metadata: highRisk.withDeclaredDigest(highRisk.computedMetadataDigest), policy: ownerPolicy, ownerSubject: "owner", explicitConfirm: true))
        XCTAssertEqual(state.decision, .deniedPolicy)
    }

    func testTeamPolicyStateDigestTamperingFailsClosed() {
        let metadata = CommunitySkillCatalogFixture.metadata
        let reducer = TeamPolicyReducer(now: reviewNow)
        var state = TeamPolicyState()
        state.policyCanonicalDigest = "sha256:tampered"
        state = reducer.reduce(state, .install(metadata: metadata, policy: .fixture, ownerSubject: "owner", explicitConfirm: true))
        XCTAssertEqual(state.decision, .deniedPolicy)
    }

    func testTeamPolicyDigestBindsOwnerAndPolicyVersion() {
        let base = TeamPolicyRules(ownerSubject: "owner-a")
        XCTAssertNotEqual(base.canonicalDigest, TeamPolicyRules(ownerSubject: "owner-b").canonicalDigest)
        XCTAssertNotEqual(base.canonicalDigest, TeamPolicyRules(ownerSubject: "owner-a", policyVersion: "team-policy.v2").canonicalDigest)
        let reducer = TeamPolicyReducer(now: reviewNow)
        var state = reducer.reduce(TeamPolicyState(), .preview(ownerSubject: "owner-a"))
        let tamperedOwner = TeamPolicyRules(ownerSubject: "owner-b")
        state = reducer.reduce(state, .install(metadata: CommunitySkillCatalogFixture.metadata, policy: tamperedOwner, ownerSubject: "owner-a", explicitConfirm: true))
        XCTAssertEqual(state.decision, .deniedOwnerConfusion)
        let tamperedVersion = TeamPolicyRules(ownerSubject: "owner-a", policyVersion: "team-policy.v2")
        state = reducer.reduce(state, .install(metadata: CommunitySkillCatalogFixture.metadata, policy: tamperedVersion, ownerSubject: "owner-a", explicitConfirm: true))
        XCTAssertEqual(state.decision, .deniedOwnerConfusion)
    }

    func testR4ConnectorGateAlwaysDeniesWithoutSeparateEvidence() {
        let reducer = R4ConnectorGateReducer()
        var state = reducer.reduce(R4ConnectorGateState(), .requestApproval)
        state = reducer.reduce(state, .attemptEnable)
        XCTAssertFalse(state.enabled)
        XCTAssertTrue(state.decision.contains("denied"))
    }
}
