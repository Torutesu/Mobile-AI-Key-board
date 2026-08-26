package com.torutesu.mobileaikeyboard.core

import java.io.File
import java.nio.charset.StandardCharsets
import java.security.MessageDigest

private typealias ShortcutJsonObject = Map<String, Any?>

/**
 * The shared shortcut fixture is a wire-contract test asset, not an Android
 * preference snapshot.  Keep its parser and validator dependency-free so the
 * native test can consume the exact checked-in bytes produced by the
 * TypeScript contracts package.
 */
object ShortcutGoldenFixture {
    const val FILE_NAME = "shortcut-golden-vectors.json"
    private const val FIXTURE_SCHEMA = "mobile-ai-keyboard.shortcut-golden.v1"
    private const val AUTHORITY = "typescript-contracts"

    data class VectorResult(
        val id: String,
        val contractValid: Boolean,
        val contentDigest: String?,
        val rejection: String?,
    )

    data class FixtureResult(
        val schemaVersion: String,
        val authority: String,
        val nativeConsumptionStatus: String,
        val vectors: List<VectorResult>,
    )

    /** Parse and classify every vector, failing closed on malformed fixture data. */
    fun validate(bytes: ByteArray): FixtureResult {
        val root = JsonParser(bytes.toString(StandardCharsets.UTF_8)).parseObject()
        val schemaVersion = root.string("schema_version")
        val authority = root.string("authority")
        val nativeStatus = root.string("native_consumption_status")
        require(schemaVersion == FIXTURE_SCHEMA) { "unsupported golden fixture schema" }
        require(authority == AUTHORITY) { "golden fixture authority mismatch" }
        require(nativeStatus in setOf("not_proven", "native_unit_consumers")) {
            "unsupported native consumption status"
        }
        val vectors = root.array("vectors").map { value ->
            val vector = value.asObject()
            val id = vector.string("id")
            require(vector.string("kind") == "shortcut_snapshot") { "$id: unsupported vector kind" }
            val input = vector.objectValue("input")
            val expected = vector.objectValue("expected")
            val expectedValid = expected.boolean("contract_valid")
            val expectedDigest = expected.nullableString("content_digest")
            val expectedRejection = expected.nullableString("rejection")
            val classified = classify(input)
            require(classified.contractValid == expectedValid) {
                "$id: expected contract_valid=$expectedValid, got ${classified.contractValid}"
            }
            require(classified.contentDigest == expectedDigest) {
                "$id: expected content_digest=$expectedDigest, got ${classified.contentDigest}"
            }
            require(classified.rejection == expectedRejection) {
                "$id: expected rejection=$expectedRejection, got ${classified.rejection}"
            }
            classified.copy(id = id)
        }
        require(vectors.map { it.id }.toSet().size == vectors.size) { "golden fixture contains duplicate vector IDs" }
        return FixtureResult(schemaVersion, authority, nativeStatus, vectors)
    }

    /**
     * Locate only the repository's checked-in fixture.  No copied test
     * resource is accepted: this prevents a stale local fixture from making
     * the native contract test look green.
     */
    fun repositoryFixture(): File {
        val cwd = File(System.getProperty("user.dir") ?: ".").canonicalFile
        val candidates = sequence {
            yield(cwd.resolve("fixtures/$FILE_NAME"))
            yield(cwd.parentFile?.resolve("fixtures/$FILE_NAME"))
            yield(cwd.parentFile?.parentFile?.resolve("fixtures/$FILE_NAME"))
            yield(cwd.parentFile?.parentFile?.parentFile?.resolve("fixtures/$FILE_NAME"))
        }.filterNotNull().map { it.canonicalFile }.distinct().toList()
        return candidates.firstOrNull { it.isFile }
            ?: error("authoritative fixture not found from ${cwd.path}")
    }

