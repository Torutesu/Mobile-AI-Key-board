package com.torutesu.mobileaikeyboard.core

import android.content.Context

/**
 * Minimal host/IME convergence marker for device-local private data.
 * It contains no token or editor content. Every private store independently
 * binds its envelope to this exact owner and epoch and therefore fails closed
 * after sign-out, revocation, deletion, or an account switch.
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

class AccountBoundaryStore(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    fun read(): ActiveAccountBoundary? = withAccountBoundaryLock {
        val processBoundary = ProcessAccountAuthority.read() ?: return@withAccountBoundaryLock null
        if (!preferences.getBoolean(ACTIVE, false)) return@withAccountBoundaryLock null
        val owner = preferences.getString(OWNER, null)?.takeIf { it.isNotBlank() && it.length <= MAX_OWNER_LENGTH } ?: return@withAccountBoundaryLock null
        val epoch = preferences.getInt(EPOCH, 0).takeIf { it > 0 } ?: return@withAccountBoundaryLock null
        ActiveAccountBoundary(owner, epoch).takeIf { it == processBoundary }
    }

    private fun activate(ownerSubject: String, sessionEpoch: Int): Boolean = withAccountBoundaryLock {
        if (ownerSubject.isBlank() || ownerSubject.length > MAX_OWNER_LENGTH || sessionEpoch <= 0) return@withAccountBoundaryLock false
        ProcessAccountAuthority.close()
        LocalSkillRegistry.clearInstalled()
        val committed = preferences.edit()
            .putString(OWNER, ownerSubject)
            .putInt(EPOCH, sessionEpoch)
            .putInt(EPOCH_COUNTER, maxOf(preferences.getInt(EPOCH_COUNTER, 0), sessionEpoch))
            .putBoolean(ACTIVE, true)
            .commit()
        if (committed) ProcessAccountAuthority.open(ActiveAccountBoundary(ownerSubject, sessionEpoch))
        committed
    }

    fun activateNewSession(ownerSubject: String): ActiveAccountBoundary? = withAccountBoundaryLock {
        if (ownerSubject.isBlank() || ownerSubject.length > MAX_OWNER_LENGTH) {
            deactivate()
            return@withAccountBoundaryLock null
        }
        // Re-authentication is a closed transition. No previous process
        // authority remains usable if resume/new-session activation fails.
        ProcessAccountAuthority.close()
        LocalSkillRegistry.clearInstalled()
        val persistedOwner = preferences.getString(OWNER, null)
        val persistedEpoch = preferences.getInt(EPOCH, 0)
        // A fresh process has no authority, but an explicitly authenticated
        // owner may resume its exact durable boundary. This preserves private
        // Skill Keys across process death without trusting persisted bytes as
        // authentication or exposing them to a different owner.
        if (preferences.getBoolean(ACTIVE, false) && persistedOwner == ownerSubject && persistedEpoch > 0) {
            ProcessAccountAuthority.open(ActiveAccountBoundary(ownerSubject, persistedEpoch))
            return@withAccountBoundaryLock read()
        }
        val nextEpoch = preferences.getInt(EPOCH_COUNTER, 0).toLong() + 1L
        if (nextEpoch > Int.MAX_VALUE || !activate(ownerSubject, nextEpoch.toInt())) return@withAccountBoundaryLock null
        read()
    }

    /** Instrumentation-only authority setup; production callers are monotonic. */
    internal fun activateForTesting(ownerSubject: String, sessionEpoch: Int): Boolean = activate(ownerSubject, sessionEpoch)

    /** Invalidate authority before attempting best-effort payload deletion. */
    fun deactivate(): Boolean = withAccountBoundaryLock {
        ProcessAccountAuthority.close()
        LocalSkillRegistry.clearInstalled()
        preferences.edit()
            .putBoolean(ACTIVE, false)
            .remove(OWNER)
            .remove(EPOCH)
            .commit()
    }

    /** Test-only cold-start simulation; persisted bytes intentionally remain. */
    internal fun closeProcessAuthorityForTesting() = withAccountBoundaryLock {
        ProcessAccountAuthority.close()
        LocalSkillRegistry.clearInstalled()
    }

    companion object {
        private const val PREFERENCES = "mobile_ai_keyboard_account_boundary_v1"
        private const val ACTIVE = "active"
        private const val OWNER = "owner_subject"
        private const val EPOCH = "session_epoch"
        private const val EPOCH_COUNTER = "session_epoch_counter"
        private const val MAX_OWNER_LENGTH = 200
    }
}
