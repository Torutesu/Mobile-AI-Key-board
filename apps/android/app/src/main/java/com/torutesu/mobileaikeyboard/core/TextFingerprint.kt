package com.torutesu.mobileaikeyboard.core

import java.security.MessageDigest

object TextFingerprint {
    fun of(text: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }
}
