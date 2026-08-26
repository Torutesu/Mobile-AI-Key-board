package com.torutesu.mobileaikeyboard

import androidx.activity.ComponentActivity
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.action.ViewActions.click
import androidx.test.espresso.action.ViewActions.longClick
import androidx.test.espresso.matcher.ViewMatchers.withContentDescription
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.torutesu.mobileaikeyboard.core.ExecutableLocalSkills
import com.torutesu.mobileaikeyboard.core.HostAppState
import com.torutesu.mobileaikeyboard.core.HostEvent
import com.torutesu.mobileaikeyboard.core.HostFixtureClient
import com.torutesu.mobileaikeyboard.core.InstalledSkillStore
import com.torutesu.mobileaikeyboard.core.KeyboardState
import com.torutesu.mobileaikeyboard.core.LocalSkillDescriptor
import com.torutesu.mobileaikeyboard.core.LocalSkillExecutorKind
import com.torutesu.mobileaikeyboard.core.LocalSkillRegistry
import com.torutesu.mobileaikeyboard.core.PrivateSkillDraft
import com.torutesu.mobileaikeyboard.core.PrivateSkillVersion
import com.torutesu.mobileaikeyboard.core.SkillBuilderEvent
import com.torutesu.mobileaikeyboard.core.SkillBuilderPhase
import com.torutesu.mobileaikeyboard.core.ShortcutEditResult
import com.torutesu.mobileaikeyboard.core.ShortcutRegistry
import com.torutesu.mobileaikeyboard.core.ShortcutSnapshot
import com.torutesu.mobileaikeyboard.core.ShortcutSnapshotStore
import com.torutesu.mobileaikeyboard.core.TextFingerprint
import com.torutesu.mobileaikeyboard.core.TriggerKeyBinding
import com.torutesu.mobileaikeyboard.ime.KeyboardSurface
import com.torutesu.mobileaikeyboard.ui.SkillBuilderDashboard
import com.torutesu.mobileaikeyboard.ui.ShortcutKeysDashboard
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Runtime UI harness for the local vertical slice. These tests require an
 * emulator/device; they do not claim that Android's system IME picker, a
 * third-party editor, or TalkBack itself has been qualified.
 */
