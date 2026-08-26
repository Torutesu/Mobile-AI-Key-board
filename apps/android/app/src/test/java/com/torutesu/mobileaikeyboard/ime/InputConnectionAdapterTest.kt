package com.torutesu.mobileaikeyboard.ime

import android.view.inputmethod.InputConnection
import java.lang.reflect.InvocationHandler
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import kotlin.math.max
import kotlin.math.min
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class InputConnectionAdapterTest {
    @Test
    fun captureExposesOnlyEnabledSourcesButUsesBoundedContextForSelectionLock() {
        val editor = FakeEditor("before selected after", 7, 15)
        val adapter = InputConnectionAdapter(editor.connection)

        val selectionOnly = adapter.captureContext(useSelection = true, useSurrounding = false)
        assertEquals("selected", selectionOnly.selected)
        assertEquals(1, editor.selectedReads)
        assertEquals("", selectionOnly.before)
        assertEquals("", selectionOnly.after)
        assertEquals(1, editor.beforeReads)
        assertEquals(1, editor.afterReads)

        editor.resetReadCounts()
        val commandOnly = adapter.captureContext(useSelection = false, useSurrounding = false)
        assertNull(commandOnly.fieldFingerprint)
        assertEquals(0, editor.selectedReads)
        assertEquals(0, editor.beforeReads)
        assertEquals(0, editor.afterReads)
    }

    @Test
    fun selectionApplyAndUndoRestoreTheExactOriginal() {
        val editor = FakeEditor("hello old world", 6, 9)
        val adapter = InputConnectionAdapter(editor.connection)
        val captured = adapter.captureContext(useSelection = true, useSurrounding = false)

        val edit = adapter.applySelection(captured.fieldFingerprint, "old", "new", selectionEnabled = true)

        requireNotNull(edit)
        assertEquals("hello new world", editor.text)
        assertTrue(adapter.undo(edit))
        assertEquals("hello old world", editor.text)
    }

    @Test
    fun commandOnlyCaptureDoesNotMintAnInsertionRevisionToken() {
        val editor = FakeEditor("hello old world", 6, 9)
        val adapter = InputConnectionAdapter(editor.connection)
        val capturedWithoutSelection = adapter.captureContext(useSelection = false, useSurrounding = false)

        assertNull(capturedWithoutSelection.fieldFingerprint)
        assertEquals("hello old world", editor.text)
    }

    @Test
    fun applyAndUndoFailClosedAfterEditorMutation() {
        val editor = FakeEditor("hello old world", 6, 9)
        val adapter = InputConnectionAdapter(editor.connection)
        val captured = adapter.captureContext(useSelection = true, useSurrounding = false)
        editor.replace("hello other world", 6, 11)
        assertNull(adapter.applySelection(captured.fieldFingerprint, "old", "new", selectionEnabled = true))

        editor.replace("hello old world", 6, 9)
        val fresh = adapter.captureContext(useSelection = true, useSurrounding = false)
        val edit = requireNotNull(adapter.applySelection(fresh.fieldFingerprint, "old", "new", selectionEnabled = true))
        editor.replace("hello new! world", 10, 10)
        assertFalse(adapter.undo(edit))
        assertEquals("hello new! world", editor.text)
    }

    @Test
    fun duplicateSelectedTextCannotBeAppliedAtAnotherOccurrence() {
        val editor = FakeEditor("old middle old", 0, 3)
        val adapter = InputConnectionAdapter(editor.connection)
        val first = adapter.captureContext(useSelection = true, useSurrounding = false)

        editor.moveSelection(11, 14)
        assertNull(adapter.applySelection(first.fieldFingerprint, "old", "new", selectionEnabled = true))
        assertEquals("old middle old", editor.text)
    }

    @Test
    fun undoCannotTargetAnotherIdenticalAppliedSuffix() {
        val editor = FakeEditor("new middle old", 11, 14)
        val adapter = InputConnectionAdapter(editor.connection)
        val captured = adapter.captureContext(useSelection = true, useSurrounding = false)
        val edit = requireNotNull(adapter.applySelection(captured.fieldFingerprint, "old", "new", selectionEnabled = true))
        assertEquals("new middle new", editor.text)

        editor.moveSelection(3, 3)
        assertFalse(adapter.undo(edit))
        assertEquals("new middle new", editor.text)
    }

    @Test
    fun applyAndUndoRejectFalseOrExceptionalEditorOperations() {
        val commitFalse = FakeEditor("old", 0, 3).apply { commitResult = false }
        val commitAdapter = InputConnectionAdapter(commitFalse.connection)
        val captured = commitAdapter.captureContext(useSelection = true, useSurrounding = false)
        assertNull(commitAdapter.applySelection(captured.fieldFingerprint, "old", "new", true))
        assertEquals("old", commitFalse.text)

        val commitThrows = FakeEditor("old", 0, 3).apply { throwOnCommit = true }
        val throwingAdapter = InputConnectionAdapter(commitThrows.connection)
        val throwingCapture = throwingAdapter.captureContext(useSelection = true, useSurrounding = false)
        assertNull(throwingAdapter.applySelection(throwingCapture.fieldFingerprint, "old", "new", true))
        assertEquals("old", commitThrows.text)

        val deleteFalse = FakeEditor("old", 0, 3)
        val deleteAdapter = InputConnectionAdapter(deleteFalse.connection)
        val deleteCapture = deleteAdapter.captureContext(useSelection = true, useSurrounding = false)
        val edit = requireNotNull(deleteAdapter.applySelection(deleteCapture.fieldFingerprint, "old", "new", true))
        deleteFalse.deleteResult = false
        assertFalse(deleteAdapter.undo(edit))
        assertEquals("new", deleteFalse.text)
    }

    @Test
    fun unavailableRevisionNeverBecomesAValidEmptyFingerprint() {
        val editor = FakeEditor("", 0, 0).apply {
            nullSelectedRead = true
            nullSurroundingRead = true
        }
        val adapter = InputConnectionAdapter(editor.connection)
        val context = adapter.captureContext(useSelection = true, useSurrounding = true)

        assertNull(context.fieldFingerprint)
        assertNull(adapter.applySelection(context.fieldFingerprint, "", "new", selectionEnabled = true))
        assertEquals("", editor.text)
    }

    @Test
    fun deleteBackwardRemovesOneWholeGraphemeCluster() {
        listOf("😀", "e\u0301", "👩‍💻", "🇯🇵").forEach { grapheme ->
            val editor = FakeEditor("A$grapheme", "A$grapheme".length, "A$grapheme".length)
            assertTrue(InputConnectionAdapter(editor.connection).deleteBackward())
            assertEquals("A", editor.text)
        }
    }

    @Test
    fun ordinaryInsertAndDeleteContainEditorExceptions() {
        val editor = FakeEditor("x", 1, 1).apply {
            throwOnCommit = true
            throwOnDelete = true
        }
        val adapter = InputConnectionAdapter(editor.connection)
        assertFalse(adapter.insertAtCursor("y"))
        assertFalse(adapter.deleteBackward())
        assertEquals("x", editor.text)
    }
}

