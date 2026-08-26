package com.torutesu.mobileaikeyboard.core

data class ProtectedEntity(val category: String, val value: String, val start: Int, val end: Int)

data class ProtectedText(val masked: String, val entities: List<ProtectedEntity>) {
    fun restore(candidate: String): String {
        var output = candidate
        entities.forEachIndexed { index, entity ->
            output = output.replace(token(index), entity.value)
        }
        return output
    }

    private fun token(index: Int) = "__MOBILE_AI_ENTITY_${index}__"
}

/** Local, deterministic entity locking for text transformations. */
object EntityProtector {
    private val patterns = listOf(
        "url" to Regex("https?://[^\\s]+", RegexOption.IGNORE_CASE),
        "email" to Regex("[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", RegexOption.IGNORE_CASE),
        "handle" to Regex("(?<![A-Za-z0-9_])[#@][\\p{L}0-9_]+"),
        "date" to Regex("\\d{1,4}(?:年\\d{1,2}月\\d{1,2}日?|[/-]\\d{1,2}[/-]\\d{1,4})"),
        "number" to Regex("(?<![\\p{L}\\d])[+-]?\\d+(?:[.,]\\d+)?(?:%|円|ドル|人|件)?"),
    )

    fun protect(input: String): ProtectedText {
        val matches = patterns.flatMap { (category, regex) ->
            regex.findAll(input).map { match -> ProtectedEntity(category, match.value, match.range.first, match.range.last + 1) }
        }.distinctBy { it.start to it.end }.sortedBy { it.start }
        val nonOverlapping = buildList {
            var end = -1
            matches.forEach { entity ->
                if (entity.start >= end) {
                    add(entity)
                    end = entity.end
                }
            }
        }
        val masked = buildString {
            var cursor = 0
            nonOverlapping.forEachIndexed { index, entity ->
                append(input, cursor, entity.start)
                append("__MOBILE_AI_ENTITY_").append(index).append("__")
                cursor = entity.end
            }
            append(input, cursor, input.length)
        }
        return ProtectedText(masked, nonOverlapping)
    }

    fun transformPreserving(input: String, transform: (String) -> String): String {
        val protected = protect(input)
        return protected.restore(transform(protected.masked))
    }
}
