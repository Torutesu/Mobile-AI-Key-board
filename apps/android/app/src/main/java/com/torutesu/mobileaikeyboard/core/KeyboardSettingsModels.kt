package com.torutesu.mobileaikeyboard.core

enum class KeyboardTheme { SYSTEM, LIGHT, DARK, HIGH_CONTRAST }
enum class HapticMode { OFF, KEY_TAP, COMMAND_ONLY }
enum class KeySize { COMPACT, STANDARD, LARGE }
enum class OneHandedMode { OFF, LEFT, RIGHT }
enum class JapaneseWorkflowPack { POLITE, SHORTEN, KEY_POINTS, ABSOLUTE_DATE }
enum class QualificationStatus { NOT_PROVEN, FIXTURE_PASSED, BROAD_FIXTURE_PASSED, CLEARED }
data class QualificationMetrics(val coldP50Ms: Long, val coldP95Ms: Long, val warmP95Ms: Long, val keyP95Ms: Long, val sessions: Int, val crashes: Int) {
    val crashFreeBasisPoints: Int get() = if (sessions <= 0) 0 else ((sessions - crashes).toLong() * 10_000L / sessions).toInt()
}

data class KeyboardSettingsState(
    val schemaVersion: Int = 2,
    val theme: KeyboardTheme = KeyboardTheme.SYSTEM,
    val haptics: HapticMode = HapticMode.KEY_TAP,
    val keySize: KeySize = KeySize.STANDARD,
    val oneHanded: OneHandedMode = OneHandedMode.OFF,
    val workflowPack: JapaneseWorkflowPack = JapaneseWorkflowPack.POLITE,
    val qualificationStatus: QualificationStatus = QualificationStatus.NOT_PROVEN,
    val coldLatencyBucket: String = "not_proven",
    val warmLatencyBucket: String = "not_proven",
    val keyLatencyBucket: String = "not_proven",
    val crashFreeBucket: String = "not_proven",
    val qualificationMetrics: QualificationMetrics? = null,
)

data class ImeConsumableConfig(val theme: KeyboardTheme, val haptics: HapticMode, val keySize: KeySize, val oneHanded: OneHandedMode, val workflowPack: JapaneseWorkflowPack)

sealed interface KeyboardSettingsEvent {
    data class SetTheme(val value: KeyboardTheme) : KeyboardSettingsEvent
    data class SetHaptics(val value: HapticMode) : KeyboardSettingsEvent
    data class SetKeySize(val value: KeySize) : KeyboardSettingsEvent
    data class SetOneHanded(val value: OneHandedMode) : KeyboardSettingsEvent
    data class SelectWorkflowPack(val value: JapaneseWorkflowPack) : KeyboardSettingsEvent
    data object Reset : KeyboardSettingsEvent
    data class MigrateLegacy(val oldVersion: Int) : KeyboardSettingsEvent
    data class RecordFixtureQualification(val metrics: QualificationMetrics) : KeyboardSettingsEvent
    data object ClearQualification : KeyboardSettingsEvent
}

object KeyboardSettingsReducer {
    fun reduce(state: KeyboardSettingsState, event: KeyboardSettingsEvent): KeyboardSettingsState = when (event) {
        is KeyboardSettingsEvent.SetTheme -> state.copy(theme = event.value)
        is KeyboardSettingsEvent.SetHaptics -> state.copy(haptics = event.value)
        is KeyboardSettingsEvent.SetKeySize -> state.copy(keySize = event.value)
        is KeyboardSettingsEvent.SetOneHanded -> state.copy(oneHanded = event.value)
        is KeyboardSettingsEvent.SelectWorkflowPack -> state.copy(workflowPack = event.value)
        KeyboardSettingsEvent.Reset -> KeyboardSettingsState(schemaVersion = 2)
        is KeyboardSettingsEvent.MigrateLegacy -> if (event.oldVersion < 2) state.copy(schemaVersion = 2, haptics = HapticMode.KEY_TAP, keySize = KeySize.STANDARD) else state
        is KeyboardSettingsEvent.RecordFixtureQualification -> {
            val m = event.metrics
            val valid = m.coldP50Ms in 0..60_000 && m.coldP95Ms in 0..60_000 && m.coldP50Ms <= m.coldP95Ms && m.warmP95Ms in 0..60_000 && m.keyP95Ms in 0..60_000 && m.sessions in 1..1_000_000 && m.crashes in 0..m.sessions
            val latency = valid && m.coldP50Ms <= 250 && m.coldP95Ms <= 400 && m.warmP95Ms <= 150 && m.keyP95Ms <= 50
            val status = when { latency && m.crashFreeBasisPoints >= 9_995 -> QualificationStatus.BROAD_FIXTURE_PASSED; latency && m.crashFreeBasisPoints >= 9_980 -> QualificationStatus.FIXTURE_PASSED; else -> QualificationStatus.NOT_PROVEN }
            state.copy(qualificationStatus = status, qualificationMetrics = if (valid) m else null, coldLatencyBucket = if (valid) "p50=${m.coldP50Ms}ms p95=${m.coldP95Ms}ms" else "not_proven", warmLatencyBucket = if (valid) "p95=${m.warmP95Ms}ms" else "not_proven", keyLatencyBucket = if (valid) "p95=${m.keyP95Ms}ms" else "not_proven", crashFreeBucket = if (valid) "${m.crashFreeBasisPoints}bp" else "not_proven")
        }
        KeyboardSettingsEvent.ClearQualification -> state.copy(qualificationStatus = QualificationStatus.CLEARED, qualificationMetrics = null, coldLatencyBucket = "not_proven", warmLatencyBucket = "not_proven", keyLatencyBucket = "not_proven", crashFreeBucket = "not_proven")
    }
    fun imeConfig(state: KeyboardSettingsState) = ImeConsumableConfig(state.theme, state.haptics, state.keySize, state.oneHanded, state.workflowPack)
}

data class WorkflowFixtureResult(val pack: JapaneseWorkflowPack, val preview: String, val contentPreserved: Boolean, val localOnly: Boolean = true)

object JapaneseWorkflowFixtures {
    fun apply(pack: JapaneseWorkflowPack, input: String): WorkflowFixtureResult {
        val protected = EntityProtector.protect(input)
        val service = LocalPoliteRewriteService()
        val candidate = when (pack) {
            JapaneseWorkflowPack.POLITE -> service.rewrite(protected.masked).rewritten
            JapaneseWorkflowPack.SHORTEN -> protected.masked.replace("することができます", "できます").replace("よろしくお願いいたします", "お願いします")
            JapaneseWorkflowPack.KEY_POINTS -> protected.masked.split(Regex("[。！？]"), limit = 4).filter { it.isNotBlank() }.take(3).joinToString("。", postfix = if (protected.masked.contains("。")) "。" else "")
            JapaneseWorkflowPack.ABSOLUTE_DATE -> protected.masked.replace(Regex("(明日|明後日|今日)")) { "${it.value}（絶対日付は端末設定依存のため未確定）" }
        }
        val hasSubstantiveOutput = candidate.any { !it.isWhitespace() && it !in "。！？!?" }
        val preview = if (!hasSubstantiveOutput) "" else EntityProtector.transformPreserving(input) { candidate }
        val preserved = preview.isNotBlank() && (protected.entities.all { preview.contains(it.value) } || input == preview)
        return WorkflowFixtureResult(pack, if (preserved) preview else "", preserved)
    }
}
