package com.torutesu.mobileaikeyboard.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.Typeface
import android.media.AudioManager
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.torutesu.mobileaikeyboard.core.KeyboardMode
import com.torutesu.mobileaikeyboard.core.KeyboardState
import com.torutesu.mobileaikeyboard.core.ImeConsumableConfig
import com.torutesu.mobileaikeyboard.core.KeyboardLayer
import com.torutesu.mobileaikeyboard.core.KeySoundMode
import com.torutesu.mobileaikeyboard.core.ReturnKeySpec
import com.torutesu.mobileaikeyboard.core.ShortcutSnapshot
import com.torutesu.mobileaikeyboard.core.ShortcutKeyCode
import com.torutesu.mobileaikeyboard.core.TriggerKeyBinding
import com.torutesu.mobileaikeyboard.core.ShiftState
import com.torutesu.mobileaikeyboard.core.TypingModeReducer
import com.torutesu.mobileaikeyboard.core.TypingModeState

/** Small dependency-free keyboard surface; all touch targets are at least 48dp. */
@SuppressLint("ViewConstructor") // Instantiated only by KeyboardImeService with mandatory callbacks; never inflated from XML.
class KeyboardSurface(context: Context, private val callbacks: Callbacks) : ScrollView(context) {
    class Callbacks(
        val onCommand: () -> Unit,
        val onShortcut: (TriggerKeyBinding) -> Unit,
        val onText: (String) -> Unit,
        val onDelete: () -> Unit,
        val onEnter: () -> Unit,
        val onSwitchKeyboard: () -> Unit,
        val onCapture: (String, Boolean, Boolean) -> Unit,
        val onAcknowledge: () -> Unit,
        val onEditResult: (String) -> Unit,
        val onRegenerate: () -> Unit,
        val onApply: (String) -> Unit,
        val onCopy: (String) -> Unit,
        val onUndo: () -> Unit,
        val onCancel: () -> Unit,
    )

