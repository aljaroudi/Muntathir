package com.aljaroudi.muntathir.ui.today

import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import com.aljaroudi.muntathir.FakeLocator
import com.aljaroudi.muntathir.MainActivity
import com.aljaroudi.muntathir.MemoryStorage
import com.aljaroudi.muntathir.core.app.AppStorage
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.core.prayer.PrayerName
import com.aljaroudi.muntathir.data.StorageModule
import com.aljaroudi.muntathir.location.DeviceLocator
import com.aljaroudi.muntathir.location.LocationModule
import dagger.hilt.android.testing.BindValue
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import dagger.hilt.android.testing.UninstallModules
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.RuleChain

@HiltAndroidTest
@UninstallModules(StorageModule::class, LocationModule::class)
class TodayTest {
    private val hilt = HiltAndroidRule(this)
    private val compose = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val rules: RuleChain = RuleChain.outerRule(hilt).around(compose)

    private val memory =
        MemoryStorage(device = DeviceState(onboardingCompleted = true, liveLocation = FakeLocator.MECCA))

    @BindValue @JvmField
    val storage: AppStorage = memory

    @BindValue @JvmField
    val locator: DeviceLocator = FakeLocator()

    /** Every content description in the tree under [node]. */
    private fun allDescriptions(node: SemanticsNode): List<String> =
        node.config.getOrElse(SemanticsProperties.ContentDescription) { emptyList() } +
            node.children.flatMap(::allDescriptions)

    @Test
    fun showsPrayersAndDailyAyahAndHidesOptionalTimes() {
        compose.onNodeWithTag("prayer-fajr").assertIsDisplayed()
        compose.onNodeWithTag("prayer-asr").assertExists()
        // The schedule and verse come from the bundled database.
        compose.waitUntil(10_000) {
            compose
                .onAllNodes(
                    androidx.compose.ui.test
                        .hasTestTag("daily-ayah-text"),
                ).fetchSemanticsNodes()
                .isNotEmpty()
        }
        // A 3-digit time gets an invisible alignment digit; assistive tech must read the real time, never "44:31".
        val clock = Regex("(\\d+):\\d{2}")
        val hours =
            compose
                .onAllNodes(
                    androidx.compose.ui.test
                        .isRoot(),
                    useUnmergedTree = true,
                ).fetchSemanticsNodes()
                .flatMap { root -> allDescriptions(root) }
                .mapNotNull {
                    clock
                        .matchEntire(it)
                        ?.groupValues
                        ?.get(1)
                        ?.toInt()
                }
        assertTrue(hours.isNotEmpty())
        assertTrue(hours.all { it <= 23 })
        compose.onNodeWithTag("prayer-asr").performTouchInput { longClick() }
        compose.onNodeWithTag("hide-asr").performClick()
        compose.waitUntil { memory.preferences?.hiddenPrayers == setOf(PrayerName.Asr) }
        compose.onNodeWithTag("prayer-asr").assertDoesNotExist()
        assertEquals(setOf(PrayerName.Asr), memory.preferences?.hiddenPrayers)
    }
}