private class FakeEditor(initialText: String, selectionStart: Int, selectionEnd: Int) : InvocationHandler {
    var text: String = initialText
        private set
    private var selectionStart: Int = selectionStart
    private var selectionEnd: Int = selectionEnd
    var selectedReads = 0
    var beforeReads = 0
    var afterReads = 0
    var commitResult = true
    var deleteResult = true
    var throwOnCommit = false
    var throwOnDelete = false
    var nullSelectedRead = false
    var nullSurroundingRead = false

    val connection: InputConnection = Proxy.newProxyInstance(
        InputConnection::class.java.classLoader,
        arrayOf(InputConnection::class.java),
        this,
    ) as InputConnection

    fun replace(value: String, start: Int, end: Int) {
        text = value
        selectionStart = start
        selectionEnd = end
    }

    fun moveSelection(start: Int, end: Int) {
        selectionStart = start
        selectionEnd = end
    }

    fun resetReadCounts() {
        selectedReads = 0
        beforeReads = 0
        afterReads = 0
    }

    override fun invoke(proxy: Any, method: Method, arguments: Array<out Any?>?): Any? {
        val args = arguments.orEmpty()
        return when (method.name) {
            "getSelectedText" -> {
                selectedReads++
                if (nullSelectedRead || selectionStart == selectionEnd) null else text.substring(selectionStart, selectionEnd)
            }
            "getTextBeforeCursor" -> {
                beforeReads++
                if (nullSurroundingRead) return null
                val count = args[0] as Int
                text.substring(max(0, selectionStart - count), selectionStart)
            }
            "getTextAfterCursor" -> {
                afterReads++
                if (nullSurroundingRead) return null
                val count = args[0] as Int
                text.substring(selectionEnd, min(text.length, selectionEnd + count))
            }
            "commitText" -> {
                if (throwOnCommit) throw IllegalStateException("commit failure")
                if (!commitResult) return false
                val replacement = args[0].toString()
                text = text.replaceRange(selectionStart, selectionEnd, replacement)
                selectionStart += replacement.length
                selectionEnd = selectionStart
                true
            }
            "deleteSurroundingText" -> {
                if (throwOnDelete) throw IllegalStateException("delete failure")
                if (!deleteResult) return false
                val before = args[0] as Int
                val after = args[1] as Int
                val start = max(0, selectionStart - before)
                val end = min(text.length, selectionEnd + after)
                text = text.removeRange(start, end)
                selectionStart = start
                selectionEnd = start
                true
            }
            "toString" -> "FakeInputConnection"
            "hashCode" -> System.identityHashCode(proxy)
            "equals" -> proxy === args.firstOrNull()
            else -> when (method.returnType) {
                Boolean::class.javaPrimitiveType -> false
                Int::class.javaPrimitiveType -> 0
                Long::class.javaPrimitiveType -> 0L
                Float::class.javaPrimitiveType -> 0f
                Double::class.javaPrimitiveType -> 0.0
                else -> null
            }
        }
    }
}
