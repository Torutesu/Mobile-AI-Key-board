package com.torutesu.mobileaikeyboard.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.view.Gravity
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.torutesu.mobileaikeyboard.core.KeyboardMode
import com.torutesu.mobileaikeyboard.core.KeyboardState

/** Small dependency-free keyboard surface; all touch targets are at least 48dp. */
@SuppressLint("ViewConstructor") // Instantiated only by KeyboardImeService with mandatory callbacks; never inflated from XML.
class KeyboardSurface(context: Context, private val callbacks: Callbacks) : ScrollView(context) {
    class Callbacks(
        val onCommand: () -> Unit,
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
    private var shift = false
    private var numericMode = false
    private val root = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(6), dp(5), dp(6), dp(5))
        contentDescription = "Mobile AI Keyboard"
    }

    init {
        isFillViewport = true
        addView(root)
    }

    fun render(state: KeyboardState) {
        root.removeAllViews()
        when (state.mode) {
            KeyboardMode.COMMAND, KeyboardMode.CAPTURE_REVIEW, KeyboardMode.RESULT_REVIEW, KeyboardMode.ERROR -> renderCommand(state)
            KeyboardMode.LOCKED -> renderLocked(state)
            KeyboardMode.RECEIPT -> renderReceipt(state)
            else -> renderTyping(state)
        }
    }

    private fun renderTyping(state: KeyboardState, showCommandControls: Boolean = state.mode != KeyboardMode.LOCKED) {
        val toolbar = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        toolbar.addView(label(if (state.mode == KeyboardMode.RECEIPT) "完了" else "通常入力", 14f), weight(1f))
        if (showCommandControls) toolbar.addView(actionButton("Command", "Command mode") { callbacks.onCommand() })
        root.addView(toolbar)
        val rows = if (numericMode) listOf("1234567890", "-/:;()\$&@", ".,?!'\"")
        else listOf("qwertyuiop", "asdfghjkl", "zxcvbnm")
        rows.forEach { letters ->
            val row = row()
            letters.forEach { letter -> row.addView(key(letter.uppercase(), letter.toString())) }
            root.addView(row)
        }
        val controls = row()
        controls.addView(key("⇧", "Shift", weight = 1.4f).apply {
            setOnClickListener { shift = !shift; contentDescription = if (shift) "Shift on" else "Shift off" }
        })
        controls.addView(key(if (numericMode) "ABC" else "123", "Numbers and symbols", weight = 1.2f).apply {
            setOnClickListener { numericMode = !numericMode; render(state) }
        })
        controls.addView(key("🌐", "Switch keyboard", weight = 1.2f).apply { setOnClickListener { callbacks.onSwitchKeyboard() } })
        controls.addView(key("space", "Space", weight = 3f).apply { setOnClickListener { callbacks.onText(" ") } })
        controls.addView(key("⌫", "Delete", weight = 1.2f).apply { setOnClickListener { callbacks.onDelete() } })
        controls.addView(key("↵", "Return", weight = 1.2f).apply { setOnClickListener { callbacks.onEnter() } })
        root.addView(controls)
        if (showCommandControls) {
            val ai = key("AI hold", "AI command: hold to enter, or use Command button", weight = 1f)
            ai.setOnClickListener { /* A tap has no capture or network meaning. */ }
            ai.setOnLongClickListener { callbacks.onCommand(); true }
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
            root.addView(actionButton("戻る", "通常入力へ戻る") { callbacks.onCancel() })
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

    private fun key(text: String, accessibleName: String, weight: Float = 1f) = Button(context).apply {
        this.text = text
        textSize = 15f
        minHeight = dp(48)
        minWidth = dp(48)
        contentDescription = accessibleName
        layoutParams = LinearLayout.LayoutParams(0, dp(52), weight).apply { setMargins(dp(2), dp(2), dp(2), dp(2)) }
        setOnClickListener {
            if (text.length == 1 && text[0].isLetter()) {
                callbacks.onText(if (shift) text.uppercase() else text.lowercase())
                shift = false
            } else if (text.length == 1 && !text[0].isLetterOrDigit()) {
                callbacks.onText(text)
            }
        }
    }

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
