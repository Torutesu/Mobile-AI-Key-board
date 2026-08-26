package com.torutesu.mobileaikeyboard.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.torutesu.mobileaikeyboard.core.AccountState
import com.torutesu.mobileaikeyboard.core.ActivityRun
import com.torutesu.mobileaikeyboard.core.AuthStatus
import com.torutesu.mobileaikeyboard.core.DeletionStatus
import com.torutesu.mobileaikeyboard.core.DeviceStatus
import com.torutesu.mobileaikeyboard.core.DeviceState
import com.torutesu.mobileaikeyboard.core.HostAppState
import com.torutesu.mobileaikeyboard.core.HostEvent
import com.torutesu.mobileaikeyboard.core.HostFixtureClient
import com.torutesu.mobileaikeyboard.core.RetentionPolicy
import com.torutesu.mobileaikeyboard.core.RunStatus
import com.torutesu.mobileaikeyboard.core.SessionStatus
import com.torutesu.mobileaikeyboard.core.ShortcutSnapshot

@Composable
fun HostAppDashboard(
    state: HostAppState,
    dispatch: (HostEvent) -> Unit,
    shortcutSnapshot: ShortcutSnapshot = ShortcutSnapshot.empty(),
    onShortcutPublish: (ShortcutSnapshot) -> Boolean = { false },
) {
    Text("アカウント・デバイス・Activity", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
    Text("接続先に依存しないローカルfixture表示。実identity/backend接続は未証明です。")
    AccountCard(state.account, dispatch)
    DevicesCard(state, dispatch)
    ConnectionsDashboard(state, dispatch)
    CalendarWriteDashboard(state, dispatch)
    SkillBuilderDashboard(state, dispatch)
    ShortcutKeysDashboard(shortcutSnapshot, onShortcutPublish)
    KeyboardSettingsDashboard(state, dispatch)
    SuggestionTrustDashboard(state, dispatch)
    ActivityCard(state, dispatch)
    PrivacyControlsCard(state, dispatch)
}

@Composable
private fun AccountCard(account: AccountState, dispatch: (HostEvent) -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Account", style = MaterialTheme.typography.titleLarge)
            Text(
                when (account.authStatus) {
                    AuthStatus.ANONYMOUS -> "匿名モードです。通常入力とローカル機能は利用できます。同期、デバイス管理、外部Activityにはサインインが必要です。"
                    AuthStatus.SIGNED_IN -> "サインイン済み（ただし現在はローカルfixture表示のみ）: ${account.displayName.orEmpty()}"
                },
            )
            Text("認証状態: ${authLabel(account.authStatus)}")
            Text("セッション: ${sessionLabel(account.sessionStatus)}")
            account.sessionExpiresAt?.let { Text("有効期限（fixture）: $it") }
            Text("外部identity/backend接続: 未証明", style = MaterialTheme.typography.bodySmall)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (account.authStatus == AuthStatus.ANONYMOUS) {
                    Button(
                        onClick = { dispatch(HostEvent.EnterFixtureSignedIn) },
                        modifier = Modifier.semantics { contentDescription = "Show local fixture signed-in state" },
                    ) { Text("fixtureサインイン状態を表示") }
                } else {
                    TextButton(onClick = { dispatch(HostEvent.SimulateSessionExpiry) }) { Text("期限切れを表示") }
                    TextButton(onClick = { dispatch(HostEvent.SimulateSessionRevocation) }) { Text("revoke状態を表示") }
                }
            }
        }
    }
}

@Composable
private fun DevicesCard(state: HostAppState, dispatch: (HostEvent) -> Unit) {
    val pending = state.devices.firstOrNull { it.id == state.pendingRevokeDeviceId }
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Devices", style = MaterialTheme.typography.titleLarge)
            Text("現在の端末とセッション状態。revokeはfixture内の確認フローです。", style = MaterialTheme.typography.bodySmall)
            state.devices.forEach { device -> DeviceRow(device, dispatch) }
        }
    }
    if (pending != null) {
        AlertDialog(
            onDismissRequest = { dispatch(HostEvent.CancelDeviceRevoke) },
            title = { Text("デバイスをrevokeしますか？") },
            text = { Text("${pending.label} の新しいセッションを停止します。既存セッションの外部反映は未証明です。") },
            confirmButton = {
                TextButton(onClick = { dispatch(HostEvent.ConfirmDeviceRevoke) }) { Text("revoke") }
            },
            dismissButton = {
                TextButton(onClick = { dispatch(HostEvent.CancelDeviceRevoke) }) { Text("キャンセル") }
            },
        )
    }
}

@Composable
private fun DeviceRow(device: DeviceState, dispatch: (HostEvent) -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Device ${device.label}" },
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Column(modifier = Modifier.weight(1f)) {
                Text(device.label, fontWeight = FontWeight.Bold)
                Text("${device.platform} · ${if (device.isCurrent) "current device" else "remote device"}")
                Text("最終確認: ${device.lastSeenAt}", style = MaterialTheme.typography.bodySmall)
            }
            Text(if (device.status == DeviceStatus.ACTIVE) "active" else "revoked")
        }
        if (device.status == DeviceStatus.ACTIVE) {
            TextButton(
                onClick = { dispatch(HostEvent.RequestDeviceRevoke(device.id)) },
                modifier = Modifier.semantics { contentDescription = "Revoke ${device.label}" },
            ) { Text("revoke確認") }
        } else {
            Text("revoke済み: ${device.revokedAt.orEmpty()}", style = MaterialTheme.typography.bodySmall)
        }
        HorizontalDivider()
    }
}

