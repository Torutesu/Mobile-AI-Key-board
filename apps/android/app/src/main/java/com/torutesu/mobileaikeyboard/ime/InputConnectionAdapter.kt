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
    val fieldFingerprint: String?,
) {
    val selectedCharacterCount: Int get() = selected.codePointCount(0, selected.length)
}

/** Bounded adapter. It never reads clipboard or unbounded editor content. */
class InputConnectionAdapter(
    private val inputConnection: InputConnection,
    private val beforeLimit: Int = CaptureLimits.surroundingBeforeCodePoints,
    private val afterLimit: Int = CaptureLimits.surroundingAfterCodePoints,
) {
    fun captureSelection(): String = safely { inputConnection.getSelectedText(0)?.toString() }.orEmpty()

    fun captureContext(useSelection: Boolean, useSurrounding: Boolean): CapturedContext {
        // Reading editor content is itself a capability. Never touch a source
        // that the user did not explicitly enable for this capture.
        val selectedRaw = if (useSelection) safely { inputConnection.getSelectedText(0)?.toString() } else null
        val beforeRaw = if (useSurrounding) safely { inputConnection.getTextBeforeCursor(beforeLimit, 0)?.toString() } else null
        val afterRaw = if (useSurrounding) safely { inputConnection.getTextAfterCursor(afterLimit, 0)?.toString() } else null
        val selectedValue = selectedRaw.orEmpty()
        val selectionOverLimit = selectedValue.codePointCount(0, selectedValue.length) > CaptureLimits.selectionCodePoints
        val selected = if (selectionOverLimit) {
            selectedValue.substringToCodePoints(CaptureLimits.selectionCodePoints)
        } else selectedValue
        val before = if (useSurrounding) beforeRaw.orEmpty() else ""
        val after = if (useSurrounding) afterRaw.orEmpty() else ""
        // A null token means that an exact editor revision was not observable.
        // Apply must then fail closed and keep Copy as the recovery path.
        val fingerprint = when {
            useSurrounding && beforeRaw != null && afterRaw != null ->
                TextFingerprint.of("surrounding\u0000$beforeRaw\u0000$selected\u0000$afterRaw")
            useSelection && selectedRaw != null -> TextFingerprint.of("selection\u0000$selected")
            else -> null
        }
        return CapturedContext(
            selected = selected,
            before = before,
            after = after,
            selectionAvailable = selected.isNotEmpty(),
            surroundingAvailable = useSurrounding && beforeRaw != null && afterRaw != null,
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
        expectedFingerprint: String?,
        originalText: String,
        replacement: String,
        selectionEnabled: Boolean,
    ): AppliedEdit? {
        val current = captureContext(useSelection = selectionEnabled, useSurrounding = false)
        if (expectedFingerprint == null || current.fieldFingerprint != expectedFingerprint) return null
        if (safelyBoolean { inputConnection.commitText(replacement, 1) } != true) return null
        return AppliedEdit(
            originalText,
            replacement,
            appliedSuffixFingerprint(replacement),
            wasReplacement = originalText.isNotEmpty(),
        )
    }

    fun undo(edit: AppliedEdit): Boolean {
        val appliedBeforeCursor = safely { inputConnection.getTextBeforeCursor(edit.appliedText.length, 0)?.toString() }
        if (appliedBeforeCursor != edit.appliedText) return false
        if (appliedSuffixFingerprint(appliedBeforeCursor) != edit.expectedAfterFingerprint) return false
        if (safelyBoolean { inputConnection.deleteSurroundingText(edit.appliedText.length, 0) } != true) return false
        if (edit.originalText.isNotEmpty() && safelyBoolean { inputConnection.commitText(edit.originalText, 1) } != true) {
            // Best-effort rollback prevents a failed restore from silently
            // presenting itself as a successful Undo.
            safelyBoolean { inputConnection.commitText(edit.appliedText, 1) }
            return false
        }
        return true
    }

    fun replaceSelection(expectedFingerprint: String?, replacement: String): Boolean {
        val current = captureContext(includeSurrounding = true)
        if (expectedFingerprint == null || expectedFingerprint != current.fieldFingerprint) return false
        return safelyBoolean { inputConnection.commitText(replacement, 1) } == true
    }

    fun insertAtCursor(text: String): Boolean = safelyBoolean { inputConnection.commitText(text, 1) } == true

    fun deleteBackward(): Boolean {
        val selected = safely { inputConnection.getSelectedText(0)?.toString() }
        if (!selected.isNullOrEmpty()) return safelyBoolean { inputConnection.commitText("", 1) } == true
        val before = safely { inputConnection.getTextBeforeCursor(64, 0)?.toString() } ?: return false
        if (before.isEmpty()) return false
        val count = previousGraphemeUtf16Length(before)
        return count > 0 && safelyBoolean { inputConnection.deleteSurroundingText(count, 0) } == true
    }

    private fun appliedSuffixFingerprint(value: String): String = TextFingerprint.of("applied-suffix\u0000$value")

    private fun <T> safely(block: () -> T): T? = try {
        block()
    } catch (_: RuntimeException) {
        null
    }

    private fun safelyBoolean(block: () -> Boolean): Boolean? = safely(block)
}

/**
 * Returns the UTF-16 length of the previous user-perceived character.
 * Covers combining marks, variation selectors, emoji modifiers, flags and
 * ZWJ emoji families without splitting surrogate pairs.
 */
internal fun previousGraphemeUtf16Length(value: String): Int {
    if (value.isEmpty()) return 0
    var start = value.offsetByCodePoints(value.length, -1)
    val last = value.codePointAt(start)

    fun isExtension(codePoint: Int): Boolean {
        val type = Character.getType(codePoint)
        return type == Character.NON_SPACING_MARK.toInt() ||
            type == Character.COMBINING_SPACING_MARK.toInt() ||
            type == Character.ENCLOSING_MARK.toInt() ||
            codePoint in 0xFE00..0xFE0F ||
            codePoint in 0xE0100..0xE01EF ||
            codePoint in 0x1F3FB..0x1F3FF
    }

    // Attach trailing marks/modifiers to their base.
    while (start > 0 && isExtension(value.codePointAt(start))) {
        start = value.offsetByCodePoints(start, -1)
    }

    // A flag is one grapheme made from a pair of regional indicators.
    if (last in 0x1F1E6..0x1F1FF && start > 0) {
        val previousStart = value.offsetByCodePoints(start, -1)
        if (value.codePointAt(previousStart) in 0x1F1E6..0x1F1FF) start = previousStart
    }

    // Include every preceding base joined with U+200D and its extensions.
    while (start > 0) {
        val joinerStart = value.offsetByCodePoints(start, -1)
        if (value.codePointAt(joinerStart) != 0x200D || joinerStart == 0) break
        start = value.offsetByCodePoints(joinerStart, -1)
        while (start > 0 && isExtension(value.codePointAt(start))) {
            start = value.offsetByCodePoints(start, -1)
        }
    }
    return value.length - start
}

private fun String.substringToCodePoints(limit: Int): String {
    if (codePointCount(0, length) <= limit) return this
    val end = offsetByCodePoints(0, limit)
    return substring(0, end)
}
