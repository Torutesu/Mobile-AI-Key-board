package com.torutesu.mobileaikeyboard.ime

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
class KeyboardSurface(context: Context, private val callbacks: Callbacks) : ScrollView(context) {
    class Callbacks(
        val onCommand: () -> Unit,
        val onText: (String) -> Unit,
        val onDelete: () -> Unit,
        val onEnter: () -> Unit,
        val onSwitchKeyboard: () -> Unit,
        val onRewrite: (String, Boolean) -> Unit,
        val onApply: () -> Unit,
        val onCopy: (String) -> Unit,
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
        if (state.mode == KeyboardMode.RESULT_REVIEW) {
            val result = state.resultText.orEmpty()
            root.addView(label(result, 16f).apply { contentDescription = "生成結果: $result" })
            root.addView(actionButton("適用", "結果を入力欄へ適用") { callbacks.onApply() })
            root.addView(actionButton("コピー", "結果をクリップボードへコピー") { callbacks.onCopy(result) })
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
            contentDescription = "Command input"
        }
        root.addView(command)
        val surrounding = android.widget.CheckBox(context).apply {
            text = "前後の文章を使う（この実行のみ）"
            isChecked = false
            minHeight = dp(48)
            contentDescription = "Surrounding text source, off by default"
        }
        root.addView(surrounding)
        root.addView(actionButton("丁寧にする（端末内）", "ローカルの固定変換を実行") {
            callbacks.onRewrite(command.text.toString(), surrounding.isChecked)
        })
        root.addView(actionButton("キャンセル", "Commandをキャンセル") { callbacks.onCancel() })
    }

    private fun renderLocked(state: KeyboardState) {
        root.addView(label("安全な入力モード", 16f).apply { setTypeface(Typeface.DEFAULT, Typeface.BOLD) })
        root.addView(label(state.sensitiveReason ?: "この入力欄ではAI機能を利用できません", 14f))
        root.addView(label("通常入力は端末内で引き続き利用できます。", 13f))
        renderTyping(state, showCommandControls = false)
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
