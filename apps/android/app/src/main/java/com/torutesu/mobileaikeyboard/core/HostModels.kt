package com.torutesu.mobileaikeyboard.core

/** Provider-neutral W3 host-app models. These models intentionally contain no raw content. */
enum class AuthStatus { ANONYMOUS, SIGNED_IN }
enum class SessionStatus { NOT_AUTHENTICATED, ACTIVE, EXPIRED, REVOKED }
enum class DataOrigin { LOCAL_FIXTURE, UNVERIFIED_REMOTE }
enum class DeviceStatus { ACTIVE, REVOKED }
enum class RunStatus { SUCCEEDED, FAILED, PARTIAL, UNKNOWN, PENDING }
enum class RiskClass { R0, R1, R2, R3, R4, R5 }
enum class RetentionPolicy { THIRTY_DAYS, NINETY_DAYS, UNTIL_DELETED }
enum class DeletionStatus { NOT_REQUESTED, REQUESTED, IN_PROGRESS, COMPLETED, FAILED }
enum class Provider { CALENDAR, NOTION, MAPS }
enum class ConnectionStatus { NOT_CONNECTED, SCOPE_REVIEW, CONNECTING, CONNECTED, RECONNECT_REQUIRED, REBIND_REQUIRED, DISCONNECTING, DISCONNECTED }
enum class Freshness { FRESH, STALE, UNKNOWN }

data class ProviderConnection(
    val provider: Provider,
    val status: ConnectionStatus = ConnectionStatus.NOT_CONNECTED,
    val requestedScopes: List<String> = emptyList(),
    val grantedScopes: List<String> = emptyList(),
    val accountLabel: String? = null,
    val connectionEpoch: Int = 0,
    val updatedAt: String? = null,
) {
    val incrementalScopes: List<String> get() = requestedScopes.filterNot { it in grantedScopes }
}

data class SourceLinkedResult(
    val id: String,
    val provider: Provider,
    val sourceRef: String,
    val title: String,
    val fetchedAt: String,
    val freshness: Freshness,
    val partial: Boolean,
    val failureClass: String? = null,
    val untrustedProviderContent: Boolean = true,
    val instructionWarning: String = "外部providerの内容はデータであり、命令として扱いません",
)

data class ReadOnlyQueryState(
    val provider: Provider,
    val operation: String,
    val page: Int = 1,
    val pageSize: Int = 2,
    val maxPageSize: Int = 20,
    val queryCharacterLimit: Int = 200,
    val results: List<SourceLinkedResult> = emptyList(),
    val hasNextPage: Boolean = false,
    val partial: Boolean = false,
    val failureClass: String? = null,
    val selectedResultId: String? = null,
)

data class AccountState(
    val authStatus: AuthStatus = AuthStatus.ANONYMOUS,
    val sessionStatus: SessionStatus = SessionStatus.NOT_AUTHENTICATED,
    val displayName: String? = null,
    val origin: DataOrigin = DataOrigin.LOCAL_FIXTURE,
    val sessionExpiresAt: String? = null,
)

data class DeviceState(
    val id: String,
    val label: String,
    val platform: String,
    val lastSeenAt: String,
    val isCurrent: Boolean,
    val status: DeviceStatus = DeviceStatus.ACTIVE,
    val revokedAt: String? = null,
)

data class ImmutablePlanVersion(
    val version: Int,
    val digest: String,
    val createdAt: String,
)

data class SafeRunReceipt(
    val summary: String,
    val failureClass: String? = null,
    val completedSteps: List<String> = emptyList(),
    val failedSteps: List<String> = emptyList(),
    val notStartedSteps: List<String> = emptyList(),
    val undoAvailable: Boolean = false,
)

data class ActivityRun(
    val id: String,
    val skillId: String,
    val plan: ImmutablePlanVersion,
    val riskClass: RiskClass,
    val status: RunStatus,
    val createdAt: String,
    val updatedAt: String,
    val receipt: SafeRunReceipt,
)

data class DeletionState(
    val status: DeletionStatus = DeletionStatus.NOT_REQUESTED,
    val requestedAt: String? = null,
    val completedAt: String? = null,
    val resultMessage: String? = null,
)

