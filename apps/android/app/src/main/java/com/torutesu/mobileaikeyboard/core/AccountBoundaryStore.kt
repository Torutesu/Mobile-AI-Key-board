package com.torutesu.mobileaikeyboard.core

import android.content.Context

/**
 * Content-free owner/session authority shared by the host and IME.
 *
 * The durable envelope is integrity-bound, monotonically versioned, and
 * leased. This lets a keyboard process recover after Android reclaims it
 * without treating an unbounded SharedPreferences marker as authentication.
 * Sign-out, expiry, corruption, or an account switch all fail closed.
 */
data class ActiveAccountBoundary(val ownerSubject: String, val sessionEpoch: Int)

private object ProcessAccountAuthority {
    @Volatile private var current: ActiveAccountBoundary? = null
    fun read(): ActiveAccountBoundary? = current
    fun open(boundary: ActiveAccountBoundary) { current = boundary }
    fun close() { current = null }
}

private object AccountBoundaryLock
internal fun <T> withAccountBoundaryLock(block: () -> T): T = synchronized(AccountBoundaryLock, block)

class AccountBoundaryStore(
    context: Context,
    private val nowMillis: () -> Long = System::currentTimeMillis,
) {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    fun read(): ActiveAccountBoundary? = withAccountBoundaryLock {
        val durable = readDurableActive() ?: run {
            ProcessAccountAuthority.close()
            return@withAccountBoundaryLock null
        }
        if (ProcessAccountAuthority.read() != durable) ProcessAccountAuthority.open(durable)
        durable
    }

    private fun readDurableActive(): ActiveAccountBoundary? {
        if (!preferences.getBoolean(ACTIVE, false)) return null
        val owner = preferences.getString(OWNER, null)
            ?.takeIf { it.isNotBlank() && it.length <= MAX_OWNER_LENGTH }
            ?: return null
        val epoch = preferences.getInt(EPOCH, 0).takeIf { it > 0 } ?: return null
        val now = nowMillis()
        val expiresAt = preferences.getLong(EXPIRES_AT_MILLIS, 0L)
            .takeIf { it > now && it <= now + MAX_LEASE_MILLIS }
            ?: return null
        if (epoch <= preferences.getInt(REVOCATION_FLOOR, 0)) return null
        val expected = digest(owner, epoch, active = true, expiresAtMillis = expiresAt)
        if (preferences.getString(CONTENT_DIGEST, null) != expected) return null
        return ActiveAccountBoundary(owner, epoch)
    }

    private fun writeBoundary(
        ownerSubject: String?,
        sessionEpoch: Int,
        active: Boolean,
        expiresAtMillis: Long,
        revocationFloor: Int,
    ): Boolean {
        if (sessionEpoch <= 0 || revocationFloor < 0) return false
        if (active && (ownerSubject.isNullOrBlank() || ownerSubject.length > MAX_OWNER_LENGTH)) return false
        val owner = ownerSubject.orEmpty()
        val editor = preferences.edit()
            .putBoolean(ACTIVE, active)
            .putInt(EPOCH, sessionEpoch)
            .putInt(EPOCH_COUNTER, maxOf(preferences.getInt(EPOCH_COUNTER, 0), sessionEpoch))
            .putInt(REVOCATION_FLOOR, revocationFloor)
            .putLong(EXPIRES_AT_MILLIS, expiresAtMillis)
            .putString(CONTENT_DIGEST, digest(owner, sessionEpoch, active, expiresAtMillis))
        if (active) editor.putString(OWNER, owner) else editor.remove(OWNER)
        return editor.commit()
    }

    private fun activate(ownerSubject: String, sessionEpoch: Int): Boolean = withAccountBoundaryLock {
        if (ownerSubject.isBlank() || ownerSubject.length > MAX_OWNER_LENGTH || sessionEpoch <= 0) return@withAccountBoundaryLock false
        ProcessAccountAuthority.close()
        LocalSkillRegistry.clearInstalled()
        val floor = preferences.getInt(REVOCATION_FLOOR, 0)
        if (sessionEpoch <= floor) return@withAccountBoundaryLock false
        val committed = writeBoundary(
            ownerSubject,
            sessionEpoch,
            active = true,
            expiresAtMillis = nowMillis() + DEFAULT_LEASE_MILLIS,
            revocationFloor = floor,
        )
        if (committed) ProcessAccountAuthority.open(ActiveAccountBoundary(ownerSubject, sessionEpoch))
        committed
    }

    fun activateNewSession(ownerSubject: String): ActiveAccountBoundary? = withAccountBoundaryLock {
        if (ownerSubject.isBlank() || ownerSubject.length > MAX_OWNER_LENGTH) {
            deactivate()
            return@withAccountBoundaryLock null
        }
        ProcessAccountAuthority.close()
        LocalSkillRegistry.clearInstalled()

        // Renew only an exact, unexpired, integrity-valid owner boundary. A
        // stale/corrupt marker never gets silently upgraded into authority.
        val current = readDurableActive()
        if (current?.ownerSubject == ownerSubject && activate(ownerSubject, current.sessionEpoch)) {
            return@withAccountBoundaryLock read()
        }

        val highest = maxOf(
            preferences.getInt(EPOCH_COUNTER, 0),
            preferences.getInt(EPOCH, 0),
            preferences.getInt(REVOCATION_FLOOR, 0),
        ).toLong()
        if (highest >= Int.MAX_VALUE) return@withAccountBoundaryLock null
        if (!activate(ownerSubject, (highest + 1L).toInt())) return@withAccountBoundaryLock null
        read()
    }

    /** Instrumentation-only authority setup; production callers are monotonic. */
    internal fun activateForTesting(ownerSubject: String, sessionEpoch: Int): Boolean = activate(ownerSubject, sessionEpoch)

    /**
     * Revoke durable authority before callers attempt best-effort payload
     * deletion. The floor prevents an older active envelope from being
     * accepted if snapshot cleanup is interrupted.
     */
    fun deactivate(): Boolean = withAccountBoundaryLock {
        ProcessAccountAuthority.close()
        LocalSkillRegistry.clearInstalled()
        val highest = maxOf(
            preferences.getInt(EPOCH_COUNTER, 0),
            preferences.getInt(EPOCH, 0),
            preferences.getInt(REVOCATION_FLOOR, 0),
        ).toLong()
        if (highest >= Int.MAX_VALUE) return@withAccountBoundaryLock false
        val revokedEpoch = (highest + 1L).toInt()
        writeBoundary(
            ownerSubject = null,
            sessionEpoch = revokedEpoch,
            active = false,
            expiresAtMillis = nowMillis(),
            revocationFloor = revokedEpoch,
        )
    }

    /** Test-only cold-start simulation; persisted bytes intentionally remain. */
    internal fun closeProcessAuthorityForTesting() = withAccountBoundaryLock {
        ProcessAccountAuthority.close()
        LocalSkillRegistry.clearInstalled()
    }

    internal fun corruptDigestForTesting() = withAccountBoundaryLock {
        ProcessAccountAuthority.close()
        LocalSkillRegistry.clearInstalled()
        preferences.edit().putString(CONTENT_DIGEST, "sha256:corrupt").commit()
    }

    internal fun expireForTesting() = withAccountBoundaryLock {
        ProcessAccountAuthority.close()
        LocalSkillRegistry.clearInstalled()
        val owner = preferences.getString(OWNER, null).orEmpty()
        val epoch = preferences.getInt(EPOCH, 0)
        val expiredAt = nowMillis() - 1L
        preferences.edit()
            .putLong(EXPIRES_AT_MILLIS, expiredAt)
            .putString(CONTENT_DIGEST, digest(owner, epoch, active = true, expiresAtMillis = expiredAt))
            .commit()
    }

    internal fun resetForTesting() = withAccountBoundaryLock {
        ProcessAccountAuthority.close()
        LocalSkillRegistry.clearInstalled()
        preferences.edit().clear().commit()
    }

    private fun digest(owner: String, epoch: Int, active: Boolean, expiresAtMillis: Long): String =
        "sha256:${TextFingerprint.of("account-boundary-v2\u0000$owner\u0000$epoch\u0000${if (active) 1 else 0}\u0000$expiresAtMillis")}"

    companion object {
        private const val PREFERENCES = "mobile_ai_keyboard_account_boundary_v1"
        private const val ACTIVE = "active"
        private const val OWNER = "owner_subject"
        private const val EPOCH = "session_epoch"
        private const val EPOCH_COUNTER = "session_epoch_counter"
        private const val EXPIRES_AT_MILLIS = "expires_at_millis"
        private const val CONTENT_DIGEST = "content_digest"
        private const val REVOCATION_FLOOR = "revocation_floor"
        private const val MAX_OWNER_LENGTH = 200
        private const val DEFAULT_LEASE_MILLIS = 60L * 60L * 1_000L
        private const val MAX_LEASE_MILLIS = 24L * 60L * 60L * 1_000L
    }
}
