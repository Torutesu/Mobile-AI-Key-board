package com.torutesu.mobileaikeyboard.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.heightIn
import com.torutesu.mobileaikeyboard.core.HostAppState
import com.torutesu.mobileaikeyboard.core.HostEvent
import com.torutesu.mobileaikeyboard.core.HapticMode
import com.torutesu.mobileaikeyboard.core.KeySoundMode
import com.torutesu.mobileaikeyboard.core.JapaneseWorkflowPack
import com.torutesu.mobileaikeyboard.core.KeyboardSettingsEvent
import com.torutesu.mobileaikeyboard.core.KeyboardTheme
import com.torutesu.mobileaikeyboard.core.KeySize
import com.torutesu.mobileaikeyboard.core.OneHandedMode
import com.torutesu.mobileaikeyboard.core.QualificationMetrics
import com.torutesu.mobileaikeyboard.core.AuthStatus
import com.torutesu.mobileaikeyboard.core.SessionStatus
import com.torutesu.mobileaikeyboard.core.DeletionStatus

@Composable
fun KeyboardSettingsDashboard(state: HostAppState, dispatch: (HostEvent) -> Unit) {
    val settings = state.keyboardSettings
    val send: (KeyboardSettingsEvent) -> Unit = { dispatch(HostEvent.KeyboardSettingsAction(it)) }
    Card(modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Keyboard customization and local workflow settings" }) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Keyboard customization", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text("端末内設定 v${settings.schemaVersion}。HostとIMEが端末内SharedPreferencesで共有します。実機再起動・OEM差は未証明で、Android標準の変換エンジンは置き換えません。")
            ChoiceRow("Theme", settings.theme.name) { send(KeyboardSettingsEvent.SetTheme(next(settings.theme))) }
            ChoiceRow("Haptics", settings.haptics.name) { send(KeyboardSettingsEvent.SetHaptics(next(settings.haptics))) }
            ChoiceRow("Key sound", settings.keySound.name) { send(KeyboardSettingsEvent.SetKeySound(next(settings.keySound))) }
            ChoiceRow("Character preview", if (settings.characterPreview) "ON" else "OFF") { send(KeyboardSettingsEvent.SetCharacterPreview(!settings.characterPreview)) }
            ChoiceRow("Key size", settings.keySize.name) { send(KeyboardSettingsEvent.SetKeySize(next(settings.keySize))) }
            ChoiceRow("One-handed", settings.oneHanded.name) { send(KeyboardSettingsEvent.SetOneHanded(next(settings.oneHanded))) }
            Text("Japanese workflow packs（local fixture）", fontWeight = FontWeight.Bold)
            JapaneseWorkflowPack.values().forEach { pack ->
                Button(onClick = { send(KeyboardSettingsEvent.SelectWorkflowPack(pack)) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp), enabled = settings.workflowPack != pack) { Text(packLabel(pack)) }
            }
            Text("丁寧化・短縮・要点・日付絶対化はlocal fixture previewです。Japanese IME conversionとは主張しません。")
            Text("Qualification: ${settings.qualificationStatus} · cold=${settings.coldLatencyBucket} warm=${settings.warmLatencyBucket} key=${settings.keyLatencyBucket} crash-free=${settings.crashFreeBucket}")
            settings.qualificationMetrics?.let { Text("typed fixture metrics: cold p50=${it.coldP50Ms}ms p95=${it.coldP95Ms}ms warm p95=${it.warmP95Ms}ms key p95=${it.keyP95Ms}ms sessions=${it.sessions} crashes=${it.crashes} crash-free=${it.crashFreeBasisPoints}bp") }
            Text("physical-device qualification: not_proven。content-free budget表示のみで、実機証明ではありません。", style = MaterialTheme.typography.bodySmall)
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { send(KeyboardSettingsEvent.RecordFixtureQualification(QualificationMetrics(120, 300, 100, 30, 1000, 1))) }, enabled = state.account.authStatus == AuthStatus.SIGNED_IN && state.account.sessionStatus == SessionStatus.ACTIVE && state.deletion.status != DeletionStatus.COMPLETED, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("fixture budget") }
                TextButton(onClick = { send(KeyboardSettingsEvent.Reset) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("Reset") }
            }
            Text("Data safety: 通常キー入力・workflow previewは端末内。INTERNET permissionなし。OAuth/provider/LLM接続なし。", style = MaterialTheme.typography.bodySmall)
            Text("Store readiness: support/incident対応はfixture表示、外部配布・実機クラッシュ率・ストア審査は未証明。", style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun ChoiceRow(label: String, value: String, onClick: () -> Unit) {
    Button(onClick = onClick, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).semantics { contentDescription = "$label $value" }) { Text("$label: $value") }
}

private fun next(value: KeyboardTheme) = KeyboardTheme.values()[(value.ordinal + 1) % KeyboardTheme.values().size]
private fun next(value: HapticMode) = HapticMode.values()[(value.ordinal + 1) % HapticMode.values().size]
private fun next(value: KeySoundMode) = KeySoundMode.values()[(value.ordinal + 1) % KeySoundMode.values().size]
private fun next(value: KeySize) = KeySize.values()[(value.ordinal + 1) % KeySize.values().size]
private fun next(value: OneHandedMode) = OneHandedMode.values()[(value.ordinal + 1) % OneHandedMode.values().size]
private fun packLabel(pack: JapaneseWorkflowPack) = when (pack) {
    JapaneseWorkflowPack.POLITE -> "丁寧化"
    JapaneseWorkflowPack.SHORTEN -> "短縮"
    JapaneseWorkflowPack.KEY_POINTS -> "要点"
    JapaneseWorkflowPack.ABSOLUTE_DATE -> "日付絶対化（未確定fixture）"
}