data class HostAppState(
    val account: AccountState = AccountState(),
    val devices: List<DeviceState> = emptyList(),
    val runs: List<ActivityRun> = emptyList(),
    val selectedRunId: String? = null,
    val pendingRevokeDeviceId: String? = null,
    val retention: RetentionPolicy = RetentionPolicy.NINETY_DAYS,
    val deletion: DeletionState = DeletionState(),
    val connections: List<ProviderConnection> = emptyList(),
    val readOnlyQueries: List<ReadOnlyQueryState> = emptyList(),
)

sealed interface HostEvent {
    data object EnterFixtureSignedIn : HostEvent
    data object SimulateSessionExpiry : HostEvent
    data object SimulateSessionRevocation : HostEvent
    data class RequestDeviceRevoke(val deviceId: String) : HostEvent
    data object CancelDeviceRevoke : HostEvent
    data object ConfirmDeviceRevoke : HostEvent
    data class SelectRun(val runId: String?) : HostEvent
    data class SelectRetention(val policy: RetentionPolicy) : HostEvent
    data object RequestDeletion : HostEvent
    data object AdvanceDeletion : HostEvent
    data class ReviewConnection(val provider: Provider) : HostEvent
    data class BeginConnection(val provider: Provider) : HostEvent
    data class CompleteFixtureConnection(val provider: Provider) : HostEvent
    data class MarkReconnectRequired(val provider: Provider) : HostEvent
    data class MarkRebindRequired(val provider: Provider) : HostEvent
    data class RequestDisconnect(val provider: Provider) : HostEvent
    data class CompleteDisconnect(val provider: Provider) : HostEvent
    data class RunReadOnly(val provider: Provider) : HostEvent
    data class NextResults(val provider: Provider) : HostEvent
    data class SelectResult(val provider: Provider, val resultId: String?) : HostEvent
}

object HostFixtureClient {
    private const val NOW = "2026-08-26T09:00:00Z"
    private fun planDigest(seed: String) = "sha256:${TextFingerprint.of(seed)}"

    fun initialState(): HostAppState = HostAppState(
        devices = listOf(
            DeviceState("device-current", "このAndroid端末", "Android", NOW, isCurrent = true),
            DeviceState("device-desktop", "MacBook Pro", "macOS", "2026-08-25T18:22:00Z", isCurrent = false),
        ),
        runs = listOf(
            ActivityRun(
                id = "run-local-001",
                skillId = "local.polite-rewrite",
                plan = ImmutablePlanVersion(1, planDigest("fixture-plan-001"), "2026-08-26T08:44:00Z"),
                riskClass = RiskClass.R1,
                status = RunStatus.SUCCEEDED,
                createdAt = "2026-08-26T08:44:00Z",
                updatedAt = "2026-08-26T08:44:01Z",
                receipt = SafeRunReceipt("ローカル文章変換を適用しました", undoAvailable = true),
            ),
            ActivityRun(
                id = "run-calendar-002",
                skillId = "calendar.availability.read",
                plan = ImmutablePlanVersion(2, planDigest("fixture-plan-002"), "2026-08-25T13:10:00Z"),
                riskClass = RiskClass.R2,
                status = RunStatus.PARTIAL,
                createdAt = "2026-08-25T13:10:00Z",
                updatedAt = "2026-08-25T13:10:04Z",
                receipt = SafeRunReceipt(
                    summary = "一部の読み取り結果を取得しました",
                    failureClass = "provider_timeout",
                    completedSteps = listOf("calendar.availability.read"),
                    failedSteps = listOf("receipt.sync"),
                ),
            ),
            ActivityRun(
                id = "run-expired-003",
                skillId = "notion.pages.search",
                plan = ImmutablePlanVersion(1, planDigest("fixture-plan-003"), "2026-08-24T10:02:00Z"),
                riskClass = RiskClass.R2,
                status = RunStatus.FAILED,
                createdAt = "2026-08-24T10:02:00Z",
                updatedAt = "2026-08-24T10:02:02Z",
                receipt = SafeRunReceipt("実行されませんでした", failureClass = "session_expired"),
            ),
        ),
        connections = listOf(
            ProviderConnection(Provider.CALENDAR, requestedScopes = listOf("calendar.availability.read")),
            ProviderConnection(Provider.NOTION, requestedScopes = listOf("notion.pages.search")),
            ProviderConnection(Provider.MAPS, requestedScopes = listOf("maps.places.search")),
        ),
    )

