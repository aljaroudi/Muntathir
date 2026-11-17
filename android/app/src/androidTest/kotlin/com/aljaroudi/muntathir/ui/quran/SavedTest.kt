package com.aljaroudi.muntathir.ui.quran

import android.text.Selection
import android.text.Spannable
import android.view.View
import android.view.ViewGroup
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import com.aljaroudi.muntathir.FakeLocator
import com.aljaroudi.muntathir.MainActivity
import com.aljaroudi.muntathir.MemoryStorage
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppStorage
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.core.highlight.HighlightColor
import com.aljaroudi.muntathir.core.highlight.QuranUserStore
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.core.progress.ProgressActivityKind
import com.aljaroudi.muntathir.data.StorageModule
import com.aljaroudi.muntathir.data.user.ProgressStore
import com.aljaroudi.muntathir.data.user.RoomUserRecords
import com.aljaroudi.muntathir.data.user.UserDataModule
import com.aljaroudi.muntathir.data.user.UserDatabase
import com.aljaroudi.muntathir.location.DeviceLocator
import com.aljaroudi.muntathir.location.LocationModule
import com.aljaroudi.muntathir.ui.reader.HighlightTextView
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

@HiltAndroidTest
@UninstallModules(StorageModule::class, LocationModule::class, UserDataModule::class)
class SavedTest {
    private val hilt = HiltAndroidRule(this)
    private val compose = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val rules: RuleChain = RuleChain.outerRule(hilt).around(compose)

    @BindValue @JvmField
    val storage: AppStorage =
        MemoryStorage(device = DeviceState(onboardingCompleted = true, liveLocation = FakeLocator.MECCA))

    @BindValue @JvmField
    val locator: DeviceLocator = FakeLocator()

    private val database = UserDatabase.inMemory(InstrumentationRegistry.getInstrumentation().targetContext)

    @BindValue @JvmField
    val user: QuranUserStore = QuranUserStore(RoomUserRecords(database.dao()), { "test-device" })

    @BindValue @JvmField
    val progress: ProgressStore = ProgressStore(database.dao(), CoroutineScope(Dispatchers.IO))

    @Before
    fun setUp() {
        runBlocking { user.reopen() }
    }

    private fun waitFor(tag: String) =
        compose.waitUntil(15_000) { compose.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty() }

    private fun string(id: Int) = compose.activity.getString(id)

    /** The reader's text views, in layout order. */
    private fun textViews(): List<HighlightTextView> {
        val found = mutableListOf<HighlightTextView>()

        fun visit(view: View) {
            if (view is HighlightTextView) found += view
            if (view is ViewGroup) (0 until view.childCount).forEach { visit(view.getChildAt(it)) }
        }
        compose.activityRule.scenario.onActivity { visit(it.window.decorView) }
        return found
    }

    @Test
    fun selectingVerseTextSavesAHighlightThatReopensInTheEditor() {
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNodeWithTag("holy-quran").performClick()
        waitFor("quran-surah-1")
        compose.onNodeWithTag("quran-surah-1").performClick()
        waitFor("quran-arabic-1:1")
        compose.waitForIdle()
        val arabic = textViews().first { it.text.isNotEmpty() }
        compose.activityRule.scenario.onActivity {
            Selection.setSelection(arabic.text as Spannable, 0, 4)
            arabic.highlightSelection()
        }
        waitFor("highlight-color-green")
        compose.onNodeWithTag("highlight-color-green").performClick()
        compose.waitUntil(10_000) { user.highlights.value.isNotEmpty() }
        val saved = user.highlights.value.single()
        assertEquals("1:1", saved.source)
        assertEquals("arabic", saved.block)
        assertEquals(HighlightColor.Green, saved.color)
        assertEquals(4, saved.ranges.single().length)
        // The saved highlight is drawn and a tap on it opens the editor with its note.
        compose.waitUntil(10_000) {
            var drawn = false
            compose.activityRule.scenario.onActivity { drawn = arabic.highlightsAt(1).isNotEmpty() }
            drawn
        }
        compose.activityRule.scenario.onActivity { arabic.onOpenHighlights(arabic.highlightsAt(1)) }
        waitFor("highlight-note-editor")
    }

    @Test
    fun bookmarksAVerseAndOpensSavedHighlights() {
        // A highlight saved earlier (as Room stores it) shows in Saved and opens its verse.
        runBlocking {
            user.save(
                listOf(
                    ReadingHighlight(
                        source = "1:2",
                        isHadith = false,
                        excerpt = "Praise",
                        reference = "1:2",
                        color = HighlightColor.Green,
                    ),
                ),
            )
        }
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNodeWithTag("holy-quran").performClick()
        waitFor("quran-surah-1")
        compose.onNodeWithTag("quran-surah-1").performClick()
        waitFor("verse-actions-1:1")
        compose.onNodeWithTag("verse-actions-1:1").performClick()
        compose.onNodeWithTag("verse-bookmark").performClick()
        compose.waitUntil(10_000) { user.bookmark("1:1") != null }
        compose.activityRule.scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }

        waitFor("quran-saved")
        compose.onNodeWithTag("quran-saved").performClick()
        waitFor("saved-verse-1:2")
        compose.onNodeWithText(string(R.string.bookmarks)).performClick()
        waitFor("saved-verse-1:1")
        compose.onNodeWithText(string(R.string.highlights)).performClick()
        compose.onNodeWithTag("saved-verse-1:2").performClick()
        waitFor("quran-verse-1:2")
        compose.activityRule.scenario.onActivity { it.onBackPressedDispatcher.onBackPressed() }

        // Removing the bookmark from Saved writes a tombstone.
        compose.onNodeWithText(string(R.string.bookmarks)).performClick()
        waitFor("saved-verse-1:1")
        // The row's menu button is labelled by its only action.
        compose.onNodeWithContentDescription(string(R.string.remove_bookmark)).performClick()
        compose.onNodeWithText(string(R.string.remove_bookmark)).performClick()
        compose.waitUntil(10_000) { user.bookmark("1:1") == null }
        assertTrue(user.bookmarks.value.isEmpty())
        assertEquals(1, user.highlights.value.size)
        // Time in the reader was saved for Activity when it closed.
        compose.waitUntil(10_000) {
            runBlocking { progress.activities() }.any {
                it.kind ==
                    ProgressActivityKind.QuranReading
            }
        }
    }
}
