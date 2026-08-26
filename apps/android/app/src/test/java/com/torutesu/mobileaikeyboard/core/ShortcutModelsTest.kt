package com.torutesu.mobileaikeyboard.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ShortcutModelsTest {
    private fun binding(id: String = "binding-a", key: String = "KeyA") = TriggerKeyBinding(
        bindingId = id,
        skillId = "local.polite-rewrite",
        skillVersion = 1,
        skillDigest = "sha256:${TextFingerprint.of("skill-v1")}",
        keyCode = key,
        skillName = "丁寧に書き換え",
        accessibleLabel = "丁寧に書き換え、長押しで実行",
    )

    @Test
    fun snapshotDigestIsStableAndContainsOnlyMetadata() {
        val snapshot = ShortcutSnapshot(generation = 1, bindings = listOf(binding()))
        assertTrue(snapshot.isValid())
        assertEquals(snapshot.digest, ShortcutSnapshotCanonical.digest(1, 1, LATIN_QWERTY_V1, snapshot.bindings))
        assertFalse(ShortcutSnapshotCanonical.payload(1, 1, LATIN_QWERTY_V1, snapshot.bindings).contains("入力内容"))
    }

    @Test
    fun registryRejectsOccupiedKeyAndPublishesWholeGeneration() {
        val first = ShortcutRegistry.add(ShortcutSnapshot.empty(), binding()) as ShortcutEditResult.Success
        assertEquals(1, first.snapshot.generation)
        val conflict = ShortcutRegistry.add(first.snapshot, binding("binding-b", "KeyA")) as ShortcutEditResult.Rejected
        assertEquals("key_occupied", conflict.reason)
        val second = ShortcutRegistry.add(first.snapshot, binding("binding-b", "B")) as ShortcutEditResult.Success
        assertEquals(2, second.snapshot.generation)
        assertEquals(2, second.snapshot.bindings.size)
    }

    @Test
    fun reassignAndRemovePreserveIdentityAndRejectDuplicates() {
        val first = ShortcutRegistry.add(ShortcutSnapshot.empty(), binding()) as ShortcutEditResult.Success
        val reassigned = ShortcutRegistry.reassign(first.snapshot, "binding-a", "Z") as ShortcutEditResult.Success
        assertEquals("binding-a", reassigned.snapshot.bindings.single().bindingId)
        assertEquals("KeyZ", reassigned.snapshot.bindings.single().keyCode)
        val removed = ShortcutRegistry.remove(reassigned.snapshot, "binding-a") as ShortcutEditResult.Success
        assertTrue(removed.snapshot.bindings.isEmpty())
        assertFalse(removed.snapshot.generation == reassigned.snapshot.generation)
    }

    @Test
    fun longPressThresholdAndMovementFailClosed() {
        val gesture = ShortcutGestureStateMachine()
        gesture.down(100)
        assertFalse(gesture.up(549))
        gesture.down(100)
        assertTrue(gesture.up(550))
        gesture.down(100)
        gesture.move(12.1f)
        assertFalse(gesture.up(550))
    }

    @Test
    fun nativeProjectionRoundTripsAndRejectsCorruption() {
        val snapshot = ShortcutSnapshot(generation = 3, bindings = listOf(binding()))
        val encoded = ShortcutSnapshotCodec.encode(snapshot)
        assertEquals(snapshot, ShortcutSnapshotCodec.decode(encoded))
        val lines = encoded.split('\n').toMutableList()
        val header = lines.first().split('|').toMutableList()
        header[4] = header[4].dropLast(1) + if (header[4].last() == 'A') "B" else "A"
        lines[0] = header.joinToString("|")
        assertFalse(ShortcutSnapshotCodec.decode(lines.joinToString("\n"))?.isValid() == true)
        assertEquals(null, ShortcutSnapshotCodec.decode(encoded + "\nmalformed"))
        val invalidEnabledLines = encoded.split('\n').toMutableList()
        val invalidEnabledFields = invalidEnabledLines[1].split('\t').toMutableList()
        invalidEnabledFields[8] = "eA" // base64url("x")
        invalidEnabledLines[1] = invalidEnabledFields.joinToString("\t")
        assertEquals(null, ShortcutSnapshotCodec.decode(invalidEnabledLines.joinToString("\n")))
    }
}