    fun dispatch(state: HostAppState, event: HostEvent): HostAppState = when (event) {
        HostEvent.EnterFixtureSignedIn -> state.copy(
            account = state.account.copy(
                authStatus = AuthStatus.SIGNED_IN,
                sessionStatus = SessionStatus.ACTIVE,
                displayName = "Fixture account（実接続なし）",
                origin = DataOrigin.LOCAL_FIXTURE,
                sessionExpiresAt = "2026-08-26T10:00:00Z",
            ),
        )
        HostEvent.SimulateSessionExpiry -> state.copy(account = state.account.copy(sessionStatus = SessionStatus.EXPIRED))
        HostEvent.SimulateSessionRevocation -> state.copy(account = state.account.copy(sessionStatus = SessionStatus.REVOKED))
        is HostEvent.RequestDeviceRevoke -> if (state.devices.any { it.id == event.deviceId && it.status == DeviceStatus.ACTIVE }) {
            state.copy(pendingRevokeDeviceId = event.deviceId)
        } else state
        HostEvent.CancelDeviceRevoke -> state.copy(pendingRevokeDeviceId = null)
        HostEvent.ConfirmDeviceRevoke -> {
            val id = state.pendingRevokeDeviceId
            if (id == null) state else state.copy(
                devices = state.devices.map { device ->
                    if (device.id == id) device.copy(status = DeviceStatus.REVOKED, revokedAt = NOW) else device
                },
                pendingRevokeDeviceId = null,
                account = if (state.devices.firstOrNull { it.id == id }?.isCurrent == true) {
                    state.account.copy(sessionStatus = SessionStatus.REVOKED)
                } else state.account,
            )
        }
        is HostEvent.SelectRun -> if (event.runId == null || state.runs.any { it.id == event.runId }) state.copy(selectedRunId = event.runId) else state
        is HostEvent.SelectRetention -> state.copy(retention = event.policy)
        HostEvent.RequestDeletion -> if (state.deletion.status == DeletionStatus.NOT_REQUESTED) {
            state.copy(deletion = DeletionState(DeletionStatus.REQUESTED, requestedAt = NOW))
        } else state
        HostEvent.AdvanceDeletion -> when (state.deletion.status) {
            DeletionStatus.REQUESTED -> state.copy(deletion = state.deletion.copy(status = DeletionStatus.IN_PROGRESS))
            DeletionStatus.IN_PROGRESS -> state.copy(
                account = AccountState(origin = DataOrigin.LOCAL_FIXTURE),
                devices = emptyList(),
                runs = emptyList(),
                selectedRunId = null,
                pendingRevokeDeviceId = null,
                connections = emptyList(),
                readOnlyQueries = emptyList(),
                deletion = state.deletion.copy(
                    status = DeletionStatus.COMPLETED,
                    completedAt = NOW,
                    resultMessage = "アクティブなfixtureデータを削除しました。外部サービスの削除は未証明です。",
                ),
            )
            else -> state
        }
        is HostEvent.ReviewConnection -> state.updateConnection(event.provider) {
            if (it.status == ConnectionStatus.NOT_CONNECTED || it.status == ConnectionStatus.DISCONNECTED) {
                it.copy(status = ConnectionStatus.SCOPE_REVIEW)
            } else it
        }
        is HostEvent.BeginConnection -> state.updateConnection(event.provider) {
            if (it.status == ConnectionStatus.SCOPE_REVIEW || it.status == ConnectionStatus.RECONNECT_REQUIRED || it.status == ConnectionStatus.REBIND_REQUIRED) {
                it.copy(status = ConnectionStatus.CONNECTING)
            } else it
        }
        is HostEvent.CompleteFixtureConnection -> state.updateConnection(event.provider) {
            if (it.status == ConnectionStatus.CONNECTING) it.copy(
                status = ConnectionStatus.CONNECTED,
                grantedScopes = it.requestedScopes,
                accountLabel = "${it.provider.name.lowercase()} fixture account（実OAuthなし）",
                connectionEpoch = it.connectionEpoch + 1,
                updatedAt = NOW,
            ) else it
        }
        is HostEvent.MarkReconnectRequired -> state.updateConnection(event.provider) {
            if (it.status == ConnectionStatus.CONNECTED) it.copy(status = ConnectionStatus.RECONNECT_REQUIRED, updatedAt = NOW) else it
        }
        is HostEvent.MarkRebindRequired -> state.updateConnection(event.provider) {
            if (it.status == ConnectionStatus.CONNECTED) it.copy(status = ConnectionStatus.REBIND_REQUIRED, updatedAt = NOW) else it
        }
        is HostEvent.RequestDisconnect -> state.updateConnection(event.provider) {
            if (it.status == ConnectionStatus.CONNECTED || it.status == ConnectionStatus.RECONNECT_REQUIRED || it.status == ConnectionStatus.REBIND_REQUIRED) {
                it.copy(status = ConnectionStatus.DISCONNECTING, updatedAt = NOW)
            } else it
        }
        is HostEvent.CompleteDisconnect -> state.updateConnection(event.provider) {
            if (it.status == ConnectionStatus.DISCONNECTING) it.copy(
                status = ConnectionStatus.DISCONNECTED,
                grantedScopes = emptyList(),
                accountLabel = null,
                updatedAt = NOW,
            ) else it
        }.updateQuery(event.provider) { it.copy(results = emptyList(), hasNextPage = false, selectedResultId = null, failureClass = "connection_required", partial = false) }
        is HostEvent.RunReadOnly -> state.runReadOnly(event.provider)
        is HostEvent.NextResults -> state.nextResults(event.provider)
        is HostEvent.SelectResult -> state.updateQuery(event.provider) {
            if (event.resultId == null || it.results.any { result -> result.id == event.resultId }) it.copy(selectedResultId = event.resultId) else it
        }
    }

