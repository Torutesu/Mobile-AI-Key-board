package com.torutesu.mobileaikeyboard.core

data class RewriteResult(
    val original: String,
    val rewritten: String,
    val preservedEntities: List<ProtectedEntity>,
    val wasChanged: Boolean,
)

/** Offline fixture for W1/W2. It intentionally has no Android, network, or model dependency. */
class LocalPoliteRewriteService {
    fun rewrite(input: String): RewriteResult {
        if (input.isBlank()) return RewriteResult(input, input, emptyList(), false)
        val protected = EntityProtector.protect(input)
        val rewrittenMasked = politeTransform(protected.masked)
        val rewritten = protected.restore(rewrittenMasked)
        return RewriteResult(input, rewritten, protected.entities, input != rewritten)
    }

    private fun politeTransform(input: String): String {
        var value = input.trim()
        listOf(
            "ちょうだい" to "いただけますか",
            "お願い" to "お願いいたします",
            "ありがとう" to "ありがとうございます",
            "ごめん" to "申し訳ありません",
            "だよ" to "です",
            "だね" to "ですね",
            "して" to "してください",
            "ください" to "いただけますか",
        ).forEach { (from, to) -> value = value.replace(from, to) }
        value = value.replace(Regex("\\bthanks\\b", RegexOption.IGNORE_CASE), "Thank you")
        value = value.replace(Regex("\\bcan you\\b", RegexOption.IGNORE_CASE), "Could you please")
        if (value.isNotEmpty() && value.last() !in "。.!！?？" && value.any { it in '\u3040'..'\u30ff' }) {
            value += "。"
        }
        return value
    }
}
