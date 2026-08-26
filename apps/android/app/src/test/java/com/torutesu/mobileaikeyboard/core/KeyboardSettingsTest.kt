package com.torutesu.mobileaikeyboard.core

import android.text.InputType
import android.view.inputmethod.EditorInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyboardSettingsTest {
    @Test
    fun imeOnboardingRequiresEnablementSelectionFreshProbeAndNonBlankTestField() {
        assertFalse(ImeOnboardingStatus(false, true, true, "typed").complete)
        assertFalse(ImeOnboardingStatus(true, false, true, "typed").complete)
        assertFalse(ImeOnboardingStatus(true, true, false, "typed").complete)
        assertFalse(ImeOnboardingStatus(true, true, true, "").complete)
        assertTrue(ImeOnboardingStatus(true, true, true, "typed").complete)
        assertFalse(ImeOnboardingStatus(true, true, true, "  \n").complete)
    }

    @Test
    fun settingsV3MigrationAddsSafeSoundAndPreviewDefaults() {
        val legacy = KeyboardSettingsState(schemaVersion = 2, haptics = HapticMode.OFF, keySound = KeySoundMode.KEY_TAP, characterPreview = false)
        val migrated = KeyboardSettingsReducer.reduce(legacy, KeyboardSettingsEvent.MigrateLegacy(2))
        assertEquals(3, migrated.schemaVersion)
        assertEquals(KeySoundMode.OFF, migrated.keySound)
        assertTrue(migrated.characterPreview)
    }

    @Test
    fun typingModeSupportsOneShotCapsAndLayerReset() {
        var mode = TypingModeState()
        mode = TypingModeReducer.shiftTapped(mode)
        assertEquals(ShiftState.ONE_SHOT, mode.shift)
        mode = TypingModeReducer.characterCommitted(mode)
        assertEquals(ShiftState.OFF, mode.shift)
        mode = TypingModeReducer.shiftTapped(mode)
        mode = TypingModeReducer.shiftTapped(mode)
        assertEquals(ShiftState.CAPS_LOCK, mode.shift)
        mode = TypingModeReducer.layerToggled(mode)
        assertEquals(KeyboardLayer.SYMBOLS, mode.layer)
        assertEquals(ShiftState.OFF, mode.shift)
        mode = TypingModeReducer.layerToggled(mode)
        assertEquals(TypingModeState(), mode)
    }

    @Test
    fun returnKeyUsesEditorActionOnlyForSingleLineActionFields() {
        assertEquals("完了", ReturnKeyModel.from(EditorInfo.IME_ACTION_DONE, InputType.TYPE_CLASS_TEXT).label)
        assertEquals(EditorInfo.IME_ACTION_SEARCH, ReturnKeyModel.from(EditorInfo.IME_ACTION_SEARCH, InputType.TYPE_CLASS_TEXT).editorAction)
        val multiline = ReturnKeyModel.from(EditorInfo.IME_ACTION_DONE, InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE)
        assertEquals("↵", multiline.label)
        assertEquals(null, multiline.editorAction)
        val noAction = ReturnKeyModel.from(EditorInfo.IME_ACTION_DONE or EditorInfo.IME_FLAG_NO_ENTER_ACTION, InputType.TYPE_CLASS_TEXT)
        assertEquals(null, noAction.editorAction)
    }
    @Test
    fun settingsAreVersionedImeConsumableAndResettable() {
        var state = KeyboardSettingsState()
        state = KeyboardSettingsReducer.reduce(state, KeyboardSettingsEvent.SetTheme(KeyboardTheme.DARK))
        state = KeyboardSettingsReducer.reduce(state, KeyboardSettingsEvent.SetKeySize(KeySize.LARGE))
        state = KeyboardSettingsReducer.reduce(state, KeyboardSettingsEvent.SetKeySound(KeySoundMode.KEY_TAP))
        state = KeyboardSettingsReducer.reduce(state, KeyboardSettingsEvent.SetCharacterPreview(false))
        state = KeyboardSettingsReducer.reduce(state, KeyboardSettingsEvent.SelectWorkflowPack(JapaneseWorkflowPack.KEY_POINTS))
        assertEquals(KeyboardTheme.DARK, KeyboardSettingsReducer.imeConfig(state).theme)
        assertEquals(JapaneseWorkflowPack.KEY_POINTS, KeyboardSettingsReducer.imeConfig(state).workflowPack)
        assertEquals(KeySoundMode.KEY_TAP, KeyboardSettingsReducer.imeConfig(state).keySound)
        assertEquals(false, KeyboardSettingsReducer.imeConfig(state).characterPreview)
        state = KeyboardSettingsReducer.reduce(state, KeyboardSettingsEvent.MigrateLegacy(1))
        assertEquals(3, state.schemaVersion)
        state = KeyboardSettingsReducer.reduce(state, KeyboardSettingsEvent.Reset)
        assertEquals(KeyboardTheme.SYSTEM, state.theme)
        assertEquals(3, state.schemaVersion)
    }

    @Test
    fun workflowPacksAreLocalFixturesAndJapaneseImeClaimIsNotMade() {
        val input = "田中さんによろしくお願いいたします。URL https://example.com"
        JapaneseWorkflowPack.values().forEach { pack ->
            val result = JapaneseWorkflowFixtures.apply(pack, input)
            assertTrue(result.localOnly)
            assertTrue(result.preview.isNotBlank())
            assertTrue(result.contentPreserved)
        }
    }

    @Test
    fun qualificationIsContentFreeAndClearsOnSessionAndDeletionBoundaries() {
        var state = HostFixtureClient.dispatch(HostFixtureClient.initialState(), HostEvent.EnterFixtureSignedIn)
        state = HostFixtureClient.dispatch(state, HostEvent.KeyboardSettingsAction(KeyboardSettingsEvent.RecordFixtureQualification(QualificationMetrics(120, 300, 100, 30, 1000, 1))))
        assertEquals(QualificationStatus.FIXTURE_PASSED, state.keyboardSettings.qualificationStatus)
        state = HostFixtureClient.dispatch(state, HostEvent.SimulateSessionExpiry)
        assertEquals(QualificationStatus.CLEARED, state.keyboardSettings.qualificationStatus)
        state = HostFixtureClient.dispatch(state, HostEvent.EnterFixtureSignedIn)
        state = HostFixtureClient.dispatch(state, HostEvent.KeyboardSettingsAction(KeyboardSettingsEvent.RecordFixtureQualification(QualificationMetrics(120, 300, 100, 30, 1000, 1))))
        state = HostFixtureClient.dispatch(state, HostEvent.RequestDeletion)
        state = HostFixtureClient.dispatch(state, HostEvent.AdvanceDeletion)
        state = HostFixtureClient.dispatch(state, HostEvent.AdvanceDeletion)
        assertEquals(QualificationStatus.NOT_PROVEN, state.keyboardSettings.qualificationStatus)
        assertEquals(KeyboardSettingsState(), state.keyboardSettings)
    }

    @Test
    fun ordinarySettingsSurviveBoundaryButProtectedQualificationDoesNot() {
        var state = HostFixtureClient.dispatch(HostFixtureClient.initialState(), HostEvent.EnterFixtureSignedIn)
        state = HostFixtureClient.dispatch(state, HostEvent.KeyboardSettingsAction(KeyboardSettingsEvent.SetOneHanded(OneHandedMode.RIGHT)))
        state = HostFixtureClient.dispatch(state, HostEvent.KeyboardSettingsAction(KeyboardSettingsEvent.RecordFixtureQualification(QualificationMetrics(120, 300, 100, 30, 1000, 1))))
        state = HostFixtureClient.dispatch(state, HostEvent.SimulateSessionRevocation)
        assertEquals(OneHandedMode.RIGHT, state.keyboardSettings.oneHanded)
        assertEquals(QualificationStatus.CLEARED, state.keyboardSettings.qualificationStatus)
    }

    @Test
    fun currentDeviceRevocationClearsQualificationButPreservesOrdinaryPreferences() {
        var state = HostFixtureClient.dispatch(HostFixtureClient.initialState(), HostEvent.EnterFixtureSignedIn)
        state = HostFixtureClient.dispatch(state, HostEvent.KeyboardSettingsAction(KeyboardSettingsEvent.SetTheme(KeyboardTheme.DARK)))
        state = HostFixtureClient.dispatch(state, HostEvent.KeyboardSettingsAction(KeyboardSettingsEvent.RecordFixtureQualification(QualificationMetrics(120, 300, 100, 30, 1000, 1))))
        state = HostFixtureClient.dispatch(state, HostEvent.RequestDeviceRevoke("device-current"))
        state = HostFixtureClient.dispatch(state, HostEvent.ConfirmDeviceRevoke)
        assertEquals(SessionStatus.REVOKED, state.account.sessionStatus)
        assertEquals(KeyboardTheme.DARK, state.keyboardSettings.theme)
        assertEquals(QualificationStatus.CLEARED, state.keyboardSettings.qualificationStatus)
    }

    @Test
    fun qualificationRejectsUnboundedMetricsAndExpiredSessionCannotRerecord() {
        var state = HostFixtureClient.dispatch(HostFixtureClient.initialState(), HostEvent.EnterFixtureSignedIn)
        state = HostFixtureClient.dispatch(state, HostEvent.KeyboardSettingsAction(KeyboardSettingsEvent.RecordFixtureQualification(QualificationMetrics(-1, 300, 100, 30, 1000, 1))))
        assertEquals(QualificationStatus.NOT_PROVEN, state.keyboardSettings.qualificationStatus)
        state = HostFixtureClient.dispatch(state, HostEvent.KeyboardSettingsAction(KeyboardSettingsEvent.RecordFixtureQualification(QualificationMetrics(120, 300, 100, 30, 1000, 1))))
        assertEquals(QualificationStatus.FIXTURE_PASSED, state.keyboardSettings.qualificationStatus)
        state = HostFixtureClient.dispatch(state, HostEvent.SimulateSessionExpiry)
        val expired = HostFixtureClient.dispatch(state, HostEvent.KeyboardSettingsAction(KeyboardSettingsEvent.RecordFixtureQualification(QualificationMetrics(120, 300, 100, 30, 1000, 1))))
        assertEquals(QualificationStatus.CLEARED, expired.keyboardSettings.qualificationStatus)
        assertEquals(null, expired.keyboardSettings.qualificationMetrics)
    }

    @Test
    fun workflowFailsClosedWhenLaterEntityWouldBeDropped() {
        val input = "第一文。第二文。第三文。第四文 https://example.com 田中さん。"
        val result = JapaneseWorkflowFixtures.apply(JapaneseWorkflowPack.KEY_POINTS, input)
        assertEquals(false, result.contentPreserved)
        assertEquals("", result.preview)
        val emptyResult = JapaneseWorkflowFixtures.apply(JapaneseWorkflowPack.KEY_POINTS, "。。。")
        assertEquals(false, emptyResult.contentPreserved)
        assertEquals("", emptyResult.preview)
    }

    @Test
    fun qualificationUsesExactLatencyAndCrashFreeBoundaries() {
        var state = HostFixtureClient.dispatch(HostFixtureClient.initialState(), HostEvent.EnterFixtureSignedIn)
        state = HostFixtureClient.dispatch(state, HostEvent.KeyboardSettingsAction(KeyboardSettingsEvent.RecordFixtureQualification(QualificationMetrics(250, 400, 150, 50, 10000, 5))))
        assertEquals(QualificationStatus.BROAD_FIXTURE_PASSED, state.keyboardSettings.qualificationStatus)
        state = HostFixtureClient.dispatch(state, HostEvent.KeyboardSettingsAction(KeyboardSettingsEvent.RecordFixtureQualification(QualificationMetrics(251, 400, 150, 50, 10000, 0))))
        assertEquals(QualificationStatus.NOT_PROVEN, state.keyboardSettings.qualificationStatus)
        state = HostFixtureClient.dispatch(state, HostEvent.KeyboardSettingsAction(KeyboardSettingsEvent.RecordFixtureQualification(QualificationMetrics(250, 400, 150, 50, 1000, 1))))
        assertEquals(QualificationStatus.FIXTURE_PASSED, state.keyboardSettings.qualificationStatus)
        assertEquals(9990, state.keyboardSettings.qualificationMetrics!!.crashFreeBasisPoints)
        state = HostFixtureClient.dispatch(state, HostEvent.KeyboardSettingsAction(KeyboardSettingsEvent.RecordFixtureQualification(QualificationMetrics(401, 250, 150, 50, 1000, 0))))
        assertEquals(QualificationStatus.NOT_PROVEN, state.keyboardSettings.qualificationStatus)
    }
}
