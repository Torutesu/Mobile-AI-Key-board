package com.torutesu.mobileaikeyboard.core

import android.content.Context
import android.text.InputType
import android.view.inputmethod.EditorInfo

data class ImeActivationProbe(val counter: Long, val observedAtMillis: Long)

/** Content-free proof that this app's InputMethodService actually entered an editor. */
class ImeActivationProbeStore(
    context: Context,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    @Synchronized fun publish(): Boolean {
        val previous = read()?.counter ?: 0L
        if (previous == Long.MAX_VALUE) return false
        val counter = previous + 1L
        val observedAt = nowMillis()
        if (observedAt <= 0) return false
        return preferences.edit()
            .putLong(COUNTER, counter)
            .putLong(OBSERVED_AT, observedAt)
            .putString(DIGEST, digest(counter, observedAt))
            .commit()
    }

    @Synchronized fun read(): ImeActivationProbe? {
        val counter = preferences.getLong(COUNTER, 0L)
        val observedAt = preferences.getLong(OBSERVED_AT, 0L)
        if (counter <= 0 || observedAt <= 0 || preferences.getString(DIGEST, null) != digest(counter, observedAt)) return null
        return ImeActivationProbe(counter, observedAt)
    }

    private fun digest(counter: Long, observedAt: Long) =
        "sha256:${TextFingerprint.of("ime-activation-probe-v1\u0000$counter\u0000$observedAt")}"

    companion object {
        private const val PREFERENCES = "mobile_ai_keyboard_ime_activation_probe_v1"
        private const val COUNTER = "counter"
        private const val OBSERVED_AT = "observed_at_millis"
        private const val DIGEST = "content_digest"
    }
}

enum class ShiftState { OFF, ONE_SHOT, CAPS_LOCK }
enum class KeyboardLayer { LETTERS, SYMBOLS }

data class TypingModeState(
    val shift: ShiftState = ShiftState.OFF,
    val layer: KeyboardLayer = KeyboardLayer.LETTERS,
) {
    val lettersUppercase: Boolean get() = shift != ShiftState.OFF
}

object TypingModeReducer {
    fun shiftTapped(state: TypingModeState): TypingModeState = state.copy(
        shift = when (state.shift) {
            ShiftState.OFF -> ShiftState.ONE_SHOT
            ShiftState.ONE_SHOT -> ShiftState.CAPS_LOCK
            ShiftState.CAPS_LOCK -> ShiftState.OFF
        },
    )

    fun characterCommitted(state: TypingModeState): TypingModeState = state.copy(
        shift = if (state.shift == ShiftState.ONE_SHOT) ShiftState.OFF else state.shift,
    )

    fun layerToggled(state: TypingModeState): TypingModeState = state.copy(
        layer = if (state.layer == KeyboardLayer.LETTERS) KeyboardLayer.SYMBOLS else KeyboardLayer.LETTERS,
        // Symbols have no case; returning to letters must not resurrect Caps Lock.
        shift = ShiftState.OFF,
    )

    fun resetForInput(): TypingModeState = TypingModeState()
}

data class ReturnKeySpec(val label: String, val editorAction: Int? = null)

object ReturnKeyModel {
    fun from(editorInfo: EditorInfo?): ReturnKeySpec = editorInfo?.let {
        from(it.imeOptions, it.inputType)
    } ?: ReturnKeySpec("↵")

    fun from(imeOptions: Int, inputType: Int): ReturnKeySpec {
        val multiline = inputType and InputType.TYPE_TEXT_FLAG_MULTI_LINE != 0
        val action = imeOptions and EditorInfo.IME_MASK_ACTION
        val noEnterAction = imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION != 0
        if (multiline || noEnterAction || action == EditorInfo.IME_ACTION_NONE || action == EditorInfo.IME_ACTION_UNSPECIFIED) {
            return ReturnKeySpec("↵")
        }
        return when (action) {
            EditorInfo.IME_ACTION_GO -> ReturnKeySpec("移動", action)
            EditorInfo.IME_ACTION_SEARCH -> ReturnKeySpec("検索", action)
            EditorInfo.IME_ACTION_SEND -> ReturnKeySpec("送信", action)
            EditorInfo.IME_ACTION_NEXT -> ReturnKeySpec("次へ", action)
            EditorInfo.IME_ACTION_DONE -> ReturnKeySpec("完了", action)
            else -> ReturnKeySpec("↵")
        }
    }
}

/** Small shared preferences projection consumed by the IME process. */
class KeyboardSettingsStore(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    @Synchronized fun readState(): KeyboardSettingsState {
        val v3 = preferences.getInt(SCHEMA_VERSION, 0) >= 3
        return KeyboardSettingsState(
            schemaVersion = 3,
            theme = enumOrDefault(THEME, KeyboardTheme.SYSTEM),
            haptics = enumOrDefault(HAPTICS, HapticMode.KEY_TAP),
            keySize = enumOrDefault(KEY_SIZE, KeySize.STANDARD),
            oneHanded = enumOrDefault(ONE_HANDED, OneHandedMode.OFF),
            workflowPack = enumOrDefault(WORKFLOW_PACK, JapaneseWorkflowPack.POLITE),
            keySound = if (v3) enumOrDefault(KEY_SOUND, KeySoundMode.OFF) else KeySoundMode.OFF,
            characterPreview = if (v3) preferences.getBoolean(CHARACTER_PREVIEW, true) else true,
        )
    }

    @Synchronized fun read(): ImeConsumableConfig = KeyboardSettingsReducer.imeConfig(readState())

    private inline fun <reified T : Enum<T>> enumOrDefault(key: String, fallback: T): T =
        runCatching { enumValueOf<T>(preferences.getString(key, fallback.name)!!) }.getOrDefault(fallback)

    @Suppress("UseKtx") // commit() is intentional: the IME must observe settings synchronously.
    @Synchronized fun write(state: KeyboardSettingsState): Boolean = preferences.edit()
        .putInt(SCHEMA_VERSION, 3)
        .putString(THEME, state.theme.name)
        .putString(HAPTICS, state.haptics.name)
        .putString(KEY_SIZE, state.keySize.name)
        .putString(ONE_HANDED, state.oneHanded.name)
        .putString(WORKFLOW_PACK, state.workflowPack.name)
        .putString(KEY_SOUND, state.keySound.name)
        .putBoolean(CHARACTER_PREVIEW, state.characterPreview)
        .commit()

    companion object {
        private const val PREFERENCES = "mobile_ai_keyboard_settings_v1"
        private const val SCHEMA_VERSION = "schema_version"
        private const val THEME = "theme"
        private const val HAPTICS = "haptics"
        private const val KEY_SIZE = "key_size"
        private const val ONE_HANDED = "one_handed"
        private const val WORKFLOW_PACK = "workflow_pack"
        private const val KEY_SOUND = "key_sound"
        private const val CHARACTER_PREVIEW = "character_preview"
    }
}
