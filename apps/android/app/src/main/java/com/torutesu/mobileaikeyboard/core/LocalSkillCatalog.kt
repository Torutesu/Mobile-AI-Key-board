package com.torutesu.mobileaikeyboard.core

import android.content.Context
import java.nio.charset.StandardCharsets
import java.util.Base64

/**
 * The only executable implementations available to the IME. A Skill's
 * instruction is metadata and is never interpreted as code or passed to a
 * provider. Every installed entry is pinned by (id, version, digest).
 */
enum class LocalSkillExecutorKind {
    POLITE_REWRITE,
    PUNCTUATION_POLISH,
    PRIVATE_LOCAL_REWRITE,
}

data class LocalSkillDescriptor(
    val skillId: String,
    val skillVersion: Int,
    val skillDigest: String,
    val skillName: String,
    val executor: LocalSkillExecutorKind,
)

object LocalSkillRegistry {
    private val installed = linkedMapOf<String, LocalSkillDescriptor>()
    private val builtinKeys = mutableSetOf<String>()

    init {
        listOf(
            LocalSkillDescriptor(
                ExecutableLocalSkills.POLITE_REWRITE_ID,
                ExecutableLocalSkills.VERSION,
                "sha256:${TextFingerprint.of("local.polite-rewrite:v1")}",
                "丁寧に書き換え",
                LocalSkillExecutorKind.POLITE_REWRITE,
            ),
            LocalSkillDescriptor(
                ExecutableLocalSkills.PUNCTUATION_POLISH_ID,
                ExecutableLocalSkills.VERSION,
                "sha256:${TextFingerprint.of("local.punctuation-polish:v1")}",
                "句読点を整える",
                LocalSkillExecutorKind.PUNCTUATION_POLISH,
            ),
        ).forEach { installed[key(it)] = it; builtinKeys += key(it) }
    }

    private fun key(descriptor: LocalSkillDescriptor): String = "${descriptor.skillId}#${descriptor.skillVersion}"

    @Synchronized
    fun install(descriptor: LocalSkillDescriptor): Boolean {
        if (!isWellFormed(descriptor)) return false
        val existing = installed[key(descriptor)]
        if (existing != null) return existing == descriptor
        installed[key(descriptor)] = descriptor
        return true
    }

    @Synchronized
    fun installAll(descriptors: Iterable<LocalSkillDescriptor>): Boolean {
        installed.keys.filterNot { it in builtinKeys }.toList().forEach { installed.remove(it) }
        descriptors.forEach {
            if (!install(it)) {
                clearInstalled()
                return false
            }
        }
        return true
    }

    @Synchronized
    fun clearInstalled() {
        installed.keys.filterNot { it in builtinKeys }.toList().forEach { installed.remove(it) }
    }

    @Synchronized
    fun all(): List<LocalSkillDescriptor> = installed.values.toList()

    @Synchronized
    fun resolve(binding: TriggerKeyBinding): LocalSkillDescriptor? = installed["${binding.skillId}#${binding.skillVersion}"]
        ?.takeIf { it.skillDigest == binding.skillDigest }

    fun execute(binding: TriggerKeyBinding, input: String): String? {
        return executeResult(binding, input)?.rewritten
    }

    fun executeResult(binding: TriggerKeyBinding, input: String): RewriteResult? {
        val descriptor = resolve(binding) ?: return null
        // This switch is intentionally closed. The user-authored instruction,
        // schema and fixture are never evaluated as Kotlin, shell, URL, or LLM input.
        return when (descriptor.executor) {
            LocalSkillExecutorKind.POLITE_REWRITE,
            LocalSkillExecutorKind.PRIVATE_LOCAL_REWRITE -> LocalPoliteRewriteService().rewrite(input)
            LocalSkillExecutorKind.PUNCTUATION_POLISH -> LocalPoliteRewriteService().polishPunctuation(input)
        }
    }

    fun fromPrivateVersion(version: PrivateSkillVersion): LocalSkillDescriptor? {
        val descriptor = LocalSkillDescriptor(
            skillId = version.skillId,
            skillVersion = version.version,
            skillDigest = version.digest,
            skillName = version.skillName,
            executor = LocalSkillExecutorKind.PRIVATE_LOCAL_REWRITE,
        )
        return descriptor.takeIf(::isWellFormed)
    }

    internal fun isWellFormed(descriptor: LocalSkillDescriptor): Boolean =
        descriptor.skillId.isNotBlank() && descriptor.skillId.length <= 160 &&
            descriptor.skillVersion >= 1 && descriptor.skillDigest.matches(SHA256) &&
            descriptor.skillName.isNotBlank() && descriptor.skillName.codePointCount(0, descriptor.skillName.length) <= 80

