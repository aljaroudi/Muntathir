package com.aljaroudi.muntathir.ui.quran

import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import com.aljaroudi.muntathir.FakeLocator
import com.aljaroudi.muntathir.MainActivity
import com.aljaroudi.muntathir.MemoryStorage
import com.aljaroudi.muntathir.core.app.AppStorage
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.core.app.QuranReadingMode
import com.aljaroudi.muntathir.data.ReadingSettings
import com.aljaroudi.muntathir.data.StorageModule
import com.aljaroudi.muntathir.location.DeviceLocator
import com.aljaroudi.muntathir.location.LocationModule
import dagger.hilt.android.testing.BindValue
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import dagger.hilt.android.testing.UninstallModules
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain
import javax.inject.Inject

@HiltAndroidTest
@UninstallModules(StorageModule::class, LocationModule::class)
class QuranTest {
    private val hilt = HiltAndroidRule(this)
    private val compose = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val rules: RuleChain = RuleChain.outerRule(hilt).around(compose)

    @BindValue @JvmField
    val storage: AppStorage =
        MemoryStorage(device = DeviceState(onboardingCompleted = true, liveLocation = FakeLocator.MECCA))

    @BindValue @JvmField
    val locator: DeviceLocator = FakeLocator()

    @Inject lateinit var reading: ReadingSettings

    @Before
    fun setUp() {
        hilt.inject()
        runBlocking { reading.update { it.copy(quranReadingMode = QuranReadingMode.Verses) } }
    }

    @After
    fun tearDown() {
        runBlocking { reading.update { it.copy(quranReadingMode = QuranReadingMode.Verses) } }
    }

    private fun waitFor(tag: String) =
        compose.waitUntil(10_000) { compose.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty() }

    @Test
    fun opensSurahAsVersesAndKeepsThePlaceInTheMushaf() {
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNodeWithTag("holy-quran").performClick()
        waitFor("quran-surah-2")
        compose.onNodeWithTag("quran-list").performScrollToNode(hasTestTag("quran-surah-2"))
        compose.onNodeWithTag("quran-surah-2").performClick()
        waitFor("quran-verse-2:1")
        compose.onNodeWithTag("quran-arabic-2:1").assertExists()
        compose.onNodeWithTag("quran-reading-options").performClick()
        compose.onNodeWithTag("reading-mode-mushaf").performClick()
        // Al-Baqarah starts on the second page.
        waitFor("quran-page-text-2")
        compose.onNodeWithTag("quran-reading-options").performClick()
        compose.onNodeWithTag("reading-mode-verses").performClick()
        waitFor("quran-verse-2:1")
    }
}
