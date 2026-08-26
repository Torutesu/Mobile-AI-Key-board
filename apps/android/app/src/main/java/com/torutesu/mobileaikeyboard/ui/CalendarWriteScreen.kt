package com.torutesu.mobileaikeyboard.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.torutesu.mobileaikeyboard.core.CalendarWritePhase
import com.torutesu.mobileaikeyboard.core.AuthStatus
import com.torutesu.mobileaikeyboard.core.HostAppState
import com.torutesu.mobileaikeyboard.core.HostEvent
import com.torutesu.mobileaikeyboard.core.PrivateCalendarDraft
import com.torutesu.mobileaikeyboard.core.SessionStatus

@Composable
fun CalendarWriteDashboard(state: HostAppState, dispatch: (HostEvent) -> Unit) {
    val write = state.calendarWrite
    val calendar = state.connections.firstOrNull { it.provider.name == "CALENDAR" }
    val activeFixtureSession = state.account.authStatus == AuthStatus.SIGNED_IN && state.account.sessionStatus == SessionStatus.ACTIVE
    val canEnableWrite = activeFixtureSession && calendar?.status?.name == "CONNECTED" && calendar.fixtureWriteCapability.not()
    val writeReady = activeFixtureSession && calendar?.status?.name == "CONNECTED" && calendar.fixtureWriteCapability
    Card(modifier = Modifier.fillMaxWidth().semantics { contentDescription = "R3 private Calendar event write" }) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Calendar · R3 write fixture", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text("許可する書き込みは、招待なしのprivate eventを1件作成することだけです。attendee / invite / repeat はありません。")
            Text("OAuth・provider network・外部identity/backend接続は未証明。これは端末内fixtureです。", style = MaterialTheme.typography.bodySmall)
            Text("接続: ${calendar?.status ?: "未接続"} · exact write fixture capability: ${if (calendar?.fixtureWriteCapability == true) "有効" else "無効"}")
            if (calendar?.fixtureWriteCapability != true) {
                Button(onClick = { dispatch(HostEvent.EnableCalendarWriteFixture) }, enabled = canEnableWrite, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).semantics { contentDescription = "Enable exact Calendar write fixture capability" }) {
                    Text("exact write fixture capabilityを有効化")
                }
                Text("read scopeやOAuth権限とは別の、ローカルfixture専用の明示的な能力です。")
                if (!canEnableWrite) Text("fixtureサインインとCalendar接続を先に完了してください。", style = MaterialTheme.typography.bodySmall)
            }
            if (write.phase == CalendarWritePhase.IDLE || write.phase == CalendarWritePhase.FAILED) {
                Button(onClick = { dispatch(HostEvent.OpenCalendarWrite) }, enabled = writeReady, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).semantics { contentDescription = "Open Calendar event draft" }) {
                    Text("private eventのdraftを開始")
                }
            }
            write.error?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.semantics { contentDescription = "Calendar write error" }) }
            when (write.phase) {
                CalendarWritePhase.DRAFT -> DraftEditor(write.draft, dispatch)
                CalendarWritePhase.REVIEW -> ReviewPanel(state, dispatch)
                CalendarWritePhase.EXECUTING -> OutcomePanel(dispatch)
                CalendarWritePhase.SUCCEEDED -> SuccessPanel(write, dispatch)
                CalendarWritePhase.FAILED, CalendarWritePhase.PARTIAL, CalendarWritePhase.UNKNOWN -> OutcomeReceipt(write, dispatch)
                CalendarWritePhase.RECONCILIATION_REVIEW -> ReconciliationReview(dispatch)
                CalendarWritePhase.RECONCILING -> ReconciliationPanel(write, dispatch)
                CalendarWritePhase.UNDO_REVIEW -> UndoReview(write, dispatch)
                CalendarWritePhase.UNDOING -> Button(onClick = { dispatch(HostEvent.CompleteCalendarUndo) }) { Text("fixture Undoを完了") }
                CalendarWritePhase.UNDONE, CalendarWritePhase.UNDO_EXPIRED -> Text(if (write.phase == CalendarWritePhase.UNDONE) "Undo済み。二重実行はできません。" else "Undo期限切れ。eventの削除は行いません。")
                CalendarWritePhase.IDLE -> Unit
            }
        }
    }
}

