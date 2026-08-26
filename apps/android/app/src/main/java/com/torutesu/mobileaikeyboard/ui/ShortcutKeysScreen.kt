package com.torutesu.mobileaikeyboard.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.torutesu.mobileaikeyboard.core.LATIN_QWERTY_V1
import com.torutesu.mobileaikeyboard.core.ExecutableLocalSkills
import com.torutesu.mobileaikeyboard.core.ShortcutEditResult
import com.torutesu.mobileaikeyboard.core.ShortcutConflictResolution
import com.torutesu.mobileaikeyboard.core.ShortcutFixtureRunner
import com.torutesu.mobileaikeyboard.core.ShortcutFixtureTestResult
import com.torutesu.mobileaikeyboard.core.ShortcutRegistry
import com.torutesu.mobileaikeyboard.core.ShortcutSnapshot
import com.torutesu.mobileaikeyboard.core.ShortcutKeyCode
import com.torutesu.mobileaikeyboard.core.TextFingerprint
import com.torutesu.mobileaikeyboard.core.TriggerKeyBinding

private data class SkillCandidate(val id: String, val name: String, val version: Int, val digest: String)

private val localSkillCandidates = listOf(
    SkillCandidate(ExecutableLocalSkills.POLITE_REWRITE_ID, "丁寧に書き換え", ExecutableLocalSkills.VERSION, "sha256:${TextFingerprint.of("local.polite-rewrite:v1")}"),
    SkillCandidate(ExecutableLocalSkills.PUNCTUATION_POLISH_ID, "句読点を整える", ExecutableLocalSkills.VERSION, "sha256:${TextFingerprint.of("local.punctuation-polish:v1")}"),
)

@Composable
fun ShortcutKeysDashboard(
    snapshot: ShortcutSnapshot,
    onPublish: (ShortcutSnapshot) -> Boolean,
) {
    var dialogOpen by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<TriggerKeyBinding?>(null) }
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Skill Keys", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text("タップは通常入力のまま。割り当てキーを450ms以上長押しすると、入力確認から実行します。")
            Text("レイアウト: $LATIN_QWERTY_V1 · generation ${snapshot.generation}", style = MaterialTheme.typography.bodySmall)
            KeyboardPreview(snapshot)
            if (snapshot.bindings.isEmpty()) {
                Text("まだSkill Keysはありません。追加するとキーボード上で発見できます。", style = MaterialTheme.typography.bodySmall)
            } else {
                snapshot.bindings.sortedBy { it.order }.forEach { binding ->
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text("${ShortcutKeyCode.displayLabel(binding.keyCode)} — ${binding.skillName}", fontWeight = FontWeight.SemiBold)
                            Text(if (binding.enabled) "長押しで実行 · v${binding.skillVersion}" else "無効 · v${binding.skillVersion}", style = MaterialTheme.typography.bodySmall)
                        }
                        TextButton(onClick = { editing = binding; dialogOpen = true }, modifier = Modifier.heightIn(min = 48.dp)) { Text("再割当") }
                        TextButton(onClick = {
                            val result = ShortcutRegistry.remove(snapshot, binding.bindingId)
                            if (result is ShortcutEditResult.Success) onPublish(result.snapshot)
                        }, modifier = Modifier.heightIn(min = 48.dp)) { Text("削除") }
                    }
                }
            }
            Button(
                onClick = { editing = null; dialogOpen = true },
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                content = { Text("Skill Keyを追加") },
            )
            Text("資格情報・入力内容・実行レシートはこのスナップショットに保存しません。", style = MaterialTheme.typography.bodySmall)
        }
    }
    if (dialogOpen) {
        ShortcutPickerDialog(
            current = snapshot,
            editing = editing,
            onDismiss = { dialogOpen = false },
            onPublish = onPublish,
        )
    }
}

