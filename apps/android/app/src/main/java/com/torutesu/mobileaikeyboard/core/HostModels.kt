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
}

object HostFixtureClient {
    private const val NOW = "2026-08-26T09:00:00Z"

    fun initialState(): HostAppState = HostAppState(
        devices = listOf(
            DeviceState("device-current", "このAndroid端末", "Android", NOW, isCurrent = true),
            DeviceState("device-desktop", "MacBook Pro", "macOS", "2026-08-25T18:22:00Z", isCurrent = false),
        ),
        runs = listOf(
            ActivityRun(
                id = "run-local-001",
                skillId = "local.polite-rewrite",
                plan = ImmutablePlanVersion(1, "sha256:fixture-plan-001", "2026-08-26T08:44:00Z"),
                riskClass = RiskClass.R1,
                status = RunStatus.SUCCEEDED,
                createdAt = "2026-08-26T08:44:00Z",
                updatedAt = "2026-08-26T08:44:01Z",
                receipt = SafeRunReceipt("ローカル文章変換を適用しました", undoAvailable = true),
            ),
            ActivityRun(
                id = "run-calendar-002",
                skillId = "calendar.availability.read",
                plan = ImmutablePlanVersion(2, "sha256:fixture-plan-002", "2026-08-25T13:10:00Z"),
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
                plan = ImmutablePlanVersion(1, "sha256:fixture-plan-003", "2026-08-24T10:02:00Z"),
                riskClass = RiskClass.R2,
                status = RunStatus.FAILED,
                createdAt = "2026-08-24T10:02:00Z",
                updatedAt = "2026-08-24T10:02:02Z",
                receipt = SafeRunReceipt("実行されませんでした", failureClass = "session_expired"),
            ),
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
                deletion = state.deletion.copy(
                    status = DeletionStatus.COMPLETED,
                    completedAt = NOW,
                    resultMessage = "アクティブなfixtureデータを削除しました。外部サービスの削除は未証明です。",
                ),
            )
            else -> state
        }
    }
}
