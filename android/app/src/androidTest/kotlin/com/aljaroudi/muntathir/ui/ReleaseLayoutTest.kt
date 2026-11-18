package com.aljaroudi.muntathir.ui

import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isFocused
import androidx.compose.ui.test.junit4.accessibility.enableAccessibilityChecks
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.printToLog
import androidx.compose.ui.test.tryPerformAccessibilityChecks
import androidx.core.os.LocaleListCompat
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.aljaroudi.muntathir.FakeLocator
import com.aljaroudi.muntathir.MainActivity
import com.aljaroudi.muntathir.MemoryStorage
import com.aljaroudi.muntathir.core.app.AppStorage
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.data.StorageModule
import com.aljaroudi.muntathir.location.DeviceLocator
import com.aljaroudi.muntathir.location.LocationModule
import dagger.hilt.android.testing.BindValue
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import dagger.hilt.android.testing.UninstallModules
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain
import java.io.FileInputStream

/**
 * Swift `ReleaseLayoutUITests`: English in light mode, and Arabic in dark mode at 200% font, through Today,
 * Tools, Settings, Calendar and the Quran list and reader, with the Accessibility Test Framework checking each
 * screen (labels, touch targets, contrast, clipped text).
 */
@HiltAndroidTest
@UninstallModules(StorageModule::class, LocationModule::class)
class ReleaseLayoutTest {
    private val hilt = HiltAndroidRule(this)
    private val compose = createEmptyComposeRule()

    @get:Rule
    val rules: RuleChain = RuleChain.outerRule(hilt).around(compose)

    @BindValue @JvmField
    val storage: AppStorage =
        MemoryStorage(device = DeviceState(onboardingCompleted = true, liveLocation = FakeLocator.MECCA))

    @BindValue @JvmField
    val locator: DeviceLocator = FakeLocator()

    @Test
    fun englishLight() = inspect(locale = "en", night = false, fontScale = 1f)

    @Test
    fun arabicDarkLargeText() = inspect(locale = "ar", night = true, fontScale = 2f)

    @Test
    fun arabicLightStoreScreenshots() = inspect(locale = "ar", night = false, fontScale = 1f)

    @Test
    fun diacriticsPreviewFollowsSettingsAfterRecreation() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            fun openSettings() {
                compose.onNodeWithTag("tab-tools").performClick()
                compose.onNode(hasScrollAction()).performScrollToNode(hasTestTag("settings"))
                compose.onNodeWithTag("settings").performClick()
                waitFor("settings-list")
            }
            openSettings()
            compose.onNodeWithTag("settings-list").performScrollToNode(hasTestTag("reading-size"))
            compose.onNodeWithTag("reading-size").performClick()
            val toggle =
                compose.onNode(hasTestTag("reading-diacritics") and hasAnyAncestor(hasTestTag("reading-size-sheet")))
            compose.onNodeWithText("بِسْمِ اللَّهِ").assertExists()
            toggle.performClick()
            compose.onNodeWithText("بسم الله").assertExists()
            scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }
            scenario.recreate()
            compose.waitForIdle()
            if (compose.onAllNodesWithTag("settings-list").fetchSemanticsNodes().isEmpty()) openSettings()
            compose.onNodeWithTag("settings-list").performScrollToNode(hasTestTag("reading-size"))
            compose.onNodeWithTag("reading-size").performClick()
            compose.onNodeWithText("بسم الله").assertExists()
            toggle.performClick()
            compose.onNodeWithText("بِسْمِ اللَّهِ").assertExists()
        }
    }

    private fun inspect(
        locale: String,
        night: Boolean,
        fontScale: Float,
    ) {
        shell("cmd uimode night ${if (night) "yes" else "no"}")
        shell("settings put system font_scale $fontScale")
        try {
            shell("mkdir -p $SCREENSHOTS/$locale")
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                // AppCompat applies the language to running activities, recreating them like the in-app picker.
                setLanguage(locale)
                compose.waitForIdle()
                visitMainScreens(locale) { scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() } }
            }
        } finally {
            shell("settings put system font_scale 1.0")
            shell("cmd uimode night no")
            setLanguage(null)
        }
    }

    /** The in-app language picker's call, so the app reads it back like a user's choice. */
    private fun setLanguage(tag: String?) =
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            AppCompatDelegate.setApplicationLocales(
                tag?.let(LocaleListCompat::forLanguageTags) ?: LocaleListCompat.getEmptyLocaleList(),
            )
        }

    /** [back] is the system back without a key event, which would leave touch mode and focus a text field. */
    private fun visitMainScreens(
        locale: String,
        back: () -> Unit,
    ) {
        fun check(name: String) {
            compose.waitForIdle()
            shell("screencap -p $SCREENSHOTS/$locale/$name.png")
            compose.onRoot().tryPerformAccessibilityChecks()
        }

        compose.enableAccessibilityChecks()
        waitFor("tab-today")
        check("Today")

        compose.onNodeWithTag("tab-tools").performClick()
        waitFor("holy-quran")
        check("Tools")
        compose.onNode(hasScrollAction()).performScrollToNode(hasTestTag("settings"))
        compose.onNodeWithTag("settings").performClick()
        waitFor("settings-list")
        check("Settings")
        back()

        compose.onNodeWithTag("tab-calendar").performClick()
        waitFor("calendar-year")
        check("Calendar")

        compose.onNodeWithTag("tab-tools").performClick()
        // Scrolled back to the top, the tile sits under the app bar, so use its click action.
        compose.onNode(hasScrollAction()).performScrollToNode(hasTestTag("holy-quran"))
        compose.onNodeWithTag("holy-quran").performSemanticsAction(SemanticsActions.OnClick)
        waitFor("quran-surah-1")
        check("Quran")
        compose.onNodeWithTag("quran-surah-1").performClick()
        // In two panes the surah list stays beside the reader.
        waitFor("quran-verses")
        // On touch, a pane appearing must not focus the list's search field (and open the keyboard).
        compose.onAllNodes(isFocused() and hasSetTextAction()).assertCountEquals(0)
        check("Reader")
        back()
        back()

        // Drawn tools: the bead loop and the Activity bars.
        openTool("tasbih")
        waitFor("tasbih-beads")
        check("Tasbih")
        back()
        openTool("prayer-progress")
        compose.waitUntil(10_000) { compose.onAllNodesWithTag("prayer-progress").fetchSemanticsNodes().isEmpty() }
        check("Activity")
    }

    private fun openTool(tag: String) {
        waitFor("holy-quran")
        compose.onNode(hasScrollAction()).performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)
    }

    private fun waitFor(tag: String) {
        try {
            compose.waitUntil(10_000) { compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }
        } catch (timeout: androidx.compose.ui.test.ComposeTimeoutException) {
            compose.onRoot().printToLog("ReleaseLayoutTest")
            throw timeout
        }
    }

    private fun shell(command: String) {
        // Reading the output waits for the command to finish.
        InstrumentationRegistry
            .getInstrumentation()
            .uiAutomation
            .executeShellCommand(command)
            .use { FileInputStream(it.fileDescriptor).readBytes() }
    }

    private companion object {
        /** Pull with `adb pull /data/local/tmp/release-layout` to review the screens by eye. */
        const val SCREENSHOTS = "/data/local/tmp/release-layout"
    }
}
