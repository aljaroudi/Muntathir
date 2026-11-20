package com.aljaroudi.muntathir.ui.quran

import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performImeAction
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import com.aljaroudi.muntathir.FakeLocator
import com.aljaroudi.muntathir.MainActivity
import com.aljaroudi.muntathir.MemoryStorage
import com.aljaroudi.muntathir.core.app.AppStorage
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.core.search.SemanticSearchClient
import com.aljaroudi.muntathir.core.text.SearchArea
import com.aljaroudi.muntathir.data.SearchHistoryStore
import com.aljaroudi.muntathir.data.StorageModule
import com.aljaroudi.muntathir.location.DeviceLocator
import com.aljaroudi.muntathir.location.LocationModule
import com.aljaroudi.muntathir.search.SearchModule
import com.aljaroudi.muntathir.search.SmartSearch
import dagger.hilt.android.testing.BindValue
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import dagger.hilt.android.testing.UninstallModules
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain
import javax.inject.Inject

@HiltAndroidTest
@UninstallModules(StorageModule::class, LocationModule::class, SearchModule::class)
class QuranSearchTest {
    private val hilt = HiltAndroidRule(this)
    private val compose = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val rules: RuleChain = RuleChain.outerRule(hilt).around(compose)

    @BindValue @JvmField
    val storage: AppStorage =
        MemoryStorage(device = DeviceState(onboardingCompleted = true, liveLocation = FakeLocator.MECCA))

    @BindValue @JvmField
    val locator: DeviceLocator = FakeLocator()

    private val requests = mutableListOf<String>()

    /** Swift's `--ui-testing-semantic-fixture`: always 2:255. */
    @BindValue @JvmField
    val smartSearch: SmartSearch =
        SmartSearch(
            SemanticSearchClient("https://search.invalid/v1/search") { _, body ->
                requests += body
                if ("zzzz" !in body) {
                    503 to ""
                } else {
                    200 to """{"results":[{"kind":"quran","chapter":2,"verse":255,"score":0.8}]}"""
                }
            },
        )

    @Inject lateinit var history: SearchHistoryStore

    @Before
    fun setUp() {
        hilt.inject()
        history.clear(SearchArea.Quran)
    }

    private fun waitFor(tag: String) =
        compose.waitUntil(15_000) { compose.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty() }

    private fun search(query: String) {
        compose.onNodeWithTag("search-field").performTextClearance()
        compose.onNodeWithTag("search-field").performTextInput(query)
        compose.onNodeWithTag("search-field").performImeAction()
    }

    @Test
    fun searchesTextOpensResultsRemembersQueriesAndFallsBackOffline() {
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNodeWithTag("holy-quran").performClick()
        waitFor("search-field")
        search("يستحي")
        waitFor("quran-result-2:26")
        waitFor("quran-result-33:53")
        compose.onNodeWithTag("quran-result-2:26").performClick()
        waitFor("quran-verse-2:26")
        compose.activityRule.scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }

        waitFor("search-field")
        compose.onNodeWithTag("search-field").performTextClearance()
        compose.onNodeWithTag("search-field").performClick()
        waitFor("search-history-يستحي")

        search("zzzz")
        waitFor("quran-result-2:255")
        assertTrue(requests.last().contains("\"kinds\":[\"quran\"]"))

        search("2:300")
        waitFor("quran-list")
        compose.waitUntil(15_000) {
            compose.onAllNodes(hasTestTag("search-by-meaning")).fetchSemanticsNodes().isEmpty()
        }
    }
}