@Composable
private fun DraftEditor(draft: PrivateCalendarDraft, dispatch: (HostEvent) -> Unit) {
    Text("1 · Draft", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
    Text("Review前に編集できます。変更すると以前のdigest確認は無効になります。")
    OutlinedTextField(draft.title, { dispatch(HostEvent.UpdateCalendarDraft(draft.copy(title = it))) }, Modifier.fillMaxWidth().semantics { contentDescription = "Calendar event title" }, label = { Text("タイトル") }, singleLine = true)
    OutlinedTextField(draft.start, { dispatch(HostEvent.UpdateCalendarDraft(draft.copy(start = it))) }, Modifier.fillMaxWidth().semantics { contentDescription = "Calendar event start" }, label = { Text("開始 (ISO-8601 UTC)") }, singleLine = true)
    OutlinedTextField(draft.end, { dispatch(HostEvent.UpdateCalendarDraft(draft.copy(end = it))) }, Modifier.fillMaxWidth().semantics { contentDescription = "Calendar event end" }, label = { Text("終了 (ISO-8601 UTC)") }, singleLine = true)
    OutlinedTextField(draft.timezone, { dispatch(HostEvent.UpdateCalendarDraft(draft.copy(timezone = it))) }, Modifier.fillMaxWidth().semantics { contentDescription = "Calendar event timezone" }, label = { Text("タイムゾーン") }, singleLine = true)
    Text("Calendar: ${draft.calendarLabel}（選択肢はprivate fixtureのみ）")
    Text("外部効果: Calendarにprivate eventを1件作成。参加者・招待は送信しません。", style = MaterialTheme.typography.bodySmall)
    Button(onClick = { dispatch(HostEvent.ReviewCalendarWrite) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).semantics { contentDescription = "Review Calendar event disclosure" }) { Text("Review") }
    TextButton(onClick = { dispatch(HostEvent.CancelCalendarWrite) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("キャンセル") }
}

@Composable
private fun ReviewPanel(state: HostAppState, dispatch: (HostEvent) -> Unit) {
    val plan = state.calendarWrite.plan ?: return
    Text("2 · Capture / effect review", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
    Text("送信・変更対象を確認してください。確認はこのdigestに対して一回だけ有効です。")
    Text("開示データ: title / start / end / timezone / private calendar id")
    Text("Service: ${plan.service}（OAuth/provider networkなしのfixture）")
    Text("External effect: ${plan.externalEffect}")
    Text("calendar: ${plan.draft.calendarLabel} · plan v${plan.immutableVersion} · connection epoch ${plan.connectionEpoch}")
    Text("canonical digest: ${plan.digest}", modifier = Modifier.semantics { contentDescription = "Canonical confirmation digest ${plan.digest}" })
    HorizontalDivider()
    Button(onClick = { dispatch(HostEvent.ConfirmCalendarWrite(plan.digest)) }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).semantics { contentDescription = "Confirm one Calendar write" }) { Text("この1件をConfirm") }
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        TextButton(onClick = { dispatch(HostEvent.UpdateCalendarDraft(plan.draft)) }, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) { Text("Edit") }
        TextButton(onClick = { dispatch(HostEvent.CancelCalendarWrite) }, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) { Text("Cancel") }
    }
}

@Composable
private fun OutcomePanel(dispatch: (HostEvent) -> Unit) {
    Text("3 · Executing（fixture simulation）", fontWeight = FontWeight.Bold)
    Text("実providerへ接続していません。結果を選択してreceiptの境界を確認できます。")
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Button(onClick = { dispatch(HostEvent.SetCalendarWriteOutcome(CalendarWritePhase.SUCCEEDED)) }, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) { Text("Succeeded") }
        Button(onClick = { dispatch(HostEvent.SetCalendarWriteOutcome(CalendarWritePhase.FAILED)) }, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) { Text("Failed") }
    }
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Button(onClick = { dispatch(HostEvent.SetCalendarWriteOutcome(CalendarWritePhase.PARTIAL)) }, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) { Text("Partial") }
        Button(onClick = { dispatch(HostEvent.SetCalendarWriteOutcome(CalendarWritePhase.UNKNOWN)) }, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) { Text("Unknown") }
    }
}

