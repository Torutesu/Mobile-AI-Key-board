package com.torutesu.mobileaikeyboard.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SuggestionTrustTest {
    @Test
    fun suggestionNeverAutoExecutesOrStoresRawContentAndSensitiveBlocks() {
        var state = ContextualSuggestionState()
        state = SuggestionReducer.reduce(state, SuggestionEvent.Preview(42, false))
        assertEquals(SuggestionPhase.PREVIEW, state.phase)
        assertEquals("21-100", state.inputLengthBucket)
        assertTrue(!state.autoCommit)
        state = SuggestionReducer.reduce(state, SuggestionEvent.Preview(42, true))
        assertEquals(SuggestionPhase.BLOCKED_SENSITIVE, state.phase)
        assertEquals(null, state.suggestionKind)
        assertEquals(null, state.inputLengthBucket)
        assertFalse(ContextualSuggestionState::class.java.declaredFields.any { it.name == "suggestion" })
    }

    @Test
    fun trustMetadataTamperOwnerTeamVersionAndRevocationFailClosed() {
        val initial = TrustCatalogState()
        val entry = initial.entries.first()
        var state = TrustCatalogReducer.reduce(initial, TrustCatalogEvent.Install("SK-006", "sha256:tampered"))
        assertTrue(state.installed.isEmpty())
        state = TrustCatalogReducer.reduce(initial.copy(policy = TeamSkillPolicy("other-team", "other-owner", 1, emptySet(), emptySet(), emptySet(), RiskClass.R1, "preview", true)), TrustCatalogEvent.Install(entry.skillId, entry.digest))
        assertTrue(state.installed.isEmpty())
        state = TrustCatalogReducer.reduce(initial, TrustCatalogEvent.Install(entry.skillId, entry.digest))
        assertEquals(1, state.installed.size)
        state = TrustCatalogReducer.reduce(state, TrustCatalogEvent.Revoke(entry.digest))
        assertTrue(state.installed.single().revoked)
        state = TrustCatalogReducer.reduce(state, TrustCatalogEvent.ExplicitUpgrade(entry.skillId, entry.digest))
        assertTrue(state.installed.single().revoked)
    }

    @Test
    fun hostSessionAndDeletionBoundariesClearSuggestionAndTrust() {
        var state = HostFixtureClient.dispatch(HostFixtureClient.initialState(), HostEvent.EnterFixtureSignedIn)
        state = HostFixtureClient.dispatch(state, HostEvent.SuggestionAction(SuggestionEvent.Preview(10, false)))
        state = HostFixtureClient.dispatch(state, HostEvent.TrustCatalogAction(TrustCatalogEvent.Install("SK-006", "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")))
        state = HostFixtureClient.dispatch(state, HostEvent.SimulateSessionExpiry)
        assertEquals(SuggestionPhase.IDLE, state.suggestions.phase)
        assertTrue(state.trustCatalog.installed.isEmpty())
        state = HostFixtureClient.dispatch(HostFixtureClient.initialState(), HostEvent.EnterFixtureSignedIn)
        state = HostFixtureClient.dispatch(state, HostEvent.RequestDeletion)
        state = HostFixtureClient.dispatch(state, HostEvent.AdvanceDeletion)
        state = HostFixtureClient.dispatch(state, HostEvent.AdvanceDeletion)
        val blocked = HostFixtureClient.dispatch(state, HostEvent.SuggestionAction(SuggestionEvent.Preview(10, false)))
        assertEquals(SuggestionPhase.IDLE, blocked.suggestions.phase)
    }

    @Test
    fun v1InstallThenExplicitV2UpgradeIsTheOnlyMonotonicPath() {
        val initial = TrustCatalogState()
        val v1 = initial.entries[0]
        val v2 = initial.entries[1]
        var state = TrustCatalogReducer.reduce(initial, TrustCatalogEvent.Install(v1.skillId, v1.digest))
        assertEquals(1, state.installed.single().version)
        state = TrustCatalogReducer.reduce(state, TrustCatalogEvent.ExplicitUpgrade(v2.skillId, v2.digest))
        assertEquals(2, state.installed.single().version)
        state = TrustCatalogReducer.reduce(state, TrustCatalogEvent.ExplicitUpgrade(v1.skillId, v1.digest))
        assertEquals(2, state.installed.single().version)
        state = TrustCatalogReducer.reduce(initial, TrustCatalogEvent.Install(v1.skillId, "sha256:tampered"))
        assertTrue(state.installed.isEmpty())
    }

    @Test
    fun staleReviewPolicyTamperOperationsRiskConfirmationAndIssueCountsFail() {
        val initial = TrustCatalogState()
        val entry = initial.entries.first()
        assertTrue(TrustCatalogReducer.reduce(initial.copy(reviewDate = "2026-10-01"), TrustCatalogEvent.Install(entry.skillId, entry.digest)).installed.isEmpty())
        assertTrue(TrustCatalogReducer.reduce(initial.copy(policy = initial.policy.copy(policyDigest = "sha256:bad")), TrustCatalogEvent.Install(entry.skillId, entry.digest)).installed.isEmpty())
        val badOps = entry.copy(safety = entry.safety.copy(requestedOperations = listOf("provider.write")))
        assertTrue(TrustCatalogReducer.reduce(initial.copy(entries = listOf(badOps)), TrustCatalogEvent.Install(entry.skillId, entry.digest)).installed.isEmpty())
        val badRisk = entry.copy(safety = entry.safety.copy(riskClass = RiskClass.R4))
        assertTrue(TrustCatalogReducer.reduce(initial.copy(entries = listOf(badRisk)), TrustCatalogEvent.Install(entry.skillId, entry.digest)).installed.isEmpty())
        val badConfirmation = entry.copy(safety = entry.safety.copy(confirmationFloor = "none"))
        assertTrue(TrustCatalogReducer.reduce(initial.copy(entries = listOf(badConfirmation)), TrustCatalogEvent.Install(entry.skillId, entry.digest)).installed.isEmpty())
        val badIssues = entry.copy(safety = entry.safety.copy(reportedIssues = IssueCounts(safety = -1)))
        assertTrue(TrustCatalogReducer.reduce(initial.copy(entries = listOf(badIssues)), TrustCatalogEvent.Install(entry.skillId, entry.digest)).installed.isEmpty())
        val futureReview = entry.copy(safety = entry.safety.copy(lastReview = "2026-09-01"))
        assertTrue(TrustCatalogReducer.reduce(initial.copy(entries = listOf(futureReview)), TrustCatalogEvent.Install(entry.skillId, entry.digest)).installed.isEmpty())
        val invalidReview = entry.copy(safety = entry.safety.copy(lastReview = "not-a-date"))
        assertTrue(TrustCatalogReducer.reduce(initial.copy(entries = listOf(invalidReview)), TrustCatalogEvent.Install(entry.skillId, entry.digest)).installed.isEmpty())
        val tooManyIssues = entry.copy(safety = entry.safety.copy(reportedIssues = IssueCounts(safety = IssueCounts.MAX_COUNT, privacy = 1)))
        assertTrue(TrustCatalogReducer.reduce(initial.copy(entries = listOf(tooManyIssues)), TrustCatalogEvent.Install(entry.skillId, entry.digest)).installed.isEmpty())
        val badReport = entry.copy(report = SkillCompletionReport(attempts = 2, completions = 3))
        assertTrue(TrustCatalogReducer.reduce(initial.copy(entries = listOf(badReport)), TrustCatalogEvent.Install(entry.skillId, entry.digest)).installed.isEmpty())
    }

    @Test
    fun policyFieldTamperingAndRevocationAreFailClosed() {
        val initial = TrustCatalogState()
        val entry = initial.entries.first()
        val policyChanges = listOf(
            initial.policy.copy(owner = "attacker"),
            initial.policy.copy(teamId = "other-team"),
            initial.policy.copy(epoch = 2),
            initial.policy.copy(allowedOperations = setOf("provider.write")),
            initial.policy.copy(allowedScopes = setOf("calendar.write")),
            initial.policy.copy(riskCeiling = RiskClass.R4),
            initial.policy.copy(confirmationFloor = "none"),
            initial.policy.copy(policyVersion = 2),
        )
        policyChanges.forEach { changed ->
            assertTrue(TrustCatalogReducer.reduce(initial.copy(policy = changed), TrustCatalogEvent.Install(entry.skillId, entry.digest)).installed.isEmpty())
        }
        val revoked = TrustCatalogReducer.reduce(initial, TrustCatalogEvent.Revoke(entry.digest))
        assertEquals(TrustPolicyDigest.compute(revoked.policy), revoked.policy.policyDigest)
        assertTrue(TrustCatalogReducer.reduce(revoked, TrustCatalogEvent.Install(entry.skillId, entry.digest)).installed.isEmpty())
    }

    @Test
    fun sameDowngradeAndSkippedVersionsCannotBeInstalled() {
        val initial = TrustCatalogState()
        val v1 = initial.entries[0]
        val v2 = initial.entries[1]
        var state = TrustCatalogReducer.reduce(initial, TrustCatalogEvent.Install(v1.skillId, v1.digest))
        state = TrustCatalogReducer.reduce(state, TrustCatalogEvent.Install(v1.skillId, v1.digest))
        assertEquals(1, state.installed.single().version)
        state = TrustCatalogReducer.reduce(state, TrustCatalogEvent.ExplicitUpgrade(v2.skillId, v2.digest))
        assertEquals(2, state.installed.single().version)
        state = TrustCatalogReducer.reduce(state, TrustCatalogEvent.ExplicitUpgrade(v1.skillId, v1.digest))
        assertEquals(2, state.installed.single().version)
        val skipped = v2.copy(version = 4, digest = "sha256:fedcba0123456789fedcba0123456789fedcba0123456789fedcba0123456789")
        assertTrue(TrustCatalogReducer.reduce(initial.copy(entries = initial.entries + skipped), TrustCatalogEvent.Install(skipped.skillId, skipped.digest)).installed.isEmpty())
    }

    @Test
    fun policyCanonicalizationIsStructuralAndCompletionConfidenceIsDerived() {
        val left = TrustCatalogState().policy.copy(allowedOperations = setOf("a,b", "c"))
        val right = TrustCatalogState().policy.copy(allowedOperations = setOf("a", "b,c"))
        assertTrue(TrustPolicyDigest.canonical(left) != TrustPolicyDigest.canonical(right))
        assertEquals(CompletionConfidence.NOT_PROVEN, SkillCompletionReport().confidence)
        assertEquals(CompletionConfidence.LOW, SkillCompletionReport(10, 7).confidence)
        assertEquals(CompletionConfidence.LOW, SkillCompletionReport(10, 10).confidence)
        assertEquals(CompletionConfidence.REPORTED, SkillCompletionReport(100, 80).confidence)
    }

    @Test
    fun successfulActionsClearPriorError() {
        val initial = TrustCatalogState()
        val entry = initial.entries.first()
        val failed = TrustCatalogReducer.reduce(initial, TrustCatalogEvent.Install(entry.skillId, "sha256:wrong"))
        assertTrue(failed.error != null)
        val installed = TrustCatalogReducer.reduce(failed, TrustCatalogEvent.Install(entry.skillId, entry.digest))
        assertEquals(null, installed.error)
        val revoked = TrustCatalogReducer.reduce(installed.copy(error = "old error"), TrustCatalogEvent.Revoke(entry.digest))
        assertEquals(null, revoked.error)
    }
}
