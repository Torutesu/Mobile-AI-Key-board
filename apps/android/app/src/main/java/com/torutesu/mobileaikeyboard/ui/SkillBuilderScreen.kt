package com.torutesu.mobileaikeyboard.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.torutesu.mobileaikeyboard.core.HostAppState
import com.torutesu.mobileaikeyboard.core.HostEvent
import com.torutesu.mobileaikeyboard.core.PrivateSkillDraft
import com.torutesu.mobileaikeyboard.core.SkillBuilderEvent
import com.torutesu.mobileaikeyboard.core.SkillBuilderPhase

@Composable
fun SkillBuilderDashboard(state: HostAppState, dispatch: (HostEvent) -> Unit) {
    val builder = state.skillBuilder
    val action: (SkillBuilderEvent) -> Unit = { dispatch(HostEvent.SkillBuilderAction(it)) }
    Card(modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Private Skill builder" }) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
            Text("Private Skill Builder · W6", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Icon(Icons.Filled.AutoAwesome, contentDescription = "Private Skill icon", modifier = Modifier.padding(4.dp))
            Text("コードを書かずに、desired outcomeから端末内fixture Skillを作ります。ネットワーク、LLM、providerは呼び出しません。")
            Text("quota: ${builder.draft.quotaPerDay}/day · estimated cost: ${builder.estimatedCost} · public publish: disabled")
            builder.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            when (builder.phase) {
                SkillBuilderPhase.IDLE, SkillBuilderPhase.FAILED -> Button(onClick = { action(SkillBuilderEvent.Open) }) { Text("Skillを作る") }
                SkillBuilderPhase.OUTCOME, SkillBuilderPhase.MISSING_INFO, SkillBuilderPhase.DRAFT -> BuilderForm(builder.draft, builder.phase, action)
                SkillBuilderPhase.VALIDATING -> Text("schema / policy / static injectionを検証中")
                SkillBuilderPhase.READY_TO_TEST -> { Text("検証済み。外部効果なしのdry-runを実行できます"); Button(onClick = { action(SkillBuilderEvent.RunDryTest) }) { Text("fixture dry-run") } }
                SkillBuilderPhase.TEST_RESULT -> { Text(builder.dryRun?.summary ?: "dry-run receipt"); Button(onClick = { action(SkillBuilderEvent.OpenDeployReview) }) { Text("private v1 deploy review") } }
                SkillBuilderPhase.DEPLOY_REVIEW -> { Text("immutable v${builder.version?.version} · digest ${builder.version?.digest}"); Text("bindingはこのversionへpinされます。public publishは常にdisabledです。"); Button(onClick = { action(SkillBuilderEvent.ConfirmDeploy(builder.version!!.digest)) }) { Text("このversionをDeploy") } }
                SkillBuilderPhase.DEPLOYED -> {
                    Text("private Skillをpublishしました。既存bindingは明示Upgradeまで旧versionのままです。")
                    Text("digest: ${builder.confirmedDigest}")
                    Button(onClick = { builder.version?.let { action(SkillBuilderEvent.UpgradeBinding(it.digest)) } }, modifier = Modifier.fillMaxWidth()) { Text("bindingをこのversionへUpgrade") }
                    Button(onClick = { builder.version?.let { action(SkillBuilderEvent.CreateShare("fixture@example.invalid", "2026-08-27T09:00:00Z")) } }, modifier = Modifier.fillMaxWidth()) { Text("private share fixtureを作成") }
                    builder.shares.filter { !it.revoked }.forEach { share ->
                        Text("share: ${share.recipient} · expires ${share.expiresAt}")
                        TextButton(onClick = { action(SkillBuilderEvent.RevokeShare(share.recipient)) }, modifier = Modifier.fillMaxWidth()) { Text("shareをrevoke") }
                    }
                }
            }
        }
    }
}

@Composable
private fun BuilderForm(draft: PrivateSkillDraft, phase: SkillBuilderPhase, action: (SkillBuilderEvent) -> Unit) {
    val update: (PrivateSkillDraft) -> Unit = { action(SkillBuilderEvent.UpdateDraft(it)) }
    if (phase == SkillBuilderPhase.OUTCOME) Text("1 · desired outcome", fontWeight = FontWeight.Bold)
    OutlinedTextField(draft.desiredOutcome, { update(draft.copy(desiredOutcome = it)) }, Modifier.fillMaxWidth().semantics { contentDescription = "Desired outcome" }, label = { Text("したい結果") })
    OutlinedTextField(draft.name, { update(draft.copy(name = it)) }, Modifier.fillMaxWidth().semantics { contentDescription = "Private Skill name" }, label = { Text("Skill名") }, singleLine = true)
    OutlinedTextField(draft.icon, { update(draft.copy(icon = it)) }, Modifier.fillMaxWidth().semantics { contentDescription = "Skill icon" }, label = { Text("アイコン") }, singleLine = true)
    OutlinedTextField(draft.plainInstruction, { update(draft.copy(plainInstruction = it)) }, Modifier.fillMaxWidth().semantics { contentDescription = "Plain language instruction" }, label = { Text("plain-language instruction") })
    OutlinedTextField(draft.advancedSchema, { update(draft.copy(advancedSchema = it)) }, Modifier.fillMaxWidth().semantics { contentDescription = "Advanced schema" }, label = { Text("advanced schema（任意）") })
    OutlinedTextField(draft.fixtureInput, { update(draft.copy(fixtureInput = it)) }, Modifier.fillMaxWidth().semantics { contentDescription = "Visible fixture test input" }, label = { Text("dry-run input（表示）") })
    OutlinedTextField(draft.fixtureExpected, { update(draft.copy(fixtureExpected = it)) }, Modifier.fillMaxWidth().semantics { contentDescription = "Visible fixture expected output" }, label = { Text("dry-run expected（表示）") })
    Text("binding: ${draft.bindingId} · policy: private / local-only / no network / no LLM / no provider", style = MaterialTheme.typography.bodySmall)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Button(onClick = { action(SkillBuilderEvent.ContinueToDraft) }, modifier = Modifier.fillMaxWidth()) { Text("Draftへ") }
        Button(onClick = { action(SkillBuilderEvent.Validate) }, modifier = Modifier.fillMaxWidth()) { Text("Validate") }
        TextButton(onClick = { action(SkillBuilderEvent.Cancel) }, modifier = Modifier.fillMaxWidth()) { Text("Cancel") }
    }
}
