package com.torutesu.mobileaikeyboard.ui

import android.os.Bundle
import android.content.Intent
import android.provider.Settings
import android.content.Context
import android.view.inputmethod.InputMethodManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
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
import com.torutesu.mobileaikeyboard.core.HostEvent
import com.torutesu.mobileaikeyboard.core.HostFixtureClient
import com.torutesu.mobileaikeyboard.core.ImeOnboardingStatus
import com.torutesu.mobileaikeyboard.core.KeyboardSettingsStore
import com.torutesu.mobileaikeyboard.core.InstalledSkillStore
import com.torutesu.mobileaikeyboard.core.LocalSkillRegistry
import com.torutesu.mobileaikeyboard.core.ShortcutSnapshotStore

class MainActivity : ComponentActivity() {
    private val imeEnabled = mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        imeEnabled.value = isKeyboardEnabled()
        setContent { MobileAiKeyboardApp(imeEnabled.value) }
    }

    override fun onResume() {
        super.onResume()
        // Returning from Android's keyboard settings is the important onboarding
        // boundary; refresh status instead of leaving a stale "not enabled" card.
        imeEnabled.value = isKeyboardEnabled()
    }

    private fun isKeyboardEnabled(): Boolean {
        val manager = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        return manager.enabledInputMethodList.any { it.packageName == packageName }
    }
}

@androidx.compose.runtime.Composable
private fun MobileAiKeyboardApp(imeEnabled: Boolean) {
    val fixtureClient = remember { HostFixtureClient }
    val context = LocalContext.current
    val installedSkillStore = remember(context) { InstalledSkillStore(context.applicationContext) }
    val shortcutStore = remember(context) { ShortcutSnapshotStore(context.applicationContext) }
    val settingsStore = remember(context) { KeyboardSettingsStore(context.applicationContext) }
    var hostState by remember { mutableStateOf(fixtureClient.initialState().copy(keyboardSettings = settingsStore.readState())) }
    var shortcutSnapshot by remember { mutableStateOf(shortcutStore.read()) }
    var installedSkills by remember(context) { mutableStateOf(LocalSkillRegistry.all()) }
    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            Column(
                modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Text("Mobile AI Keyboard", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                Text("入力の主導権を、あなたの手元に。", style = MaterialTheme.typography.titleMedium)
                ReadinessCard(imeEnabled)
                HostAppDashboard(
                    state = hostState,
                    dispatch = { event ->
                        val previous = hostState
                        hostState = fixtureClient.dispatch(previous, event)
                        if (event is HostEvent.KeyboardSettingsAction) settingsStore.write(hostState.keyboardSettings)
                        val currentDeviceRevoked = event is HostEvent.ConfirmDeviceRevoke && previous.devices.firstOrNull { it.id == previous.pendingRevokeDeviceId }?.isCurrent == true
                        val accountBoundary = event is HostEvent.SignOut || event is HostEvent.SimulateSessionExpiry || event is HostEvent.SimulateSessionRevocation || currentDeviceRevoked
                        val deletionCompleted = event is HostEvent.AdvanceDeletion && previous.deletion.status == com.torutesu.mobileaikeyboard.core.DeletionStatus.IN_PROGRESS
                        if (accountBoundary || deletionCompleted) {
                            installedSkillStore.clear()
                            shortcutStore.clear()
                            installedSkills = LocalSkillRegistry.all()
                            shortcutSnapshot = shortcutStore.read()
                        }
                    },
                    shortcutSnapshot = shortcutSnapshot,
                    installedSkills = installedSkills,
                    onShortcutPublish = { candidate ->
                        val published = shortcutStore.publish(candidate)
                        if (published) shortcutSnapshot = shortcutStore.read()
                        published
                    },
                    onAddToMyKeyboard = { version ->
                        val installed = installedSkillStore.install(version)
                        if (installed) installedSkills = LocalSkillRegistry.all()
                        installed
                    },
                )
                SandboxCard()
                PrivacyCard()
            }
        }
    }
}

@androidx.compose.runtime.Composable
private fun ReadinessCard(imeEnabled: Boolean) {
    val context = LocalContext.current
    var testText by remember { mutableStateOf("") }
    val onboarding = ImeOnboardingStatus(imeEnabled, testText)
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("セットアップ", style = MaterialTheme.typography.titleLarge)
            Text(if (imeEnabled) "キーボードは有効です。入力欄で選択して動作を確認してください。" else "まずAndroid設定でMobile AI Keyboardを有効にしてください。")
            Text(
                if (imeEnabled) "✓ 1. キーボードを有効化" else "1. キーボードを有効化（未完了）",
                color = if (imeEnabled) androidx.compose.ui.graphics.Color(0xFF18794E) else MaterialTheme.colorScheme.onSurface,
            )
            OutlinedTextField(
                value = testText,
                onValueChange = { testText = it },
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = "IME onboarding test field" },
                label = { Text("2. テスト入力") },
                placeholder = { Text("ここに入力してキーボードを確認") },
                singleLine = true,
            )
            Text(
                when {
                    onboarding.complete -> "✓ 2. テスト入力に成功 — セットアップ完了"
                    imeEnabled -> "2. テスト入力を行うとセットアップ完了です"
                    else -> "2. キーボード有効化後、ここでテスト入力してください"
                },
                color = if (onboarding.complete) androidx.compose.ui.graphics.Color(0xFF18794E) else MaterialTheme.colorScheme.onSurface,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = {
                        context.startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
                    },
                    modifier = Modifier.heightIn(min = 48.dp),
                ) { Text("キーボード設定") }
                if (imeEnabled) {
                    TextButton(
                        onClick = {
                            val manager = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                            manager.showInputMethodPicker()
                        },
                        modifier = Modifier.heightIn(min = 48.dp),
                    ) { Text("キーボードを選択") }
                }
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
