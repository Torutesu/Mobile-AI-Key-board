package com.torutesu.mobileaikeyboard.ime

import android.inputmethodservice.InputMethodService
import android.view.View
import android.view.inputmethod.EditorInfo
import com.torutesu.mobileaikeyboard.core.BoundedCapture
import com.torutesu.mobileaikeyboard.core.CommandSession
import com.torutesu.mobileaikeyboard.core.CommandSessionReducer
import com.torutesu.mobileaikeyboard.core.ContentFreeTelemetry
import com.torutesu.mobileaikeyboard.core.ExecutableLocalSkills
import com.torutesu.mobileaikeyboard.core.InputSource
import com.torutesu.mobileaikeyboard.core.KeyboardSettingsStore
import com.torutesu.mobileaikeyboard.core.LocalPoliteRewriteService
import com.torutesu.mobileaikeyboard.core.NoOpTelemetry
import com.torutesu.mobileaikeyboard.core.SensitiveFieldClassifier
import com.torutesu.mobileaikeyboard.core.SessionEvent
import com.torutesu.mobileaikeyboard.core.SessionPhase
import com.torutesu.mobileaikeyboard.core.ShortcutActivation
import com.torutesu.mobileaikeyboard.core.ShortcutSnapshot
import com.torutesu.mobileaikeyboard.core.ShortcutSnapshotStore
import com.torutesu.mobileaikeyboard.core.TriggerKeyBinding
import com.torutesu.mobileaikeyboard.core.ReturnKeyModel
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
    private lateinit var shortcutStore: ShortcutSnapshotStore
    private lateinit var settingsStore: KeyboardSettingsStore
    private var currentEditorInfo: EditorInfo? = null
    private var shortcutSnapshot: ShortcutSnapshot = ShortcutSnapshot.empty()
    private var activeShortcut: ShortcutActivation? = null

    override fun onCreate() {
        super.onCreate()
        shortcutStore = ShortcutSnapshotStore(this)
        settingsStore = KeyboardSettingsStore(this)
        shortcutSnapshot = shortcutStore.read()
    }

    override fun onCreateInputView(): View {
        shortcutSnapshot = shortcutStore.read()
        surface = KeyboardSurface(this, KeyboardSurface.Callbacks(
            onCommand = { enterCommand() },
            onShortcut = { binding -> invokeShortcut(binding) },
            onText = { text -> adapter?.insertAtCursor(text) },
            onDelete = { adapter?.deleteBackward() },
            onEnter = {
                currentInputConnection?.let { input ->
                    val action = ReturnKeyModel.from(currentEditorInfo).editorAction
                    if (action == null || !input.performEditorAction(action)) {
                        input.sendKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_ENTER))
                        input.sendKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, android.view.KeyEvent.KEYCODE_ENTER))
                    }
                }
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

    override fun onWindowShown() {
        super.onWindowShown()
        // Re-read on every foreground/open boundary. This is the lost-notification
        // convergence path and keeps the IME independent of account/network state.
        shortcutSnapshot = shortcutStore.read()
        settingsStore.read()
        syncSurface()
    }

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        adapter = currentInputConnection?.let(::InputConnectionAdapter)
        currentEditorInfo = attribute
        shortcutSnapshot = shortcutStore.read()
        // EditorInfo may change without a matching onFinishInput. Drop every
        // prior field's capture/result/undo before inspecting the new boundary.
        session = CommandSession()
        appliedEdit = null
        activeShortcut = null
        surface?.resetTypingState()
        val classification = SensitiveFieldClassifier.classify(attribute)
        lockReason = classification.explanation.takeUnless { classification.aiCaptureAllowed }
        syncSurface()
    }

    override fun onFinishInput() {
        adapter = null
        appliedEdit = null
        activeShortcut = null
        currentEditorInfo = null
        surface?.resetTypingState()
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

    /** A physical key is an explicit action surface; it never runs on key-down. */
    private fun invokeShortcut(binding: TriggerKeyBinding) {
        if (lockReason != null || !binding.enabled || !ExecutableLocalSkills.isExecutable(binding)) return
        val current = shortcutStore.read()
        val exact = current.bindings.firstOrNull {
            it.bindingId == binding.bindingId && it.keyCode == binding.keyCode && it.skillDigest == binding.skillDigest && it.enabled
        } ?: return
        activeShortcut = ShortcutActivation(
            bindingId = exact.bindingId,
            skillId = exact.skillId,
            skillVersion = exact.skillVersion,
            skillDigest = exact.skillDigest,
            snapshotGeneration = current.generation,
            layoutId = current.layoutId,
        )
        session = CommandSessionReducer.reduce(session, SessionEvent.BeginCommand)
        // The skill label is metadata only. Actual editor text is captured below
        // and remains ephemeral until the existing Capture Review acknowledges it.
        // Bundled v1 Skill Keys declare selection-only input. Do not capture
        // surrounding editor text merely because the IME can access it.
        // A Skill label is metadata, never fallback editor content. Bundled v1
        // shortcuts are selection-only; an empty selection must therefore
        // produce a blocked Capture Review instead of rewriting the Skill name.
        capture(command = "", useSelection = true, useSurrounding = false)
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
        telemetry.record(TelemetryEvent.CommandStarted(activeShortcut?.skillId ?: "local.polite-rewrite", "R1", session.sources))
        syncSurface()
    }

    private fun acknowledgeCapture() {
        if (!session.canAcknowledge) return
        if (!shortcutStillCurrent()) {
            session = CommandSessionReducer.reduce(session, SessionEvent.Failed("Skill Keyの設定が変わったため、確認をやり直してください"))
            activeShortcut = null
            syncSurface()
            return
        }
        session = CommandSessionReducer.reduce(session, SessionEvent.AcknowledgeCapture)
        syncSurface()
        val target = session.target ?: return
        // Deliberately local and synchronous: acknowledgement is required before
        // this fixture runs, and there is no transport or provider dependency.
        val rewritten = rewriteForActiveSkill(target) ?: run {
            session = CommandSessionReducer.reduce(session, SessionEvent.Failed("このSkill versionは端末内で利用できません"))
            activeShortcut = null
            syncSurface()
            return
        }
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
        val rewritten = rewriteForActiveSkill(target) ?: return
        session = CommandSessionReducer.reduce(session, SessionEvent.Generated(rewritten.rewritten, rewritten.preservedEntities.map { it.value }))
        syncSurface()
    }

    private fun applyResult(editedResult: String) {
        if (activeShortcut != null && !shortcutStillCurrent()) {
            session = CommandSessionReducer.reduce(session, SessionEvent.ApplyRejected("Skill Keyの設定が変わったため適用を停止しました"))
            activeShortcut = null
            syncSurface()
            return
        }
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
        activeShortcut = null
        syncSurface()
    }

    private fun syncSurface() {
        shortcutSnapshot = if (::shortcutStore.isInitialized) shortcutStore.read() else shortcutSnapshot
        if (::settingsStore.isInitialized) {
            surface?.render(
                session.asKeyboardState(lockReason),
                shortcutSnapshot,
                settingsStore.read(),
                ReturnKeyModel.from(currentEditorInfo),
            )
        } else {
            surface?.render(session.asKeyboardState(lockReason), shortcutSnapshot)
        }
    }

    private fun shortcutStillCurrent(): Boolean {
        val activation = activeShortcut ?: return true
        val current = shortcutStore.read()
        return current.generation == activation.snapshotGeneration &&
            current.layoutId == activation.layoutId &&
            current.bindings.any {
                it.bindingId == activation.bindingId && it.skillId == activation.skillId &&
                    it.skillVersion == activation.skillVersion && it.skillDigest == activation.skillDigest && it.enabled
            }
    }

    private fun rewriteForActiveSkill(target: String): com.torutesu.mobileaikeyboard.core.RewriteResult? {
        val activation = activeShortcut ?: return rewriteService.rewrite(target)
        val binding = shortcutStore.read().bindings.firstOrNull {
            it.bindingId == activation.bindingId && it.skillId == activation.skillId &&
                it.skillVersion == activation.skillVersion && it.skillDigest == activation.skillDigest && it.enabled
        } ?: return null
        // Fail closed when the catalog or exact immutable identity is stale.
        // Falling back to another transform would execute behavior the user did
        // not assign to this physical key.
        return com.torutesu.mobileaikeyboard.core.ExecutableLocalSkills.executeResult(binding, target)
    }

    private fun bucket(count: Int) = when {
        count <= 20 -> "0_20"
        count <= 100 -> "21_100"
        count <= 500 -> "101_500"
        else -> "501_plus"
    }
}
