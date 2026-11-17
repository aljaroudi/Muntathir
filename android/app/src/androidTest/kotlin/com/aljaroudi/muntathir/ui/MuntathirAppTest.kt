package com.aljaroudi.muntathir.ui

import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import com.aljaroudi.muntathir.FakeLocator
import com.aljaroudi.muntathir.MainActivity
import com.aljaroudi.muntathir.MemoryStorage
import com.aljaroudi.muntathir.core.app.AppStorage
import com.aljaroudi.muntathir.core.app.AppTool
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.data.StorageModule
import com.aljaroudi.muntathir.location.DeviceLocator
import com.aljaroudi.muntathir.location.LocationModule
import com.aljaroudi.muntathir.ui.navigation.OpenRequest
import dagger.hilt.android.testing.BindValue
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import dagger.hilt.android.testing.UninstallModules
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain

@HiltAndroidTest
@UninstallModules(StorageModule::class, LocationModule::class)
class MuntathirAppTest {
    private val hilt = HiltAndroidRule(this)
    private val compose = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val rules: RuleChain = RuleChain.outerRule(hilt).around(compose)

    @BindValue @JvmField
    val storage: AppStorage =
        MemoryStorage(device = DeviceState(onboardingCompleted = true, liveLocation = FakeLocator.MECCA))

    @BindValue @JvmField
    val locator: DeviceLocator = FakeLocator()

    @Test
    fun tabsShowShortcutsAndToolsHidesThem() {
        compose.onNodeWithTag("tab-today").assertIsSelected()
        compose.onNodeWithTag("tab-calendar").assertIsDisplayed()
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNodeWithTag("tab-tools").assertIsSelected()
        compose.onNodeWithTag("holy-quran").assertIsDisplayed()
        compose.onNodeWithTag("calendar").assertDoesNotExist()
        compose.onNodeWithTag("holy-quran").performClick()
        compose.onNodeWithTag("tab-today").performClick()
        compose.onNodeWithTag("tab-today").assertIsSelected()
    }

    /** Launcher shortcuts, widgets and the tile reach the running activity with an [OpenRequest]. */
    @Test
    fun openRequestsShowTheToolOrItsTab() {
        val activity = compose.activity
        // Tasbih isn't a tab: it opens on top of Tools.
        activity.startActivity(OpenRequest.intent(activity, AppTool.Tasbih))
        compose.waitUntil { compose.onAllNodesWithTag("tasbih-beads").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("tab-tools").assertIsSelected()
        // Calendar is a default tab: its tab is selected.
        activity.startActivity(OpenRequest.intent(activity, AppTool.Calendar))
        compose.waitUntil { compose.onNodeWithTag("tab-calendar").isSelected() }
        // Today pops back to the first tab.
        activity.startActivity(OpenRequest.intent(activity, null))
        compose.waitUntil { compose.onNodeWithTag("tab-today").isSelected() }
    }
}

private fun SemanticsNodeInteraction.isSelected(): Boolean = runCatching { assertIsSelected() }.isSuccess
