package com.aljaroudi.muntathir.ui.figures

import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
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

/** Swift `FiguresUITests`: browse, search, profile, relatives, the family tree, and observance links. */
@HiltAndroidTest
@UninstallModules(StorageModule::class, LocationModule::class)
class FiguresTest {
    private val hilt = HiltAndroidRule(this)
    private val compose = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val rules: RuleChain = RuleChain.outerRule(hilt).around(compose)

    @BindValue @JvmField
    val storage: AppStorage =
        MemoryStorage(device = DeviceState(onboardingCompleted = true, liveLocation = FakeLocator.MECCA))

    @BindValue @JvmField
    val locator: DeviceLocator = FakeLocator()

    private fun waitFor(matcher: SemanticsMatcher) =
        compose.waitUntil(10_000) { compose.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty() }

    private fun waitFor(tag: String) = waitFor(hasTestTag(tag))

    @Test
    fun browseSearchProfileRelativeAndTree() {
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNodeWithTag("figures").performClick()
        waitFor("figure-prophet-muhammad")
        compose.onNodeWithTag("search-field").performTextInput("Hasan")
        waitFor("figure-hasan-ibn-ali")
        compose.onNodeWithTag("figure-hasan-ibn-ali").performClick()

        // Profile → the father among the relatives.
        waitFor("figure-profile-hasan-ibn-ali")
        val profile = compose.onNodeWithTag("figure-profile-hasan-ibn-ali")
        profile.performScrollToNode(hasTestTag("figure-age"))
        profile.performScrollToNode(hasTestTag("figure-relative-ali-ibn-abi-talib"))
        compose.onNodeWithTag("figure-relative-ali-ibn-abi-talib").performClick()
        waitFor("figure-profile-ali-ibn-abi-talib")

        // Family tree centered on Ali; tapping a child refocuses it.
        compose.onNodeWithTag("figure-family-tree").performClick()
        waitFor("family-node-hasan-ibn-ali")
        compose.onNodeWithTag("family-node-hasan-ibn-ali").performScrollTo().performClick()
        waitFor("family-back-to-original")
        waitFor("family-node-ali-ibn-abi-talib")
        compose.onNodeWithTag("family-view-profile").performClick()
        waitFor("figure-profile-hasan-ibn-ali")
    }

    @Test
    fun observanceOpensItsFigures() {
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNodeWithTag("events").performClick()
        waitFor("events-list")
        compose.onNodeWithTag("events-list").performScrollToNode(hasTestTag("observance-prophet-khadija-marriage"))
        // Rows link once the figures have loaded.
        waitFor(hasTestTag("observance-prophet-khadija-marriage") and hasClickAction())
        compose.onNodeWithTag("observance-prophet-khadija-marriage").performClick()
        waitFor("figure-khadija-bint-khuwaylid")
        compose.onNodeWithTag("figure-prophet-muhammad").assertExists()
        compose.onNodeWithTag("figure-khadija-bint-khuwaylid").performClick()
        waitFor("figure-profile-khadija-bint-khuwaylid")
    }
}
