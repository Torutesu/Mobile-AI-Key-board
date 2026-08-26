package com.torutesu.mobileaikeyboard.core

enum class SuggestionPhase { IDLE, PREVIEW, BLOCKED_SENSITIVE, INVALID_CONTEXT, COPY_PATH_PREVIEWED, DISMISSED }
enum class SuggestionSource { LOCAL_WORKFLOW_FIXTURE }
enum class ConnectorGateStatus { DISABLED_NOT_PROVEN }
enum class SuggestionKind { POLITE_LOCAL_FIXTURE }

data class ContextualSuggestionState(
    val phase: SuggestionPhase = SuggestionPhase.IDLE,
    val source: SuggestionSource = SuggestionSource.LOCAL_WORKFLOW_FIXTURE,
    val inputLengthBucket: String? = null,
    val sensitiveSuppressed: Boolean = false,
    // Opaque kind only: contextual/raw output never enters reducer state.
    val suggestionKind: SuggestionKind? = null,
    val autoCommit: Boolean = false,
)

data class IssueCounts(val safety: Int = 0, val privacy: Int = 0, val reliability: Int = 0) {
    val aggregate: Int get() = safety + privacy + reliability
    companion object { const val MAX_COUNT = 1_000_000 }
}
data class SkillSafetyMetadata(
    val skillId: String,
    val riskClass: RiskClass,
    val network: Boolean,
    val rawTextRetention: Boolean,
    val telemetry: String,
    val autoCommit: Boolean,
    val sensitiveSuppression: Boolean,
    val confirmationFloor: String,
    val requestedOperations: List<String>,
    val publisherVerification: String,
    val requestedConnectors: List<String>,
    val requestedScopes: List<String>,
    val inputTypes: List<String>,
    val lastReview: String,
    val reportedIssues: IssueCounts,
)
enum class FixtureProvenance { FIXTURE_NOT_PROVEN }
enum class CompletionConfidence(val label: String) { NOT_PROVEN("not_proven"), LOW("low_confidence"), REPORTED("reported_fixture") }
data class SkillCompletionReport(val attempts: Int = 0, val completions: Int = 0) {
    companion object { const val MIN_REPORTED_SAMPLE = 100 }
    val rate: Double? get() = if (attempts <= 0 || completions !in 0..attempts) null else completions.toDouble() / attempts
    val confidence: CompletionConfidence get() = when {
        rate == null -> CompletionConfidence.NOT_PROVEN
        attempts < MIN_REPORTED_SAMPLE -> CompletionConfidence.LOW
        else -> CompletionConfidence.REPORTED
    }
}
data class TrustCatalogEntry(val skillId: String, val name: String, val version: Int, val digest: String, val owner: String, val teamId: String, val epoch: Int, val provenance: FixtureProvenance, val safety: SkillSafetyMetadata, val report: SkillCompletionReport = SkillCompletionReport(), val policyVersion: Int = 1)
data class TeamSkillPolicy(val teamId: String, val owner: String, val epoch: Int, val allowedSkillIds: Set<String>, val allowedOperations: Set<String>, val allowedScopes: Set<String>, val riskCeiling: RiskClass, val confirmationFloor: String, val requireExplicitUpgrade: Boolean, val revokedDigests: Set<String> = emptySet(), val policyDigest: String = "", val policyVersion: Int = 1)
data class InstalledTeamSkill(val skillId: String, val version: Int, val digest: String, val teamId: String, val owner: String, val epoch: Int, val revoked: Boolean = false, val policyVersion: Int = 1)

