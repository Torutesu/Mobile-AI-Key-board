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
    fun insertionRejectsAnUnacknowledgedActiveSelection() {
        val editor = FakeEditor("hello old world", 6, 9)
        val adapter = InputConnectionAdapter(editor.connection)
        val capturedWithoutSelection = adapter.captureContext(useSelection = false, useSurrounding = false)

        assertNull(adapter.applyInsertion(capturedWithoutSelection.fieldFingerprint, "new"))
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
}

private class FakeEditor(initialText: String, selectionStart: Int, selectionEnd: Int) : InvocationHandler {
    var text: String = initialText
        private set
    private var selectionStart: Int = selectionStart
    private var selectionEnd: Int = selectionEnd

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

    override fun invoke(proxy: Any, method: Method, arguments: Array<out Any?>?): Any? {
        val args = arguments.orEmpty()
        return when (method.name) {
            "getSelectedText" -> if (selectionStart == selectionEnd) null else text.substring(selectionStart, selectionEnd)
            "getTextBeforeCursor" -> {
                val count = args[0] as Int
                text.substring(max(0, selectionStart - count), selectionStart)
            }
            "getTextAfterCursor" -> {
                val count = args[0] as Int
                text.substring(selectionEnd, min(text.length, selectionEnd + count))
            }
            "commitText" -> {
                val replacement = args[0].toString()
                text = text.replaceRange(selectionStart, selectionEnd, replacement)
                selectionStart += replacement.length
                selectionEnd = selectionStart
                true
            }
            "deleteSurroundingText" -> {
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
