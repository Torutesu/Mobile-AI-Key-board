package com.torutesu.mobileaikeyboard.core

import java.nio.charset.StandardCharsets
import java.security.MessageDigest

/** W6 local-only private Skill builder. It never invokes an LLM, provider, or network. */
enum class SkillBuilderPhase { IDLE, OUTCOME, MISSING_INFO, DRAFT, VALIDATING, READY_TO_TEST, TEST_RESULT, DEPLOY_REVIEW, DEPLOYED, FAILED }

data class PrivateSkillDraft(
    val skillId: String = "private.keyboard.skill",
    val desiredOutcome: String = "",
    val name: String = "",
    val icon: String = "sparkles",
    val plainInstruction: String = "",
    val advancedSchema: String = "{\"trigger\":{\"type\":\"manual\"},\"input\":{\"type\":\"text\"},\"output\":{\"type\":\"text\"},\"tools\":[],\"risk\":\"R1\",\"confirmation\":\"preview\",\"retention\":\"none\",\"test\":{\"input\":\"fixture input\",\"expected\":\"fixture output\"}}",
    val policy: String = "private; local fixture only; no network; no LLM; no provider",
    val bindingId: String = "keyboard-private",
    val quotaPerDay: Int = 20,
    val fixtureInput: String = "fixture input",
    val fixtureExpected: String = "fixture output",
)

data class PrivateSkillVersion(val version: Int, val digest: String, val createdAt: String, val skillName: String = "", val ownerSubject: String = "", val sessionEpoch: Int = 0, val skillId: String = "", val bindingId: String = "")
data class InstalledSkillBinding(val bindingId: String, val skillName: String, val pinned: PrivateSkillVersion, val skillId: String = "")
data class PrivateSkillShare(val digest: String, val recipient: String, val expiresAt: String, val ownerSubject: String, val sessionEpoch: Int, val revoked: Boolean = false)
data class SkillDryRunReceipt(val summary: String, val passed: Boolean, val checkedFields: List<String>, val failureClass: String? = null)
data class SkillBuilderState(
    val phase: SkillBuilderPhase = SkillBuilderPhase.IDLE,
    val draft: PrivateSkillDraft = PrivateSkillDraft(),
    val version: PrivateSkillVersion? = null,
    val published: List<PrivateSkillVersion> = emptyList(),
    val shares: List<PrivateSkillShare> = emptyList(),
    val confirmedDigest: String? = null,
    val dryRun: SkillDryRunReceipt? = null,
    val installed: List<InstalledSkillBinding> = listOf(InstalledSkillBinding("legacy-fixture-binding", "既存fixture Skill", PrivateSkillVersion(1, "sha256:fixture", "2026-08-26T08:00:00Z"))),
    val error: String? = null,
    val publicPublishEnabled: Boolean = false,
    val estimatedCost: String = "0円（端末内fixture）",
    val quotaUsed: Int = 0,
    val quotaReserved: Int = 0,
    val ownerSubject: String = "",
    val sessionEpoch: Int = 0,
)

sealed interface SkillBuilderEvent {
    data object Open : SkillBuilderEvent
    data class UpdateDraft(val draft: PrivateSkillDraft) : SkillBuilderEvent
    data object ContinueToDraft : SkillBuilderEvent
    data object Validate : SkillBuilderEvent
    data object RunDryTest : SkillBuilderEvent
    data object OpenDeployReview : SkillBuilderEvent
    data class ConfirmDeploy(val digest: String) : SkillBuilderEvent
    data class UpgradeBinding(val digest: String) : SkillBuilderEvent
    data class CreateShare(val recipient: String, val expiresAt: String) : SkillBuilderEvent
    data class RevokeShare(val recipient: String) : SkillBuilderEvent
    data object Cancel : SkillBuilderEvent
}