@Composable
private fun ActivityCard(state: HostAppState, dispatch: (HostEvent) -> Unit) {
    val selected = state.runs.firstOrNull { it.id == state.selectedRunId }
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Activity", style = MaterialTheme.typography.titleLarge)
            Text("content-free receiptのみを表示します。入力文、選択文、出力文は保存・表示しません。", style = MaterialTheme.typography.bodySmall)
            state.runs.forEach { run -> ActivityRow(run, selected?.id == run.id, dispatch) }
            selected?.let { ActivityDetail(it) }
        }
    }
}

@Composable
private fun ActivityRow(run: ActivityRun, selected: Boolean, dispatch: (HostEvent) -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth()
            .clickable { dispatch(HostEvent.SelectRun(if (selected) null else run.id)) }
            .padding(vertical = 8.dp)
            .semantics { contentDescription = "Activity ${run.skillId}, ${run.status}" },
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(run.skillId, fontWeight = FontWeight.Bold)
            Text(runStatusLabel(run.status))
        }
        Text("risk ${run.riskClass} · plan v${run.plan.version} · ${run.createdAt}")
        Text(if (selected) "詳細を表示中" else "タップして詳細", style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun ActivityDetail(run: ActivityRun) {
    Card(modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Activity detail" }) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text("Run detail", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text("immutable plan version: v${run.plan.version}")
            Text("plan digest: ${run.plan.digest}")
            Text("risk class: ${run.riskClass}")
            Text("status: ${runStatusLabel(run.status)}")
            Text("created: ${run.createdAt}")
            Text("updated: ${run.updatedAt}")
            Text("receipt: ${run.receipt.summary}")
            run.receipt.failureClass?.let { Text("failure class: $it") }
            if (run.receipt.completedSteps.isNotEmpty()) Text("completed: ${run.receipt.completedSteps.joinToString()}")
            if (run.receipt.failedSteps.isNotEmpty()) Text("failed: ${run.receipt.failedSteps.joinToString()}")
            if (run.receipt.notStartedSteps.isNotEmpty()) Text("not started: ${run.receipt.notStartedSteps.joinToString()}")
            Text("undo: ${if (run.receipt.undoAvailable) "available" else "not available"}")
        }
    }
}

@Composable
private fun PrivacyControlsCard(state: HostAppState, dispatch: (HostEvent) -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Privacy & deletion", style = MaterialTheme.typography.titleLarge)
            Text("保持期間はreceiptとsecurity metadataの設定です。未送信のキー入力は対象外です。")
            RetentionPolicy.values().forEach { policy ->
                Row(
                    modifier = Modifier.fillMaxWidth().clickable { dispatch(HostEvent.SelectRetention(policy)) },
                    verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                ) {
                    RadioButton(
                        selected = state.retention == policy,
                        onClick = { dispatch(HostEvent.SelectRetention(policy)) },
                    )
                    Text(retentionLabel(policy))
                }
            }
            Text("現在の保持設定: ${retentionLabel(state.retention)}")
            Text("削除状態: ${deletionLabel(state.deletion.status)}")
            state.deletion.resultMessage?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
            when (state.deletion.status) {
                DeletionStatus.NOT_REQUESTED -> Button(onClick = { dispatch(HostEvent.RequestDeletion) }) { Text("削除をリクエスト") }
                DeletionStatus.REQUESTED, DeletionStatus.IN_PROGRESS -> Button(onClick = { dispatch(HostEvent.AdvanceDeletion) }) { Text("fixture削除を進める") }
                DeletionStatus.COMPLETED, DeletionStatus.FAILED -> Text("削除結果を確認済み", style = MaterialTheme.typography.bodySmall)
            }
            Text("外部providerのrevocation・削除・backup expiryは未証明です。", style = MaterialTheme.typography.bodySmall)
        }
    }
}

private fun authLabel(status: AuthStatus) = when (status) {
    AuthStatus.ANONYMOUS -> "anonymous / sign-in required"
    AuthStatus.SIGNED_IN -> "signed in (local fixture)"
}

private fun sessionLabel(status: SessionStatus) = when (status) {
    SessionStatus.NOT_AUTHENTICATED -> "not authenticated"
    SessionStatus.ACTIVE -> "active"
    SessionStatus.EXPIRED -> "expired — sign in again required"
    SessionStatus.REVOKED -> "revoked — new operations blocked"
}

private fun runStatusLabel(status: RunStatus) = when (status) {
    RunStatus.SUCCEEDED -> "succeeded"
    RunStatus.FAILED -> "failed"
    RunStatus.PARTIAL -> "partial"
    RunStatus.UNKNOWN -> "unknown"
    RunStatus.PENDING -> "pending"
}

private fun retentionLabel(policy: RetentionPolicy) = when (policy) {
    RetentionPolicy.THIRTY_DAYS -> "30日後に削除"
    RetentionPolicy.NINETY_DAYS -> "90日後に削除（標準）"
    RetentionPolicy.UNTIL_DELETED -> "手動削除まで保持"
}

private fun deletionLabel(status: DeletionStatus) = when (status) {
    DeletionStatus.NOT_REQUESTED -> "未依頼"
    DeletionStatus.REQUESTED -> "依頼済み"
    DeletionStatus.IN_PROGRESS -> "処理中"
    DeletionStatus.COMPLETED -> "完了"
    DeletionStatus.FAILED -> "失敗"
}
