package com.aljaroudi.muntathir.ui.sermons

import androidx.compose.ui.test.assertContentDescriptionContains
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToKey
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

@HiltAndroidTest
@UninstallModules(StorageModule::class, LocationModule::class)
class SermonsTest {
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
    fun openBundledSermonAndReadEnglishEdition() {
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNodeWithTag("sermons").performClick()
        val title = "خطبة الزهراء"
        compose.waitUntil(10_000) { compose.onAllNodes(hasText(title)).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText(title).performClick()
        val picker = compose.onNodeWithTag("sermon-edition")
        compose.onNodeWithTag("s006").assertIsDisplayed()
        compose.onNodeWithTag("sermon-passages").performScrollToKey("s093")
        val choices =
            listOf(
                "en-3" to "Ahl al-Bayt World Assembly",
                "de-1" to "Ahl al-Bayt Weltversammlung",
                "es-1" to "Fundación Cultural Oriente",
                "en-literal" to "English",
                "en-simplified" to "English",
                "zh-CN-literal" to "简体中文",
                "zh-CN-simplified" to "简体中文",
            )
        for ((id, credit) in choices) {
            picker.performClick()
            compose.onNodeWithTag("sermon-editions").performScrollToNode(hasTestTag("edition-$id"))
            compose.onNodeWithTag("edition-$id").performClick()
            picker.assertContentDescriptionContains(credit, substring = true)
            compose.onNodeWithTag("s093").assertIsDisplayed()
        }
        compose.activityRule.scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }
        compose.waitUntil(10_000) {
            compose.onAllNodes(hasTestTag("sermon-passages")).fetchSemanticsNodes().isEmpty()
        }
        compose.onNodeWithText(title).assertIsDisplayed()
    }

    @Test
    fun opensUnvocalizedArabicSearchResultAtItsPassage() {
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNodeWithTag("sermons").performClick()
        val search = compose.onNodeWithTag("search-field")
        compose.waitUntil(10_000) {
            compose.onAllNodes(hasText("Search sermons")).fetchSemanticsNodes().isNotEmpty()
        }
        search.performTextInput("الشكر")
        val result = "خطبة الزهراء · العربية"
        compose.waitUntil(10_000) { compose.onAllNodes(hasText(result)).fetchSemanticsNodes().isNotEmpty() }
        compose.onAllNodes(hasText(result))[0].performClick()
        compose.onNodeWithTag("s009").assertIsDisplayed()
    }

    @Test
    fun speakerOpensFigureProfile() {
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNodeWithTag("sermons").performClick()
        val title = "خطبة الزهراء"
        compose.waitUntil(10_000) { compose.onAllNodes(hasText(title)).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText(title).performClick()
        compose.waitUntil(
            10_000,
        ) { compose.onAllNodes(hasTestTag("sermon-speaker")).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("sermon-speaker").performClick()
        compose.waitUntil(10_000) {
            compose.onAllNodes(hasTestTag("figure-profile-fatima-al-zahra")).fetchSemanticsNodes().isNotEmpty()
        }
    }
}
