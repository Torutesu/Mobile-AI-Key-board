package com.torutesu.mobileaikeyboard.ui

import android.os.Bundle
import android.content.Intent
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.torutesu.mobileaikeyboard.core.LocalPoliteRewriteService

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MobileAiKeyboardApp() }
    }
}

@androidx.compose.runtime.Composable
private fun MobileAiKeyboardApp() {
    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Text("Mobile AI Keyboard", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                Text("入力の主導権を、あなたの手元に。", style = MaterialTheme.typography.titleMedium)
                ReadinessCard()
                SandboxCard()
                PrivacyCard()
            }
        }
    }
}

@androidx.compose.runtime.Composable
private fun ReadinessCard() {
    val context = LocalContext.current
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("セットアップ", style = MaterialTheme.typography.titleLarge)
            Text("キーボードを有効にすると、通常入力を端末内で利用できます。")
            Text("● 端末内のローカル変換: 準備完了", color = androidx.compose.ui.graphics.Color(0xFF18794E))
            Text("○ Android設定でキーボードを有効化: 次のステップ")
            TextButton(onClick = {
                context.startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
            }) {
                Text("キーボード設定を開く")
            }
        }
    }
}

@androidx.compose.runtime.Composable
private fun SandboxCard() {
    val service = remember { LocalPoliteRewriteService() }
    var draft by remember { mutableStateOf("来週の打ち合わせ、時間を変えてちょうだい") }
    var result by remember { mutableStateOf<String?>(null) }
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("ローカル sandbox", style = MaterialTheme.typography.titleLarge)
            Text("入力内容は送信されません。Previewしてから適用できます。")
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it; result = null },
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Sandbox input" },
                label = { Text("試してみる") },
            )
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Button(onClick = { result = service.rewrite(draft).rewritten }) { Text("Preview") }
                Spacer(Modifier.width(8.dp))
                TextButton(onClick = { result?.let { draft = it } }, enabled = result != null) { Text("Apply") }
            }
            result?.let {
                Text("プレビュー", fontWeight = FontWeight.Bold)
                Text(it, modifier = Modifier.semantics { contentDescription = "Local rewrite preview" })
            }
        }
    }
}

@androidx.compose.runtime.Composable
private fun PrivacyCard() {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("プライバシー", style = MaterialTheme.typography.titleLarge)
            Text("通常のキー入力はネットワークへ送信しません。パスワード、ワンタイムコード、電話番号欄ではAI機能を無効化します。")
            Text("W1/W2のローカル変換には、アカウント・Full Access・インターネット権限は不要です。", style = MaterialTheme.typography.bodySmall)
        }
    }
}
