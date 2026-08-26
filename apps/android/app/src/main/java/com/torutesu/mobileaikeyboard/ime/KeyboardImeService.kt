package com.torutesu.mobileaikeyboard.ime

import android.inputmethodservice.InputMethodService
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.inputmethod.EditorInfo
import com.torutesu.mobileaikeyboard.core.BoundedCapture
import com.torutesu.mobileaikeyboard.core.AccountBoundaryStore
import com.torutesu.mobileaikeyboard.core.ActiveAccountBoundary
import com.torutesu.mobileaikeyboard.core.CommandSession
import com.torutesu.mobileaikeyboard.core.CommandSessionReducer
import com.torutesu.mobileaikeyboard.core.ContentFreeTelemetry
import com.torutesu.mobileaikeyboard.core.ExecutableLocalSkills
import com.torutesu.mobileaikeyboard.core.InputSource
import com.torutesu.mobileaikeyboard.core.ImeActivationProbeStore
import com.torutesu.mobileaikeyboard.core.KeyboardSettingsStore
import com.torutesu.mobileaikeyboard.core.LocalPoliteRewriteService
import com.torutesu.mobileaikeyboard.core.NativeSkillExecutionDecision
import com.torutesu.mobileaikeyboard.core.NativeSkillFailureStore
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
import com.torutesu.mobileaikeyboard.core.withAccountBoundaryLock
import java.util.concurrent.Executors

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
    private lateinit var accountBoundaryStore: AccountBoundaryStore
    private lateinit var nativeSkillFailureStore: NativeSkillFailureStore
    private lateinit var imeActivationProbeStore: ImeActivationProbeStore
    private var currentEditorInfo: EditorInfo? = null
    private var shortcutSnapshot: ShortcutSnapshot = ShortcutSnapshot.empty()
    private var activeShortcut: ShortcutActivation? = null
    private var editorSessionId = 0L
    private val mainHandler = Handler(Looper.getMainLooper())
    private val shortcutRefreshExecutor = Executors.newSingleThreadExecutor()
    private var shortcutRefreshEpoch = 0L
    private var keyboardWindowVisible = false

    override fun onCreate() {
        super.onCreate()
        shortcutStore = ShortcutSnapshotStore(this)
        settingsStore = KeyboardSettingsStore(this)
        accountBoundaryStore = AccountBoundaryStore(this)
        nativeSkillFailureStore = NativeSkillFailureStore(this)
        imeActivationProbeStore = ImeActivationProbeStore(this)
        shortcutSnapshot = shortcutStore.read()
    }

    override fun onCreateInputView(): View {
        surface?.cancelPendingGestures()
        // A recreated IME view is a fresh editor capability boundary even when
        // an OEM omits a matching onStartInput callback. Never carry review,
        // Apply, or Undo authority into the replacement view.
        appliedEdit = null
        activeShortcut = null
        session = CommandSession()
        shortcutSnapshot = shortcutStore.read()
        surface = KeyboardSurface(this, KeyboardSurface.Callbacks(
            onCommand = { enterCommand() },
            onShortcut = { binding -> invokeShortcut(binding) },
            onText = { text ->
                val committed = currentAdapter()?.insertAtCursor(text) == true
                if (!committed) surface?.reportOrdinaryInputFailure()
                committed
            },
            onDelete = { if (currentAdapter()?.deleteBackward() != true) surface?.reportOrdinaryInputFailure() },
            onEnter = {
                val input = currentInputConnection
                if (input == null) {
                    surface?.reportOrdinaryInputFailure()
                } else {
                    val action = ReturnKeyModel.from(currentEditorInfo).editorAction
                    if (action == null || !input.performEditorAction(action)) {
                        val down = input.sendKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_ENTER))
                        val up = input.sendKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, android.view.KeyEvent.KEYCODE_ENTER))
                        if (!down || !up) surface?.reportOrdinaryInputFailure()
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
        keyboardWindowVisible = true
        shortcutRefreshEpoch += 1L
        scheduleShortcutRefresh(shortcutRefreshEpoch)
    }

    override fun onWindowHidden() {
        keyboardWindowVisible = false
        shortcutRefreshEpoch += 1L
        mainHandler.removeCallbacksAndMessages(null)
        clearEphemeralEditorState()
        super.onWindowHidden()
    }

    override fun onStartInput(attribute: EditorInfo?, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        // Content-free handshake consumed by host onboarding. It proves this
        // exact IME entered an editor without persisting any editor metadata.
        imeActivationProbeStore.publish()
        editorSessionId += 1L
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
        editorSessionId += 1L
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

    override fun onDestroy() {
        keyboardWindowVisible = false
        shortcutRefreshEpoch += 1L
        mainHandler.removeCallbacksAndMessages(null)
        shortcutRefreshExecutor.shutdownNow()
        editorSessionId += 1L
        clearEphemeralEditorState()
        surface = null
        super.onDestroy()
    }

    private fun clearEphemeralEditorState() {
        surface?.cancelPendingGestures()
        appliedEdit = null
        activeShortcut = null
        session = CommandSession()
        surface?.resetTypingState()
        syncSurface()
    }

    /**
     * SharedPreferences notifications are not a cross-process contract. Poll a
     * bounded, content-free snapshot off the IME main thread while visible so
     * host publishes, missed notifications, and warm nil -> active transitions
     * converge within the documented two-second window.
     */
    private fun scheduleShortcutRefresh(epoch: Long) {
        if (!keyboardWindowVisible || epoch != shortcutRefreshEpoch) return
        mainHandler.postDelayed({
            if (!keyboardWindowVisible || epoch != shortcutRefreshEpoch || shortcutRefreshExecutor.isShutdown) return@postDelayed
            shortcutRefreshExecutor.execute {
                val refreshed = shortcutStore.read()
                mainHandler.post {
                    if (!keyboardWindowVisible || epoch != shortcutRefreshEpoch) return@post
                    if (refreshed != shortcutSnapshot) {
                        surface?.cancelPendingGestures()
                        activeShortcut = null
                        appliedEdit = null
                        session = CommandSession()
                        shortcutSnapshot = refreshed
                        syncSurface()
                    }
                    scheduleShortcutRefresh(epoch)
                }
            }
        }, SHORTCUT_REFRESH_INTERVAL_MILLIS)
    }

    private fun enterCommand() {
        if (lockReason != null) return
        session = CommandSessionReducer.reduce(session, SessionEvent.BeginCommand)
        syncSurface()
    }

    /** A physical key is an explicit action surface; it never runs on key-down. */
    private fun invokeShortcut(binding: TriggerKeyBinding) {
        if (lockReason != null || !binding.enabled || !ExecutableLocalSkills.isExecutable(binding)) return
        val boundary = accountBoundaryStore.read() ?: return
        if (nativeSkillFailureStore.decision(binding, boundary) != NativeSkillExecutionDecision.ALLOWED) {
            // The key remains an ordinary typing key; only its Skill action and
            // decoration are suppressed by the version-bound circuit breaker.
            syncSurface()
            return
        }
        val current = shortcutStore.readForBoundary(boundary) ?: return
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
            ownerSubject = boundary.ownerSubject,
            sessionEpoch = boundary.sessionEpoch,
            editorSessionId = editorSessionId,
            requestedAtElapsedMillis = android.os.SystemClock.elapsedRealtime(),
            expiresAtElapsedMillis = android.os.SystemClock.elapsedRealtime() + SHORTCUT_ACTIVATION_TTL_MILLIS,
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
        val rewritten = safelyRewriteForActiveSkill(target) ?: run {
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
        if (session.phase != SessionPhase.RESULT_REVIEW && session.phase != SessionPhase.ERROR) return
        val target = session.target ?: return
        session = CommandSessionReducer.reduce(session, SessionEvent.Regenerate)
        if (session.phase != SessionPhase.TRANSFORMING) return
        syncSurface()
        val rewritten = safelyRewriteForActiveSkill(target) ?: run {
            session = CommandSessionReducer.reduce(session, SessionEvent.Failed("このSkill versionは端末内で利用できません。結果をコピーするか、キャンセルしてください"))
            syncSurface()
            return
        }
        session = CommandSessionReducer.reduce(session, SessionEvent.Generated(rewritten.rewritten, rewritten.preservedEntities.map { it.value }))
        syncSurface()
    }

    private fun applyResult(editedResult: String) = withAccountBoundaryLock {
        applyResultUnderStableBoundary(editedResult)
    }

    private fun applyResultUnderStableBoundary(editedResult: String) {
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
            // Without an explicitly captured non-empty selection Android does
            // not expose a trustworthy, content-free cursor revision token.
            // Auto-insertion could silently replace an undeclared selection,
            // so Copy remains the safe recovery path.
            null
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
        if (::accountBoundaryStore.isInitialized) {
            val activation = activeShortcut
            val boundary = accountBoundaryStore.read()
            if (activation != null && (boundary == null || boundary.ownerSubject != activation.ownerSubject || boundary.sessionEpoch != activation.sessionEpoch)) {
                activeShortcut = null
                appliedEdit = null
                session = CommandSession()
            }
        }
        if (::settingsStore.isInitialized) {
            surface?.render(
                session.asKeyboardState(lockReason),
                shortcutSnapshotForRendering(),
                settingsStore.read(),
                ReturnKeyModel.from(currentEditorInfo),
            )
        } else {
            surface?.render(session.asKeyboardState(lockReason), shortcutSnapshotForRendering())
        }
    }

    private fun shortcutSnapshotForRendering(): ShortcutSnapshot {
        if (!::nativeSkillFailureStore.isInitialized || !::accountBoundaryStore.isInitialized) return ShortcutSnapshot.empty()
        val boundary = accountBoundaryStore.read() ?: return ShortcutSnapshot.empty()
        val visible = shortcutSnapshot.bindings.filter {
            nativeSkillFailureStore.decision(it, boundary) == NativeSkillExecutionDecision.ALLOWED
        }
        return if (visible.size == shortcutSnapshot.bindings.size) shortcutSnapshot else ShortcutSnapshot(
            schemaVersion = shortcutSnapshot.schemaVersion,
            generation = shortcutSnapshot.generation,
            layoutId = shortcutSnapshot.layoutId,
            bindings = visible,
        )
    }

    private fun shortcutStillCurrent(): Boolean {
        val activation = activeShortcut ?: return true
        val now = android.os.SystemClock.elapsedRealtime()
        if (activation.editorSessionId != editorSessionId ||
            activation.requestedAtElapsedMillis > now ||
            activation.expiresAtElapsedMillis < now
        ) return false
        val boundary = ActiveAccountBoundary(activation.ownerSubject, activation.sessionEpoch)
        val current = shortcutStore.readForBoundary(boundary) ?: return false
        val binding = current.bindings.firstOrNull {
            it.bindingId == activation.bindingId && it.skillId == activation.skillId &&
                it.skillVersion == activation.skillVersion && it.skillDigest == activation.skillDigest && it.enabled
        } ?: return false
        return current.generation == activation.snapshotGeneration &&
            current.layoutId == activation.layoutId &&
            nativeSkillFailureStore.decision(binding, boundary) == NativeSkillExecutionDecision.ALLOWED
    }

    private fun bindingForActiveSkill(): Pair<ActiveAccountBoundary, TriggerKeyBinding>? {
        val activation = activeShortcut ?: return null
        val boundary = ActiveAccountBoundary(activation.ownerSubject, activation.sessionEpoch)
        val binding = shortcutStore.readForBoundary(boundary)?.bindings?.firstOrNull {
            it.bindingId == activation.bindingId && it.skillId == activation.skillId &&
                it.skillVersion == activation.skillVersion && it.skillDigest == activation.skillDigest && it.enabled
        } ?: return null
        return boundary to binding
    }

    private fun safelyRewriteForActiveSkill(target: String): com.torutesu.mobileaikeyboard.core.RewriteResult? = withAccountBoundaryLock {
        if (activeShortcut == null) return@withAccountBoundaryLock try { rewriteService.rewrite(target) } catch (_: RuntimeException) { null }
        val (boundary, binding) = bindingForActiveSkill() ?: return@withAccountBoundaryLock null
        if (nativeSkillFailureStore.decision(binding, boundary) != NativeSkillExecutionDecision.ALLOWED) return@withAccountBoundaryLock null
        try {
            // Fail closed when the catalog or exact immutable identity is stale.
            // Falling back to another transform would execute behavior the user
            // did not assign to this physical key.
            val result = com.torutesu.mobileaikeyboard.core.ExecutableLocalSkills.executeResult(binding, target)
            if (result == null) {
                nativeSkillFailureStore.recordFailure(binding, boundary)
                syncSurface()
                null
            } else {
                nativeSkillFailureStore.recordSuccess(binding, boundary)
                result
            }
        } catch (_: RuntimeException) {
            nativeSkillFailureStore.recordFailure(binding, boundary)
            syncSurface()
            null
        }
    }

    private fun currentAdapter(): InputConnectionAdapter? {
        adapter?.let { return it }
        return currentInputConnection?.let(::InputConnectionAdapter)?.also { adapter = it }
    }

    private fun bucket(count: Int) = when {
        count <= 20 -> "0_20"
        count <= 100 -> "21_100"
        count <= 500 -> "101_500"
        else -> "501_plus"
    }

    companion object {
        private const val SHORTCUT_ACTIVATION_TTL_MILLIS = 60_000L
        private const val SHORTCUT_REFRESH_INTERVAL_MILLIS = 2_000L
    }
}
