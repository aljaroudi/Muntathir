package com.aljaroudi.muntathir.ui.hadith

import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performImeAction
import androidx.compose.ui.test.performScrollTo
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
import com.aljaroudi.muntathir.core.highlight.QuranUserStore
import com.aljaroudi.muntathir.core.highlight.ReadingBookmark
import com.aljaroudi.muntathir.data.StorageModule
import com.aljaroudi.muntathir.data.library.ContentLibraries
import com.aljaroudi.muntathir.data.user.ProgressStore
import com.aljaroudi.muntathir.data.user.RoomUserRecords
import com.aljaroudi.muntathir.data.user.UserDataModule
import com.aljaroudi.muntathir.data.user.UserDatabase
import com.aljaroudi.muntathir.location.DeviceLocator
import com.aljaroudi.muntathir.location.LocationModule
import dagger.hilt.android.testing.BindValue
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import dagger.hilt.android.testing.UninstallModules
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain
import java.io.File
import javax.inject.Inject

/** Swift `HadithUITests`: download, browse a book, read and bookmark a narration, and search. */
@HiltAndroidTest
@UninstallModules(StorageModule::class, LocationModule::class, UserDataModule::class, AssetPackModule::class)
class HadithTest {
    private val hilt = HiltAndroidRule(this)
    private val compose = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val rules: RuleChain = RuleChain.outerRule(hilt).around(compose)

    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    init {
        // A fresh library and session for each test; singletons start after this.
        File(context.noBackupFilesDir, "Libraries").deleteRecursively()
        File(context.noBackupFilesDir, "hadith.session.v1.json").delete()
    }

    @BindValue @JvmField
    val storage: AppStorage =
        MemoryStorage(device = DeviceState(onboardingCompleted = true, liveLocation = FakeLocator.MECCA))

    @BindValue @JvmField
    val locator: DeviceLocator = FakeLocator()

    private val database = UserDatabase.inMemory(context)

    @BindValue @JvmField
    val user: QuranUserStore = QuranUserStore(RoomUserRecords(database.dao()), { "test-device" })

    @BindValue @JvmField
    val progress: ProgressStore = ProgressStore(database.dao(), CoroutineScope(Dispatchers.IO))

    val packs =
        FakeAssetPackBackend(
            File(context.cacheDir, "packs").apply { deleteRecursively() },
            mapOf(ContentPack.Hadith to FakeAssetPackBackend::hadith),
        )

    @BindValue @JvmField
    val backend: AssetPackBackend = packs

    @Inject lateinit var libraries: ContentLibraries

    @Before
    fun setUp() {
        hilt.inject()
        runBlocking { user.reopen() }
    }

    private fun waitFor(
        tag: String,
        timeout: Long = 20_000,
    ) = compose.waitUntil(timeout) { compose.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty() }

    private fun openHadith() {
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNodeWithTag("hadith").performClick()
    }

    @Test
    fun downloadCopiesThePackThenBrowseReadAndBookmark() {
        openHadith()
        waitFor("hadith-download")
        compose.onNodeWithTag("hadith-download").performClick()
        waitFor("hadith-book-bukhari")
        // The pack was copied into the app's library and removed.
        assertTrue(File(context.noBackupFilesDir, "Libraries/hadith/library.db").isFile)
        val state = libraries.hadith.state
        compose.waitUntil(10_000) { !state.value.busy }
        assertTrue("Pack not removed: ${state.value}", packs.assetsGone())
        compose.onNodeWithTag("hadith-book-bukhari").performClick()
        waitFor("hadith-introduction-1")
        compose.onNodeWithTag("hadith-chapter-1").performClick()
        waitFor("hadith-result-1")
        compose.onNodeWithTag("hadith-result-1").performClick()
        waitFor("hadith-detail-book")
        compose.onNodeWithTag("hadith-bookmark").performClick()
        compose.waitUntil(10_000) { user.bookmarks.value.isNotEmpty() }
        val bookmark = user.bookmarks.value.single()
        assertEquals(ReadingBookmark.Kind.Hadith, bookmark.kind)
        assertEquals("Test book · 1", bookmark.reference)
        compose.onNodeWithTag("hadith-next").performScrollTo().performClick()
        compose.waitUntil(10_000) { compose.onAllNodes(hasText("Narration 2")).fetchSemanticsNodes().isNotEmpty() }
    }

    @Test
    fun searchFindsNarrationsAndNumbers() {
        openHadith()
        waitFor("hadith-download")
        compose.onNodeWithTag("hadith-download").performClick()
        waitFor("hadith-book-bukhari")
        compose.onNodeWithTag("search-field").performTextInput("intentions")
        compose.onNodeWithTag("search-field").performImeAction()
        waitFor("hadith-result-105")
    }

    private fun FakeAssetPackBackend.assetsGone() = assets(ContentPack.Hadith) == null
}