@RunWith(AndroidJUnit4::class)
class VerticalSliceUiTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Before
    fun resetProcessLocalSkillCatalog() {
        // Instrumentation methods share one app process. A previous account-
        // boundary test must never make a later fixture result order-dependent.
        LocalSkillRegistry.clearInstalled()
    }

    @Test
    fun builderDeployThenExplicitAddExposesSuccessAndCandidate() {
        val version = deployedVersion()
        var added: PrivateSkillVersion? = null
        composeRule.setContent {
            MaterialTheme {
                SkillBuilderDashboard(
                    state = HostFixtureClient.initialState().copy(skillBuilder = HostAppState().skillBuilder.copy(phase = SkillBuilderPhase.DEPLOYED, version = version, confirmedDigest = version.digest)),
                    dispatch = {},
                    onAddToMyKeyboard = { added = it; true },
                )
            }
        }

        composeRule.onNodeWithText("Add To My Keyboard").assertIsEnabled().performClick()
        composeRule.onNodeWithText("追加しました。Skill KeysでA〜Zのキーを割り当てられます。").assertExists()
        composeRule.runOnIdle { assertEquals(version, added) }
    }

    @Test
    fun shortcutPickerAssignsPrivateCandidateToZAfterFixtureGate() {
        val version = deployedVersion("private.ui.assign")
        val descriptor = LocalSkillRegistry.fromPrivateVersion(version)!!
        assertTrue(LocalSkillRegistry.install(descriptor))
        var published: ShortcutSnapshot? = null
        composeRule.setContent {
            MaterialTheme {
                ShortcutKeysDashboard(
                    snapshot = ShortcutSnapshot.empty(),
                    onPublish = { published = it; true },
                    candidates = listOf(descriptor),
                )
            }
        }

        composeRule.onNodeWithText("Skill Keyを追加").performClick()
        composeRule.onNodeWithText("${version.skillName}（端末内 v${version.version}）").performClick()
        ('A'..'Z').forEach { key ->
            composeRule.onNodeWithContentDescription("$key、割り当て可能")
                .assertExists()
                .assertHeightIsAtLeast(48.dp)
                .assertHasClickAction()
        }
        composeRule.onNodeWithContentDescription("Z、割り当て可能").performScrollTo().assertIsDisplayed().performClick()
        composeRule.onNodeWithContentDescription("端末内fixtureテスト").assertIsDisplayed().assertHeightIsAtLeast(48.dp).performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithText("端末内fixture testに成功（外部送信なし）").assertExists()
        composeRule.onNodeWithContentDescription("Skill Keyを保存").assertHeightIsAtLeast(48.dp).assertIsEnabled().performClick()
        composeRule.runOnIdle {
            val snapshot = published
            assertNotNull(snapshot)
            assertEquals("KeyZ", snapshot!!.bindings.single().keyCode)
            assertEquals(version.skillId, snapshot.bindings.single().skillId)
            assertEquals(version.digest, snapshot.bindings.single().skillDigest)
            assertTrue(ExecutableLocalSkills.isExecutable(snapshot.bindings.single()))
        }
    }

    @Test
    fun shortcutPickerRemainsOperableAtLargeFontScale() {
        val version = deployedVersion("private.ui.large-font")
        val descriptor = LocalSkillRegistry.fromPrivateVersion(version)!!
        assertTrue(LocalSkillRegistry.install(descriptor))
        var published: ShortcutSnapshot? = null
        val deviceDensity = composeRule.activity.resources.displayMetrics.density
        composeRule.setContent {
            CompositionLocalProvider(LocalDensity provides Density(deviceDensity, fontScale = 2.0f)) {
                MaterialTheme {
                    ShortcutKeysDashboard(
                        snapshot = ShortcutSnapshot.empty(),
                        onPublish = { published = it; true },
                        candidates = listOf(descriptor),
                    )
                }
            }
        }

        composeRule.onNodeWithText("Skill Keyを追加").performClick()
        composeRule.onNodeWithText("${version.skillName}（端末内 v${version.version}）").performClick()
        composeRule.onNodeWithContentDescription("M、割り当て可能").performScrollTo().assertIsDisplayed().assertHeightIsAtLeast(48.dp).performClick()
        composeRule.onNodeWithContentDescription("端末内fixtureテスト").assertIsDisplayed().assertHeightIsAtLeast(48.dp).performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithText("端末内fixture testに成功（外部送信なし）").assertExists()
        composeRule.onNodeWithContentDescription("Skill Keyを保存").assertHeightIsAtLeast(48.dp).assertIsEnabled().performClick()
        composeRule.runOnIdle {
            assertEquals("KeyM", published!!.bindings.single().keyCode)
            assertTrue(ExecutableLocalSkills.isExecutable(published!!.bindings.single()))
        }
    }

    @Test
    fun physicalKeyboardTapAndAccessibleLongClickAreDistinctActions() {
        var typed = ""
        var triggered = 0
        val descriptor = LocalSkillDescriptor(
            "private.ui.gesture", 1, "sha256:${TextFingerprint.of("gesture")}", "Gesture Skill", LocalSkillExecutorKind.PRIVATE_LOCAL_REWRITE,
        )
        LocalSkillRegistry.install(descriptor)
        val binding = TriggerKeyBinding("binding-gesture", descriptor.skillId, descriptor.skillVersion, descriptor.skillDigest, keyCode = "KeyZ", skillName = descriptor.skillName)
        val surface = KeyboardSurface(composeRule.activity, KeyboardSurface.Callbacks(
                onCommand = {}, onShortcut = { triggered++ }, onText = { typed += it }, onDelete = {}, onEnter = {},
                onSwitchKeyboard = {}, onCapture = { _, _, _ -> }, onAcknowledge = {}, onEditResult = {}, onRegenerate = {},
                onApply = {}, onCopy = {}, onUndo = {}, onCancel = {},
            ))
        composeRule.activity.runOnUiThread {
            composeRule.activity.setContentView(surface)
            surface.render(KeyboardState(), ShortcutSnapshot(generation = 1, bindings = listOf(binding)))
        }
        composeRule.waitForIdle()

        onView(withContentDescription("q")).perform(click())
        onView(withContentDescription("Z、${descriptor.skillName}、長押しで実行")).perform(longClick())
        composeRule.runOnIdle {
            assertEquals("q", typed)
            assertEquals(1, triggered)
        }
    }

    @Test
    fun accountBoundaryClearRemovesPersistedCatalogAndShortcuts() {
        val version = deployedVersion("private.ui.boundary")
        val appContext = composeRule.activity.applicationContext
        val installedStore = InstalledSkillStore(appContext)
        val shortcutStore = ShortcutSnapshotStore(appContext)
        installedStore.clear()
        shortcutStore.clear()
        assertTrue(installedStore.install(version))
        val descriptor = LocalSkillRegistry.fromPrivateVersion(version)!!
        val binding = TriggerKeyBinding("binding-boundary", descriptor.skillId, descriptor.skillVersion, descriptor.skillDigest, keyCode = "KeyA", skillName = descriptor.skillName)
        val snapshot = ShortcutRegistry.add(ShortcutSnapshot.empty(), binding) as ShortcutEditResult.Success
        assertTrue(shortcutStore.publish(snapshot.snapshot))
        assertTrue(ExecutableLocalSkills.isExecutable(binding))

        assertTrue(installedStore.clear())
        assertTrue(shortcutStore.clear())
        assertTrue(shortcutStore.read().bindings.isEmpty())
        assertFalse(ExecutableLocalSkills.isExecutable(binding))
    }

    private fun deployedVersion(skillId: String = "private.ui.builder"): PrivateSkillVersion {
        val draft = PrivateSkillDraft(
            skillId = skillId,
            desiredOutcome = "短い丁寧な返信を作る",
            name = "UI Reply Skill",
            plainInstruction = "入力を短く丁寧に整える",
        )
        var state = HostFixtureClient.dispatch(HostFixtureClient.initialState(), HostEvent.EnterFixtureSignedIn)
        state = HostFixtureClient.dispatch(state, HostEvent.SkillBuilderAction(SkillBuilderEvent.Open))
        state = HostFixtureClient.dispatch(state, HostEvent.SkillBuilderAction(SkillBuilderEvent.UpdateDraft(draft)))
        state = HostFixtureClient.dispatch(state, HostEvent.SkillBuilderAction(SkillBuilderEvent.Validate))
        state = HostFixtureClient.dispatch(state, HostEvent.SkillBuilderAction(SkillBuilderEvent.RunDryTest))
        state = HostFixtureClient.dispatch(state, HostEvent.SkillBuilderAction(SkillBuilderEvent.OpenDeployReview))
        val version = state.skillBuilder.version!!
        state = HostFixtureClient.dispatch(state, HostEvent.SkillBuilderAction(SkillBuilderEvent.ConfirmDeploy(version.digest)))
        assertEquals(SkillBuilderPhase.DEPLOYED, state.skillBuilder.phase)
        return version
    }
}