object SkillBuilderValidator {
    private val injection = Regex("(?i)(ignore\\s+(all\\s+)?previous|system\\s*:|developer\\s*:|<script|javascript:|\\$\\{)")
    fun missing(draft: PrivateSkillDraft): List<String> = buildList {
        if (draft.desiredOutcome.isBlank()) add("desired outcome")
        if (draft.name.isBlank()) add("skill name")
        if (draft.plainInstruction.isBlank()) add("plain-language instruction")
        if (draft.bindingId.isBlank()) add("binding")
        if (draft.fixtureInput.isBlank() || draft.fixtureExpected.isBlank()) add("fixture test input/expected")
    }
    fun validate(draft: PrivateSkillDraft, installed: List<InstalledSkillBinding>): String? {
        val missing = missing(draft)
        if (missing.isNotEmpty()) return "不足: ${missing.joinToString()}"
        if (draft.name.length > 40) return "Skill名は40文字以内です"
        if (draft.icon !in setOf("sparkles", "wand", "edit", "translate", "check")) return "icon identifierが未許可です"
        if (draft.quotaPerDay !in 1..100) return "quotaは1〜100です"
        if (injection.containsMatchIn(draft.desiredOutcome) || injection.containsMatchIn(draft.plainInstruction) || injection.containsMatchIn(draft.advancedSchema)) return "命令注入らしき文字列を拒否しました"
        val schemaError = StrictSkillSchema.validate(draft.advancedSchema, draft.fixtureInput, draft.fixtureExpected)
        if (schemaError != null) return schemaError
        if (!draft.policy.contains("private") || !draft.policy.contains("no network") || !draft.policy.contains("no LLM") || !draft.policy.contains("no provider")) return "private/local-only policyが必要です"
        if (draft.bindingId != "keyboard-private" || draft.bindingId in setOf("ime-system", "accessibility-system")) return "許可されたprivate bindingではありません"
        val sameName = installed.firstOrNull { it.skillName.equals(draft.name, ignoreCase = true) }
        if (sameName != null && sameName.bindingId != draft.bindingId) return "同名Skillのbindingが一致しません"
        if (installed.any { it.bindingId == draft.bindingId && it != sameName }) return "binding conflict: ${draft.bindingId}"
        return null
    }
    fun canonical(draft: PrivateSkillDraft, version: Int, owner: String = "", epoch: Int = 0): String {
        fun q(value: String) = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\""
        return "{" + listOf(
            "\"binding\":${q(draft.bindingId)}", "\"epoch\":$epoch", "\"fixtureExpected\":${q(draft.fixtureExpected)}", "\"fixtureInput\":${q(draft.fixtureInput)}", "\"skillId\":${q(draft.skillId)}",
            "\"icon\":${q(draft.icon)}", "\"name\":${q(draft.name)}", "\"operation\":${q("private_skill.deploy")}",
            "\"outcome\":${q(draft.desiredOutcome)}", "\"owner\":${q(owner)}", "\"plain\":${q(draft.plainInstruction)}", "\"policy\":${q(draft.policy)}",
            "\"public\":false", "\"quota\":${draft.quotaPerDay}", "\"schema\":${q(draft.advancedSchema)}", "\"version\":$version",
        ).joinToString(",") + "}"
    }
    fun digest(draft: PrivateSkillDraft, version: Int, owner: String = "", epoch: Int = 0): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(canonical(draft, version, owner, epoch).toByteArray(StandardCharsets.UTF_8))
        return "sha256:" + bytes.joinToString("") { "%02x".format(it) }
    }
}

private sealed interface SchemaValue { data class Obj(val fields: Map<String, SchemaValue>) : SchemaValue; data class Arr(val values: List<SchemaValue>) : SchemaValue; data class Str(val value: String) : SchemaValue; data object Bool : SchemaValue; data object Null : SchemaValue }