data class TrustCatalogState(
    val entries: List<TrustCatalogEntry> = listOf(
        TrustCatalogEntry("SK-006", "Polite local suggestion", 1, "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", "fixture-owner", "fixture-team", 1, FixtureProvenance.FIXTURE_NOT_PROVEN, SkillSafetyMetadata("SK-006", RiskClass.R1, false, false, "content_free", false, true, "preview", listOf("local.suggestion.preview"), "not_proven", emptyList(), emptyList(), listOf("text"), "2026-08-26", IssueCounts()), SkillCompletionReport(), policyVersion = 1),
        TrustCatalogEntry("SK-006", "Polite local suggestion", 2, "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789", "fixture-owner", "fixture-team", 1, FixtureProvenance.FIXTURE_NOT_PROVEN, SkillSafetyMetadata("SK-006", RiskClass.R1, false, false, "content_free", false, true, "preview", listOf("local.suggestion.preview"), "not_proven", emptyList(), emptyList(), listOf("text"), "2026-08-26", IssueCounts()), SkillCompletionReport(), policyVersion = 1),
    ),
    val policy: TeamSkillPolicy = TeamSkillPolicy("fixture-team", "fixture-owner", 1, setOf("SK-006"), setOf("local.suggestion.preview"), emptySet(), RiskClass.R1, "preview", requireExplicitUpgrade = true).let { it.copy(policyDigest = TrustPolicyDigest.compute(it)) },
    val installed: List<InstalledTeamSkill> = emptyList(),
    val connectorGate: ConnectorGateStatus = ConnectorGateStatus.DISABLED_NOT_PROVEN,
    val reviewDate: String = "2026-08-26",
    val maxReviewAgeDays: Long = 30,
    val error: String? = null,
)

sealed interface TrustCatalogEvent {
    data class Install(val skillId: String, val digest: String) : TrustCatalogEvent
    data class ExplicitUpgrade(val skillId: String, val digest: String) : TrustCatalogEvent
    data class Revoke(val digest: String) : TrustCatalogEvent
}

sealed interface SuggestionEvent {
    data class Preview(val inputLength: Int, val sensitive: Boolean) : SuggestionEvent
    data object Copy : SuggestionEvent
    data object Dismiss : SuggestionEvent
}

object SuggestionReducer {
    fun reduce(state: ContextualSuggestionState, event: SuggestionEvent): ContextualSuggestionState = when (event) {
        is SuggestionEvent.Preview -> when { event.sensitive -> state.copy(phase = SuggestionPhase.BLOCKED_SENSITIVE, inputLengthBucket = null, suggestionKind = null, sensitiveSuppressed = true); event.inputLength !in 0..1_000_000 -> state.copy(phase = SuggestionPhase.INVALID_CONTEXT, inputLengthBucket = null, suggestionKind = null, sensitiveSuppressed = false); else -> state.copy(phase = SuggestionPhase.PREVIEW, inputLengthBucket = bucket(event.inputLength), suggestionKind = SuggestionKind.POLITE_LOCAL_FIXTURE, sensitiveSuppressed = false) }
        SuggestionEvent.Copy -> if (state.phase == SuggestionPhase.PREVIEW) state.copy(phase = SuggestionPhase.COPY_PATH_PREVIEWED) else state
        SuggestionEvent.Dismiss -> state.copy(phase = SuggestionPhase.DISMISSED, suggestionKind = null)
    }
    private fun bucket(length: Int) = when { length < 0 -> "not_proven"; length <= 20 -> "0-20"; length <= 100 -> "21-100"; else -> "101+" }
}

