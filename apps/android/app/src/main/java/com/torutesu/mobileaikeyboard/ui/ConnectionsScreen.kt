package com.torutesu.mobileaikeyboard.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.torutesu.mobileaikeyboard.core.ConnectionStatus
import com.torutesu.mobileaikeyboard.core.Freshness
import com.torutesu.mobileaikeyboard.core.HostAppState
import com.torutesu.mobileaikeyboard.core.HostEvent
import com.torutesu.mobileaikeyboard.core.Provider
import com.torutesu.mobileaikeyboard.core.ProviderConnection
import com.torutesu.mobileaikeyboard.core.ReadOnlyQueryState
import com.torutesu.mobileaikeyboard.core.SourceLinkedResult

@Composable
fun ConnectionsDashboard(state: HostAppState, dispatch: (HostEvent) -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Connections", style = MaterialTheme.typography.titleLarge)
            Text("read-only接続のみ。OAuth、network、secretはこのfixtureに存在しません。")
            state.connections.forEach { connection ->
                ConnectionRow(connection, dispatch)
                state.readOnlyQueries.firstOrNull { it.provider == connection.provider }?.let {
                    ReadOnlyResults(it, dispatch)
                }
                HorizontalDivider()
            }
            Text("実OAuth・provider token・外部identity/backend接続は未証明です。", style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun ConnectionRow(connection: ProviderConnection, dispatch: (HostEvent) -> Unit) {
    val provider = connection.provider
    Column(
        modifier = Modifier.fillMaxWidth().semantics { contentDescription = "${providerLabel(provider)} connection" },
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(providerLabel(provider), fontWeight = FontWeight.Bold)
            Text(connectionStatusLabel(connection.status))
        }
        Text("操作: ${operationLabel(provider)}")
        Text("権限: ${connection.requestedScopes.joinToString()}", style = MaterialTheme.typography.bodySmall)
        if (connection.incrementalScopes.isNotEmpty()) {
            Text("追加で確認する権限: ${connection.incrementalScopes.joinToString()}")
        } else if (connection.grantedScopes.isNotEmpty()) {
            Text("確認済み権限: ${connection.grantedScopes.joinToString()}")
        }
        connection.accountLabel?.let { Text("account: $it", style = MaterialTheme.typography.bodySmall) }
        Text("connection epoch: ${connection.connectionEpoch}", style = MaterialTheme.typography.bodySmall)
        ConnectionActions(connection, dispatch)
    }
}

@Composable
private fun ConnectionActions(connection: ProviderConnection, dispatch: (HostEvent) -> Unit) {
    val provider = connection.provider
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        when (connection.status) {
            ConnectionStatus.NOT_CONNECTED, ConnectionStatus.DISCONNECTED ->
                Button(onClick = { dispatch(HostEvent.ReviewConnection(provider)) }) { Text("scope確認") }
            ConnectionStatus.SCOPE_REVIEW ->
                Button(onClick = { dispatch(HostEvent.BeginConnection(provider)) }) { Text("fixture接続開始") }
            ConnectionStatus.CONNECTING ->
                Button(onClick = { dispatch(HostEvent.CompleteFixtureConnection(provider)) }) { Text("接続結果を表示") }
            ConnectionStatus.CONNECTED -> {
                TextButton(onClick = { dispatch(HostEvent.MarkReconnectRequired(provider)) }) { Text("reconnect") }
                TextButton(onClick = { dispatch(HostEvent.MarkRebindRequired(provider)) }) { Text("rebind") }
                TextButton(onClick = { dispatch(HostEvent.RequestDisconnect(provider)) }) { Text("disconnect") }
            }
            ConnectionStatus.RECONNECT_REQUIRED ->
                Button(onClick = { dispatch(HostEvent.BeginConnection(provider)) }) { Text("reconnect確認") }
            ConnectionStatus.REBIND_REQUIRED ->
                Button(onClick = { dispatch(HostEvent.BeginConnection(provider)) }) { Text("rebind確認") }
            ConnectionStatus.DISCONNECTING ->
                Button(onClick = { dispatch(HostEvent.CompleteDisconnect(provider)) }) { Text("disconnect結果") }
        }
    }
    if (connection.status == ConnectionStatus.CONNECTED) {
        Button(
            onClick = { dispatch(HostEvent.RunReadOnly(provider)) },
            modifier = Modifier.semantics { contentDescription = "Run read-only ${providerLabel(provider)} fixture" },
        ) { Text("read-only検索を実行") }
    }
}

@Composable
private fun ReadOnlyResults(query: ReadOnlyQueryState, dispatch: (HostEvent) -> Unit) {
    Column(modifier = Modifier.fillMaxWidth().padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
        Text("Results · ${operationLabel(query.provider)}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        Text("page ${query.page} · page size ${query.pageSize}/${query.maxPageSize} · query limit ${query.queryCharacterLimit}文字")
        query.failureClass?.let { Text("failure: $it") }
        if (query.partial) Text("partial: 一部結果のみ。全件成功とは扱いません。")
        query.results.forEach { result -> SourceResultRow(result, query.selectedResultId == result.id, dispatch) }
        if (query.results.isEmpty() && query.failureClass == "connection_required") {
            Text("接続が必要です。scope確認から開始してください。")
        }
        if (query.hasNextPage) {
            TextButton(onClick = { dispatch(HostEvent.NextResults(query.provider)) }) { Text("次の結果") }
        }
    }
}

@Composable
private fun SourceResultRow(result: SourceLinkedResult, selected: Boolean, dispatch: (HostEvent) -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth()
            .clickable { dispatch(HostEvent.SelectResult(result.provider, if (selected) null else result.id)) }
            .padding(vertical = 6.dp)
            .semantics { contentDescription = "Source result ${result.title}" },
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Text(result.title, fontWeight = FontWeight.Bold)
        Text("source: ${result.sourceRef}")
        Text("fetchedAt: ${result.fetchedAt} · freshness: ${freshnessLabel(result.freshness)}")
        if (result.partial) Text("partial${result.failureClass?.let { " · failure: $it" } ?: ""}")
        Text("警告: ${result.instructionWarning}", style = MaterialTheme.typography.bodySmall)
        if (selected) Text("選択中（外部書き込み・命令実行はありません）", style = MaterialTheme.typography.bodySmall)
    }
}

private fun providerLabel(provider: Provider) = when (provider) {
    Provider.CALENDAR -> "Calendar"
    Provider.NOTION -> "Notion"
    Provider.MAPS -> "Maps"
}

private fun operationLabel(provider: Provider) = when (provider) {
    Provider.CALENDAR -> "calendar.availability.read"
    Provider.NOTION -> "notion.pages.search"
    Provider.MAPS -> "maps.places.search"
}

private fun connectionStatusLabel(status: ConnectionStatus) = when (status) {
    ConnectionStatus.NOT_CONNECTED -> "未接続"
    ConnectionStatus.SCOPE_REVIEW -> "scope確認"
    ConnectionStatus.CONNECTING -> "接続中（fixture）"
    ConnectionStatus.CONNECTED -> "接続済み（fixture）"
    ConnectionStatus.RECONNECT_REQUIRED -> "再接続が必要"
    ConnectionStatus.REBIND_REQUIRED -> "rebindが必要"
    ConnectionStatus.DISCONNECTING -> "切断中（fixture）"
    ConnectionStatus.DISCONNECTED -> "切断済み"
}

private fun freshnessLabel(freshness: Freshness) = when (freshness) {
    Freshness.FRESH -> "fresh"
    Freshness.STALE -> "stale"
    Freshness.UNKNOWN -> "unknown"
}