    private fun HostAppState.updateConnection(provider: Provider, update: (ProviderConnection) -> ProviderConnection): HostAppState =
        copy(connections = connections.map { if (it.provider == provider) update(it) else it })

    private fun HostAppState.updateQuery(provider: Provider, update: (ReadOnlyQueryState) -> ReadOnlyQueryState): HostAppState =
        copy(readOnlyQueries = readOnlyQueries.map { if (it.provider == provider) update(it) else it })

    private fun HostAppState.runReadOnly(provider: Provider): HostAppState {
        val connection = connections.firstOrNull { it.provider == provider } ?: return this
        val query = readOnlyQueries.firstOrNull { it.provider == provider }
            ?: ReadOnlyQueryState(provider, operationFor(provider))
        if (connection.status != ConnectionStatus.CONNECTED) {
            val failedQuery = query.copy(results = emptyList(), hasNextPage = false, failureClass = "connection_required", partial = false, selectedResultId = null)
            return copy(readOnlyQueries = readOnlyQueries.filterNot { it.provider == provider } + failedQuery)
                .appendReadOnlyReceipt(provider, failedQuery)
        }
        val fixture = fixtureResults(provider)
        val boundedPageSize = query.pageSize.coerceIn(1, query.maxPageSize)
        val firstPage = fixture.take(boundedPageSize)
        val next = fixture.size > firstPage.size
        val nextQuery = query.copy(
            page = 1,
            pageSize = boundedPageSize,
            results = firstPage,
            hasNextPage = next,
            partial = firstPage.any { it.partial },
            failureClass = firstPage.firstOrNull { it.failureClass != null }?.failureClass,
            selectedResultId = null,
        )
        val nextState = copy(readOnlyQueries = (readOnlyQueries.filterNot { it.provider == provider } + nextQuery))
        return nextState.appendReadOnlyReceipt(provider, nextQuery)
    }

