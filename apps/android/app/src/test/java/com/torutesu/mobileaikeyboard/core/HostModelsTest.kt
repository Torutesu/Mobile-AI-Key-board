package com.torutesu.mobileaikeyboard.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HostModelsTest {
    @Test
    fun fixtureStartsAnonymousWithProviderNeutralActivityReceipts() {
        val state = HostFixtureClient.initialState()
        assertEquals(AuthStatus.ANONYMOUS, state.account.authStatus)
        assertEquals(SessionStatus.NOT_AUTHENTICATED, state.account.sessionStatus)
        assertTrue(state.runs.isNotEmpty())
        assertTrue(state.runs.all { it.receipt.summary.isNotBlank() })
        assertTrue(state.runs.none { it.receipt.summary.contains("来週") || it.receipt.summary.contains("http") })
    }

    @Test
    fun fixtureSignInAndSessionExpiryAreTypedStates() {
        var state = HostFixtureClient.dispatch(HostFixtureClient.initialState(), HostEvent.EnterFixtureSignedIn)
        assertEquals(AuthStatus.SIGNED_IN, state.account.authStatus)
        assertEquals(SessionStatus.ACTIVE, state.account.sessionStatus)
        assertEquals(DataOrigin.LOCAL_FIXTURE, state.account.origin)
        state = HostFixtureClient.dispatch(state, HostEvent.SimulateSessionExpiry)
        assertEquals(SessionStatus.EXPIRED, state.account.sessionStatus)
        state = HostFixtureClient.dispatch(state, HostEvent.SimulateSessionRevocation)
        assertEquals(SessionStatus.REVOKED, state.account.sessionStatus)
    }

    @Test
    fun revokeRequiresConfirmationAndRevokingCurrentDeviceRevokesSession() {
        var state = HostFixtureClient.initialState()
        state = HostFixtureClient.dispatch(state, HostEvent.RequestDeviceRevoke("device-current"))
        assertEquals("device-current", state.pendingRevokeDeviceId)
        val cancelled = HostFixtureClient.dispatch(state, HostEvent.CancelDeviceRevoke)
        assertEquals(null, cancelled.pendingRevokeDeviceId)
        state = HostFixtureClient.dispatch(state, HostEvent.RequestDeviceRevoke("device-current"))
        state = HostFixtureClient.dispatch(state, HostEvent.ConfirmDeviceRevoke)
        assertEquals(DeviceStatus.REVOKED, state.devices.first { it.id == "device-current" }.status)
        assertEquals(SessionStatus.REVOKED, state.account.sessionStatus)
    }

    @Test
    fun activitySelectionExposesImmutablePlanAndReceiptWithoutContent() {
        var state = HostFixtureClient.initialState()
        state = HostFixtureClient.dispatch(state, HostEvent.SelectRun("run-calendar-002"))
        val run = state.runs.first { it.id == state.selectedRunId }
        assertEquals(2, run.plan.version)
        assertTrue(run.plan.digest.startsWith("sha256:"))
        assertEquals(RunStatus.PARTIAL, run.status)
        assertTrue(run.receipt.failedSteps.isNotEmpty())
        assertFalse(run.receipt.summary.contains("選択"))
    }

    @Test
    fun retentionAndDeletionHaveExplicitProgressAndResult() {
        var state = HostFixtureClient.initialState()
        state = HostFixtureClient.dispatch(state, HostEvent.SelectRetention(RetentionPolicy.THIRTY_DAYS))
        assertEquals(RetentionPolicy.THIRTY_DAYS, state.retention)
        state = HostFixtureClient.dispatch(state, HostEvent.RequestDeletion)
        assertEquals(DeletionStatus.REQUESTED, state.deletion.status)
        state = HostFixtureClient.dispatch(state, HostEvent.AdvanceDeletion)
        assertEquals(DeletionStatus.IN_PROGRESS, state.deletion.status)
        state = HostFixtureClient.dispatch(state, HostEvent.AdvanceDeletion)
        assertEquals(DeletionStatus.COMPLETED, state.deletion.status)
        assertEquals(AuthStatus.ANONYMOUS, state.account.authStatus)
        assertTrue(state.devices.isEmpty())
        assertTrue(state.runs.isEmpty())
        assertTrue(state.deletion.resultMessage?.contains("未証明") == true)
    }
}