object TrustCatalogReducer {
    fun reduce(state: TrustCatalogState, event: TrustCatalogEvent): TrustCatalogState = when (event) {
        is TrustCatalogEvent.Install -> install(state, event.skillId, event.digest, explicit = false)
        is TrustCatalogEvent.ExplicitUpgrade -> install(state, event.skillId, event.digest, explicit = true)
        is TrustCatalogEvent.Revoke -> {
            val nextPolicy = state.policy.copy(revokedDigests = state.policy.revokedDigests + event.digest)
            state.copy(
                installed = state.installed.map { if (it.digest == event.digest) it.copy(revoked = true) else it },
                policy = nextPolicy.copy(policyDigest = TrustPolicyDigest.compute(nextPolicy)),
                error = null,
            )
        }
    }
    private fun install(state: TrustCatalogState, skillId: String, digest: String, explicit: Boolean): TrustCatalogState {
        val entry = state.entries.firstOrNull { it.skillId == skillId && it.digest == digest } ?: return state.copy(error = "catalog metadata、team policy、digest、owner、versionを確認できないため停止しました")
        val current = state.installed.firstOrNull { it.skillId == entry.skillId }
        val validDigest = Regex("^sha256:[0-9a-f]{64}$").matches(entry.digest)
        val reviewFresh = runCatching { val review = java.time.LocalDate.parse(entry.safety.lastReview); val today = java.time.LocalDate.parse(state.reviewDate); !review.isAfter(today) && !review.isBefore(today.minusDays(state.maxReviewAgeDays)) }.getOrDefault(false)
        val issues = entry.safety.reportedIssues
        val issuesValid = listOf(issues.safety, issues.privacy, issues.reliability).all { it in 0..IssueCounts.MAX_COUNT } && issues.aggregate <= IssueCounts.MAX_COUNT
        val report = entry.report
        val reportValid = report.attempts in 0..IssueCounts.MAX_COUNT && report.completions in 0..report.attempts
        val policyReviewWindowValid = state.maxReviewAgeDays in 0..3650
        val monotonic = if (current == null) entry.version == 1 && entry.epoch == state.policy.epoch && entry.policyVersion == state.policy.policyVersion else explicit && entry.version == current.version + 1 && entry.epoch == current.epoch && entry.policyVersion == current.policyVersion && entry.version > current.version
        val currentBindingValid = current?.let { it.teamId == state.policy.teamId && it.owner == state.policy.owner && it.epoch == state.policy.epoch && it.policyVersion == state.policy.policyVersion } != false
        val valid = validDigest && state.policy.policyVersion > 0 && entry.policyVersion > 0 && entry.provenance == FixtureProvenance.FIXTURE_NOT_PROVEN && entry.owner == state.policy.owner && entry.teamId == state.policy.teamId && entry.epoch == state.policy.epoch && entry.policyVersion == state.policy.policyVersion && TrustPolicyDigest.compute(state.policy) == state.policy.policyDigest && state.policy.allowedSkillIds.contains(entry.skillId) && entry.safety.requestedOperations.isNotEmpty() && entry.safety.requestedOperations.size == entry.safety.requestedOperations.toSet().size && entry.safety.requestedOperations.all { it in state.policy.allowedOperations } && entry.safety.requestedConnectors.isEmpty() && entry.safety.requestedScopes.toSet().size == entry.safety.requestedScopes.size && entry.safety.requestedScopes.all { it in state.policy.allowedScopes } && entry.safety.riskClass.ordinal <= state.policy.riskCeiling.ordinal && entry.safety.confirmationFloor == state.policy.confirmationFloor && !state.policy.revokedDigests.contains(entry.digest) && currentBindingValid && current?.let { !state.policy.revokedDigests.contains(it.digest) } != false && entry.safety.network.not() && entry.safety.rawTextRetention.not() && entry.safety.autoCommit.not() && entry.safety.sensitiveSuppression && policyReviewWindowValid && reviewFresh && issuesValid && reportValid && monotonic
        if (!valid) return state.copy(error = "catalog metadata、team policy、digest、owner、versionを確認できないため停止しました")
        return state.copy(installed = state.installed.filterNot { it.skillId == entry.skillId } + InstalledTeamSkill(entry.skillId, entry.version, entry.digest, state.policy.teamId, entry.owner, entry.epoch, policyVersion = state.policy.policyVersion), error = null)
    }
}

object TrustPolicyDigest {
    // Length-prefix every value so policy fields cannot collide through delimiter injection.
    private fun encodeList(values: Collection<String>): String = values.sorted().joinToString("") { "${it.length}:$it;" }.let { "${values.size}[$it]" }
    private fun encode(value: String): String = "${value.length}:$value;"
    fun canonical(policy: TeamSkillPolicy): String = buildString {
        append(encode(policy.teamId)); append(encode(policy.owner)); append(encode(policy.epoch.toString())); append(encode(policy.policyVersion.toString()))
        append(encodeList(policy.allowedSkillIds)); append(encodeList(policy.allowedOperations)); append(encodeList(policy.allowedScopes))
        append(encode(policy.riskCeiling.name)); append(encode(policy.confirmationFloor)); append(encode(policy.requireExplicitUpgrade.toString())); append(encodeList(policy.revokedDigests))
    }
    fun compute(policy: TeamSkillPolicy): String = "sha256:" + java.security.MessageDigest.getInstance("SHA-256").digest(canonical(policy).toByteArray()).joinToString("") { "%02x".format(it) }
}
