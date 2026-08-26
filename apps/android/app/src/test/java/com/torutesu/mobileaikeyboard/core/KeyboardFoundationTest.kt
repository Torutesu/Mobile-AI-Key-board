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
        assertEquals(result.preservedEntities.size, 4)
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
}
