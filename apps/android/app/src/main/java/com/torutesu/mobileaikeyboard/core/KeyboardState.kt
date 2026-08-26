package com.torutesu.mobileaikeyboard.core

/** The native IME state machine. Network and account state are deliberately absent. */
enum class KeyboardMode {
    TYPING,
    COMMAND,
    CAPTURE_REVIEW,
    PLANNING,
    RESULT_REVIEW,
    ACTION_REVIEW,
    EXECUTING,
    RECEIPT,
    ERROR,
    LOCKED,
}

enum class InputSource { COMMAND, SELECTION, SURROUNDING, CLIPBOARD, LOCALE }

data class KeyboardState(
    val mode: KeyboardMode = KeyboardMode.TYPING,
    val command: String = "",
    val selectedSources: Set<InputSource> = setOf(InputSource.COMMAND),
    val capturedText: String? = null,
    val fieldFingerprint: String? = null,
    val resultText: String? = null,
    val errorMessage: String? = null,
    val sensitiveReason: String? = null,
)

sealed interface KeyboardAction {
    data object EnterCommand : KeyboardAction
    data object OpenCaptureReview : KeyboardAction
    data object StartPlanning : KeyboardAction
    data class ShowResult(val text: String) : KeyboardAction
    data object ApplyResult : KeyboardAction
    data object Cancel : KeyboardAction
    data class Lock(val reason: String) : KeyboardAction
    data object Unlock : KeyboardAction
    data class Fail(val message: String) : KeyboardAction
    data object CompleteReceipt : KeyboardAction
}

object KeyboardReducer {
    fun reduce(state: KeyboardState, action: KeyboardAction): KeyboardState = when (action) {
        KeyboardAction.EnterCommand -> if (state.mode == KeyboardMode.LOCKED) state else state.copy(
            mode = KeyboardMode.COMMAND,
            errorMessage = null,
            sensitiveReason = null,
        )
        KeyboardAction.OpenCaptureReview -> if (state.mode == KeyboardMode.COMMAND) {
            state.copy(mode = KeyboardMode.CAPTURE_REVIEW)
        } else state
        KeyboardAction.StartPlanning -> if (state.mode == KeyboardMode.CAPTURE_REVIEW) {
            state.copy(mode = KeyboardMode.PLANNING)
        } else state
        is KeyboardAction.ShowResult -> state.copy(
            mode = KeyboardMode.RESULT_REVIEW,
            resultText = action.text,
            errorMessage = null,
        )
        KeyboardAction.ApplyResult -> if (state.mode == KeyboardMode.RESULT_REVIEW) {
            state.copy(mode = KeyboardMode.TYPING, resultText = null, capturedText = null)
        } else state
        KeyboardAction.Cancel -> state.copy(
            mode = KeyboardMode.TYPING,
            capturedText = null,
            resultText = null,
            errorMessage = null,
        )
        is KeyboardAction.Lock -> state.copy(
            mode = KeyboardMode.LOCKED,
            sensitiveReason = action.reason,
            capturedText = null,
            resultText = null,
        )
        KeyboardAction.Unlock -> if (state.mode == KeyboardMode.LOCKED) {
            state.copy(mode = KeyboardMode.TYPING, sensitiveReason = null)
        } else state
        is KeyboardAction.Fail -> state.copy(mode = KeyboardMode.ERROR, errorMessage = action.message)
        KeyboardAction.CompleteReceipt -> state.copy(mode = KeyboardMode.RECEIPT)
    }
}
