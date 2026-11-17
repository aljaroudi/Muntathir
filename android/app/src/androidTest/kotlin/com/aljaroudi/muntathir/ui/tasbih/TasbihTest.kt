package com.aljaroudi.muntathir.ui.tasbih

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import com.aljaroudi.muntathir.FakeLocator
import com.aljaroudi.muntathir.MainActivity
import com.aljaroudi.muntathir.MemoryStorage
import com.aljaroudi.muntathir.core.app.AppStorage
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.core.highlight.QuranUserStore
import com.aljaroudi.muntathir.core.progress.ProgressActivityKind
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
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain

/** Swift `TasbihUITests`: pull validation, the phrase stages, the swipe hint and the recorded visit. */
@HiltAndroidTest
@UninstallModules(StorageModule::class, LocationModule::class, UserDataModule::class)
class TasbihTest {
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

    /** Lets the beads settle, during which pulls are ignored. */
    private fun settle() {
        compose.mainClock.advanceTimeBy(300)
        compose.waitForIdle()
    }

    private fun assertCount(count: String) = compose.onNodeWithTag("tasbih-count").assertTextEquals(count)

    @Test
    fun pullsAndTheAccessibilityActionCountThroughTheFirstPhraseAndRecordTheVisit() {
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNode(hasScrollAction()).performScrollToNode(hasTestTag("tasbih"))
        compose.onNodeWithTag("tasbih").performClick()
        compose.waitUntil(5_000) { compose.onAllNodes(hasTestTag("tasbih-count")).fetchSemanticsNodes().isNotEmpty() }
        assertCount("0")
        compose.onNodeWithTag("tasbih-phrase").assertTextEquals("الله أكبر")
        compose.onNodeWithTag("tasbih-swipe-hint").assertExists()

        // A short pull doesn't count.
        compose.onNodeWithTag("tasbih-beads").performTouchInput {
            val start = Offset(centerX, height * 0.35f)
            swipe(start, start + Offset(0f, 20.dp.toPx()))
        }
        settle()
        assertCount("0")

        // A long one does, and hides the hint.
        compose.onNodeWithTag("tasbih-beads").performTouchInput {
            swipeDown(startY = height * 0.35f, endY = height * 0.35f + 100.dp.toPx())
        }
        settle()
        assertCount("1")
        compose.onNodeWithTag("tasbih-swipe-hint").assertDoesNotExist()

        repeat(33) {
            compose.onNodeWithTag("tasbih-beads").performSemanticsAction(SemanticsActions.OnClick)
            settle()
        }
        compose.onNodeWithTag("tasbih-phrase").assertTextEquals("الحمد لله")
        assertCount("0")

        // The visit was saved once, at its running total.
        compose.waitUntil(10_000) {
            runBlocking { progress.activities() }.any { it.kind == ProgressActivityKind.Tasbih && it.amount == 34.0 }
        }
    }
}
