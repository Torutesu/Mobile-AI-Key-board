package com.torutesu.mobileaikeyboard.core

import android.content.Context
import java.nio.charset.StandardCharsets
import java.util.Base64

/**
 * Content-free native circuit breaker for one immutable Skill version.
 *
 * The store never contains editor text, results, prompts, package names, or
 * credentials. Three consecutive executor failures inside a bounded window
 * hide only the affected Skill decoration/action. Ordinary key taps are owned
 * by KeyboardSurface and remain available even when this store is corrupt.
 */
data class NativeSkillFailureIdentity(
    val skillId: String,
    val skillVersion: Int,
    val skillDigest: String,
) {
    companion object {
        fun from(binding: TriggerKeyBinding) = NativeSkillFailureIdentity(
            binding.skillId,
            binding.skillVersion,
            binding.skillDigest,
        )
    }
}

data class NativeSkillFailureRecord(
    val identity: NativeSkillFailureIdentity,
    val consecutiveFailures: Int,
    val firstFailureAtMillis: Long,
    val lastFailureAtMillis: Long,
    val disabled: Boolean,
)

enum class NativeSkillExecutionDecision { ALLOWED, DISABLED, STORE_UNAVAILABLE }

class NativeSkillFailureStore(
    context: Context,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    private val boundaryStore = AccountBoundaryStore(context.applicationContext, nowMillis)
    private val unavailableScopes = mutableSetOf<String>()
    private var forceWriteFailureForTesting = false

    fun decision(binding: TriggerKeyBinding, boundary: ActiveAccountBoundary): NativeSkillExecutionDecision =
        withAccountBoundaryLock {
            if (boundaryStore.read() != boundary) return@withAccountBoundaryLock NativeSkillExecutionDecision.STORE_UNAVAILABLE
            if (failureScope(binding, boundary) in unavailableScopes) return@withAccountBoundaryLock NativeSkillExecutionDecision.STORE_UNAVAILABLE
            val state = readState(boundary) ?: return@withAccountBoundaryLock NativeSkillExecutionDecision.STORE_UNAVAILABLE
            val now = nowMillis()
            val record = state.firstOrNull { it.identity == NativeSkillFailureIdentity.from(binding) }
                ?: return@withAccountBoundaryLock NativeSkillExecutionDecision.ALLOWED
            if (now < record.lastFailureAtMillis) {
                NativeSkillExecutionDecision.STORE_UNAVAILABLE
            } else if (record.disabled && now - record.lastFailureAtMillis <= FAILURE_WINDOW_MILLIS) {
                NativeSkillExecutionDecision.DISABLED
            } else {
                NativeSkillExecutionDecision.ALLOWED
            }
        }

    /** Records one executor failure and returns the resulting decision. */
    fun recordFailure(binding: TriggerKeyBinding, boundary: ActiveAccountBoundary): NativeSkillExecutionDecision =
        withAccountBoundaryLock {
            if (boundaryStore.read() != boundary) return@withAccountBoundaryLock NativeSkillExecutionDecision.STORE_UNAVAILABLE
            val current = readState(boundary) ?: return@withAccountBoundaryLock NativeSkillExecutionDecision.STORE_UNAVAILABLE
            val now = nowMillis()
            if (current.any { it.lastFailureAtMillis > now }) {
                return@withAccountBoundaryLock NativeSkillExecutionDecision.STORE_UNAVAILABLE
            }
            // Expired exact-version records must not permanently disable a
            // Skill or consume the bounded record budget forever.
            val active = current.filter { now - it.lastFailureAtMillis <= FAILURE_WINDOW_MILLIS }
            val identity = NativeSkillFailureIdentity.from(binding)
            val previous = active.firstOrNull { it.identity == identity }
            val inWindow = previous != null && now >= previous.lastFailureAtMillis && now - previous.lastFailureAtMillis <= FAILURE_WINDOW_MILLIS
            val count = if (inWindow) minOf(FAILURE_THRESHOLD, previous!!.consecutiveFailures + 1) else 1
            val first = if (inWindow) previous!!.firstFailureAtMillis else now
            val nextRecord = NativeSkillFailureRecord(identity, count, first, now, count >= FAILURE_THRESHOLD)
            val next = (active.filterNot { it.identity == identity } + nextRecord)
                .sortedWith(compareBy({ it.identity.skillId }, { it.identity.skillVersion }, { it.identity.skillDigest }))
            if (!writeState(boundary, next)) {
                unavailableScopes += failureScope(binding, boundary)
                return@withAccountBoundaryLock NativeSkillExecutionDecision.STORE_UNAVAILABLE
            }
            if (nextRecord.disabled) NativeSkillExecutionDecision.DISABLED else NativeSkillExecutionDecision.ALLOWED
        }

    /** A successful exact-version execution clears its consecutive-failure history. */
    fun recordSuccess(binding: TriggerKeyBinding, boundary: ActiveAccountBoundary): Boolean =
        withAccountBoundaryLock {
            if (boundaryStore.read() != boundary) return@withAccountBoundaryLock false
            val current = readState(boundary) ?: return@withAccountBoundaryLock false
            val identity = NativeSkillFailureIdentity.from(binding)
            if (current.none { it.identity == identity }) return@withAccountBoundaryLock true
            writeState(boundary, current.filterNot { it.identity == identity })
        }

    fun clear(): Boolean = withAccountBoundaryLock {
        unavailableScopes.clear()
        preferences.edit().clear().commit()
    }

    private fun readState(boundary: ActiveAccountBoundary): List<NativeSkillFailureRecord>? {
        val serialized = preferences.getString(ACTIVE, null) ?: return emptyList()
        if (preferences.getString(OWNER, null) != boundary.ownerSubject || preferences.getInt(EPOCH, 0) != boundary.sessionEpoch) {
            // A new exact owner/session starts with no inherited failures.
            return emptyList()
        }
        return NativeSkillFailureCodec.decode(serialized)
    }

    private fun writeState(boundary: ActiveAccountBoundary, records: List<NativeSkillFailureRecord>): Boolean {
        if (forceWriteFailureForTesting || boundaryStore.read() != boundary || records.size > MAX_RECORDS) return false
        val encoded = NativeSkillFailureCodec.encode(records)
        if (encoded.length > MAX_SERIALIZED_BYTES) return false
        return preferences.edit()
            .putString(ACTIVE, encoded)
            .putString(OWNER, boundary.ownerSubject)
            .putInt(EPOCH, boundary.sessionEpoch)
            .commit()
    }

    internal fun corruptForTesting() = preferences.edit().putString(ACTIVE, "corrupt").commit()

    internal fun failWritesForTesting() = withAccountBoundaryLock { forceWriteFailureForTesting = true }

    private fun failureScope(binding: TriggerKeyBinding, boundary: ActiveAccountBoundary): String =
        listOf(boundary.ownerSubject, boundary.sessionEpoch, binding.skillId, binding.skillVersion, binding.skillDigest).joinToString("\u0000")

    companion object {
        internal const val FAILURE_THRESHOLD = 3
        internal const val FAILURE_WINDOW_MILLIS = 10L * 60L * 1_000L
        private const val PREFERENCES = "mobile_ai_keyboard_native_skill_failures_v1"
        private const val ACTIVE = "active"
        private const val OWNER = "owner_subject"
        private const val EPOCH = "session_epoch"
        private const val MAX_RECORDS = 32
        private const val MAX_SERIALIZED_BYTES = 16 * 1024
    }
}

