package com.torutesu.mobileaikeyboard.core

/** Pure W2 session model. It has no Android, network, or clipboard dependency. */
enum class SessionPhase { IDLE, COMMAND, CAPTURE_REVIEW, TRANSFORMING, RESULT_REVIEW, RECEIPT, ERROR }

data class BoundedCapture(
    val command: String,
    val selected: String,
    val before: String,
    val after: String,
    val selectionAvailable: Boolean,
    val surroundingAvailable: Boolean,
    val fieldFingerprint: String,
    val selectionOverLimit: Boolean = false,
) {
    fun target(sources: Set<InputSource>): String {
        val selection = if (InputSource.SELECTION in sources) selected else ""
        val context = if (InputSource.SURROUNDING in sources) before + selection + after else ""
        return when {
            InputSource.SELECTION in sources && !selectionAvailable && command.isNotBlank() -> command.trim()
            InputSource.SURROUNDING in sources && !surroundingAvailable && command.isNotBlank() -> command.trim()
            selection.isNotBlank() -> selection
            context.isNotBlank() -> context
            command.isNotBlank() -> command.trim()
            else -> ""
        }
    }
}

data class CapturePreview(
    val exactText: String,
    val redactedText: String,
    val characterCount: Int,
    val sources: Set<InputSource>,
    val destination: String = "端末内のみ",
    val externalTransmission: Boolean = false,
    val notice: String? = null,
    val blockedReason: String? = null,
) {
    val acknowledgementRequired: Boolean get() = blockedReason == null
}

data class UndoTicket(
    val originalText: String,
    val appliedText: String,
    val expectedAfterFingerprint: String,
    val wasReplacement: Boolean,
)

data class CommandSession(
    val phase: SessionPhase = SessionPhase.IDLE,
    val command: String = "",
    val sources: Set<InputSource> = setOf(InputSource.COMMAND),
    val capture: BoundedCapture? = null,
    val preview: CapturePreview? = null,
    val target: String? = null,
    val resultText: String? = null,
    val preservedEntities: List<String> = emptyList(),
    val undoTicket: UndoTicket? = null,
    val error: String? = null,
) {
    val canAcknowledge: Boolean get() = phase == SessionPhase.CAPTURE_REVIEW && preview?.acknowledgementRequired == true
}

sealed interface SessionEvent {
    data object BeginCommand : SessionEvent
    data class UpdateCommand(val value: String) : SessionEvent
    data class ToggleSource(val source: InputSource, val enabled: Boolean) : SessionEvent
    data class CapturePrepared(val capture: BoundedCapture) : SessionEvent
    data object AcknowledgeCapture : SessionEvent
    data class Generated(val rewritten: String, val preservedEntities: List<String> = emptyList()) : SessionEvent
    data class EditResult(val value: String) : SessionEvent
    data object Regenerate : SessionEvent
    data class Applied(val ticket: UndoTicket) : SessionEvent
    data class ApplyRejected(val reason: String) : SessionEvent
    data object Undone : SessionEvent
    data class UndoRejected(val reason: String) : SessionEvent
    data object Cancel : SessionEvent
    data class Failed(val reason: String) : SessionEvent
}

