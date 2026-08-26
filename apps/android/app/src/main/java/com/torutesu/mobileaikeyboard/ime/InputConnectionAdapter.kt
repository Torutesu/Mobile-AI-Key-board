package com.torutesu.mobileaikeyboard.ime

import android.view.inputmethod.InputConnection
import com.torutesu.mobileaikeyboard.core.TextFingerprint

data class CapturedContext(
    val selected: String,
    val before: String,
    val after: String,
    val fieldFingerprint: String,
) {
    val selectedCharacterCount: Int get() = selected.codePointCount(0, selected.length)
}

/** Bounded adapter. It never reads clipboard or unbounded editor content. */
class InputConnectionAdapter(
    private val inputConnection: InputConnection,
    private val beforeLimit: Int = 1_000,
    private val afterLimit: Int = 500,
) {
    fun captureSelection(): String = inputConnection.getSelectedText(0)?.toString().orEmpty()

    fun captureContext(includeSurrounding: Boolean): CapturedContext {
        val selected = captureSelection()
        val before = if (includeSurrounding) {
            inputConnection.getTextBeforeCursor(beforeLimit, 0)?.toString().orEmpty()
        } else ""
        val after = if (includeSurrounding) {
            inputConnection.getTextAfterCursor(afterLimit, 0)?.toString().orEmpty()
        } else ""
        return CapturedContext(selected, before, after, TextFingerprint.of(before + "\u0000" + selected + "\u0000" + after))
    }

    fun replaceSelection(expectedFingerprint: String?, replacement: String): Boolean {
        val current = captureContext(includeSurrounding = true)
        if (expectedFingerprint != null && expectedFingerprint != current.fieldFingerprint) return false
        inputConnection.commitText(replacement, 1)
        return true
    }

    fun insertAtCursor(text: String) { inputConnection.commitText(text, 1) }

    fun deleteBackward() { inputConnection.deleteSurroundingText(1, 0) }
}