internal object NativeSkillFailureCodec {
    private const val PREFIX = "native-skill-failures-v1"
    private fun part(value: String): String = Base64.getUrlEncoder().withoutPadding().encodeToString(value.toByteArray(StandardCharsets.UTF_8))
    private fun unpart(value: String): String = String(Base64.getUrlDecoder().decode(value), StandardCharsets.UTF_8)

    fun encode(records: List<NativeSkillFailureRecord>): String {
        val body = records.joinToString("\n") { record ->
            listOf(
                record.identity.skillId,
                record.identity.skillVersion.toString(),
                record.identity.skillDigest,
                record.consecutiveFailures.toString(),
                record.firstFailureAtMillis.toString(),
                record.lastFailureAtMillis.toString(),
                if (record.disabled) "1" else "0",
            ).joinToString("\t", transform = ::part)
        }
        val payload = if (body.isEmpty()) PREFIX else "$PREFIX\n$body"
        return "$payload\n#${TextFingerprint.of(payload)}"
    }

    fun decode(serialized: String): List<NativeSkillFailureRecord>? = runCatching {
        if (serialized.length > 16 * 1024) return null
        val lines = serialized.split('\n')
        if (lines.size < 2 || lines.first() != PREFIX || !lines.last().startsWith("#")) return null
        val payload = lines.dropLast(1).joinToString("\n")
        if (lines.last() != "#${TextFingerprint.of(payload)}") return null
        val records = lines.drop(1).dropLast(1).filter { it.isNotEmpty() }.map { line ->
            val fields = line.split('\t').map(::unpart)
            if (fields.size != 7) error("field count")
            val identity = NativeSkillFailureIdentity(fields[0], fields[1].toInt(), fields[2])
            val disabled = when (fields[6]) { "0" -> false; "1" -> true; else -> error("disabled") }
            NativeSkillFailureRecord(identity, fields[3].toInt(), fields[4].toLong(), fields[5].toLong(), disabled)
        }
        if (records.size > 32 || records.distinctBy { it.identity }.size != records.size) return null
        if (records.any {
                it.identity.skillId.isBlank() || it.identity.skillId.length > 160 || it.identity.skillVersion < 1 ||
                    !it.identity.skillDigest.matches(Regex("sha256:[0-9a-f]{64}")) ||
                    it.consecutiveFailures !in 1..NativeSkillFailureStore.FAILURE_THRESHOLD ||
                    it.firstFailureAtMillis < 0 || it.lastFailureAtMillis < it.firstFailureAtMillis ||
                    it.disabled != (it.consecutiveFailures >= NativeSkillFailureStore.FAILURE_THRESHOLD)
            }) return null
        records
    }.getOrNull()
}
