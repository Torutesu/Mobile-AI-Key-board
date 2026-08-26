package com.torutesu.mobileaikeyboard.ime

import android.view.inputmethod.InputConnection
import com.torutesu.mobileaikeyboard.core.CaptureLimits
import com.torutesu.mobileaikeyboard.core.TextFingerprint

data class CapturedContext(
    val selected: String,
    val before: String,
    val after: String,
    val selectionAvailable: Boolean,
    val surroundingAvailable: Boolean,
    val selectionOverLimit: Boolean,
    val fieldFingerprint: String,
) {
    val selectedCharacterCount: Int get() = selected.codePointCount(0, selected.length)
}

/** Bounded adapter. It never reads clipboard or unbounded editor content. */
class InputConnectionAdapter(
    private val inputConnection: InputConnection,
    private val beforeLimit: Int = CaptureLimits.surroundingBeforeCodePoints,
    private val afterLimit: Int = CaptureLimits.surroundingAfterCodePoints,
) {
    fun captureSelection(): String = inputConnection.getSelectedText(0)?.toString().orEmpty()

    fun captureContext(useSelection: Boolean, useSurrounding: Boolean): CapturedContext {
        val selectedRaw = if (useSelection) inputConnection.getSelectedText(0)?.toString() else null
        val beforeRaw = inputConnection.getTextBeforeCursor(beforeLimit, 0)?.toString()
        val afterRaw = inputConnection.getTextAfterCursor(afterLimit, 0)?.toString()
        val selectedValue = selectedRaw.orEmpty()
        val selectionOverLimit = selectedValue.codePointCount(0, selectedValue.length) > CaptureLimits.selectionCodePoints
        val selected = if (selectionOverLimit) {
            selectedValue.substringToCodePoints(CaptureLimits.selectionCodePoints)
        } else selectedValue
        val before = if (useSurrounding) beforeRaw.orEmpty() else ""
        val after = if (useSurrounding) afterRaw.orEmpty() else ""
        // The bounded local fingerprint still includes the surrounding window to
        // reject stale Apply/Undo, while the source is not exposed in the preview
        // unless the user opted in.
        val fingerprint = TextFingerprint.of(beforeRaw.orEmpty() + "\u0000" + selected + "\u0000" + afterRaw.orEmpty())
        return CapturedContext(
            selected = selected,
            before = before,
            after = after,
            selectionAvailable = selected.isNotEmpty(),
            surroundingAvailable = beforeRaw != null && afterRaw != null,
            selectionOverLimit = selectionOverLimit,
            fieldFingerprint = fingerprint,
        )
    }

    fun captureContext(includeSurrounding: Boolean): CapturedContext =
        captureContext(useSelection = true, useSurrounding = includeSurrounding)

    data class AppliedEdit(
        val originalText: String,
        val appliedText: String,
        val expectedAfterFingerprint: String,
        val wasReplacement: Boolean,
    )

    fun applySelection(
        expectedFingerprint: String,
        originalText: String,
        replacement: String,
        selectionEnabled: Boolean,
    ): AppliedEdit? {
        val current = captureContext(useSelection = selectionEnabled, useSurrounding = false)
        if (current.fieldFingerprint != expectedFingerprint) return null
        inputConnection.commitText(replacement, 1)
        val after = captureContext(useSelection = false, useSurrounding = false)
        return AppliedEdit(originalText, replacement, after.fieldFingerprint, wasReplacement = originalText.isNotEmpty())
    }

    fun applyInsertion(expectedFingerprint: String, replacement: String): AppliedEdit? {
        // A commit with an active host selection would replace it. When the
        // user did not opt into selection, fail closed instead of surprising
        // them with an implicit replacement.
        val current = captureContext(useSelection = true, useSurrounding = false)
        if (current.selected.isNotEmpty() || current.fieldFingerprint != expectedFingerprint) return null
        inputConnection.commitText(replacement, 1)
        val after = captureContext(useSelection = false, useSurrounding = false)
        return AppliedEdit("", replacement, after.fieldFingerprint, wasReplacement = false)
    }

    fun undo(edit: AppliedEdit): Boolean {
        val current = captureContext(useSelection = false, useSurrounding = false)
        if (current.fieldFingerprint != edit.expectedAfterFingerprint) return false
        val appliedBeforeCursor = inputConnection.getTextBeforeCursor(edit.appliedText.length, 0)?.toString()
        if (appliedBeforeCursor != edit.appliedText) return false
        inputConnection.deleteSurroundingText(edit.appliedText.length, 0)
        if (edit.originalText.isNotEmpty()) inputConnection.commitText(edit.originalText, 1)
        return true
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

private fun String.substringToCodePoints(limit: Int): String {
    if (codePointCount(0, length) <= limit) return this
    val end = offsetByCodePoints(0, limit)
    return substring(0, end)
}