    private fun classify(input: ShortcutJsonObject): VectorResult {
        val rawDigest = input.nullableString("content_digest")
        val unsigned = LinkedHashMap(input).apply { remove("content_digest") }
        val digest = sha256(canonicalJson(unsigned))

        if (input.int("schema_version") != 1) return VectorResult("", false, null, "schema")

        val bindings = input.array("bindings").map { it.asObject() }
        if (bindings.any { binding ->
                val key = binding.objectValue("trigger_key").nullableString("key_code")
                key == null || !KEY_CODE.matches(key)
            }) return VectorResult("", false, null, "key_normalization")

        if (rawDigest != digest) return VectorResult("", false, null, "digest")

        val activeKeys = bindings.filter { it.boolean("enabled") }
            .map { it.objectValue("trigger_key").string("key_code") }
        if (activeKeys.size != activeKeys.toSet().size) return VectorResult("", false, null, "duplicate_conflict")

        val projections = input.array("skills").map { it.asObject() }
        for (binding in bindings) {
            val skillId = binding.string("skill_id")
            val versionId = binding.string("version_id")
            val projection = projections.firstOrNull {
                it.string("skill_id") == skillId && it.string("version_id") == versionId
            } ?: return VectorResult("", false, null, "schema")
            val eligibility = binding.string("local_eligibility")
            val route = projection.string("execution_route")
            val tools = projection.array("tool_summaries")
            if (eligibility == "local" && (route != "keyboard_local" || tools.isNotEmpty() || binding.array("required_connection_ids").isNotEmpty())) {
                return VectorResult("", false, null, "local_route_authority")
            }
        }

        return VectorResult("", true, rawDigest, null)
    }

    private val KEY_CODE = Regex("^Key[A-Z]$")

