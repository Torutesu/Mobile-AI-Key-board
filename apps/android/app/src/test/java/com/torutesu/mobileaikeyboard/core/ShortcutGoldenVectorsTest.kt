package com.torutesu.mobileaikeyboard.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ShortcutGoldenVectorsTest {
    // MOBILE_AI_KEYBOARD_SHORTCUT_GOLDEN_CONSUMER_V1: authoritative fixture consumer.
    @Test
    fun androidConsumesAuthoritativeRootFixtureAndMatchesEveryExpectedVector() {
        val fixture = ShortcutGoldenFixture.repositoryFixture()
        assertTrue("fixture must be the checked-in root asset", fixture.path.endsWith("/fixtures/shortcut-golden-vectors.json"))

        val result = ShortcutGoldenFixture.validate(fixture.readBytes())
        assertEquals("typescript-contracts", result.authority)
        assertTrue(result.nativeConsumptionStatus in setOf("not_proven", "native_unit_consumers"))
        assertEquals(7, result.vectors.size)

        val byId = result.vectors.associateBy { it.id }
        assertNotNull(byId["valid_local_snapshot"])
        assertEquals(true, byId["valid_local_snapshot"]?.contractValid)
        assertEquals(null, byId["valid_local_snapshot"]?.rejection)
        assertTrue(byId["valid_local_snapshot"]?.contentDigest?.matches(Regex("^sha256:[a-f0-9]{64}$")) == true)

        assertEquals("schema", byId["schema_version_rejects_unknown_version"]?.rejection)
        assertEquals("key_normalization", byId["key_normalization_rejects_lowercase_physical_key"]?.rejection)
        assertEquals("digest", byId["digest_rejects_tampered_content"]?.rejection)
        assertEquals("duplicate_conflict", byId["duplicate_physical_key_conflict_rejects_distinct_bindings"]?.rejection)
        assertEquals("local_route_authority", byId["local_route_authority_rejects_host_handoff"]?.rejection)
        assertEquals("local_route_authority", byId["local_route_authority_rejects_tools"]?.rejection)
        assertTrue(result.vectors.drop(1).all { !it.contractValid && it.contentDigest == null })
    }

    @Test
    fun repositoryFixtureIsNotAStaleCopiedTestResource() {
        val fixture = ShortcutGoldenFixture.repositoryFixture()
        assertEquals("shortcut-golden-vectors.json", fixture.name)
        assertTrue(fixture.parentFile?.name == "fixtures")
        assertTrue(fixture.readText().contains("\"authority\": \"typescript-contracts\""))
    }

    @Test
    fun parserRejectsDuplicateObjectKeysAndTrailingBytes() {
        val fixture = ShortcutGoldenFixture.repositoryFixture().readText()
        val duplicate = fixture.replaceFirst(
            "\"authority\": \"typescript-contracts\",",
            "\"authority\": \"typescript-contracts\",\"authority\": \"attacker\",",
        )
        assertThrows(IllegalArgumentException::class.java) {
            ShortcutGoldenFixture.validate(duplicate.toByteArray())
        }
        assertThrows(IllegalArgumentException::class.java) {
            ShortcutGoldenFixture.validate((fixture + "\n{}\n").toByteArray())
        }
    }

    @Test
    fun validatorRejectsTamperedExpectedClassificationAndDigest() {
        val fixture = ShortcutGoldenFixture.repositoryFixture().readText()
        val expectedTamper = fixture.replaceFirst("\"rejection\": \"digest\"", "\"rejection\": \"schema\"")
        assertThrows(IllegalArgumentException::class.java) {
            ShortcutGoldenFixture.validate(expectedTamper.toByteArray())
        }

        val validDigest = "sha256:d963bd630a1469a96c935e55406139584aef97d145e257db01f8fb48db06f01e"
        val digestTamper = fixture.replaceFirst(validDigest, "sha256:${"f".repeat(64)}")
        assertThrows(IllegalArgumentException::class.java) {
            ShortcutGoldenFixture.validate(digestTamper.toByteArray())
        }
    }
}