    private fun HostAppState.nextResults(provider: Provider): HostAppState {
        val query = readOnlyQueries.firstOrNull { it.provider == provider } ?: return this
        val connection = connections.firstOrNull { it.provider == provider }
        if (connection?.status != ConnectionStatus.CONNECTED || !query.hasNextPage) return this
        val fixture = fixtureResults(provider)
        val start = query.page * query.pageSize
        val page = fixture.drop(start).take(query.pageSize)
        val nextQuery = query.copy(
            page = query.page + 1,
            results = page,
            hasNextPage = fixture.size > start + page.size,
            partial = page.any { it.partial },
            failureClass = page.firstOrNull { it.failureClass != null }?.failureClass,
            selectedResultId = null,
        )
        return copy(readOnlyQueries = readOnlyQueries.map { if (it.provider == provider) nextQuery else it })
    }

    private fun HostAppState.appendReadOnlyReceipt(provider: Provider, query: ReadOnlyQueryState): HostAppState {
        val failed = query.failureClass != null && query.results.isEmpty()
        val run = ActivityRun(
            id = "run-${provider.name.lowercase()}-${query.page}-${runs.size + 1}",
            skillId = query.operation,
            plan = ImmutablePlanVersion(1, planDigest("${query.operation}|${query.page}|${query.pageSize}|${runs.size + 1}"), NOW),
            riskClass = RiskClass.R2,
            status = if (failed) RunStatus.FAILED else if (query.partial || query.failureClass != null) RunStatus.PARTIAL else RunStatus.SUCCEEDED,
            createdAt = NOW,
            updatedAt = NOW,
            receipt = SafeRunReceipt(
                summary = "read-only結果を取得しました。外部への変更はありません。",
                failureClass = query.failureClass,
                completedSteps = if (failed) emptyList() else listOf(query.operation),
                failedSteps = if (failed) listOf(query.operation) else emptyList(),
            ),
        )
        return copy(runs = listOf(run) + runs)
    }

    private fun operationFor(provider: Provider) = when (provider) {
        Provider.CALENDAR -> "calendar.availability.read"
        Provider.NOTION -> "notion.pages.search"
        Provider.MAPS -> "maps.places.search"
    }

    private fun fixtureResults(provider: Provider): List<SourceLinkedResult> = when (provider) {
        Provider.CALENDAR -> listOf(
            SourceLinkedResult("calendar-1", provider, "calendar://availability/fixture-1", "空き時間候補（fixture）", NOW, Freshness.FRESH, partial = false),
            SourceLinkedResult("calendar-2", provider, "calendar://availability/fixture-2", "一部取得できない時間帯", NOW, Freshness.UNKNOWN, partial = true, failureClass = "provider_timeout"),
            SourceLinkedResult("calendar-3", provider, "calendar://availability/fixture-3", "別日の空き時間候補", NOW, Freshness.FRESH, partial = false),
        )
        Provider.NOTION -> listOf(
            SourceLinkedResult("notion-1", provider, "notion://page/fixture-1", "プロジェクト概要（fixture）", NOW, Freshness.FRESH, partial = false),
            SourceLinkedResult("notion-2", provider, "notion://page/fixture-2", "運用メモ（fixture）", NOW, Freshness.FRESH, partial = false),
            SourceLinkedResult("notion-3", provider, "notion://page/fixture-3", "アーカイブ済みメモ（fixture）", NOW, Freshness.STALE, partial = false),
        )
        Provider.MAPS -> listOf(
            SourceLinkedResult("maps-1", provider, "maps://place/fixture-1", "駅周辺の候補（fixture）", NOW, Freshness.FRESH, partial = false),
            SourceLinkedResult("maps-2", provider, "maps://place/fixture-2", "営業時間が古い候補", NOW, Freshness.STALE, partial = true, failureClass = "stale_provider_data"),
            SourceLinkedResult("maps-3", provider, "maps://place/fixture-3", "別エリアの候補（fixture）", NOW, Freshness.FRESH, partial = false),
        )
    }
}
