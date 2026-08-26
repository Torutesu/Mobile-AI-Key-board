package com.torutesu.mobileaikeyboard.core

import android.text.InputType
import android.view.inputmethod.EditorInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyboardFoundationTest {
    @Test
    fun stateMachine_entersCommandAndReturnsToTypingAfterApply() {
        var state = KeyboardState()
        state = KeyboardReducer.reduce(state, KeyboardAction.EnterCommand)
        assertEquals(KeyboardMode.COMMAND, state.mode)
        state = KeyboardReducer.reduce(state, KeyboardAction.ShowResult("丁寧な文章です。"))
        assertEquals(KeyboardMode.RESULT_REVIEW, state.mode)
        state = KeyboardReducer.reduce(state, KeyboardAction.ApplyResult)
        assertEquals(KeyboardMode.TYPING, state.mode)
    }

    @Test
    fun lockedState_cannotEnterCommand() {
        val locked = KeyboardReducer.reduce(KeyboardState(), KeyboardAction.Lock("password"))
        assertEquals(KeyboardMode.LOCKED, KeyboardReducer.reduce(locked, KeyboardAction.EnterCommand).mode)
    }

    @Test
    fun sensitiveFields_failClosedBeforeCapture() {
        val password = EditorInfo().apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
        }
        val otp = EditorInfo().apply {
            inputType = InputType.TYPE_CLASS_NUMBER
            privateImeOptions = "com.example.otp"
        }
        val phone = EditorInfo().apply { inputType = InputType.TYPE_CLASS_PHONE }
        assertFalse(SensitiveFieldClassifier.classify(password).aiCaptureAllowed)
        assertFalse(SensitiveFieldClassifier.classify(otp).aiCaptureAllowed)
        assertFalse(SensitiveFieldClassifier.classify(phone).aiCaptureAllowed)
        assertTrue(SensitiveFieldClassifier.classify(EditorInfo().apply { inputType = InputType.TYPE_CLASS_TEXT }).aiCaptureAllowed)
    }

    @Test
    fun rewrite_preservesNamesDatesNumbersUrlsAndEmail() {
        val original = "田中さん、2026年8月26日に https://example.com を確認して。金額は12,000円、連絡先はtest@example.com"
        val result = LocalPoliteRewriteService().rewrite(original)
        assertTrue(result.wasChanged)
        assertTrue(result.rewritten.contains("田中さん"))
        assertTrue(result.rewritten.contains("2026年8月26日"))
        assertTrue(result.rewritten.contains("https://example.com"))
        assertTrue(result.rewritten.contains("12,000円"))
        assertTrue(result.rewritten.contains("test@example.com"))
        assertEquals(result.preservedEntities.size, 5)
    }

    @Test
    fun rewrite_isLocalAndDeterministicForEnglishFixture() {
        val result = LocalPoliteRewriteService().rewrite("Can you check #launch? thanks")
        assertEquals("Could you please check #launch? Thank you", result.rewritten)
        assertEquals(result.rewritten, LocalPoliteRewriteService().rewrite("Can you check #launch? thanks").rewritten)
    }

    @Test
    fun entityProtector_doesNotChangeUnrelatedText() {
        val text = "明日の予定を確認して"
        assertEquals("明日の予定を確認して。", EntityProtector.transformPreserving(text) { "$it。" })
    }

    @Test
    fun entityProtector_locksJapaneseNamesAndProductIdsEvenWhenTransformMatchesEntity() {
        val input = "変更さん PROD-42 API様を確認して"
        val output = EntityProtector.transformPreserving(input) {
            it.replace("変更", "改変").replace("PROD", "OTHER").replace("API", "SDK")
        }
        assertEquals(input, output)
        assertTrue(EntityProtector.protect(input).entities.any { it.category == "name" && it.value == "変更さん" })
        assertTrue(EntityProtector.protect(input).entities.any { it.category == "id" && it.value == "PROD-42" })
    }

    @Test
    fun commandSession_requiresCaptureAcknowledgementBeforeRewrite() {
        var session = CommandSessionReducer.reduce(CommandSession(), SessionEvent.BeginCommand)
        session = CommandSessionReducer.reduce(session, SessionEvent.UpdateCommand("丁寧にして"))
        session = CommandSessionReducer.reduce(session, SessionEvent.ToggleSource(InputSource.SELECTION, true))
        session = CommandSessionReducer.reduce(session, SessionEvent.CapturePrepared(
            BoundedCapture("丁寧にして", "変更して", "", "", true, true, "before"),
        ))
        assertEquals(SessionPhase.CAPTURE_REVIEW, session.phase)
        assertEquals("変更して", session.preview?.exactText)
        assertEquals("端末内のみ", session.preview?.destination)
        assertFalse(session.preview?.externalTransmission == true)
        assertTrue(session.canAcknowledge)
        session = CommandSessionReducer.reduce(session, SessionEvent.Generated("should not run yet"))
        assertEquals(SessionPhase.CAPTURE_REVIEW, session.phase)
        session = CommandSessionReducer.reduce(session, SessionEvent.AcknowledgeCapture)
        assertEquals(SessionPhase.TRANSFORMING, session.phase)
        session = CommandSessionReducer.reduce(session, SessionEvent.Generated("変更してください。"))
        assertEquals(SessionPhase.RESULT_REVIEW, session.phase)
    }

    @Test
    fun unavailableSelection_fallsBackToTypedCommandWithNotice() {
        var session = CommandSessionReducer.reduce(CommandSession(), SessionEvent.BeginCommand)
        session = CommandSessionReducer.reduce(session, SessionEvent.UpdateCommand("丁寧にして"))
        session = CommandSessionReducer.reduce(session, SessionEvent.ToggleSource(InputSource.SELECTION, true))
        session = CommandSessionReducer.reduce(session, SessionEvent.CapturePrepared(
            BoundedCapture("丁寧にして", "", "周辺", "", false, true, "fingerprint"),
        ))
        assertEquals("丁寧にして", session.target)
        assertTrue(session.preview?.notice?.contains("Commandだけ") == true)
    }

    @Test
    fun applyAndUndoStateMachine_handlesStaleRejection() {
        var session = CommandSession(phase = SessionPhase.RESULT_REVIEW, resultText = "新しい文")
        session = CommandSessionReducer.reduce(session, SessionEvent.ApplyRejected("stale"))
        assertEquals(SessionPhase.ERROR, session.phase)
        session = CommandSession(phase = SessionPhase.RESULT_REVIEW, resultText = "新しい文")
        session = CommandSessionReducer.reduce(session, SessionEvent.Applied(UndoTicket("元", "新しい文", "after", true)))
        assertEquals(SessionPhase.RECEIPT, session.phase)
        session = CommandSessionReducer.reduce(session, SessionEvent.UndoRejected("field changed"))
        assertEquals(SessionPhase.ERROR, session.phase)
    }

    @Test
    fun captureAndResultLimits_failClosed() {
        var session = CommandSessionReducer.reduce(CommandSession(), SessionEvent.BeginCommand)
        val longCommand = "あ".repeat(CaptureLimits.commandCodePoints + 1)
        session = CommandSessionReducer.reduce(session, SessionEvent.UpdateCommand(longCommand))
        session = CommandSessionReducer.reduce(session, SessionEvent.CapturePrepared(
            BoundedCapture(longCommand, "", "", "", false, true, "fingerprint"),
        ))
        assertFalse(session.canAcknowledge)
        assertTrue(session.preview?.blockedReason?.contains("${CaptureLimits.commandCodePoints}") == true)

        var selectionSession = CommandSessionReducer.reduce(CommandSession(), SessionEvent.BeginCommand)
        selectionSession = CommandSessionReducer.reduce(selectionSession, SessionEvent.ToggleSource(InputSource.SELECTION, true))
        selectionSession = CommandSessionReducer.reduce(selectionSession, SessionEvent.CapturePrepared(
            BoundedCapture("", "x", "", "", true, true, "fingerprint", selectionOverLimit = true),
        ))
        assertFalse(selectionSession.canAcknowledge)
        assertTrue(selectionSession.preview?.blockedReason?.contains("${CaptureLimits.selectionCodePoints}") == true)

        var resultSession = CommandSession(phase = SessionPhase.TRANSFORMING)
        resultSession = CommandSessionReducer.reduce(resultSession, SessionEvent.Generated("x".repeat(CaptureLimits.resultCodePoints + 1)))
        assertEquals(SessionPhase.ERROR, resultSession.phase)

        var editableSession = CommandSession(phase = SessionPhase.RESULT_REVIEW, resultText = "safe")
        editableSession = CommandSessionReducer.reduce(
            editableSession,
            SessionEvent.EditResult("x".repeat(CaptureLimits.resultCodePoints + 1)),
        )
        assertEquals(SessionPhase.RESULT_REVIEW, editableSession.phase)
        assertEquals("safe", editableSession.resultText)
        assertTrue(editableSession.error?.contains("${CaptureLimits.resultCodePoints}") == true)
    }

    @Test
    fun captureReview_showsRedactedPreviewAndBlocksSecretTransmission() {
        var session = CommandSessionReducer.reduce(CommandSession(), SessionEvent.BeginCommand)
        val secret = "api_key=sk_test_1234567890abcdef"
        session = CommandSessionReducer.reduce(session, SessionEvent.UpdateCommand(secret))
        session = CommandSessionReducer.reduce(session, SessionEvent.CapturePrepared(
            BoundedCapture(secret, "", "", "", false, true, "fingerprint"),
        ))
        assertEquals("[redacted]", session.preview?.redactedText)
        assertTrue(session.preview?.blockedReason?.contains("機密") == true)
        assertFalse(session.canAcknowledge)
    }

    @Test
    fun generatedSessionRetainsProtectedEntityAuthorityAcrossEdits() {
        var session = CommandSession(phase = SessionPhase.TRANSFORMING)
        session = CommandSessionReducer.reduce(session, SessionEvent.Generated("田中さんへ連絡します。", listOf("田中さん")))
        session = CommandSessionReducer.reduce(session, SessionEvent.EditResult("担当者へ連絡します。"))
        assertEquals(listOf("田中さん"), session.preservedEntities)
        assertFalse(session.preservedEntities.all(session.resultText.orEmpty()::contains))
    }
}
