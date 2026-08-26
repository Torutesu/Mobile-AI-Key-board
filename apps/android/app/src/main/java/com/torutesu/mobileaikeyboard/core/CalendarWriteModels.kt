package com.torutesu.mobileaikeyboard.core

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.Instant

/** The only W5 write allowed by this fixture: an invite-free private event. */
enum class CalendarWritePhase {
    IDLE,
    DRAFT,
    REVIEW,
    EXECUTING,
    SUCCEEDED,
    FAILED,
    PARTIAL,
    UNKNOWN,
    RECONCILIATION_REVIEW,
    RECONCILING,
    UNDO_REVIEW,
    UNDOING,
    UNDONE,
    UNDO_EXPIRED,
}

data class PrivateCalendarDraft(
    val title: String = "打ち合わせ（fixture）",
    val start: String = "2026-08-27T10:00:00Z",
    val end: String = "2026-08-27T11:00:00Z",
    val timezone: String = "Asia/Tokyo",
    val calendarId: String = "fixture-private-calendar",
    val calendarLabel: String = "Private Calendar（fixture）",
)

data class PrivateCalendarPlan(
    val draft: PrivateCalendarDraft,
    val canonicalPayload: String,
    val digest: String,
    val immutableVersion: Int,
    val createdAt: String,
    val connectionEpoch: Int,
    val ownerSubject: String,
    val expiresAt: String = "2026-08-26T09:15:00Z",
    val idempotencyKey: String = digest.removePrefix("sha256:").take(24),
    val service: String = "Calendar",
    val externalEffect: String = "招待なしのprivate eventを1件作成",
)

data class PrivateCalendarReceipt(
    val status: CalendarWritePhase,
    val summary: String,
    val resourceRef: String? = null,
    val ownerSubject: String? = null,
    val connectionEpoch: Int? = null,
    val failureClass: String? = null,
    val createdAt: String,
    val undoExpiresAt: String? = null,
    val undoUsed: Boolean = false,
    val reconciliationRequired: Boolean = false,
)

data class CalendarWriteState(
    val phase: CalendarWritePhase = CalendarWritePhase.IDLE,
    val draft: PrivateCalendarDraft = PrivateCalendarDraft(),
    val plan: PrivateCalendarPlan? = null,
    val confirmedDigest: String? = null,
    val receipt: PrivateCalendarReceipt? = null,
    val error: String? = null,
    /** Fixture clock supplied by the host; this keeps expiry deterministic and testable. */
    val observedAt: String = "2026-08-26T09:00:00Z",
)

object CalendarWriteCanonicalizer {
    private const val MAX_TITLE_CODE_POINTS = 200
    private const val FIXTURE_CALENDAR_ID = "fixture-private-calendar"

    fun validate(draft: PrivateCalendarDraft): String? = when {
        draft.title.isBlank() -> "タイトルを入力してください"
        draft.title.codePointCount(0, draft.title.length) > MAX_TITLE_CODE_POINTS -> "タイトルは200文字以内です"
        draft.calendarId != FIXTURE_CALENDAR_ID -> "選択できるカレンダーはprivate fixtureのみです"
        draft.timezone.isBlank() -> "タイムゾーンを指定してください"
        parse(draft.start) == null -> "開始日時の形式が不正です"
        parse(draft.end) == null -> "終了日時の形式が不正です"
        parse(draft.start)!! >= parse(draft.end)!! -> "終了日時は開始日時より後にしてください"
        else -> null
    }

    fun canonicalPayload(
        draft: PrivateCalendarDraft,
        ownerSubject: String = "",
        connectionEpoch: Int = 0,
        immutableVersion: Int = 1,
        expiresAt: String = "",
    ): String {
        fun quote(value: String): String = "\"${value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")}\""
        return "{" + listOf(
            "\"attendees\":[]",
            "\"calendar_id\":${quote(draft.calendarId)}",
            "\"end\":${quote(draft.end)}",
            "\"external_effect\":${quote("招待なしのprivate eventを1件作成")}",
            "\"immutable_version\":$immutableVersion",
            "\"no_invites\":true",
            "\"operation\":${quote("calendar.event.create_private")}",
            "\"owner_subject\":${quote(ownerSubject)}",
            "\"risk_class\":${quote("R3")}",
            "\"send_updates\":${quote("none")}",
            "\"start\":${quote(draft.start)}",
            "\"timezone\":${quote(draft.timezone)}",
            "\"title\":${quote(draft.title)}",
            "\"connection_epoch\":$connectionEpoch",
            "\"expires_at\":${quote(expiresAt)}",
        ).joinToString(",") + "}"
    }

    fun digest(draft: PrivateCalendarDraft): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(canonicalPayload(draft).toByteArray(StandardCharsets.UTF_8))
        return "sha256:" + bytes.joinToString("") { "%02x".format(it) }
    }

    fun digest(draft: PrivateCalendarDraft, ownerSubject: String, connectionEpoch: Int, immutableVersion: Int, expiresAt: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(canonicalPayload(draft, ownerSubject, connectionEpoch, immutableVersion, expiresAt).toByteArray(StandardCharsets.UTF_8))
        return "sha256:" + bytes.joinToString("") { "%02x".format(it) }
    }

    private fun parse(value: String): Instant? = runCatching { Instant.parse(value) }.getOrNull()
}
