package com.torutesu.mobileaikeyboard.ime

import android.inputmethodservice.InputMethodService
import android.view.View
import android.view.inputmethod.EditorInfo
import com.torutesu.mobileaikeyboard.core.BoundedCapture
import com.torutesu.mobileaikeyboard.core.CommandSession
import com.torutesu.mobileaikeyboard.core.CommandSessionReducer
import com.torutesu.mobileaikeyboard.core.ContentFreeTelemetry
import com.torutesu.mobileaikeyboard.core.InputSource
import com.torutesu.mobileaikeyboard.core.LocalPoliteRewriteService
import com.torutesu.mobileaikeyboard.core.NoOpTelemetry
import com.torutesu.mobileaikeyboard.core.SensitiveFieldClassifier
import com.torutesu.mobileaikeyboard.core.SessionEvent
import com.torutesu.mobileaikeyboard.core.SessionPhase
import com.torutesu.mobileaikeyboard.core.TelemetryEvent
import com.torutesu.mobileaikeyboard.core.UndoTicket
import com.torutesu.mobileaikeyboard.core.asKeyboardState

class KeyboardImeService : InputMethodService() {
    private var session = CommandSession()
    private var lockReason: String? = null
    private var surface: KeyboardSurface? = null
    private var adapter: InputConnectionAdapter? = null
    private var appliedEdit: InputConnectionAdapter.AppliedEdit? = null
    private var telemetry: ContentFreeTelemetry = NoOpTelemetry
    private val rewriteService = LocalPoliteRewriteService()

