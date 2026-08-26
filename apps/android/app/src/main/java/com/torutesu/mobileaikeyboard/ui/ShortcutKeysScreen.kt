package com.torutesu.mobileaikeyboard.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import com.torutesu.mobileaikeyboard.core.ShortcutEditResult
import com.torutesu.mobileaikeyboard.core.ShortcutRegistry
import com.torutesu.mobileaikeyboard.core.ShortcutSnapshot
import com.torutesu.mobileaikeyboard.core.ShortcutKeyCode
import com.torutesu.mobileaikeyboard.core.TextFingerprint
import com.torutesu.mobileaikeyboard.core.TriggerKeyBinding

private data class SkillCandidate(val id: String, val name: String, val version: Int, val digest: String)

private val localSkillCandidates = listOf(
    SkillCandidate("local.polite-rewrite", "丁寧に書き換え", 1, "sha256:${TextFingerprint.of("local.polite-rewrite:v1")}"),
    SkillCandidate("local.punctuation-polish", "句読点を整える", 1, "sha256:${TextFingerprint.of("local.punctuation-polish:v1")}"),
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
                        TextButton(onClick = { editing = binding; dialogOpen = true }) { Text("再割当") }
                        TextButton(onClick = {
                            val result = ShortcutRegistry.remove(snapshot, binding.bindingId)
                            if (result is ShortcutEditResult.Success) onPublish(result.snapshot)
                        }) { Text("削除") }
                    }
                }
            }
            Button(onClick = { editing = null; dialogOpen = true }, modifier = Modifier.fillMaxWidth()) { Text("Skill Keyを追加") }
            Text("資格情報・入力内容・実行レシートはこのスナップショットに保存しません。", style = MaterialTheme.typography.bodySmall)
        }
    }
    if (dialogOpen) {
        ShortcutPickerDialog(
            current = snapshot,
            editing = editing,
            onDismiss = { dialogOpen = false },
            onPublish = { next -> if (onPublish(next)) dialogOpen = false },
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
    onPublish: (ShortcutSnapshot) -> Unit,
) {
    var selectedSkill by remember(editing) { mutableStateOf(localSkillCandidates.firstOrNull { it.id == editing?.skillId }) }
    var selectedKey by remember(editing) { mutableStateOf(editing?.let { ShortcutKeyCode.displayLabel(it.keyCode) }) }
    val occupiedByOther = current.bindings.filter { it.bindingId != editing?.bindingId && it.enabled }.map { ShortcutKeyCode.displayLabel(it.keyCode) }.toSet()
    val validKey = selectedKey != null && selectedKey !in occupiedByOther
    val valid = selectedKey != null && validKey && (editing != null || selectedSkill != null)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (editing == null) "割り当てるキーを選択" else "${editing.skillName}を再割当") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (editing == null) {
                    Text("Skill", fontWeight = FontWeight.SemiBold)
                    localSkillCandidates.forEach { skill ->
                        FilterChip(selected = selectedSkill == skill, onClick = { selectedSkill = skill }, label = { Text(skill.name) })
                    }
                }
                Text("QWERTY", fontWeight = FontWeight.SemiBold)
                listOf("QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM").forEach { row ->
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        row.forEach { key ->
                            val label = key.toString()
                            val occupied = label in occupiedByOther
                            OutlinedButton(
                                onClick = { selectedKey = label },
                                enabled = !occupied,
                                modifier = Modifier.weight(1f).semantics {
                                    selected = selectedKey == label
                                    contentDescription = when {
                                        occupied -> "$label、別のSkillで使用中"
                                        selectedKey == label -> "$label、選択中"
                                        else -> "$label、割り当て可能"
                                    }
                                },
                            ) {
                                Text(if (occupied) "×" else label, color = if (selectedKey == label) Color(0xFF119CF3) else Color.Unspecified)
                            }
                        }
                    }
                }
                if (!valid) Text("未選択または使用中のキーです。Addは無効です。", color = MaterialTheme.colorScheme.error)
            }
        },
        confirmButton = {
            Button(enabled = valid, onClick = {
                val result = if (editing == null) {
                    val skill = selectedSkill
                    if (skill == null) {
                        ShortcutEditResult.Rejected("skill_not_selected")
                    } else {
                        ShortcutRegistry.add(current, TriggerKeyBinding("binding-${skill.id}", skill.id, skill.version, skill.digest, keyCode = selectedKey!!, skillName = skill.name, accessibleLabel = "${skill.name}、長押しで実行"))
                    }
                } else ShortcutRegistry.reassign(current, editing.bindingId, selectedKey!!)
                if (result is ShortcutEditResult.Success) onPublish(result.snapshot)
            }) { Text(if (editing == null) "Add" else "保存") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("キャンセル") } },
    )
}
