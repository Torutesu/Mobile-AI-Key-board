package com.torutesu.mobileaikeyboard.core

import android.text.InputType
import android.view.inputmethod.EditorInfo

enum class FieldSensitivity { NORMAL, PASSWORD, ONE_TIME_CODE, PHONE, PAYMENT, NUMERIC, UNKNOWN }

data class FieldClassification(
    val sensitivity: FieldSensitivity,
    val aiCaptureAllowed: Boolean,
    val explanation: String? = null,
)

/** Fail-closed classifier used before any context read or action surface is rendered. */
object SensitiveFieldClassifier {
    fun classify(editorInfo: EditorInfo?): FieldClassification {
        if (editorInfo == null) return blocked(FieldSensitivity.UNKNOWN, "入力欄を確認できないためAI機能を利用できません")
        val inputType = editorInfo.inputType
        val variation = inputType and InputType.TYPE_MASK_VARIATION
        val klass = inputType and InputType.TYPE_MASK_CLASS
        val privateOptions = editorInfo.privateImeOptions.orEmpty().lowercase()
        val hint = editorInfo.hintText?.toString().orEmpty().lowercase()
        val metadata = "$privateOptions $hint"

        if (listOf("otp", "one_time_code", "one-time-code", "verification code", "認証コード").any(metadata::contains)) {
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
        if (listOf("credit", "card", "cc-number", "ccnumber", "cvc", "cvv", "payment", "クレジット", "カード").any(metadata::contains)) {
            return blocked(FieldSensitivity.PAYMENT, "決済情報欄ではAI機能を利用できません")
        }
        // Arbitrary numeric fields frequently contain PINs, account numbers,
        // payment data or OTPs. Without a trustworthy semantic hint, AI
        // capture is not worth the disclosure risk.
        if (klass == InputType.TYPE_CLASS_NUMBER || klass == InputType.TYPE_CLASS_DATETIME) {
            return blocked(FieldSensitivity.NUMERIC, "数値・日時欄ではAI機能を利用できません")
        }
        return FieldClassification(FieldSensitivity.NORMAL, true)
    }

    private fun blocked(type: FieldSensitivity, explanation: String) =
        FieldClassification(type, aiCaptureAllowed = false, explanation = explanation)
}
