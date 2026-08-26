package com.torutesu.mobileaikeyboard.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HostConnectionsTest {
    private fun connected(provider: Provider): HostAppState {
        var state = HostFixtureClient.initialState()
        state = HostFixtureClient.dispatch(state, HostEvent.ReviewConnection(provider))
        state = HostFixtureClient.dispatch(state, HostEvent.BeginConnection(provider))
        return HostFixtureClient.dispatch(state, HostEvent.CompleteFixtureConnection(provider))
    }

    @Test
    fun providerConnectionRequiresScopeReviewAndShowsIncrementalScopes() {
        var state = HostFixtureClient.initialState()
        var connection = state.connections.first { it.provider == Provider.CALENDAR }
        assertEquals(ConnectionStatus.NOT_CONNECTED, connection.status)
        assertEquals(listOf("calendar.availability.read"), connection.incrementalScopes)
        state = HostFixtureClient.dispatch(state, HostEvent.ReviewConnection(Provider.CALENDAR))
        assertEquals(ConnectionStatus.SCOPE_REVIEW, state.connections.first { it.provider == Provider.CALENDAR }.status)
        state = HostFixtureClient.dispatch(state, HostEvent.BeginConnection(Provider.CALENDAR))
        assertEquals(ConnectionStatus.CONNECTING, state.connections.first { it.provider == Provider.CALENDAR }.status)
        state = HostFixtureClient.dispatch(state, HostEvent.CompleteFixtureConnection(Provider.CALENDAR))
        connection = state.connections.first { it.provider == Provider.CALENDAR }
        assertEquals(ConnectionStatus.CONNECTED, connection.status)
        assertTrue(connection.grantedScopes.contains("calendar.availability.read"))
        assertTrue(connection.incrementalScopes.isEmpty())
        assertTrue(connection.connectionEpoch > 0)
    }

    @Test
    fun reconnectRebindAndDisconnectAreExplicitStates() {
        var state = connected(Provider.NOTION)
        val epoch = state.connections.first { it.provider == Provider.NOTION }.connectionEpoch
        state = HostFixtureClient.dispatch(state, HostEvent.MarkReconnectRequired(Provider.NOTION))
        assertEquals(ConnectionStatus.RECONNECT_REQUIRED, state.connections.first { it.provider == Provider.NOTION }.status)
        state = HostFixtureClient.dispatch(state, HostEvent.BeginConnection(Provider.NOTION))
        state = HostFixtureClient.dispatch(state, HostEvent.CompleteFixtureConnection(Provider.NOTION))
        assertTrue(state.connections.first { it.provider == Provider.NOTION }.connectionEpoch > epoch)
        state = HostFixtureClient.dispatch(state, HostEvent.MarkRebindRequired(Provider.NOTION))
        assertEquals(ConnectionStatus.REBIND_REQUIRED, state.connections.first { it.provider == Provider.NOTION }.status)
        state = HostFixtureClient.dispatch(state, HostEvent.BeginConnection(Provider.NOTION))
        state = HostFixtureClient.dispatch(state, HostEvent.CompleteFixtureConnection(Provider.NOTION))
        state = HostFixtureClient.dispatch(state, HostEvent.RequestDisconnect(Provider.NOTION))
        assertEquals(ConnectionStatus.DISCONNECTING, state.connections.first { it.provider == Provider.NOTION }.status)
        state = HostFixtureClient.dispatch(state, HostEvent.CompleteDisconnect(Provider.NOTION))
        val disconnected = state.connections.first { it.provider == Provider.NOTION }
        assertEquals(ConnectionStatus.DISCONNECTED, disconnected.status)
        assertTrue(disconnected.grantedScopes.isEmpty())
    }

    @Test
    fun readOnlyResultsAreSourceLinkedBoundedAndWarnAboutUntrustedContent() {
        var state = connected(Provider.CALENDAR)
        state = HostFixtureClient.dispatch(state, HostEvent.RunReadOnly(Provider.CALENDAR))
        val query = state.readOnlyQueries.first { it.provider == Provider.CALENDAR }
        assertEquals(1, query.page)
        assertEquals(2, query.results.size)
        assertTrue(query.hasNextPage)
        assertTrue(query.results.all { it.sourceRef.startsWith("calendar://") })
        assertTrue(query.results.all { it.untrustedProviderContent })
        assertTrue(query.results.all { it.instructionWarning.contains("命令") })
        assertTrue(query.partial)
        assertTrue(query.failureClass != null)
        assertTrue(state.runs.first().skillId == "calendar.availability.read")
        assertEquals(RiskClass.R2, state.runs.first().riskClass)
        assertEquals(RunStatus.PARTIAL, state.runs.first().status)
        assertTrue(Regex("^sha256:[0-9a-f]{64}$").matches(state.runs.first().plan.digest))
        state = HostFixtureClient.dispatch(state, HostEvent.NextResults(Provider.CALENDAR))
        assertEquals(2, state.readOnlyQueries.first { it.provider == Provider.CALENDAR }.page)
        assertFalse(state.readOnlyQueries.first { it.provider == Provider.CALENDAR }.hasNextPage)
    }

    @Test
    fun disconnectedReadOnlyAttemptReturnsTypedFailureReceipt() {
        var state = HostFixtureClient.dispatch(HostFixtureClient.initialState(), HostEvent.RunReadOnly(Provider.MAPS))
        val query = state.readOnlyQueries.first { it.provider == Provider.MAPS }
        assertEquals("connection_required", query.failureClass)
        assertTrue(query.results.isEmpty())
        assertEquals("maps.places.search", state.runs.first().skillId)
        assertEquals(RunStatus.FAILED, state.runs.first().status)
        assertTrue(state.runs.first().receipt.completedSteps.isEmpty())
        assertEquals(listOf("maps.places.search"), state.runs.first().receipt.failedSteps)
    }

    @Test
    fun invalidSelectionAndPaginationAfterConnectionLossFailClosed() {
        var state = connected(Provider.CALENDAR)
        state = HostFixtureClient.dispatch(state, HostEvent.RunReadOnly(Provider.CALENDAR))
        state = HostFixtureClient.dispatch(state, HostEvent.SelectResult(Provider.CALENDAR, "unknown-result"))
        assertEquals(null, state.readOnlyQueries.first { it.provider == Provider.CALENDAR }.selectedResultId)
        state = HostFixtureClient.dispatch(state, HostEvent.MarkReconnectRequired(Provider.CALENDAR))
        state = HostFixtureClient.dispatch(state, HostEvent.NextResults(Provider.CALENDAR))
        assertEquals(1, state.readOnlyQueries.first { it.provider == Provider.CALENDAR }.page)
    }
}