object CommandSessionReducer {
    fun reduce(state: CommandSession, event: SessionEvent): CommandSession = when (event) {
        SessionEvent.BeginCommand -> if (state.phase == SessionPhase.IDLE || state.phase == SessionPhase.RECEIPT) {
            CommandSession(phase = SessionPhase.COMMAND)
        } else state
        is SessionEvent.UpdateCommand -> if (state.phase == SessionPhase.COMMAND) state.copy(command = event.value) else state
        is SessionEvent.ToggleSource -> if (state.phase == SessionPhase.COMMAND && event.source != InputSource.COMMAND) {
            val next = state.sources.toMutableSet().apply {
                if (event.enabled) add(event.source) else remove(event.source)
            }
            state.copy(sources = next)
        } else state
        is SessionEvent.CapturePrepared -> if (state.phase == SessionPhase.COMMAND) {
            val capture = event.capture.copy(command = state.command)
            val target = capture.target(state.sources)
            val unavailable = buildList {
                if (InputSource.SELECTION in state.sources && !capture.selectionAvailable) add("選択されていません")
                if (InputSource.SURROUNDING in state.sources && !capture.surroundingAvailable) add("前後の文章を取得できません")
            }
            val fallback = if (unavailable.isNotEmpty() && capture.command.isNotBlank()) {
                unavailable.joinToString("。") + "。入力したCommandだけを使用します"
            } else null
            val redacted = LocalRedactor.redact(target)
            val blocked = when {
                target.isBlank() -> "変換する文章を入力するか、取得可能な文章を選択してください"
                redacted != target -> "機密らしき文字列があるため、この実行を停止しました"
                capture.command.codePointCount(0, capture.command.length) > CaptureLimits.commandCodePoints ->
                    "Commandは${CaptureLimits.commandCodePoints}文字以内にしてください"
                capture.selectionOverLimit ->
                    "選択範囲が${CaptureLimits.selectionCodePoints}文字を超えています。範囲を短くしてください"
                else -> null
            }
            state.copy(
                phase = SessionPhase.CAPTURE_REVIEW,
                command = capture.command,
                capture = capture,
                target = target,
                preview = CapturePreview(
                    exactText = target,
                    redactedText = redacted,
                    characterCount = target.codePointCount(0, target.length),
                    sources = state.sources,
                    notice = fallback,
                    blockedReason = blocked,
                ),
                error = null,
            )
        } else state
        SessionEvent.AcknowledgeCapture -> if (state.canAcknowledge) state.copy(phase = SessionPhase.TRANSFORMING) else state
        is SessionEvent.Generated -> if (state.phase == SessionPhase.TRANSFORMING) {
            if (event.rewritten.codePointCount(0, event.rewritten.length) > CaptureLimits.resultCodePoints) {
                state.copy(phase = SessionPhase.ERROR, error = "結果が${CaptureLimits.resultCodePoints}文字を超えたため停止しました")
            } else state.copy(phase = SessionPhase.RESULT_REVIEW, resultText = event.rewritten, preservedEntities = event.preservedEntities, error = null)
        } else state
        is SessionEvent.EditResult -> if (state.phase == SessionPhase.RESULT_REVIEW) {
            if (event.value.codePointCount(0, event.value.length) > CaptureLimits.resultCodePoints) {
                state.copy(error = "結果は${CaptureLimits.resultCodePoints}文字以内にしてください")
            } else state.copy(resultText = event.value, error = null)
        } else state
        SessionEvent.Regenerate -> if (state.phase == SessionPhase.RESULT_REVIEW) state.copy(phase = SessionPhase.TRANSFORMING) else state
        is SessionEvent.Applied -> if (state.phase == SessionPhase.RESULT_REVIEW) {
            state.copy(phase = SessionPhase.RECEIPT, undoTicket = event.ticket)
        } else state
        is SessionEvent.ApplyRejected -> if (state.phase == SessionPhase.RESULT_REVIEW) {
            state.copy(phase = SessionPhase.ERROR, error = event.reason)
        } else state
        SessionEvent.Undone -> if (state.phase == SessionPhase.RECEIPT) {
            state.copy(phase = SessionPhase.IDLE, undoTicket = null, resultText = null)
        } else state
        is SessionEvent.UndoRejected -> if (state.phase == SessionPhase.RECEIPT) state.copy(phase = SessionPhase.ERROR, error = event.reason) else state
        SessionEvent.Cancel -> CommandSession()
        is SessionEvent.Failed -> state.copy(phase = SessionPhase.ERROR, error = event.reason)
    }
}

object LocalRedactor {
    private val secretPatterns = listOf(
        Regex("(?i)\\b(?:bearer|password|passwd|token|api[_ -]?key)\\s*[:=]\\s*\\S+"),
        Regex("\\b(?:sk|ghp|github_pat|AIza)[_-][A-Za-z0-9_-]{8,}\\b"),
        Regex("-----BEGIN [A-Z ]+ PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]+ PRIVATE KEY-----"),
    )

    fun redact(text: String): String {
        var result = text
        secretPatterns.forEach { regex -> result = regex.replace(result) { "[redacted]" } }
        return result
    }
}

object CaptureLimits {
    const val commandCodePoints = 500
    const val selectionCodePoints = 4_000
    const val surroundingBeforeCodePoints = 1_000
    const val surroundingAfterCodePoints = 500
    const val resultCodePoints = 10_000
}

fun CommandSession.asKeyboardState(lockedReason: String? = null): KeyboardState {
    if (lockedReason != null) return KeyboardState(mode = KeyboardMode.LOCKED, sensitiveReason = lockedReason)
    val mode = when (phase) {
        SessionPhase.IDLE -> KeyboardMode.TYPING
        SessionPhase.COMMAND -> KeyboardMode.COMMAND
        SessionPhase.CAPTURE_REVIEW -> KeyboardMode.CAPTURE_REVIEW
        SessionPhase.TRANSFORMING -> KeyboardMode.PLANNING
        SessionPhase.RESULT_REVIEW -> KeyboardMode.RESULT_REVIEW
        SessionPhase.RECEIPT -> KeyboardMode.RECEIPT
        SessionPhase.ERROR -> KeyboardMode.ERROR
    }
    return KeyboardState(
        mode = mode,
        command = command,
        selectedSources = sources,
        capturedText = preview?.exactText,
        fieldFingerprint = capture?.fieldFingerprint,
        resultText = resultText,
        errorMessage = error,
        capturePreview = preview,
        undoAvailable = undoTicket != null,
    )
}
