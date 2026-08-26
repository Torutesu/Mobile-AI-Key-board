package com.torutesu.mobileaikeyboard.core

import java.nio.charset.StandardCharsets
import java.util.Base64

/**
 * Device-local physical key contracts. These objects deliberately contain only
 * Skill metadata: no prompt, editor text, account data, token, or receipt.
 *
 * This is the Android native projection. Its digest is intentionally verified
 * locally; cross-language wire/canonical parity with the shared TypeScript
 * package remains not_proven until shared golden vectors are introduced.
 */
enum class ShortcutKeyCode(val wireValue: String) {
    A("KeyA"), B("KeyB"), C("KeyC"), D("KeyD"), E("KeyE"), F("KeyF"), G("KeyG"), H("KeyH"), I("KeyI"), J("KeyJ"),
    K("KeyK"), L("KeyL"), M("KeyM"), N("KeyN"), O("KeyO"), P("KeyP"), Q("KeyQ"), R("KeyR"), S("KeyS"), T("KeyT"),
    U("KeyU"), V("KeyV"), W("KeyW"), X("KeyX"), Y("KeyY"), Z("KeyZ");

    companion object {
        fun parse(value: String): ShortcutKeyCode? = values().firstOrNull { it.wireValue == value }
        fun normalize(value: String): String = "Key${value.removePrefix("Key").removePrefix("KEY").uppercase()}"
        fun displayLabel(value: String): String = value.removePrefix("Key").uppercase()
    }
}

const val LATIN_QWERTY_V1 = "latin_qwerty_v1"
const val SHORTCUT_SCHEMA_VERSION = 1
const val SHORTCUT_MAX_BINDINGS = 26

data class TriggerKeyBinding(
    val bindingId: String,
    val skillId: String,
    val skillVersion: Int,
    val skillDigest: String,
    val layoutId: String = LATIN_QWERTY_V1,
    val keyCode: String,
    val skillName: String,
    val accessibleLabel: String = skillName,
    val enabled: Boolean = true,
    val order: Int = 0,
)

/** The only Skills the Android IME can execute without a host/provider handoff. */
object ExecutableLocalSkills {
    const val POLITE_REWRITE_ID = "local.polite-rewrite"
    const val PUNCTUATION_POLISH_ID = "local.punctuation-polish"
    const val VERSION = 1

    val ids: Set<String> = setOf(POLITE_REWRITE_ID, PUNCTUATION_POLISH_ID)

    fun canExecute(skillId: String, skillVersion: Int): Boolean =
        skillId in ids && skillVersion == VERSION

    fun isExecutable(binding: TriggerKeyBinding): Boolean =
        canExecute(binding.skillId, binding.skillVersion)
}

data class ShortcutSnapshot(
    val schemaVersion: Int = SHORTCUT_SCHEMA_VERSION,
    val generation: Long = 0,
    val layoutId: String = LATIN_QWERTY_V1,
    val bindings: List<TriggerKeyBinding> = emptyList(),
    val digest: String = ShortcutSnapshotCanonical.digest(schemaVersion, generation, layoutId, bindings),
) {
    fun bindingFor(keyCode: String): TriggerKeyBinding? = bindings.firstOrNull {
        it.layoutId == layoutId && it.keyCode == ShortcutKeyCode.normalize(keyCode) && it.enabled
    }

    fun isValid(): Boolean = ShortcutSnapshotValidator.validate(this) == null

    companion object {
        fun empty() = ShortcutSnapshot()
    }
}

data class ShortcutActivation(
    val bindingId: String,
    val skillId: String,
    val skillVersion: Int,
    val skillDigest: String,
    val snapshotGeneration: Long,
    val layoutId: String,
)

object ShortcutSnapshotCanonical {
    private fun q(value: String): String = value
        .replace("\\", "\\\\")
        .replace("|", "\\|")
        .replace("\n", "\\n")

    /** Stable, content-free representation used for the snapshot digest. */
    fun payload(schemaVersion: Int, generation: Long, layoutId: String, bindings: List<TriggerKeyBinding>): String =
        buildString {
            append("schema=").append(schemaVersion).append('|')
            append("generation=").append(generation).append('|')
            append("layout=").append(q(layoutId)).append('|')
            bindings.sortedWith(compareBy<TriggerKeyBinding> { it.keyCode }.thenBy { it.bindingId }).forEach { b ->
                append("binding=")
                    .append(q(b.bindingId)).append(',').append(q(b.skillId)).append(',')
                    .append(b.skillVersion).append(',').append(q(b.skillDigest)).append(',')
                    .append(q(b.layoutId)).append(',').append(q(b.keyCode)).append(',')
                    .append(q(b.skillName)).append(',').append(q(b.accessibleLabel)).append(',')
                    .append(if (b.enabled) '1' else '0').append(',').append(b.order).append('|')
            }
        }

    fun digest(schemaVersion: Int, generation: Long, layoutId: String, bindings: List<TriggerKeyBinding>): String =
        "sha256:${TextFingerprint.of(payload(schemaVersion, generation, layoutId, bindings))}"
}

