package com.torutesu.mobileaikeyboard.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.torutesu.mobileaikeyboard.core.HostAppState
import com.torutesu.mobileaikeyboard.core.HostEvent
import com.torutesu.mobileaikeyboard.core.SuggestionEvent
import com.torutesu.mobileaikeyboard.core.SuggestionKind
import com.torutesu.mobileaikeyboard.core.SuggestionPhase
import com.torutesu.mobileaikeyboard.core.TrustCatalogEvent

@Composable
fun SuggestionTrustDashboard(state: HostAppState, dispatch: (HostEvent) -> Unit) {
    val suggestion = state.suggestions
    val catalog = state.trustCatalog
    Card(modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Local suggestion and Trust Preview" }) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
            Text("Contextual suggestion · local-only", style = MaterialTheme.typography.titleLarge)
            Text("raw textはstate・保存・telemetryへ保持しません。auto-commitは常に無効。sensitive inputは抑止します。")
            Button(onClick = { dispatch(HostEvent.SuggestionAction(SuggestionEvent.Preview(42, false))) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("fixture preview") }
            Button(onClick = { dispatch(HostEvent.SuggestionAction(SuggestionEvent.Preview(42, true))) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("sensitive抑止を確認") }
            Text("phase=${suggestion.phase} · source=${suggestion.source} · length=${suggestion.inputLengthBucket ?: "not_proven"} · autoCommit=${suggestion.autoCommit}")
            if (suggestion.phase == SuggestionPhase.PREVIEW) {
                val previewLabel = when (suggestion.suggestionKind) {
                    SuggestionKind.POLITE_LOCAL_FIXTURE -> "固定fixtureのプレビュー（入力内容は保存しません）"
                    null -> "プレビューを利用できません"
                }
                Text(previewLabel, modifier = Modifier.semantics { contentDescription = "Suggestion preview" })
                Button(onClick = { dispatch(HostEvent.SuggestionAction(SuggestionEvent.Copy)) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("Copy path preview（実clipboard未実装）") }
            }
            Text("Trust Preview / community Skill catalog fixture", style = MaterialTheme.typography.titleMedium)
            val policy = catalog.policy
            Text("policy owner=${policy.owner} team=${policy.teamId} version=${policy.policyVersion} epoch=${policy.epoch}")
            Text("policy digest=${policy.policyDigest} operations=${policy.allowedOperations} scopes=${policy.allowedScopes} risk≤${policy.riskCeiling} confirmation≥${policy.confirmationFloor}")
            catalog.entries.forEach { entry ->
                Text("${entry.skillId} · v${entry.version} · digest=${entry.digest}")
                Text("owner=${entry.owner} team=${entry.teamId} epoch=${entry.epoch} provenance=${entry.provenance} risk=${entry.safety.riskClass} network=${entry.safety.network} rawRetention=${entry.safety.rawTextRetention} telemetry=${entry.safety.telemetry} autoCommit=${entry.safety.autoCommit} sensitiveSuppression=${entry.safety.sensitiveSuppression}")
                val issues = entry.safety.reportedIssues
                Text("publisher=${entry.safety.publisherVerification} connectors=${entry.safety.requestedConnectors} scopes=${entry.safety.requestedScopes} inputTypes=${entry.safety.inputTypes} operations=${entry.safety.requestedOperations} lastReview=${entry.safety.lastReview}")
                Text("issues(safety/privacy/reliability)=${issues.safety}/${issues.privacy}/${issues.reliability} aggregate=${issues.aggregate} completion=${entry.report.confidence.label} derivedRate=${entry.report.rate ?: "not_proven"}")
                Button(onClick = { dispatch(HostEvent.TrustCatalogAction(TrustCatalogEvent.Install(entry.skillId, entry.digest))) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("policy review / install") }
                Button(onClick = { dispatch(HostEvent.TrustCatalogAction(TrustCatalogEvent.ExplicitUpgrade(entry.skillId, entry.digest))) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("explicit upgrade") }
            }
            catalog.installed.forEach { installed ->
                Text("installed: ${installed.skillId} v${installed.version} revoked=${installed.revoked}")
                Button(onClick = { dispatch(HostEvent.TrustCatalogAction(TrustCatalogEvent.Revoke(installed.digest))) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("revoke") }
            }
            Text("R4 connector gate: DISABLED_NOT_PROVEN。separate review/evidenceが揃うまで実行不可。public marketplace/runtime syncなし。")
            catalog.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
    }
}
