package com.aljaroudi.muntathir.ui.today

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
        compose.onNodeWithTag("prayer-asr").performTouchInput { longClick() }
        compose.onNodeWithTag("hide-asr").performClick()
        compose.waitUntil { memory.preferences?.hiddenPrayers == setOf(PrayerName.Asr) }
        compose.onNodeWithTag("prayer-asr").assertDoesNotExist()
        assertEquals(setOf(PrayerName.Asr), memory.preferences?.hiddenPrayers)
    }
}