object ShortcutSnapshotValidator {
    private const val MAX_LABEL_CODE_POINTS = 80
    private const val MAX_ID_LENGTH = 160

    fun validate(snapshot: ShortcutSnapshot): String? {
        if (snapshot.schemaVersion != SHORTCUT_SCHEMA_VERSION) return "unsupported schema"
        if (snapshot.layoutId != LATIN_QWERTY_V1) return "unsupported layout"
        if (snapshot.generation < 0) return "invalid generation"
        if (snapshot.bindings.size > SHORTCUT_MAX_BINDINGS) return "too many bindings"
        if (snapshot.bindings.any { validateBinding(it, snapshot.layoutId) != null }) return "invalid binding"
        val enabled = snapshot.bindings.filter { it.enabled }
        if (enabled.map { it.keyCode }.distinct().size != enabled.size) return "key conflict"
        if (enabled.map { it.bindingId }.distinct().size != enabled.size) return "binding conflict"
        val expected = ShortcutSnapshotCanonical.digest(snapshot.schemaVersion, snapshot.generation, snapshot.layoutId, snapshot.bindings)
        if (snapshot.digest != expected) return "digest mismatch"
        return null
    }

    private fun validateBinding(binding: TriggerKeyBinding, snapshotLayout: String): String? {
        if (binding.layoutId != snapshotLayout || ShortcutKeyCode.parse(binding.keyCode) == null) return "key/layout"
        if (binding.bindingId.isBlank() || binding.skillId.isBlank() || binding.skillVersion < 1) return "identity"
        if (binding.bindingId.length > MAX_ID_LENGTH || binding.skillId.length > MAX_ID_LENGTH) return "id length"
        if (!binding.skillDigest.startsWith("sha256:") || binding.skillDigest.length != 71) return "skill digest"
        if (binding.skillName.isBlank() || binding.skillName.codePointCount(0, binding.skillName.length) > MAX_LABEL_CODE_POINTS) return "label"
        if (binding.accessibleLabel.isBlank() || binding.accessibleLabel.codePointCount(0, binding.accessibleLabel.length) > MAX_LABEL_CODE_POINTS) return "accessible label"
        if (binding.order < 0 || binding.order >= SHORTCUT_MAX_BINDINGS) return "order"
        if (!ExecutableLocalSkills.isExecutable(binding)) return "skill_not_executable_on_ime"
        return null
    }
}

sealed interface ShortcutEditResult {
    data class Success(val snapshot: ShortcutSnapshot) : ShortcutEditResult
    data class Rejected(val reason: String) : ShortcutEditResult
}

/** Pure host-side editor. Every mutation produces one complete new snapshot. */
object ShortcutRegistry {
    fun add(current: ShortcutSnapshot, binding: TriggerKeyBinding): ShortcutEditResult =
        mutate(current) {
            val normalizedKey = ShortcutKeyCode.normalize(binding.keyCode)
            if (ShortcutKeyCode.parse(normalizedKey) == null) return@mutate null to "unsupported_key"
            if (it.any { existing -> existing.bindingId == binding.bindingId }) return@mutate null to "binding_id_conflict"
            if (it.any { existing -> existing.enabled && existing.keyCode == normalizedKey }) return@mutate null to "key_occupied"
            (it + binding.copy(layoutId = current.layoutId, keyCode = normalizedKey, enabled = true, order = it.size)) to null
        }

    fun reassign(current: ShortcutSnapshot, bindingId: String, keyCode: String): ShortcutEditResult =
        mutate(current) {
            val normalized = ShortcutKeyCode.normalize(keyCode)
            if (ShortcutKeyCode.parse(normalized) == null) return@mutate null to "unsupported_key"
            if (it.any { existing -> existing.enabled && existing.keyCode == normalized && existing.bindingId != bindingId }) return@mutate null to "key_occupied"
            if (it.none { existing -> existing.bindingId == bindingId }) return@mutate null to "binding_not_found"
            it.map { existing -> if (existing.bindingId == bindingId) existing.copy(keyCode = normalized) else existing } to null
        }

    fun remove(current: ShortcutSnapshot, bindingId: String): ShortcutEditResult =
        mutate(current) { list -> if (list.none { it.bindingId == bindingId }) null to "binding_not_found" else (list.filterNot { it.bindingId == bindingId }.mapIndexed { index, item -> item.copy(order = index) } to null) }

    fun setEnabled(current: ShortcutSnapshot, bindingId: String, enabled: Boolean): ShortcutEditResult =
        mutate(current) { list -> if (list.none { it.bindingId == bindingId }) null to "binding_not_found" else (list.map { if (it.bindingId == bindingId) it.copy(enabled = enabled) else it } to null) }

    private fun mutate(current: ShortcutSnapshot, operation: (List<TriggerKeyBinding>) -> Pair<List<TriggerKeyBinding>?, String?>): ShortcutEditResult {
        if (!current.isValid()) return ShortcutEditResult.Rejected("current_snapshot_invalid")
        val (nextBindings, error) = operation(current.bindings)
        if (nextBindings == null) return ShortcutEditResult.Rejected(error ?: "invalid")
        if (nextBindings.size > SHORTCUT_MAX_BINDINGS) return ShortcutEditResult.Rejected("quota")
        val next = ShortcutSnapshot(
            schemaVersion = current.schemaVersion,
            generation = current.generation + 1,
            layoutId = current.layoutId,
            bindings = nextBindings,
        )
        return ShortcutSnapshotValidator.validate(next)?.let { ShortcutEditResult.Rejected(it) }
            ?: ShortcutEditResult.Success(next)
    }
}

