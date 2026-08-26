package com.torutesu.mobileaikeyboard.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HostCalendarWriteTest {
    private fun ready(): HostAppState {
        var state = HostFixtureClient.initialState()
        state = HostFixtureClient.dispatch(state, HostEvent.EnterFixtureSignedIn)
        state = HostFixtureClient.dispatch(state, HostEvent.ReviewConnection(Provider.CALENDAR))
        state = HostFixtureClient.dispatch(state, HostEvent.BeginConnection(Provider.CALENDAR))
        state = HostFixtureClient.dispatch(state, HostEvent.CompleteFixtureConnection(Provider.CALENDAR))
        return HostFixtureClient.dispatch(state, HostEvent.EnableCalendarWriteFixture)
    }

    private fun reviewed(): HostAppState {
        var state = HostFixtureClient.dispatch(ready(), HostEvent.OpenCalendarWrite)
        state = HostFixtureClient.dispatch(state, HostEvent.ReviewCalendarWrite)
        return state
    }

    @Test
    fun canonicalDigestIncludesAuthorityAndNoInviteContract() {
        val draft = PrivateCalendarDraft()
        val a = CalendarWriteCanonicalizer.digest(draft, "owner-a", 1, 1, "2026-08-26T09:15:00Z")
        val b = CalendarWriteCanonicalizer.digest(draft, "owner-b", 1, 1, "2026-08-26T09:15:00Z")
        assertNotEquals(a, b)
        assertTrue(CalendarWriteCanonicalizer.canonicalPayload(draft).contains("\"attendees\":[]"))
        assertTrue(CalendarWriteCanonicalizer.canonicalPayload(draft).contains("\"no_invites\":true"))
        assertTrue(CalendarWriteCanonicalizer.canonicalPayload(draft).contains("\"send_updates\":\"none\""))
    }

    @Test
    fun separateWriteCapabilityAndConnectionAreRequired() {
        var state = HostFixtureClient.dispatch(HostFixtureClient.initialState(), HostEvent.EnterFixtureSignedIn)
        state = HostFixtureClient.dispatch(state, HostEvent.OpenCalendarWrite)
        assertEquals(CalendarWritePhase.FAILED, state.calendarWrite.phase)
        state = HostFixtureClient.dispatch(state, HostEvent.ReviewConnection(Provider.CALENDAR))
        state = HostFixtureClient.dispatch(state, HostEvent.BeginConnection(Provider.CALENDAR))
        state = HostFixtureClient.dispatch(state, HostEvent.CompleteFixtureConnection(Provider.CALENDAR))
        state = HostFixtureClient.dispatch(state, HostEvent.OpenCalendarWrite)
        assertEquals(CalendarWritePhase.FAILED, state.calendarWrite.phase)
        state = HostFixtureClient.dispatch(state, HostEvent.EnableCalendarWriteFixture)
        state = HostFixtureClient.dispatch(state, HostEvent.OpenCalendarWrite)
        assertEquals(CalendarWritePhase.DRAFT, state.calendarWrite.phase)
    }

    @Test
    fun editInvalidatesDigestAndExactConfirmStartsOneRun() {
        var state = reviewed()
        val oldDigest = state.calendarWrite.plan!!.digest
        state = HostFixtureClient.dispatch(state, HostEvent.ConfirmCalendarWrite("sha256:wrong"))
        assertEquals(CalendarWritePhase.REVIEW, state.calendarWrite.phase)
        assertNull(state.calendarWrite.confirmedDigest)
        state = HostFixtureClient.dispatch(state, HostEvent.UpdateCalendarDraft(state.calendarWrite.draft.copy(title = "変更")))
        assertEquals(CalendarWritePhase.DRAFT, state.calendarWrite.phase)
        assertNull(state.calendarWrite.plan)
        state = HostFixtureClient.dispatch(state, HostEvent.ReviewCalendarWrite)
        assertNotEquals(oldDigest, state.calendarWrite.plan!!.digest)
        state = HostFixtureClient.dispatch(state, HostEvent.ConfirmCalendarWrite(state.calendarWrite.plan!!.digest))
        assertEquals(CalendarWritePhase.EXECUTING, state.calendarWrite.phase)
        assertEquals(0, state.runs.count { it.skillId == "calendar.event.create_private" })
    }

    @Test
    fun successHasExactFixtureResourceAndUndoIsOneShot() {
        var state = HostFixtureClient.dispatch(reviewed(), HostEvent.ConfirmCalendarWrite(reviewed().calendarWrite.plan!!.digest))
        state = HostFixtureClient.dispatch(state, HostEvent.SetCalendarWriteOutcome(CalendarWritePhase.SUCCEEDED))
        val receipt = state.calendarWrite.receipt!!
        assertTrue(receipt.resourceRef!!.startsWith("calendar://private-event/"))
        assertEquals("Fixture account（実接続なし）", receipt.ownerSubject)
        state = HostFixtureClient.dispatch(state, HostEvent.RequestCalendarUndo)
        assertEquals(CalendarWritePhase.UNDO_REVIEW, state.calendarWrite.phase)
        state = HostFixtureClient.dispatch(state, HostEvent.ConfirmCalendarUndo("calendar://private-event/wrong"))
        assertEquals(CalendarWritePhase.FAILED, state.calendarWrite.phase)
    }

    @Test
    fun exactUndoCannotBeRepeatedAndExpiryBlocksIt() {
        var state = HostFixtureClient.dispatch(reviewed(), HostEvent.ConfirmCalendarWrite(reviewed().calendarWrite.plan!!.digest))
        state = HostFixtureClient.dispatch(state, HostEvent.SetCalendarWriteOutcome(CalendarWritePhase.SUCCEEDED))
        val ref = state.calendarWrite.receipt!!.resourceRef!!
        state = HostFixtureClient.dispatch(state, HostEvent.RequestCalendarUndo)
        state = HostFixtureClient.dispatch(state, HostEvent.ConfirmCalendarUndo(ref))
        state = HostFixtureClient.dispatch(state, HostEvent.CompleteCalendarUndo)
        assertEquals(CalendarWritePhase.UNDONE, state.calendarWrite.phase)
        assertTrue(state.calendarWrite.receipt!!.undoUsed)
        val before = state
        state = HostFixtureClient.dispatch(state, HostEvent.RequestCalendarUndo)
        assertEquals(before, state)

        var expired = HostFixtureClient.dispatch(reviewed(), HostEvent.ConfirmCalendarWrite(reviewed().calendarWrite.plan!!.digest))
        expired = HostFixtureClient.dispatch(expired, HostEvent.SetCalendarWriteOutcome(CalendarWritePhase.SUCCEEDED))
        expired = HostFixtureClient.dispatch(expired, HostEvent.ObserveCalendarTime("2026-08-26T10:00:00Z"))
        assertEquals(CalendarWritePhase.UNDO_EXPIRED, expired.calendarWrite.phase)
        expired = HostFixtureClient.dispatch(expired, HostEvent.RequestCalendarUndo)
        assertNotEquals(CalendarWritePhase.UNDO_REVIEW, expired.calendarWrite.phase)
    }

    @Test
    fun unknownBlocksRetryAndReconciliationNeverCreatesSecondEvent() {
        var state = HostFixtureClient.dispatch(reviewed(), HostEvent.ConfirmCalendarWrite(reviewed().calendarWrite.plan!!.digest))
        state = HostFixtureClient.dispatch(state, HostEvent.SetCalendarWriteOutcome(CalendarWritePhase.UNKNOWN))
        assertEquals(CalendarWritePhase.UNKNOWN, state.calendarWrite.phase)
        assertTrue(state.calendarWrite.receipt!!.reconciliationRequired)
        assertNull(state.calendarWrite.receipt!!.resourceRef)
        assertEquals(RunStatus.UNKNOWN, state.runs.first { it.skillId == "calendar.event.create_private" }.status)
        assertTrue(state.runs.first { it.skillId == "calendar.event.create_private" }.receipt.completedSteps.isEmpty())
        state = HostFixtureClient.dispatch(state, HostEvent.ConfirmCalendarWrite("sha256:any"))
        assertEquals(CalendarWritePhase.UNKNOWN, state.calendarWrite.phase)
        state = HostFixtureClient.dispatch(state, HostEvent.RequestCalendarReconciliation)
        state = HostFixtureClient.dispatch(state, HostEvent.ConfirmCalendarReconciliation)
        assertEquals(CalendarWritePhase.RECONCILING, state.calendarWrite.phase)
        val ref = "calendar://private-event/${state.calendarWrite.plan!!.digest.removePrefix("sha256:").take(16)}"
        state = HostFixtureClient.dispatch(state, HostEvent.CompleteCalendarReconciliation(true, ref))
        assertEquals(CalendarWritePhase.SUCCEEDED, state.calendarWrite.phase)
        assertEquals(ref, state.calendarWrite.receipt!!.resourceRef)
        assertFalse(state.runs.count { it.skillId == "calendar.event.create_private" } > 2)
    }

    @Test
    fun disconnectEpochSessionAndDeletionClearPendingWrite() {
        var state = reviewed()
        state = HostFixtureClient.dispatch(state, HostEvent.MarkReconnectRequired(Provider.CALENDAR))
        assertEquals(CalendarWritePhase.IDLE, state.calendarWrite.phase)
        state = ready()
        state = HostFixtureClient.dispatch(state, HostEvent.OpenCalendarWrite)
        state = HostFixtureClient.dispatch(state, HostEvent.SimulateSessionExpiry)
        assertEquals(CalendarWritePhase.IDLE, state.calendarWrite.phase)
        state = ready()
        state = HostFixtureClient.dispatch(state, HostEvent.OpenCalendarWrite)
        state = HostFixtureClient.dispatch(state, HostEvent.RequestDeletion)
        state = HostFixtureClient.dispatch(state, HostEvent.AdvanceDeletion)
        state = HostFixtureClient.dispatch(state, HostEvent.AdvanceDeletion)
        assertEquals(CalendarWritePhase.IDLE, state.calendarWrite.phase)
        assertTrue(state.connections.isEmpty())
    }

    @Test
    fun confirmationAndUndoExpiryUseReceiptAndPlanTime() {
        var state = reviewed()
        state = HostFixtureClient.dispatch(state, HostEvent.ObserveCalendarTime("2026-08-26T09:16:00Z"))
        assertEquals(CalendarWritePhase.FAILED, state.calendarWrite.phase)

        state = reviewed()
        state = HostFixtureClient.dispatch(state, HostEvent.ConfirmCalendarWrite(state.calendarWrite.plan!!.digest))
        state = HostFixtureClient.dispatch(state, HostEvent.SetCalendarWriteOutcome(CalendarWritePhase.SUCCEEDED))
        state = HostFixtureClient.dispatch(state, HostEvent.ObserveCalendarTime("2026-08-26T10:01:00Z"))
        assertEquals(CalendarWritePhase.UNDO_EXPIRED, state.calendarWrite.phase)
    }
}