    private fun sha256(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(StandardCharsets.UTF_8))
        return "sha256:" + digest.joinToString("") { "%02x".format(it) }
    }

    /** Same limited JSON canonicalization used by packages/contracts. */
    private fun canonicalJson(value: Any?): String = when (value) {
        null -> "null"
        is Boolean -> value.toString()
        is String -> quote(value)
        is Int, is Long -> value.toString()
        is Double, is Float -> number(value.toString())
        is List<*> -> value.joinToString(prefix = "[", postfix = "]", separator = ",", transform = ::canonicalJson)
        is Map<*, *> -> value.entries
            .filter { it.value !== Undefined }
            .sortedBy { it.key as String }
            .joinToString(prefix = "{", postfix = "}", separator = ",") { "${quote(it.key as String)}:${canonicalJson(it.value)}" }
        else -> error("unsupported JSON value ${value::class.java.name}")
    }

    private fun number(value: String): String = when {
        value == "-0.0" || value == "-0" -> "0"
        value.endsWith(".0") -> value.dropLast(2)
        else -> value
    }

    private fun quote(value: String): String = buildString(value.length + 2) {
        append('"')
        value.forEach { ch ->
            when (ch) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\b' -> append("\\b")
                '\u000C' -> append("\\f")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                in '\u0000'..'\u001f' -> append("\\u%04x".format(ch.code))
                else -> append(ch)
            }
        }
        append('"')
    }

    private object Undefined

    private fun Any?.asObject(): ShortcutJsonObject {
        val map = this as? Map<*, *> ?: error("expected JSON object")
        require(map.keys.all { it is String }) { "JSON object keys must be strings" }
        return map.entries.associate { (key, value) -> key as String to value }
    }
    private fun ShortcutJsonObject.string(key: String): String = this[key] as? String ?: error("missing string $key")
    private fun ShortcutJsonObject.nullableString(key: String): String? = this[key]?.let { it as? String ?: error("invalid string $key") }
    private fun ShortcutJsonObject.boolean(key: String): Boolean = this[key] as? Boolean ?: error("missing boolean $key")
    private fun ShortcutJsonObject.int(key: String): Int = (this[key] as? Number)?.toInt() ?: error("missing integer $key")
    private fun ShortcutJsonObject.array(key: String): List<Any?> = this[key] as? List<Any?> ?: error("missing array $key")
    private fun ShortcutJsonObject.objectValue(key: String): ShortcutJsonObject = this[key].asObject()

    /** Small strict JSON parser sufficient for the contract fixture domain. */
    private class JsonParser(private val source: String) {
        private var index = 0

        fun parseObject(): ShortcutJsonObject {
            val value = parseValue().asObject()
            skipWhitespace()
            require(index == source.length) { "trailing JSON data" }
            return value
        }

        private fun parseValue(): Any? {
            skipWhitespace()
            require(index < source.length) { "unexpected end of JSON" }
            return when (source[index]) {
                '{' -> parseObjectValue()
                '[' -> parseArray()
                '"' -> parseString()
                't' -> literal("true", true)
                'f' -> literal("false", false)
                'n' -> literal("null", null)
                '-', in '0'..'9' -> parseNumber()
                else -> error("invalid JSON token at $index")
            }
        }

        private fun parseObjectValue(): ShortcutJsonObject {
            expect('{'); skipWhitespace()
            val result = LinkedHashMap<String, Any?>()
            if (takeIf('}')) return result
            while (true) {
                skipWhitespace()
                val key = parseString()
                skipWhitespace(); expect(':')
                require(!result.containsKey(key)) { "duplicate JSON object key $key" }
                result[key] = parseValue()
                skipWhitespace()
                if (takeIf('}')) return result
                expect(',')
            }
        }

        private fun parseArray(): List<Any?> {
            expect('['); skipWhitespace()
            val result = ArrayList<Any?>()
            if (takeIf(']')) return result
            while (true) {
                result += parseValue()
                skipWhitespace()
                if (takeIf(']')) return result
                expect(',')
            }
        }

        private fun parseString(): String {
            expect('"')
            val result = StringBuilder()
            while (index < source.length) {
                when (val ch = source[index++]) {
                    '"' -> return result.toString()
                    '\\' -> {
                        require(index < source.length) { "unterminated escape" }
                        when (val escaped = source[index++]) {
                            '"', '\\', '/' -> result.append(escaped)
                            'b' -> result.append('\b')
                            'f' -> result.append('\u000C')
                            'n' -> result.append('\n')
                            'r' -> result.append('\r')
                            't' -> result.append('\t')
                            'u' -> result.append(parseUnicodeEscape())
                            else -> error("invalid escape at $index")
                        }
                    }
                    in '\u0000'..'\u001f' -> error("unescaped control character")
                    else -> result.append(ch)
                }
            }
            error("unterminated string")
        }

        private fun parseUnicodeEscape(): Char {
            require(index + 4 <= source.length) { "short unicode escape" }
            val hex = source.substring(index, index + 4)
            require(hex.all { it in "0123456789abcdefABCDEF" }) { "invalid unicode escape" }
            index += 4
            return hex.toInt(16).toChar()
        }

        private fun parseNumber(): Number {
            val start = index
            if (source[index] == '-') index++
            if (takeIf('0').not()) {
                require(index < source.length && source[index] in '1'..'9') { "invalid number" }
                while (index < source.length && source[index].isDigit()) index++
            }
            var floating = false
            if (takeIf('.')) {
                floating = true
                require(index < source.length && source[index].isDigit()) { "invalid fraction" }
                while (index < source.length && source[index].isDigit()) index++
            }
            if (index < source.length && source[index] in "eE") {
                floating = true; index++
                if (index < source.length && source[index] in "+-") index++
                require(index < source.length && source[index].isDigit()) { "invalid exponent" }
                while (index < source.length && source[index].isDigit()) index++
            }
            val token = source.substring(start, index)
            return if (floating) token.toDouble() else token.toLongOrNull() ?: error("integer overflow")
        }

        private fun literal(token: String, value: Any?): Any? {
            require(source.startsWith(token, index)) { "invalid literal at $index" }
            index += token.length
            return value
        }

        private fun expect(char: Char) {
            require(index < source.length && source[index] == char) { "expected '$char' at $index" }
            index++
        }

        private fun takeIf(char: Char): Boolean = if (index < source.length && source[index] == char) { index++; true } else false
        private fun skipWhitespace() { while (index < source.length && source[index] in " \t\r\n") index++ }
    }
}