@Composable
private fun SuccessPanel(write: com.torutesu.mobileaikeyboard.core.CalendarWriteState, dispatch: (HostEvent) -> Unit) {
    val receipt = write.receipt ?: return
    Text("Succeeded · receipt", fontWeight = FontWeight.Bold)
    Text(receipt.summary)
    Text("resource ref: ${receipt.resourceRef}")
    Text("owner: ${receipt.ownerSubject} · connection epoch: ${receipt.connectionEpoch}")
    Text("Undo expiry: ${receipt.undoExpiresAt}")
    Button(onClick = { dispatch(HostEvent.RequestCalendarUndo) }, enabled = !receipt.undoUsed) { Text("Undo review") }
    TextButton(onClick = { dispatch(HostEvent.ExpireCalendarUndo) }, enabled = !receipt.undoUsed) { Text("fixture期限切れを表示") }
}

@Composable
private fun OutcomeReceipt(write: com.torutesu.mobileaikeyboard.core.CalendarWriteState, dispatch: (HostEvent) -> Unit) {
    val receipt = write.receipt
    Text("${write.phase.name} · receipt", fontWeight = FontWeight.Bold)
    receipt?.let { Text(it.summary); it.failureClass?.let { failure -> Text("failure class: $failure") } }
    if (write.phase == CalendarWritePhase.UNKNOWN) {
        Text("結果不明時はblind retry不可。resource refの照合だけを行います。")
        Button(onClick = { dispatch(HostEvent.RequestCalendarReconciliation) }) { Text("Reconciliation review") }
    }
}

@Composable
private fun ReconciliationReview(dispatch: (HostEvent) -> Unit) {
    Text("Reconciliation review", fontWeight = FontWeight.Bold)
    Text("既存resourceの照合のみ。新規作成や盲目的な再試行はしません。")
    Button(onClick = { dispatch(HostEvent.ConfirmCalendarReconciliation) }) { Text("照合をConfirm") }
}

@Composable
private fun ReconciliationPanel(write: com.torutesu.mobileaikeyboard.core.CalendarWriteState, dispatch: (HostEvent) -> Unit) {
    val ref = write.plan?.let { "calendar://private-event/${it.digest.removePrefix("sha256:").take(16)}" }
    Text("Reconciliation（fixture）", fontWeight = FontWeight.Bold)
    Button(onClick = { dispatch(HostEvent.CompleteCalendarReconciliation(true, ref)) }) { Text("既存eventを発見") }
    TextButton(onClick = { dispatch(HostEvent.CompleteCalendarReconciliation(false)) }) { Text("見つからない") }
}

@Composable
private fun UndoReview(write: com.torutesu.mobileaikeyboard.core.CalendarWriteState, dispatch: (HostEvent) -> Unit) {
    val ref = write.receipt?.resourceRef ?: return
    Text("Undo review", fontWeight = FontWeight.Bold)
    Text("このexact resourceだけを一回削除します: $ref")
    Button(onClick = { dispatch(HostEvent.ConfirmCalendarUndo(ref)) }) { Text("UndoをConfirm") }
    TextButton(onClick = { dispatch(HostEvent.CancelCalendarWrite) }) { Text("キャンセル") }
}
