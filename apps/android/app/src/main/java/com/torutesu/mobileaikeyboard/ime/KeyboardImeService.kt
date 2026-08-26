package com.torutesu.mobileaikeyboard.ime

import android.inputmethodservice.InputMethodService
import android.view.View
import android.view.inputmethod.EditorInfo
import com.torutesu.mobileaikeyboard.core.ContentFreeTelemetry
import com.torutesu.mobileaikeyboard.core.InputSource
import com.torutesu.mobileaikeyboard.core.KeyboardAction
import com.torutesu.mobileaikeyboard.core.KeyboardMode
import com.torutesu.mobileaikeyboard.core.KeyboardReducer
import com.torutesu.mobileaikeyboard.core.KeyboardState
import com.torutesu.mobileaikeyboard.core.LocalPoliteRewriteService
import com.torutesu.mobileaikeyboard.core.NoOpTelemetry
import com.torutesu.mobileaikeyboard.core.SensitiveFieldClassifier
import com.torutesu.mobileaikeyboard.core.TelemetryEvent

class KeyboardImeService : InputMethodService() {
    private var state = KeyboardState()
    private var surface: KeyboardSurface? = null
    private var adapter: InputConnectionAdapter? = null
    private var captured: CapturedContext? = null
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
            onRewrite = { command, useSurrounding -> rewrite(command, useSurrounding) },
            onApply = { applyResult() },
            onCopy = { result -> copyResult(result) },
            onCancel = { cancel() },
        ))
        surface?.render(state)
        return surface!!
    }

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        adapter = currentInputConnection?.let(::InputConnectionAdapter)
        // EditorInfo may change without a matching onFinishInput. Drop every
        // prior field's capture/result before inspecting the new field so text
        // can never cross an app or editor boundary.
        captured = null
        val classification = SensitiveFieldClassifier.classify(attribute)
        state = if (!classification.aiCaptureAllowed) {
            KeyboardReducer.reduce(KeyboardState(), KeyboardAction.Lock(classification.explanation.orEmpty()))
        } else {
            KeyboardState()
        }
        surface?.render(state)
    }

    override fun onFinishInput() {
        adapter = null
        captured = null
        state = KeyboardState()
        surface?.render(state)
        super.onFinishInput()
    }

    private fun enterCommand() {
        if (state.mode == KeyboardMode.LOCKED) return
        state = KeyboardReducer.reduce(state, KeyboardAction.EnterCommand)
        telemetry.record(TelemetryEvent.CommandStarted("local.polite-rewrite", "R1", setOf(InputSource.COMMAND)))
        surface?.render(state)
    }

    private fun rewrite(command: String, useSurrounding: Boolean) {
        if (state.mode == KeyboardMode.LOCKED) return
        val input = adapter ?: return
        captured = input.captureContext(includeSurrounding = useSurrounding)
        val selected = captured?.selected.orEmpty()
        val target = selected.ifBlank { command.trim() }
        if (target.isBlank()) {
            state = KeyboardReducer.reduce(state, KeyboardAction.Fail("変換する文章を入力するか、文章を選択してください"))
            surface?.render(state)
            return
        }
        state = KeyboardReducer.reduce(state, KeyboardAction.OpenCaptureReview)
        surface?.render(state)
        // The fixture is intentionally synchronous and local. W2 can replace this implementation
        // behind the same contract after disclosure and transport are implemented.
        val result = rewriteService.rewrite(target)
        state = KeyboardReducer.reduce(state, KeyboardAction.ShowResult(result.rewritten))
        surface?.render(state)
    }

    private fun applyResult() {
        val result = state.resultText ?: return
        val input = adapter ?: return
        val snapshot = captured
        val applied = if (snapshot?.selected?.isNotBlank() == true) {
            input.replaceSelection(snapshot.fieldFingerprint, result)
        } else {
            input.insertAtCursor(result)
            true
        }
        if (!applied) {
            state = KeyboardReducer.reduce(state, KeyboardAction.Fail("入力欄の内容が変更されたため、自動置換を止めました。結果をコピーしてください"))
        } else {
            telemetry.record(TelemetryEvent.ResultApplied(com.torutesu.mobileaikeyboard.core.ApplyMethod.REPLACEMENT, bucket(result.length)))
            state = KeyboardReducer.reduce(state, KeyboardAction.ApplyResult)
        }
        surface?.render(state)
    }

    private fun copyResult(result: String) {
        val clipboard = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
        clipboard.setPrimaryClip(android.content.ClipData.newPlainText("Mobile AI Keyboard result", result))
        telemetry.record(TelemetryEvent.ResultApplied(com.torutesu.mobileaikeyboard.core.ApplyMethod.COPY, bucket(result.length)))
    }

    private fun cancel() {
        state = KeyboardReducer.reduce(state, KeyboardAction.Cancel)
        captured = null
        surface?.render(state)
    }

    private fun bucket(count: Int) = when {
        count <= 20 -> "0_20"
        count <= 100 -> "21_100"
        count <= 500 -> "101_500"
        else -> "501_plus"
    }
}
