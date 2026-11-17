package com.aljaroudi.muntathir.ui.supplications

import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.espresso.Espresso
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
import com.aljaroudi.muntathir.core.hadith.HadithSource
import com.aljaroudi.muntathir.core.highlight.QuranUserStore
import com.aljaroudi.muntathir.data.StorageModule
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
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain
import java.io.File

/** Swift `SupplicationsUITests`: the fast-follow pack arrives on its own, then read, bookmark and search. */
@HiltAndroidTest
@UninstallModules(StorageModule::class, LocationModule::class, UserDataModule::class, AssetPackModule::class)
class SupplicationsTest {
    private val hilt = HiltAndroidRule(this)
    private val compose = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val rules: RuleChain = RuleChain.outerRule(hilt).around(compose)

    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    init {
        File(context.noBackupFilesDir, "Libraries").deleteRecursively()
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

    @BindValue @JvmField
    val backend: AssetPackBackend =
        FakeAssetPackBackend(
            File(context.cacheDir, "packs").apply { deleteRecursively() },
            mapOf(ContentPack.Supplications to FakeAssetPackBackend::hadith),
        )

    @Before
    fun setUp() {
        runBlocking { user.reopen() }
    }

    private fun waitFor(tag: String) =
        compose.waitUntil(20_000) { compose.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty() }

    @Test
    fun fastFollowPackOpensReadsAndBookmarks() {
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNodeWithTag("supplications").performClick()
        // No download button: the pack is requested at start, like iOS's essential pack.
        waitFor("supplication-1")
        compose.onNodeWithTag("supplication-1").performClick()
        waitFor("supplication-title")
        compose.onNodeWithTag("hadith-bookmark").performClick()
        compose.waitUntil(10_000) { user.bookmarks.value.isNotEmpty() }
        val bookmark = user.bookmarks.value.single()
        assertEquals("openiti-Sahifa-Sajjadiyya", HadithSource.fromKey(bookmark.source)?.book)
        Espresso.pressBack()
        waitFor("supplication-saved")
        compose.onNodeWithTag("search-field").performTextInput("الدعاء")
        waitFor("supplication-1")
    }
}