    override fun onCreateInputView(): View {
        surface = KeyboardSurface(this, KeyboardSurface.Callbacks(
            onCommand = { enterCommand() },
            onText = { text -> adapter?.insertAtCursor(text) },
            onDelete = { adapter?.deleteBackward() },
            onEnter = {
                currentInputConnection?.sendKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_ENTER))
                currentInputConnection?.sendKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, android.view.KeyEvent.KEYCODE_ENTER))
            },
            onSwitchKeyboard = { switchToNextInputMethod(false) },
            onCapture = { command, selection, surrounding -> capture(command, selection, surrounding) },
            onAcknowledge = { acknowledgeCapture() },
            onEditResult = { value -> editResult(value) },
            onRegenerate = { regenerate() },
            onApply = { result -> applyResult(result) },
            onCopy = { result -> copyResult(result) },
            onUndo = { undoResult() },
            onCancel = { cancel() },
        ))
        syncSurface()
        return surface!!
    }

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        adapter = currentInputConnection?.let(::InputConnectionAdapter)
        // EditorInfo may change without a matching onFinishInput. Drop every
        // prior field's capture/result/undo before inspecting the new boundary.
        session = CommandSession()
        appliedEdit = null
        val classification = SensitiveFieldClassifier.classify(attribute)
        lockReason = classification.explanation.takeUnless { classification.aiCaptureAllowed }
        syncSurface()
    }

    override fun onFinishInput() {
        adapter = null
        appliedEdit = null
        session = CommandSession()
        lockReason = null
        syncSurface()
        super.onFinishInput()
    }

    private fun enterCommand() {
        if (lockReason != null) return
        session = CommandSessionReducer.reduce(session, SessionEvent.BeginCommand)
        syncSurface()
    }

    private fun capture(command: String, useSelection: Boolean, useSurrounding: Boolean) {
        if (lockReason != null || session.phase != SessionPhase.COMMAND) return
        session = CommandSessionReducer.reduce(session, SessionEvent.UpdateCommand(command))
        session = CommandSessionReducer.reduce(session, SessionEvent.ToggleSource(InputSource.SELECTION, useSelection))
        session = CommandSessionReducer.reduce(session, SessionEvent.ToggleSource(InputSource.SURROUNDING, useSurrounding))
        val input = adapter ?: return
        val context = input.captureContext(useSelection = useSelection, useSurrounding = useSurrounding)
        session = CommandSessionReducer.reduce(
            session,
            SessionEvent.CapturePrepared(
                BoundedCapture(
                    command = command,
                    selected = context.selected,
                    before = context.before,
                    after = context.after,
                    selectionAvailable = context.selectionAvailable,
                    surroundingAvailable = context.surroundingAvailable,
                    selectionOverLimit = context.selectionOverLimit,
                    fieldFingerprint = context.fieldFingerprint,
                ),
            ),
        )
        telemetry.record(TelemetryEvent.CommandStarted("local.polite-rewrite", "R1", session.sources))
        syncSurface()
    }

    private fun acknowledgeCapture() {
        if (!session.canAcknowledge) return
        session = CommandSessionReducer.reduce(session, SessionEvent.AcknowledgeCapture)
        syncSurface()
        val target = session.target ?: return
        // Deliberately local and synchronous: acknowledgement is required before
        // this fixture runs, and there is no transport or provider dependency.
        val rewritten = rewriteService.rewrite(target)
        session = CommandSessionReducer.reduce(session, SessionEvent.Generated(rewritten.rewritten, rewritten.preservedEntities.map { it.value }))
        syncSurface()
    }

    private fun editResult(value: String) {
        session = CommandSessionReducer.reduce(session, SessionEvent.EditResult(value))
        syncSurface()
    }

    private fun regenerate() {
        if (session.phase != SessionPhase.RESULT_REVIEW) return
        val target = session.target ?: return
        session = CommandSessionReducer.reduce(session, SessionEvent.Regenerate)
        syncSurface()
        val rewritten = rewriteService.rewrite(target)
        session = CommandSessionReducer.reduce(session, SessionEvent.Generated(rewritten.rewritten, rewritten.preservedEntities.map { it.value }))
        syncSurface()
    }

    private fun applyResult(editedResult: String) {
        val capture = session.capture ?: return
        val result = editedResult
        val input = adapter ?: return
        session = CommandSessionReducer.reduce(session, SessionEvent.EditResult(result))
        if (session.phase != SessionPhase.RESULT_REVIEW || session.error != null) {
            syncSurface()
            return
        }
        if (!session.preservedEntities.all(result::contains)) {
            session = CommandSessionReducer.reduce(session, SessionEvent.ApplyRejected("保護対象の名前・日時・数値・URLなどが変更されたため適用を停止しました"))
            syncSurface()
            return
        }
        val selectionEnabled = InputSource.SELECTION in session.sources && capture.selected.isNotBlank()
        val edit = if (selectionEnabled) {
            input.applySelection(capture.fieldFingerprint, capture.selected, result, selectionEnabled = true)
        } else {
            input.applyInsertion(capture.fieldFingerprint, result)
        }
        if (edit == null) {
            session = CommandSessionReducer.reduce(session, SessionEvent.ApplyRejected("入力欄の内容が変更されたため、自動適用を停止しました。結果をコピーしてください"))
        } else {
            appliedEdit = edit
            val ticket = UndoTicket(edit.originalText, edit.appliedText, edit.expectedAfterFingerprint, edit.wasReplacement)
            session = CommandSessionReducer.reduce(session, SessionEvent.Applied(ticket))
            telemetry.record(
                TelemetryEvent.ResultApplied(
                    if (selectionEnabled) com.torutesu.mobileaikeyboard.core.ApplyMethod.REPLACEMENT
                    else com.torutesu.mobileaikeyboard.core.ApplyMethod.INSERTION,
                    bucket(result.codePointCount(0, result.length)),
                ),
            )
        }
        syncSurface()
    }

    private fun undoResult() {
        val edit = appliedEdit ?: return
        if (adapter?.undo(edit) == true) {
            session = CommandSessionReducer.reduce(session, SessionEvent.Undone)
            appliedEdit = null
        } else {
            session = CommandSessionReducer.reduce(session, SessionEvent.UndoRejected("入力欄の内容が変更されたため、元の文章へ戻せませんでした"))
        }
        syncSurface()
    }

    private fun copyResult(result: String) {
        session = CommandSessionReducer.reduce(session, SessionEvent.EditResult(result))
        if (session.phase == SessionPhase.RESULT_REVIEW && session.error != null) {
            syncSurface()
            return
        }
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
        clipboard.setPrimaryClip(android.content.ClipData.newPlainText("Mobile AI Keyboard result", result))
        telemetry.record(TelemetryEvent.ResultApplied(com.torutesu.mobileaikeyboard.core.ApplyMethod.COPY, bucket(result.codePointCount(0, result.length))))
    }

    private fun cancel() {
        session = CommandSessionReducer.reduce(session, SessionEvent.Cancel)
        appliedEdit = null
        syncSurface()
    }

    private fun syncSurface() {
        surface?.render(session.asKeyboardState(lockReason))
    }

    private fun bucket(count: Int) = when {
        count <= 20 -> "0_20"
        count <= 100 -> "21_100"
        count <= 500 -> "101_500"
        else -> "501_plus"
    }
}