    private val density = resources.displayMetrics.density
    private var typingMode = TypingModeState()
    private var currentConfig = ImeConsumableConfig(
        theme = com.torutesu.mobileaikeyboard.core.KeyboardTheme.SYSTEM,
        haptics = com.torutesu.mobileaikeyboard.core.HapticMode.KEY_TAP,
        keySize = com.torutesu.mobileaikeyboard.core.KeySize.STANDARD,
        oneHanded = com.torutesu.mobileaikeyboard.core.OneHandedMode.OFF,
        workflowPack = com.torutesu.mobileaikeyboard.core.JapaneseWorkflowPack.POLITE,
    )
    private var currentReturnKey = ReturnKeySpec("↵")
    private var currentKeyboardState = KeyboardState()
    private var currentShortcutSnapshot = ShortcutSnapshot.empty()
    private val pendingGestureCancels = mutableSetOf<() -> Unit>()
    private var gestureEpoch = 0L
    private val root = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(6), dp(5), dp(6), dp(5))
        contentDescription = "Mobile AI Keyboard"
    }

    init {
        isFillViewport = true
        addView(root)
    }

    fun render(
        state: KeyboardState,
        shortcutSnapshot: ShortcutSnapshot = ShortcutSnapshot.empty(),
        config: ImeConsumableConfig = currentConfig,
        returnKey: ReturnKeySpec = currentReturnKey,
    ) {
        cancelPendingGestures()
        currentConfig = config
        currentReturnKey = returnKey
        currentKeyboardState = state
        currentShortcutSnapshot = shortcutSnapshot
        root.removeAllViews()
        when (state.mode) {
            KeyboardMode.COMMAND, KeyboardMode.CAPTURE_REVIEW, KeyboardMode.RESULT_REVIEW, KeyboardMode.ERROR -> renderCommand(state)
            KeyboardMode.LOCKED -> renderLocked(state)
            KeyboardMode.RECEIPT -> renderReceipt(state)
            else -> renderTyping(state, shortcutSnapshot = shortcutSnapshot)
        }
    }

    fun resetTypingState() {
        cancelPendingGestures()
        typingMode = TypingModeReducer.resetForInput()
    }

    /** Cancels delayed long-press callbacks before an editor/view boundary. */
    fun cancelPendingGestures() {
        gestureEpoch += 1L
        val pending = pendingGestureCancels.toList()
        pendingGestureCancels.clear()
        pending.forEach { it() }
    }

    override fun onDetachedFromWindow() {
        cancelPendingGestures()
        super.onDetachedFromWindow()
    }

    private fun renderTyping(state: KeyboardState, showCommandControls: Boolean = state.mode != KeyboardMode.LOCKED, shortcutSnapshot: ShortcutSnapshot = ShortcutSnapshot.empty()) {
        val toolbar = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        toolbar.addView(label(if (state.mode == KeyboardMode.RECEIPT) "完了" else "通常入力", 14f), weight(1f))
        if (showCommandControls) toolbar.addView(actionButton("Command", "Command mode") { callbacks.onCommand() })
        root.addView(toolbar)
        val rows = if (typingMode.layer == KeyboardLayer.SYMBOLS) listOf("1234567890", "-/:;()\$&@", ".,?!'\"")
        else listOf("qwertyuiop", "asdfghjkl", "zxcvbnm")
        val activeBindings = shortcutSnapshot.bindings.filter { it.enabled }
        if (activeBindings.isNotEmpty()) {
            root.addView(label("青枠のキーは長押しでSkillを実行（${activeBindings.joinToString { it.skillName }}）", 12f))
        }
        rows.forEach { letters ->
            val row = row()
            letters.forEach { letter ->
                val keyCode = letter.uppercase()
                val display = if (typingMode.layer == KeyboardLayer.LETTERS && typingMode.lettersUppercase) letter.uppercase() else letter.toString()
                row.addView(key(display, display, binding = shortcutSnapshot.bindingFor(keyCode)))
            }
            root.addView(row)
        }
        val controls = row()
        controls.addView(key("⇧", "Shift", weight = 1.4f).apply {
            isEnabled = typingMode.layer == KeyboardLayer.LETTERS
            contentDescription = when (typingMode.shift) {
                ShiftState.OFF -> "Shift off, tap for uppercase next character"
                ShiftState.ONE_SHOT -> "Shift on for next character, tap again for caps lock"
                ShiftState.CAPS_LOCK -> "Caps Lock on, tap to turn off"
            }
            setOnClickListener {
                typingMode = TypingModeReducer.shiftTapped(typingMode)
                playKeySound()
                render(state, currentShortcutSnapshot, currentConfig, currentReturnKey)
            }
        })
        controls.addView(key(if (typingMode.layer == KeyboardLayer.SYMBOLS) "ABC" else "123", "Numbers and symbols", weight = 1.2f).apply {
            setOnClickListener {
                typingMode = TypingModeReducer.layerToggled(typingMode)
                playKeySound()
                render(state, currentShortcutSnapshot, currentConfig, currentReturnKey)
            }
        })
        controls.addView(key("🌐", "Switch keyboard", weight = 1.2f).apply { setOnClickListener { playKeySound(); callbacks.onSwitchKeyboard() } })
        controls.addView(key("space", "Space", weight = 3f).apply { setOnClickListener { emitText(" ") } })
        controls.addView(key("⌫", "Delete", weight = 1.2f).apply { setOnClickListener { playKeySound(); callbacks.onDelete() } })
        controls.addView(key(currentReturnKey.label, "${currentReturnKey.label} action", weight = 1.2f).apply { setOnClickListener { playKeySound(); callbacks.onEnter() } })
        root.addView(controls)
        if (showCommandControls) {
            val ai = key("AI hold", "AI command: hold to enter, or use Command button", weight = 1f, touchFeedback = false)
            ai.setOnClickListener { /* A tap has no capture or network meaning. */ }
            ai.setOnLongClickListener {
                if (currentConfig.haptics != com.torutesu.mobileaikeyboard.core.HapticMode.OFF) {
                    ai.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                }
                callbacks.onCommand()
                true
            }
            root.addView(ai)
        }
    }

    private fun renderCommand(state: KeyboardState) {
        val heading = label(
            when (state.mode) {
                KeyboardMode.RESULT_REVIEW -> "結果を確認"
                KeyboardMode.CAPTURE_REVIEW -> "入力を確認"
                KeyboardMode.ERROR -> "復旧が必要です"
                else -> "Command"
            },
            16f,
        )
        heading.setTypeface(Typeface.DEFAULT, Typeface.BOLD)
        root.addView(heading)
        if (state.mode == KeyboardMode.CAPTURE_REVIEW) {
            val preview = state.capturePreview
            root.addView(label("送信先: ${preview?.destination ?: "端末内のみ"}", 14f))
            root.addView(label("外部送信: なし", 14f))
            root.addView(label("文字数: ${preview?.characterCount ?: 0}", 14f))
            root.addView(label("確認前の入力（正確な表示）", 13f).apply { setTypeface(Typeface.DEFAULT, Typeface.BOLD) })
            root.addView(label(preview?.exactText.orEmpty(), 15f).apply { contentDescription = "Exact capture preview" })
            root.addView(label("機密候補を伏せた表示", 13f).apply { setTypeface(Typeface.DEFAULT, Typeface.BOLD) })
            root.addView(label(preview?.redactedText.orEmpty(), 15f).apply { contentDescription = "Redacted capture preview" })
            preview?.notice?.let { root.addView(label(it, 13f)) }
            preview?.blockedReason?.let { root.addView(label(it, 13f).apply { setTextColor(Color.rgb(150, 30, 30)) }) }
            if (preview?.acknowledgementRequired == true) {
                root.addView(actionButton("確認して端末内で実行", "Capture Reviewを確認し、端末内の変換を実行") { callbacks.onAcknowledge() })
            }
            root.addView(actionButton("キャンセル", "Capture Reviewをキャンセル") { callbacks.onCancel() })
            return
        }
        if (state.mode == KeyboardMode.RESULT_REVIEW) {
            val result = state.resultText.orEmpty()
            val edited = EditText(context).apply {
                setText(result)
                setSelection(text.length)
                minHeight = dp(72)
                setSingleLine(false)
                showSoftInputOnFocus = false
                contentDescription = "Result Preview editor"
                hint = "編集可能な結果"
            }
            root.addView(label("プレビュー（編集・再生成・適用を選べます）", 13f))
            state.errorMessage?.let { root.addView(label(it, 13f).apply { setTextColor(Color.rgb(150, 30, 30)) }) }
            root.addView(edited)
            root.addView(inlineEditorKeyboard(edited))
            root.addView(actionButton("編集", "結果を編集") { edited.requestFocus() })
            root.addView(actionButton("再生成", "同じ入力から端末内で再生成") { callbacks.onRegenerate() })
            root.addView(actionButton("適用", "編集後の結果を入力欄へ適用") { callbacks.onApply(edited.text.toString()) })
            root.addView(actionButton("コピー", "編集後の結果をクリップボードへコピー") { callbacks.onCopy(edited.text.toString()) })
            root.addView(actionButton("キャンセル", "結果を破棄") { callbacks.onCancel() })
            return
        }
        if (state.mode == KeyboardMode.ERROR) {
            root.addView(label(state.errorMessage.orEmpty(), 14f).apply { setTextColor(Color.rgb(150, 30, 30)) })
            state.resultText?.takeIf { it.isNotBlank() }?.let { result ->
                root.addView(actionButton("結果をコピー", "失敗前の結果をクリップボードへコピー") { callbacks.onCopy(result) })
                root.addView(actionButton("再試行", "同じ入力から端末内で再生成を再試行") { callbacks.onRegenerate() })
            }
            root.addView(actionButton("キャンセル", "通常入力へ戻る") { callbacks.onCancel() })
            return
        }
        val command = EditText(context).apply {
            hint = "文章を入力、または選択して実行"
            minHeight = dp(52)
            setSingleLine(false)
            showSoftInputOnFocus = false
            contentDescription = "Command input"
            setSelection(text.length)
        }
        root.addView(command)
        root.addView(inlineEditorKeyboard(command))
        val surrounding = android.widget.CheckBox(context).apply {
            text = "前後の文章を使う（この実行のみ）"
            isChecked = false
            minHeight = dp(48)
            contentDescription = "Surrounding text source, off by default"
        }
        root.addView(surrounding)
        val selection = android.widget.CheckBox(context).apply {
            text = "選択範囲を使う（この実行のみ）"
            minHeight = dp(48)
            contentDescription = "Selection text source, off by default"
        }
        root.addView(selection, 1)
        root.addView(actionButton("入力を確認", "入力ソースを確認してCapture Reviewを表示") {
            callbacks.onCapture(command.text.toString(), selection.isChecked, surrounding.isChecked)
        })
        root.addView(actionButton("キャンセル", "Commandをキャンセル") { callbacks.onCancel() })
    }

    private fun renderReceipt(state: KeyboardState) {
        root.addView(label("適用しました", 17f).apply { setTypeface(Typeface.DEFAULT, Typeface.BOLD) })
        root.addView(label("入力欄の内容を更新しました。必要なら1回だけUndoできます。", 14f))
        state.resultText?.let { root.addView(label(it, 15f).apply { contentDescription = "Applied result" }) }
        if (state.undoAvailable) root.addView(actionButton("Undo", "直前の適用を元に戻す") { callbacks.onUndo() })
        root.addView(actionButton("コピー", "適用した結果をコピー") { callbacks.onCopy(state.resultText.orEmpty()) })
        root.addView(actionButton("閉じる", "レシートを閉じる") { callbacks.onCancel() })
    }

    private fun renderLocked(state: KeyboardState) {
        root.addView(label("安全な入力モード", 16f).apply { setTypeface(Typeface.DEFAULT, Typeface.BOLD) })
        root.addView(label(state.sensitiveReason ?: "この入力欄ではAI機能を利用できません", 14f))
        root.addView(label("通常入力は端末内で引き続き利用できます。", 13f))
        renderTyping(state, showCommandControls = false)
    }

    private fun inlineEditorKeyboard(editor: EditText): LinearLayout = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        listOf("qwertyuiop", "asdfghjkl", "zxcvbnm").forEach { letters ->
            val editorRow = row()
            letters.forEach { letter ->
                editorRow.addView(key(letter.toString(), "${letter}を編集欄へ入力").apply {
                    setOnClickListener { replaceEditorSelection(editor, letter.toString()) }
                })
            }
            addView(editorRow)
        }
        val editorControls = row()
        editorControls.addView(key("space", "編集欄へスペースを入力", weight = 3f).apply {
            setOnClickListener { replaceEditorSelection(editor, " ") }
        })
        editorControls.addView(key("⌫", "編集欄の文字を削除", weight = 1f).apply {
            setOnClickListener { deleteEditorSelection(editor) }
        })
        addView(editorControls)
    }

    private fun replaceEditorSelection(editor: EditText, replacement: String) {
        val start = editor.selectionStart.coerceAtLeast(0)
        val end = editor.selectionEnd.coerceAtLeast(start)
        editor.text.replace(start, end, replacement)
        editor.setSelection(start + replacement.length)
    }

    private fun deleteEditorSelection(editor: EditText) {
        var start = editor.selectionStart.coerceAtLeast(0)
        val end = editor.selectionEnd.coerceAtLeast(start)
        if (start == end && start > 0) start = editor.text.toString().offsetByCodePoints(start, -1)
        if (start < end) editor.text.delete(start, end)
    }

    private fun row() = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER
        layoutParams = LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, dp(52))
    }

    private fun key(
        text: String,
        accessibleName: String,
        weight: Float = 1f,
        binding: TriggerKeyBinding? = null,
        touchFeedback: Boolean = true,
    ) = Button(context).apply {
        this.text = text
        textSize = 15f
        minHeight = dp(48)
        minWidth = dp(48)
        contentDescription = if (binding == null) accessibleName else "${ShortcutKeyCode.displayLabel(binding.keyCode)}、${binding.skillName}、長押しで実行"
        if (binding != null) {
            background = GradientDrawable().apply {
                setColor(Color.TRANSPARENT)
                setStroke(dp(2), Color.rgb(17, 156, 243))
                cornerRadius = dp(8).toFloat()
            }
            tooltipText = "${binding.skillName}（長押し）"
        }
        layoutParams = LinearLayout.LayoutParams(0, dp(52), weight).apply { setMargins(dp(2), dp(2), dp(2), dp(2)) }
        val commitBoundCharacter = {
            emitText(if (typingMode.lettersUppercase) text.uppercase() else text.lowercase())
            typingMode = TypingModeReducer.characterCommitted(typingMode)
        }
        setOnClickListener {
            if (binding != null) {
                commitBoundCharacter()
            } else if (text.length == 1 && text[0].isLetter()) {
                emitText(text)
                typingMode = TypingModeReducer.characterCommitted(typingMode)
            } else if (text.length == 1) {
                emitText(text)
            }
        }
        if (binding == null && touchFeedback) {
            var pressed = false
            var cancelled = false
            var downX = 0f
            var downY = 0f
            setOnTouchListener { _, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        if (currentConfig.characterPreview && stateAllowsCharacterPreview() && text.length == 1) textSize = 20f
                        pressed = true
                        cancelled = false
                        downX = event.x
                        downY = event.y
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val distance = kotlin.math.hypot((event.x - downX).toDouble(), (event.y - downY).toDouble())
                        if (distance > 12f * density) {
                            cancelled = true
                            pressed = false
                            textSize = 15f
                        }
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        textSize = 15f
                        val commitTap = pressed && !cancelled
                        if (commitTap) {
                            if (currentConfig.haptics == com.torutesu.mobileaikeyboard.core.HapticMode.KEY_TAP) {
                                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                            }
                            // Keep the click path accessible while owning the raw
                            // stream, so this cannot double-commit on OEM Buttons.
                            performClick()
                        }
                        pressed = false
                        cancelled = true
                        true
                    }
                    MotionEvent.ACTION_CANCEL -> {
                        textSize = 15f
                        pressed = false
                        cancelled = true
                        true
                    }
                    else -> true
                }
            }
        }
        binding?.let { shortcut ->
            // Expose a real ACTION_LONG_CLICK to accessibility services. Raw
            // touch still owns tap-vs-hold arbitration below, while TalkBack
            // can invoke the exact same action without synthesizing pointer
            // timing. ACTION_CLICK remains ordinary character input.
            setOnLongClickListener {
                callbacks.onShortcut(shortcut)
                true
            }
            // Own the entire touch sequence. Letting Button also process ACTION_UP
            // can commit the character after the delayed Skill callback on some OEMs.
            // Explicitly committing only the short, uncancelled path makes a Skill
            // invocation and a character tap mutually exclusive.
            var longPressFired = false
            var cancelled = false
            var isDown = false
            var downX = 0f
            var downY = 0f
            var downEpoch = -1L
            val trigger = Runnable {
                if (!cancelled && isDown && downEpoch == gestureEpoch && isAttachedToWindow) {
                    longPressFired = true
                    isPressed = false
                    if (currentConfig.haptics != com.torutesu.mobileaikeyboard.core.HapticMode.OFF) {
                        performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                    }
                    performLongClick()
                }
            }
            val cancelPending: () -> Unit = {
                removeCallbacks(trigger)
                cancelled = true
                isDown = false
                isPressed = false
                textSize = 15f
            }
            setOnTouchListener { _, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        longPressFired = false
                        cancelled = false
                        isDown = true
                        downX = event.x
                        downY = event.y
                        downEpoch = gestureEpoch
                        isPressed = true
                        if (currentConfig.characterPreview && stateAllowsCharacterPreview()) textSize = 20f
                        postDelayed(trigger, 450L)
                        pendingGestureCancels.add(cancelPending)
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.x - downX
                        val dy = event.y - downY
                        val tooFar = kotlin.math.hypot(dx.toDouble(), dy.toDouble()) > 12f * density
                        if (tooFar) {
                            cancelPending()
                            pendingGestureCancels.remove(cancelPending)
                        }
                        true
                    }
                    MotionEvent.ACTION_POINTER_DOWN -> {
                        cancelPending()
                        pendingGestureCancels.remove(cancelPending)
                        true
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        removeCallbacks(trigger)
                        pendingGestureCancels.remove(cancelPending)
                        val commitTap = event.actionMasked == MotionEvent.ACTION_UP && isDown && !cancelled && !longPressFired
                        textSize = 15f
                        if (commitTap) {
                            if (currentConfig.haptics == com.torutesu.mobileaikeyboard.core.HapticMode.KEY_TAP) {
                                performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                            }
                            // Keep the click path accessible while ensuring it is
                            // invoked once (the listener owns the raw touch stream).
                            performClick()
                        }
                        isDown = false
                        isPressed = false
                        longPressFired = false
                        cancelled = true
                        // Consume both completed and cancelled sequences so Button
                        // cannot dispatch a second click after this listener.
                        true
                    }
                    else -> {
                        cancelPending()
                        pendingGestureCancels.remove(cancelPending)
                        true
                    }
                }
            }
        }
    }

    private fun emitText(value: String) {
        callbacks.onText(value)
        playKeySound()
    }

    private fun playKeySound() {
        if (currentConfig.keySound == KeySoundMode.KEY_TAP) {
            (context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager)?.playSoundEffect(AudioManager.FX_KEY_CLICK)
        }
    }

    private fun stateAllowsCharacterPreview(): Boolean = currentKeyboardState.mode != KeyboardMode.LOCKED

    private fun actionButton(text: String, accessibleName: String, action: () -> Unit) = Button(context).apply {
        this.text = text
        minHeight = dp(48)
        contentDescription = accessibleName
        setOnClickListener { action() }
        layoutParams = LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, dp(52)).apply { setMargins(dp(2), dp(2), dp(2), dp(2)) }
    }

    private fun label(text: String, size: Float) = TextView(context).apply {
        this.text = text
        textSize = size
        setTextColor(Color.DKGRAY)
        setPadding(dp(8), dp(5), dp(8), dp(5))
        minHeight = dp(44)
        gravity = Gravity.CENTER_VERTICAL
    }

    private fun weight(value: Float) = LinearLayout.LayoutParams(0, dp(52), value)
    private fun dp(value: Int) = (value * density).toInt()
}