@Composable
private fun KeyboardPreview(snapshot: ShortcutSnapshot) {
    Card(modifier = Modifier.fillMaxWidth().background(Color(0xFFF1F5FB))) {
        Column(modifier = Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            listOf("QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM").forEach { row ->
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                    row.forEach { key ->
                        val label = key.toString()
                        val binding = snapshot.bindingFor(label)
                        Text(
                            label,
                            modifier = Modifier.weight(1f).semantics {
                                contentDescription = if (binding == null) "$label 通常入力" else "$label、${binding.skillName}、長押しで実行"
                            }.background(if (binding == null) Color.White else Color(0xFFE3F4FF)).padding(vertical = 8.dp),
                            style = MaterialTheme.typography.labelLarge,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ShortcutPickerDialog(
    current: ShortcutSnapshot,
    editing: TriggerKeyBinding?,
    onDismiss: () -> Unit,
    onPublish: (ShortcutSnapshot) -> Boolean,
) {
    var selectedSkill by remember(editing) { mutableStateOf(localSkillCandidates.firstOrNull { it.id == editing?.skillId }) }
    var selectedKey by remember(editing) { mutableStateOf(editing?.let { ShortcutKeyCode.displayLabel(it.keyCode) }) }
    var fixtureResult by remember(editing) { mutableStateOf<ShortcutFixtureTestResult?>(null) }
    var error by remember(editing) { mutableStateOf<String?>(null) }
    var assigned by remember(editing) { mutableStateOf<String?>(null) }
    var conflictBinding by remember(editing) { mutableStateOf<TriggerKeyBinding?>(null) }
    val occupiedByOther = current.bindings.filter { it.bindingId != editing?.bindingId && it.enabled }.map { ShortcutKeyCode.displayLabel(it.keyCode) }.toSet()
    val valid = selectedKey != null && (editing != null || selectedSkill != null)
    val candidate = selectedKey?.let { key ->
        editing ?: selectedSkill?.let { skill ->
            TriggerKeyBinding(
                bindingId = "binding-${skill.id}",
                skillId = skill.id,
                skillVersion = skill.version,
                skillDigest = skill.digest,
                keyCode = key,
                skillName = skill.name,
                accessibleLabel = "${skill.name}、長押しで実行",
            )
        }
    }?.let { it.copy(keyCode = ShortcutKeyCode.normalize(it.keyCode)) }
    fun publishCandidate(resolution: ShortcutConflictResolution? = null) {
        val selected = candidate ?: return
        val result = if (editing == null) {
            if (resolution == null) ShortcutRegistry.add(current, selected)
            else ShortcutRegistry.addWithResolution(current, selected, resolution)
        } else {
            if (resolution == null) ShortcutRegistry.reassign(current, editing.bindingId, selected.keyCode)
            else ShortcutRegistry.reassignWithResolution(current, editing.bindingId, selected.keyCode, resolution)
        }
        when (result) {
            is ShortcutEditResult.Success -> if (onPublish(result.snapshot)) {
                assigned = "${ShortcutKeyCode.displayLabel(selected.keyCode)}に${selected.skillName}を割り当てました（generation ${result.snapshot.generation}）"
                conflictBinding = null
            } else error = "保存に失敗しました。現在の設定は変更されていません。"
            is ShortcutEditResult.Rejected -> error = "保存を停止しました（${result.reason}）。現在の設定は変更されていません。"
        }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (editing == null) "割り当てるキーを選択" else "${editing.skillName}を再割当") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (editing == null) {
                    Text("Skill", fontWeight = FontWeight.SemiBold)
                    var query by remember { mutableStateOf("") }
                    OutlinedTextField(
                        value = query,
                        onValueChange = { query = it; fixtureResult = null; error = null },
                        modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Skill search" },
                        label = { Text("Skillを検索") },
                        singleLine = true,
                    )
                    val candidates = localSkillCandidates.filter { skill ->
                        query.isBlank() || skill.name.contains(query, ignoreCase = true) || skill.id.contains(query, ignoreCase = true)
                    }
                    candidates.forEach { skill ->
                        FilterChip(
                            selected = selectedSkill == skill,
                            onClick = { selectedSkill = skill; fixtureResult = null; error = null },
                            modifier = Modifier.heightIn(min = 48.dp).semantics { contentDescription = "${skill.name}、端末内実行可能" },
                            label = { Text("${skill.name}（端末内）") },
                        )
                    }
                    if (candidates.isEmpty()) Text("一致する実行可能なSkillがありません。", color = MaterialTheme.colorScheme.error)
                }
                Text("QWERTY", fontWeight = FontWeight.SemiBold)
                // Five columns keeps every choice comfortably tappable on narrow phones.
                listOf("QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM").flatMap { it.chunked(5) }.forEach { row ->
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        row.forEach { key ->
                            val label = key.toString()
                            val occupied = label in occupiedByOther
                            OutlinedButton(
                                onClick = { selectedKey = label; fixtureResult = null; error = null },
                                // Occupied keys stay selectable so the user can
                                // reach the explicit Swap/Replace decision.
                                enabled = true,
                                modifier = Modifier.weight(1f).heightIn(min = 48.dp).semantics {
                                    selected = selectedKey == label
                                    contentDescription = when {
                                        occupied && selectedKey == label -> "$label、別のSkillで使用中、移動先として選択中"
                                        occupied -> "$label、別のSkillで使用中"
                                        selectedKey == label -> "$label、選択中"
                                        else -> "$label、割り当て可能"
                                    }
                                },
                            ) {
                                Text(label, color = if (selectedKey == label) Color(0xFF119CF3) else Color.Unspecified)
                            }
                        }
                    }
                }
                if (selectedKey in occupiedByOther) Text("${selectedKey}は使用中です。保存時にSwapまたはReplaceを明示してください。", color = MaterialTheme.colorScheme.error)
                if (valid) {
                    Button(
                        onClick = { fixtureResult = candidate?.let(ShortcutFixtureRunner::run); error = null },
                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    ) { Text("端末内fixtureをテスト") }
                } else Text("Skillとキーを選択してください。", color = MaterialTheme.colorScheme.error)
                fixtureResult?.let { result ->
                    Text(result.summary, color = if (result.passed) Color(0xFF18794E) else MaterialTheme.colorScheme.error)
                    if (result.passed) Text("Preview: ${result.output}", style = MaterialTheme.typography.bodySmall)
                }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                assigned?.let { Text("✓ $it", color = Color(0xFF18794E), fontWeight = FontWeight.Bold) }
            }
        },
        confirmButton = {
            Button(enabled = valid && fixtureResult?.passed == true && assigned == null, onClick = {
                val selected = candidate ?: return@Button
                val occupied = current.bindings.firstOrNull { it.enabled && it.keyCode == selected.keyCode && it.bindingId != editing?.bindingId }
                if (occupied != null) conflictBinding = occupied else publishCandidate()
            }) { Text(if (editing == null) "保存" else "保存") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = 48.dp)) {
                Text(if (assigned != null) "完了" else "キャンセル")
            }
        },
    )
    conflictBinding?.let { occupied ->
        AlertDialog(
            onDismissRequest = { conflictBinding = null },
            title = { Text("キー競合を解決") },
            text = { Text("${ShortcutKeyCode.displayLabel(occupied.keyCode)}は${occupied.skillName}で使用中です。暗黙の上書きは行いません。") },
            confirmButton = {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (editing != null) {
                        TextButton(onClick = { publishCandidate(ShortcutConflictResolution.SWAP) }, modifier = Modifier.heightIn(min = 48.dp)) { Text("Swap") }
                    }
                    TextButton(onClick = { publishCandidate(ShortcutConflictResolution.REPLACE) }, modifier = Modifier.heightIn(min = 48.dp)) { Text("Replace") }
                }
            },
            dismissButton = { TextButton(onClick = { conflictBinding = null }, modifier = Modifier.heightIn(min = 48.dp)) { Text("キャンセル") } },
        )
    }
}
