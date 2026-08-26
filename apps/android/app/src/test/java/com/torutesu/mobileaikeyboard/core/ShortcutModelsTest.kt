package com.torutesu.mobileaikeyboard.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ShortcutModelsTest {
    private fun assertReindexed(snapshot: ShortcutSnapshot) {
        assertEquals(snapshot.bindings.indices.toList(), snapshot.bindings.map { it.order })
    }

    private fun binding(id: String = "binding-a", key: String = "KeyA") = TriggerKeyBinding(
        bindingId = id,
        skillId = "local.polite-rewrite",
        skillVersion = 1,
        skillDigest = "sha256:${TextFingerprint.of("local.polite-rewrite:v1")}",
        keyCode = key,
        skillName = "丁寧に書き換え",
        accessibleLabel = "丁寧に書き換え、長押しで実行",
    )

    private fun punctuationBinding(key: String = "KeyB") = binding("binding-b", key).copy(
        skillId = ExecutableLocalSkills.PUNCTUATION_POLISH_ID,
        skillDigest = "sha256:${TextFingerprint.of("local.punctuation-polish:v1")}",
        skillName = "句読点を整える",
        accessibleLabel = "句読点を整える、長押しで実行",
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
        assertReindexed(first.snapshot)
        val conflict = ShortcutRegistry.add(first.snapshot, binding("binding-b", "KeyA")) as ShortcutEditResult.Rejected
        assertEquals("key_occupied", conflict.reason)
        val second = ShortcutRegistry.add(first.snapshot, binding("binding-b", "B")) as ShortcutEditResult.Success
        assertEquals(2, second.snapshot.generation)
        assertEquals(2, second.snapshot.bindings.size)
        assertReindexed(second.snapshot)
    }

    @Test
    fun reassignAndRemovePreserveIdentityAndRejectDuplicates() {
        val first = ShortcutRegistry.add(ShortcutSnapshot.empty(), binding()) as ShortcutEditResult.Success
        val reassigned = ShortcutRegistry.reassign(first.snapshot, "binding-a", "Z") as ShortcutEditResult.Success
        assertEquals("binding-a", reassigned.snapshot.bindings.single().bindingId)
        assertEquals("KeyZ", reassigned.snapshot.bindings.single().keyCode)
        assertReindexed(reassigned.snapshot)
        val removed = ShortcutRegistry.remove(reassigned.snapshot, "binding-a") as ShortcutEditResult.Success
        assertTrue(removed.snapshot.bindings.isEmpty())
        assertReindexed(removed.snapshot)
        assertFalse(removed.snapshot.generation == reassigned.snapshot.generation)
    }

    @Test
    fun everySuccessfulMutationReindexesOrdersWithoutDuplicates() {
        val first = ShortcutRegistry.add(ShortcutSnapshot.empty(), binding()) as ShortcutEditResult.Success
        val second = ShortcutRegistry.add(first.snapshot, punctuationBinding()) as ShortcutEditResult.Success
        assertReindexed(second.snapshot)
        val replaced = ShortcutRegistry.reassignWithResolution(
            second.snapshot,
            "binding-a",
            "KeyB",
            ShortcutConflictResolution.REPLACE,
        ) as ShortcutEditResult.Success
        assertReindexed(replaced.snapshot)
        assertEquals(listOf(0), replaced.snapshot.bindings.map { it.order })

        val disabled = ShortcutRegistry.setEnabled(second.snapshot, "binding-a", false) as ShortcutEditResult.Success
        assertReindexed(disabled.snapshot)
        val swapped = ShortcutRegistry.reassignWithResolution(
            disabled.snapshot,
            "binding-a",
            "KeyB",
            ShortcutConflictResolution.SWAP,
        ) as ShortcutEditResult.Success
        assertReindexed(swapped.snapshot)
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

    @Test
    fun snapshotRejectsSkillsThatTheImeCannotExecute() {
        val unsupported = binding().copy(skillId = "calendar.availability.read")
        val snapshot = ShortcutSnapshot(generation = 1, bindings = listOf(unsupported))
        assertFalse(snapshot.isValid())
        assertTrue(ShortcutRegistry.add(ShortcutSnapshot.empty(), unsupported) is ShortcutEditResult.Rejected)
        assertTrue(ExecutableLocalSkills.canExecute(ExecutableLocalSkills.POLITE_REWRITE_ID, 1))
        assertFalse(ExecutableLocalSkills.canExecute(ExecutableLocalSkills.POLITE_REWRITE_ID, 2))
    }

    @Test
    fun storeFallsBackToLastGoodWhenAnOlderNonlocalBindingIsRejected() {
        val good = ShortcutSnapshot(generation = 1, bindings = listOf(binding()))
        val rejected = ShortcutSnapshot(
            generation = 2,
            bindings = listOf(binding().copy(skillId = "calendar.availability.read")),
        )
        assertEquals(good, ShortcutSnapshotRecovery.select(rejected, good))
        assertEquals(ShortcutSnapshot.empty(), ShortcutSnapshotRecovery.select(rejected, rejected))
    }

    @Test
    fun recoveryChoosesHighestValidGenerationRegardlessOfSlotOrder() {
        val older = ShortcutSnapshot(generation = 4, bindings = listOf(binding()))
        val newer = ShortcutSnapshot(generation = 5, bindings = listOf(binding()))
        assertEquals(newer, ShortcutSnapshotRecovery.select(older, newer))
        assertEquals(newer, ShortcutSnapshotRecovery.select(newer, older))
    }

    @Test
    fun conflictRequiresExplicitReplaceAndLeavesOriginalSnapshotUntouched() {
        val first = ShortcutRegistry.add(ShortcutSnapshot.empty(), binding()) as ShortcutEditResult.Success
        val conflicting = punctuationBinding("KeyA")
        val before = first.snapshot
        assertEquals(ShortcutEditResult.Rejected("key_occupied"), ShortcutRegistry.add(before, conflicting))
        assertEquals(before, first.snapshot)
        val replaced = ShortcutRegistry.addWithResolution(first.snapshot, conflicting, ShortcutConflictResolution.REPLACE) as ShortcutEditResult.Success
        assertEquals(2, replaced.snapshot.generation)
        assertEquals(listOf("binding-b"), replaced.snapshot.bindings.map { it.bindingId })
        assertEquals(listOf(0), replaced.snapshot.bindings.map { it.order })
        assertTrue(replaced.snapshot.digest != first.snapshot.digest)
    }

    @Test
    fun explicitSwapExchangesKeysAndFixtureMustPassBeforeAssignment() {
        val first = ShortcutRegistry.add(ShortcutSnapshot.empty(), binding()) as ShortcutEditResult.Success
        val both = ShortcutRegistry.add(first.snapshot, punctuationBinding()) as ShortcutEditResult.Success
        val swapped = ShortcutRegistry.reassignWithResolution(both.snapshot, "binding-a", "KeyB", ShortcutConflictResolution.SWAP) as ShortcutEditResult.Success
        assertEquals("KeyB", swapped.snapshot.bindings.first { it.bindingId == "binding-a" }.keyCode)
        assertEquals("KeyA", swapped.snapshot.bindings.first { it.bindingId == "binding-b" }.keyCode)
        assertEquals(listOf(0, 1), swapped.snapshot.bindings.map { it.order })
        assertEquals(swapped.snapshot.bindings.indices.toList(), swapped.snapshot.bindings.map { it.order })
        assertEquals(3, swapped.snapshot.generation)
        assertTrue(ShortcutFixtureRunner.run(binding()).passed)
        assertFalse(ShortcutFixtureRunner.run(binding().copy(skillId = "calendar.availability.read")).passed)
    }

    @Test
    fun installedPrivateSkillRequiresExactPinnedVersionAndDigestAndUsesClosedExecutor() {
        val version = PrivateSkillVersion(
            version = 1,
            digest = "sha256:${TextFingerprint.of("private-skill-v1")}",
            createdAt = "now",
            skillName = "返信アシスト",
            skillId = "private.reply-assistant.test",
            bindingId = "keyboard-private",
        )
        val descriptor = LocalSkillRegistry.fromPrivateVersion(version)!!
        assertTrue(LocalSkillRegistry.install(descriptor))
        val pinned = binding("private-binding", "KeyC").copy(
            skillId = version.skillId,
            skillVersion = version.version,
            skillDigest = version.digest,
            skillName = version.skillName,
        )
        assertTrue(pinned.isValidBindingSnapshot())
        assertTrue(ExecutableLocalSkills.isExecutable(pinned))
        assertTrue(ExecutableLocalSkills.execute(pinned, "fixture input")!!.isNotBlank())
        assertFalse(ExecutableLocalSkills.isExecutable(pinned.copy(skillDigest = "sha256:${TextFingerprint.of("tampered")}")))
        assertFalse(ExecutableLocalSkills.isExecutable(pinned.copy(skillVersion = 2)))
    }

    @Test
    fun installedCatalogCodecRoundTripsAndRejectsMalformedEntries() {
        val entry = LocalSkillDescriptor(
            "private.codec.test", 3, "sha256:${TextFingerprint.of("codec")}", "Codec Skill", LocalSkillExecutorKind.PRIVATE_LOCAL_REWRITE,
        )
        val encoded = LocalSkillCatalogCodec.encode(listOf(entry))
        assertEquals(listOf(entry), LocalSkillCatalogCodec.decode(encoded))
        assertTrue(LocalSkillCatalogCodec.decode(encoded + "\nmalformed").isEmpty())
        fun encodedField(value: String) = java.util.Base64.getUrlEncoder().withoutPadding()
            .encodeToString(value.toByteArray(java.nio.charset.StandardCharsets.UTF_8))
        val unknownExecutor = encoded.replace(encodedField("PRIVATE_LOCAL_REWRITE"), encodedField("UNKNOWN"))
        assertTrue(LocalSkillCatalogCodec.decode(unknownExecutor).isEmpty())
    }

    @Test
    fun emptyCatalogHydrationRemovesStalePrivateExecutorsButKeepsBuiltIns() {
        val descriptor = LocalSkillDescriptor(
            "private.stale.test", 1, "sha256:${TextFingerprint.of("stale")}", "Stale", LocalSkillExecutorKind.PRIVATE_LOCAL_REWRITE,
        )
        assertTrue(LocalSkillRegistry.install(descriptor))
        assertTrue(ExecutableLocalSkills.canExecute(descriptor.skillId, descriptor.skillVersion))
        assertTrue(LocalSkillRegistry.installAll(emptyList()))
        assertFalse(ExecutableLocalSkills.canExecute(descriptor.skillId, descriptor.skillVersion))
        assertTrue(ExecutableLocalSkills.canExecute(ExecutableLocalSkills.POLITE_REWRITE_ID, ExecutableLocalSkills.VERSION))
    }

    @Test
    fun rejectedCatalogHydrationFailsClosedAndEvictsStalePrivateExecutors() {
        val stale = LocalSkillDescriptor(
            "private.stale.collision", 1, "sha256:${TextFingerprint.of("stale-collision")}", "Stale", LocalSkillExecutorKind.PRIVATE_LOCAL_REWRITE,
        )
        assertTrue(LocalSkillRegistry.install(stale))
        val collidingBuiltin = LocalSkillDescriptor(
            ExecutableLocalSkills.POLITE_REWRITE_ID,
            ExecutableLocalSkills.VERSION,
            "sha256:${TextFingerprint.of("forged-builtin")}",
            "Forged",
            LocalSkillExecutorKind.PRIVATE_LOCAL_REWRITE,
        )
        assertFalse(LocalSkillRegistry.installAll(listOf(collidingBuiltin)))
        assertFalse(ExecutableLocalSkills.canExecute(stale.skillId, stale.skillVersion))
        assertTrue(ExecutableLocalSkills.canExecute(ExecutableLocalSkills.POLITE_REWRITE_ID, ExecutableLocalSkills.VERSION))
    }

    private fun TriggerKeyBinding.isValidBindingSnapshot(): Boolean =
        ShortcutSnapshot(generation = 1, bindings = listOf(this)).isValid()
}