/** Minimal strict JSON parser used only for the bounded Skill schema; duplicate/unknown keys fail closed. */
private class SchemaParser(private val source: String) {
    private var index = 0
    fun parse(): SchemaValue { val value = value(); ws(); if (index != source.length) error("trailing data"); return value }
    private fun value(): SchemaValue { ws(); if (index >= source.length) error("missing value"); return when (source[index]) { '{' -> obj(); '[' -> arr(); '"' -> SchemaValue.Str(string()); 't' -> literal("true", SchemaValue.Bool); 'n' -> literal("null", SchemaValue.Null); else -> error("only bounded object/string/array/boolean values are allowed") } }
    private fun obj(): SchemaValue.Obj { index++; ws(); val map = linkedMapOf<String, SchemaValue>(); if (peek('}')) { index++; return SchemaValue.Obj(map) }; while (true) { ws(); if (index >= source.length || source[index] != '"') error("object key"); val key = string(); if (map.containsKey(key)) error("duplicate key"); ws(); if (!peek(':')) error("colon"); index++; val parsed = value(); map[key] = parsed; ws(); if (peek('}')) { index++; return SchemaValue.Obj(map) }; if (!peek(',')) error("comma"); index++ } }
    private fun arr(): SchemaValue.Arr { index++; ws(); val list = mutableListOf<SchemaValue>(); if (peek(']')) { index++; return SchemaValue.Arr(list) }; while (true) { list += value(); ws(); if (peek(']')) { index++; return SchemaValue.Arr(list) }; if (!peek(',')) error("comma"); index++ } }
    private fun string(): String { if (!peek('"')) error("string"); index++; val out = StringBuilder(); while (index < source.length) { val c = source[index++]; if (c == '"') return out.toString(); if (c == '\\') { if (index >= source.length) error("escape"); val e = source[index++]; when (e) { '"', '\\', '/' -> out.append(e); 'b' -> out.append('\b'); 'f' -> out.append('\u000c'); 'n' -> out.append('\n'); 'r' -> out.append('\r'); 't' -> out.append('\t'); 'u' -> { if (index + 4 > source.length) error("unicode escape"); val hex = source.substring(index, index + 4); if (!hex.all { it in "0123456789abcdefABCDEF" }) error("unicode escape"); out.append(hex.toInt(16).toChar()); index += 4 }; else -> error("escape") } } else { if (c.code < 0x20) error("control character"); out.append(c) } }; error("unterminated string") }
    private fun literal(text: String, result: SchemaValue): SchemaValue { if (!source.startsWith(text, index)) error("literal"); index += text.length; return result }
    private fun ws() { while (index < source.length && source[index].isWhitespace()) index++ }
    private fun peek(c: Char): Boolean = index < source.length && source[index] == c
    private fun error(message: String): Nothing = throw IllegalArgumentException(message)
}

private object StrictSkillSchema {
    private val top = setOf("trigger", "input", "output", "tools", "risk", "confirmation", "retention", "test")
    fun validate(source: String, fixtureInput: String, fixtureExpected: String): String? {
      return try {
        val root = SchemaParser(source).parse() as? SchemaValue.Obj ?: return "advanced schemaはobjectである必要があります"
        if (root.fields.keys != top) return "advanced schemaに未知または不足fieldがあります"
        val trigger = root.fields["trigger"] as? SchemaValue.Obj ?: return "trigger structureが不正です"
        if (trigger.fields.keys != setOf("type") || (trigger.fields["type"] as? SchemaValue.Str)?.value !in setOf("manual", "keyboard")) return "trigger allowlistが不正です"
        for (key in listOf("input", "output")) { val obj = root.fields[key] as? SchemaValue.Obj ?: return "$key structureが不正です"; if (obj.fields.keys != setOf("type") || (obj.fields["type"] as? SchemaValue.Str)?.value != "text") return "$key typeが不正です" }
        if ((root.fields["tools"] as? SchemaValue.Arr)?.values?.isNotEmpty() == true) return "side-effect toolは許可されていません"
        if ((root.fields["tools"] as? SchemaValue.Arr) == null) return "tools structureが不正です"
        if ((root.fields["risk"] as? SchemaValue.Str)?.value !in setOf("R0", "R1")) return "risk allowlistが不正です"
        if ((root.fields["confirmation"] as? SchemaValue.Str)?.value != "preview") return "confirmationはpreviewのみです"
        if ((root.fields["retention"] as? SchemaValue.Str)?.value != "none") return "retentionはnoneのみです"
        val test = root.fields["test"] as? SchemaValue.Obj ?: return "test structureが不正です"
        if (test.fields.keys != setOf("input", "expected") || test.fields.values.any { it !is SchemaValue.Str }) return "test structureが不正です"
        if ((test.fields["input"] as SchemaValue.Str).value != fixtureInput || (test.fields["expected"] as SchemaValue.Str).value != fixtureExpected) return "schema testとvisible fixtureが一致しません"
        null
      } catch (_: IllegalArgumentException) { "advanced schema JSONが不正です" }
    }
}