    private val SHA256 = Regex("sha256:[0-9a-f]{64}")
}

/** Device-local catalog for explicit "Add To My Keyboard" installs. */
class InstalledSkillStore(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    private val boundaryStore = AccountBoundaryStore(context.applicationContext)

    fun read(): List<LocalSkillDescriptor> = withAccountBoundaryLock {
        val boundary = boundaryStore.read()
        val storedOwner = preferences.getString(OWNER, null)
        val storedEpoch = preferences.getInt(EPOCH, 0)
        if (boundary == null || storedOwner != boundary.ownerSubject || storedEpoch != boundary.sessionEpoch) {
            LocalSkillRegistry.installAll(emptyList())
            return@withAccountBoundaryLock emptyList()
        }
        val entries = LocalSkillCatalogCodec.decode(preferences.getString(ACTIVE, null).orEmpty())
        // Reading is also the restart boundary: an empty/corrupt catalog must
        // remove private executors left in this process by an older session.
        if (!LocalSkillRegistry.installAll(entries)) return@withAccountBoundaryLock emptyList()
        entries
    }

    fun install(version: PrivateSkillVersion): Boolean = withAccountBoundaryLock {
        val boundary = boundaryStore.read() ?: return@withAccountBoundaryLock false
        if (version.ownerSubject != boundary.ownerSubject || version.sessionEpoch != boundary.sessionEpoch) return@withAccountBoundaryLock false
        val descriptor = LocalSkillRegistry.fromPrivateVersion(version) ?: return@withAccountBoundaryLock false
        val current = read()
        val sameIdentity = current.filter { it.skillId == descriptor.skillId && it.skillVersion == descriptor.skillVersion }
        if (sameIdentity.any { it != descriptor }) return@withAccountBoundaryLock false
        val next = if (descriptor in current) current else current + descriptor
        val encoded = LocalSkillCatalogCodec.encode(next)
        if (encoded.length > MAX_SERIALIZED_BYTES) return@withAccountBoundaryLock false
        if (!preferences.edit()
                .putString(ACTIVE, encoded)
                .putString(OWNER, boundary.ownerSubject)
                .putInt(EPOCH, boundary.sessionEpoch)
                .commit()
        ) return@withAccountBoundaryLock false
        LocalSkillRegistry.install(descriptor)
    }

    fun clear(): Boolean = withAccountBoundaryLock {
        // Process-local execution authority is removed even when persistent
        // deletion reports failure.
        LocalSkillRegistry.clearInstalled()
        preferences.edit().remove(ACTIVE).remove(OWNER).remove(EPOCH).commit()
    }

    companion object {
        private const val PREFERENCES = "mobile_ai_keyboard_installed_skills_v1"
        private const val ACTIVE = "active"
        private const val OWNER = "owner_subject"
        private const val EPOCH = "session_epoch"
        private const val MAX_SERIALIZED_BYTES = 32 * 1024
    }
}

internal object LocalSkillCatalogCodec {
    private const val PREFIX = "local-skill-v1"

    private fun encodePart(value: String): String = Base64.getUrlEncoder().withoutPadding().encodeToString(value.toByteArray(StandardCharsets.UTF_8))
    private fun decodePart(value: String): String = String(Base64.getUrlDecoder().decode(value), StandardCharsets.UTF_8)

    fun encode(entries: List<LocalSkillDescriptor>): String = buildString {
        append(PREFIX)
        entries.sortedWith(compareBy<LocalSkillDescriptor> { it.skillId }.thenBy { it.skillVersion }).forEach { entry ->
            append('\n').append(listOf(entry.skillId, entry.skillVersion.toString(), entry.skillDigest, entry.skillName, entry.executor.name).joinToString("\t", transform = ::encodePart))
        }
    }

    fun decode(serialized: String): List<LocalSkillDescriptor> {
        if (serialized.isBlank()) return emptyList()
        return runCatching {
            val lines = serialized.split('\n')
            if (lines.firstOrNull() != PREFIX || lines.size > SHORTCUT_MAX_BINDINGS + 1) return emptyList()
            val entries = lines.drop(1).map { line ->
                val fields = line.split('\t').map(::decodePart)
                if (fields.size != 5) error("catalog field count")
                LocalSkillDescriptor(fields[0], fields[1].toInt(), fields[2], fields[3], LocalSkillExecutorKind.valueOf(fields[4]))
            }
            if (entries.size != entries.distinctBy { "${it.skillId}#${it.skillVersion}" }.size || entries.any { !LocalSkillRegistry.isWellFormed(it) }) return emptyList()
            entries
        }.getOrDefault(emptyList())
    }
}