/** Long-press policy is pure so threshold/cancel behavior can be unit tested. */
class ShortcutGestureStateMachine(
    private val thresholdMs: Long = 450,
    private val movementLimitDp: Float = 12f,
) {
    private var downAt: Long? = null
    private var cancelled = false
    fun down(atMs: Long) { downAt = atMs; cancelled = false }
    fun move(distanceDp: Float) { if (distanceDp > movementLimitDp) cancelled = true }
    fun up(atMs: Long): Boolean {
        val fired = !cancelled && downAt != null && atMs - downAt!! >= thresholdMs
        downAt = null
        cancelled = false
        return fired
    }
    fun cancel() { downAt = null; cancelled = true }
}

/**
 * Content-free, private-mode persistence shared by host and IME. The active
 * value is committed only after the previous valid value has been copied to a
 * last-known-good slot; readers validate schema, generation and digest.
 */
class ShortcutSnapshotStore(context: android.content.Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES, android.content.Context.MODE_PRIVATE)

    @Synchronized fun read(): ShortcutSnapshot {
        val active = preferences.getString(ACTIVE, null)?.let(ShortcutSnapshotCodec::decode)
        val previous = preferences.getString(LAST_GOOD, null)?.let(ShortcutSnapshotCodec::decode)
        return ShortcutSnapshotRecovery.select(active, previous)
    }

    @Synchronized fun publish(candidate: ShortcutSnapshot): Boolean {
        if (!candidate.isValid() || candidate.bindings.size > SHORTCUT_MAX_BINDINGS) return false
        val current = read()
        if (candidate.generation <= current.generation) return false
        val encoded = ShortcutSnapshotCodec.encode(candidate)
        if (encoded.length > MAX_SERIALIZED_BYTES) return false
        val editor = preferences.edit()
        if (current.isValid()) editor.putString(LAST_GOOD, ShortcutSnapshotCodec.encode(current))
        editor.putString(ACTIVE, encoded)
        return editor.commit()
    }

    companion object {
        private const val PREFERENCES = "mobile_ai_keyboard_shortcuts_v1"
        private const val ACTIVE = "active"
        private const val LAST_GOOD = "last_good"
        private const val MAX_SERIALIZED_BYTES = 32 * 1024
    }
}

/** Pure migration/recovery policy, shared by the store and unit tests. */
internal object ShortcutSnapshotRecovery {
    fun select(active: ShortcutSnapshot?, previous: ShortcutSnapshot?): ShortcutSnapshot = when {
        active?.isValid() == true -> active
        previous?.isValid() == true -> previous
        else -> ShortcutSnapshot.empty()
    }
}

internal object ShortcutSnapshotCodec {
    private const val PREFIX = "shortcut-v1"
    private fun encodePart(value: String): String = Base64.getUrlEncoder().withoutPadding().encodeToString(value.toByteArray(StandardCharsets.UTF_8))
    private fun decodePart(value: String): String = String(Base64.getUrlDecoder().decode(value), StandardCharsets.UTF_8)

    fun encode(snapshot: ShortcutSnapshot): String = buildString {
        append(PREFIX).append('|').append(snapshot.schemaVersion).append('|').append(snapshot.generation).append('|')
        append(encodePart(snapshot.layoutId)).append('|').append(encodePart(snapshot.digest)).append('|').append(snapshot.bindings.size)
        snapshot.bindings.forEach { b ->
            append('\n').append(listOf(b.bindingId, b.skillId, b.skillVersion.toString(), b.skillDigest, b.layoutId, b.keyCode, b.skillName, b.accessibleLabel, if (b.enabled) "1" else "0", b.order.toString()).joinToString("\t", transform = ::encodePart))
        }
    }

    fun decode(serialized: String): ShortcutSnapshot? = runCatching {
        if (serialized.length > 32 * 1024) return null
        val lines = serialized.split('\n')
        val header = lines.first().split('|')
        if (header.size != 6 || header[0] != PREFIX) return null
        val count = header[5].toInt()
        if (count !in 0..SHORTCUT_MAX_BINDINGS || lines.size != count + 1) return null
        val bindings = lines.drop(1).map { line ->
            val fields = line.split('\t').map(::decodePart)
            if (fields.size != 10) throw IllegalArgumentException("binding field count")
            val enabled = when (fields[8]) { "1" -> true; "0" -> false; else -> throw IllegalArgumentException("enabled") }
            TriggerKeyBinding(fields[0], fields[1], fields[2].toInt(), fields[3], fields[4], fields[5], fields[6], fields[7], enabled, fields[9].toInt())
        }
        ShortcutSnapshot(header[1].toInt(), header[2].toLong(), decodePart(header[3]), bindings, decodePart(header[4]))
    }.getOrNull()
}