object SkillBuilderReducer {
    private const val NOW = "2026-08-26T09:00:00Z"
    fun reduce(state: SkillBuilderState, event: SkillBuilderEvent, account: AccountState, deletion: DeletionState): SkillBuilderState {
        val allowed = account.authStatus == AuthStatus.SIGNED_IN && account.sessionStatus == SessionStatus.ACTIVE && deletion.status != DeletionStatus.COMPLETED
        return when (event) {
            SkillBuilderEvent.Open -> if (allowed) state.copy(phase = SkillBuilderPhase.OUTCOME, ownerSubject = account.displayName ?: "fixture-owner", sessionEpoch = 1, error = null) else state.copy(phase = SkillBuilderPhase.FAILED, error = "アクティブなsessionが必要です。削除完了後は作成できません")
            is SkillBuilderEvent.UpdateDraft -> if (state.phase in setOf(SkillBuilderPhase.OUTCOME, SkillBuilderPhase.MISSING_INFO, SkillBuilderPhase.DRAFT, SkillBuilderPhase.READY_TO_TEST, SkillBuilderPhase.TEST_RESULT, SkillBuilderPhase.DEPLOY_REVIEW)) state.copy(phase = SkillBuilderPhase.DRAFT, draft = event.draft, version = null, confirmedDigest = null, dryRun = null, quotaReserved = 0, error = null) else state
            SkillBuilderEvent.ContinueToDraft -> state.copy(phase = if (SkillBuilderValidator.missing(state.draft).isEmpty()) SkillBuilderPhase.DRAFT else SkillBuilderPhase.MISSING_INFO, error = null)
            SkillBuilderEvent.Validate -> {
                val error = SkillBuilderValidator.validate(state.draft, state.installed)
                if (error == null) state.copy(phase = SkillBuilderPhase.READY_TO_TEST, error = null) else state.copy(phase = SkillBuilderPhase.MISSING_INFO, error = error)
            }
            SkillBuilderEvent.RunDryTest -> if (state.phase == SkillBuilderPhase.READY_TO_TEST) {
                val error = SkillBuilderValidator.validate(state.draft, state.installed)
                val quotaError = if (state.quotaUsed + state.quotaReserved + 1 > state.draft.quotaPerDay) "quota上限を超えるためfixture実行を拒否しました" else null
                if (error == null && quotaError == null) state.copy(phase = SkillBuilderPhase.TEST_RESULT, quotaUsed = state.quotaUsed + 1, quotaReserved = 0, dryRun = SkillDryRunReceipt("fixture dry-run passed for visible input/expected; no external effect", true, listOf("schema", "policy", "static injection", "quota", "fixture input/expected")), error = null)
                else state.copy(phase = SkillBuilderPhase.MISSING_INFO, dryRun = SkillDryRunReceipt("dry-run blocked", false, emptyList(), error ?: quotaError), error = error ?: quotaError)
            } else state
            SkillBuilderEvent.OpenDeployReview -> if (state.phase == SkillBuilderPhase.TEST_RESULT && state.dryRun?.passed == true) {
                val nextVersion = (state.published.filter { it.skillId == state.draft.skillId }.maxOfOrNull { it.version } ?: 0) + 1
                val version = PrivateSkillVersion(nextVersion, SkillBuilderValidator.digest(state.draft, nextVersion, state.ownerSubject, state.sessionEpoch), NOW, state.draft.name, state.ownerSubject, state.sessionEpoch, state.draft.skillId, state.draft.bindingId)
                state.copy(phase = SkillBuilderPhase.DEPLOY_REVIEW, version = version, confirmedDigest = null, error = null)
            } else state.copy(error = "successful dry-runが必要です")
            is SkillBuilderEvent.ConfirmDeploy -> {
                val version = state.version ?: return state.copy(error = "immutable versionがありません。deployを停止しました")
                val valid = state.phase == SkillBuilderPhase.DEPLOY_REVIEW && event.digest == version.digest && SkillBuilderValidator.digest(state.draft, version.version, state.ownerSubject, state.sessionEpoch) == version.digest && version.ownerSubject == (account.displayName ?: "fixture-owner") && version.sessionEpoch == 1 && state.dryRun?.passed == true && allowed
                if (!valid) state.copy(error = "immutable versionまたはsessionが変わりました。deployを停止しました")
                else state.copy(phase = SkillBuilderPhase.DEPLOYED, confirmedDigest = event.digest, published = state.published + version, quotaReserved = 0, error = null)
            }
            is SkillBuilderEvent.UpgradeBinding -> {
                val version = state.published.firstOrNull { it.digest == event.digest }
                val valid = state.phase == SkillBuilderPhase.DEPLOYED && version != null && version.ownerSubject == state.ownerSubject && version.sessionEpoch == state.sessionEpoch && version.skillId == state.draft.skillId && version.bindingId == state.draft.bindingId && state.published.any { it.digest == event.digest }
                if (!valid) state.copy(error = "published version、owner、session epochを確認できません")
                else state.copy(installed = state.installed.filterNot { it.bindingId == state.draft.bindingId } + InstalledSkillBinding(state.draft.bindingId, state.draft.name, version!!, state.draft.skillId))
            }
            is SkillBuilderEvent.CreateShare -> {
                val version = state.version
                val expiry = runCatching { java.time.Instant.parse(event.expiresAt) }.getOrNull()
                val now = java.time.Instant.parse(NOW)
                val validRecipient = event.recipient == event.recipient.trim() && event.recipient.length in 3..254 && !event.recipient.any { it.isWhitespace() } && event.recipient.count { it == '@' } == 1
                val validExpiry = expiry != null && expiry.isAfter(now) && !expiry.isAfter(now.plus(java.time.Duration.ofDays(30)))
                val valid = state.phase == SkillBuilderPhase.DEPLOYED && version != null && validRecipient && validExpiry && version.ownerSubject == state.ownerSubject && version.sessionEpoch == state.sessionEpoch && version.skillId == state.draft.skillId && version.bindingId == state.draft.bindingId
                if (!valid) state.copy(error = "private shareのrecipient、expiry、owner、session epochが不正です")
                else state.copy(shares = state.shares + PrivateSkillShare(version!!.digest, event.recipient, event.expiresAt, state.ownerSubject, state.sessionEpoch), error = null)
            }
            is SkillBuilderEvent.RevokeShare -> state.copy(shares = state.shares.map { if (it.recipient == event.recipient && it.ownerSubject == state.ownerSubject && it.sessionEpoch == state.sessionEpoch) it.copy(revoked = true) else it })
            SkillBuilderEvent.Cancel -> SkillBuilderState(installed = state.installed, published = state.published, shares = state.shares, quotaUsed = state.quotaUsed)
        }
    }
}
