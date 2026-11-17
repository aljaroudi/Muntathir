package com.aljaroudi.muntathir.ui.hadith

import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performImeAction
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.test.platform.app.InstrumentationRegistry
import com.aljaroudi.muntathir.FakeAssetPackBackend
import com.aljaroudi.muntathir.FakeLocator
import com.aljaroudi.muntathir.MainActivity
import com.aljaroudi.muntathir.MemoryStorage
import com.aljaroudi.muntathir.assets.AssetPackBackend
import com.aljaroudi.muntathir.assets.AssetPackModule
import com.aljaroudi.muntathir.assets.ContentPack
import com.aljaroudi.muntathir.core.app.AppStorage
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.core.search.SemanticSearchClient
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
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain
import java.io.File

/** Swift `SemanticSearchUITests` for Hadith and Rulings: consent first, then results resolved locally. */
@HiltAndroidTest
@UninstallModules(StorageModule::class, LocationModule::class, AssetPackModule::class, SearchModule::class)
class SmartSearchTest {
    private val hilt = HiltAndroidRule(this)
    private val compose = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val rules: RuleChain = RuleChain.outerRule(hilt).around(compose)

    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    init {
        File(context.noBackupFilesDir, "Libraries").deleteRecursively()
        File(context.noBackupFilesDir, "hadith.session.v1.json").delete()
    }

    @BindValue @JvmField
    val storage: AppStorage =
        MemoryStorage(device = DeviceState(onboardingCompleted = true, liveLocation = FakeLocator.MECCA))

    @BindValue @JvmField
    val locator: DeviceLocator = FakeLocator()

    @BindValue @JvmField
    val backend: AssetPackBackend =
        FakeAssetPackBackend(
            File(context.cacheDir, "packs").apply { deleteRecursively() },
            mapOf(
                ContentPack.Hadith to FakeAssetPackBackend::hadith,
                ContentPack.Rulings to FakeAssetPackBackend::rulings,
            ),
        )

    private val requests = mutableListOf<String>()

    /** Swift's `--ui-testing-semantic-fixture`: narration 105, or ruling 43 for rulings searches. */
    @BindValue @JvmField
    val smartSearch: SmartSearch =
        SmartSearch(
            SemanticSearchClient("https://search.invalid/v1/search") { _, body ->
                requests += body
                if ("\"rulings\"" in body) {
                    200 to
                        """{"results":[{"kind":"rulings","authority":"sistani","language":"en","id":"43","score":0.7}]}"""
                } else {
                    200 to
                        """{"results":[{"kind":"hadith","book":"bukhari","chapter":"1.json","number":105,"score":0.8}]}"""
                }
            },
        )

    private fun waitFor(tag: String) =
        compose.waitUntil(20_000) { compose.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty() }

    @Test
    fun hadithFallbackOpensLocalNarration() {
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNodeWithTag("hadith").performClick()
        waitFor("hadith-download")
        compose.onNodeWithTag("hadith-download").performClick()
        waitFor("hadith-book-bukhari")
        compose.onNodeWithTag("search-field").performTextInput("kindness to neighbours")
        compose.onNodeWithTag("search-field").performImeAction()
        waitFor("search-by-meaning")
        // Nothing is sent before consent.
        assertTrue(requests.isEmpty())
        compose.onNodeWithTag("search-by-meaning").performClick()
        compose.onNodeWithTag("hadith-list").performScrollToNode(hasTestTag("hadith-smart-105"))
        compose.onNodeWithTag("hadith-smart-105").performClick()
        waitFor("hadith-detail-book")
        assertTrue("\"hadith\"" in requests.single())
    }

    @Test
    fun rulingsSearchStaysInScope() {
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNodeWithTag("rulings").performClick()
        waitFor("downloads-get-rulings")
        compose.onNodeWithTag("downloads-get-rulings").performClick()
        waitFor("rulings-question-42")
        compose.onNodeWithTag("search-field").performTextInput("zakat on savings")
        waitFor("search-by-meaning")
        compose.onNodeWithTag("search-by-meaning").performClick()
        compose.waitUntil(10_000) { requests.isNotEmpty() }
        compose.onNodeWithTag("rulings-list").performScrollToNode(hasTestTag("rulings-smart-43"))
        val body = requests.single()
        assertTrue("\"sistani\"" in body && "\"en\"" in body)
    }
}
