package com.torutesu.mobileaikeyboard.core

import android.text.InputType
import android.view.inputmethod.EditorInfo

enum class FieldSensitivity { NORMAL, PASSWORD, ONE_TIME_CODE, PHONE }

data class FieldClassification(
    val sensitivity: FieldSensitivity,
    val aiCaptureAllowed: Boolean,
    val explanation: String? = null,
)

/** Fail-closed classifier used before any context read or action surface is rendered. */
object SensitiveFieldClassifier {
    fun classify(editorInfo: EditorInfo?): FieldClassification {
        if (editorInfo == null) return FieldClassification(FieldSensitivity.NORMAL, true)
        val inputType = editorInfo.inputType
        val variation = inputType and InputType.TYPE_MASK_VARIATION
        val klass = inputType and InputType.TYPE_MASK_CLASS
        val privateOptions = editorInfo.privateImeOptions.orEmpty().lowercase()

        if (privateOptions.contains("otp") || privateOptions.contains("one_time_code")) {
            return blocked(FieldSensitivity.ONE_TIME_CODE, "ワンタイムコード欄ではAI機能を利用できません")
        }
        if (variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
            variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD ||
            variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
            variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD
        ) {
            return blocked(FieldSensitivity.PASSWORD, "パスワード欄ではAI機能を利用できません")
        }
        if (klass == InputType.TYPE_CLASS_PHONE) {
            return blocked(FieldSensitivity.PHONE, "電話番号欄ではAI機能を利用できません")
        }
        return FieldClassification(FieldSensitivity.NORMAL, true)
    }

    private fun blocked(type: FieldSensitivity, explanation: String) =
        FieldClassification(type, aiCaptureAllowed = false, explanation = explanation)
}
