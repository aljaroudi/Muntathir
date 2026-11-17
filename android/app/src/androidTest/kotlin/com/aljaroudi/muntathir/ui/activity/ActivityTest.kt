package com.aljaroudi.muntathir.ui.activity

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import com.aljaroudi.muntathir.FakeLocator
import com.aljaroudi.muntathir.MainActivity
import com.aljaroudi.muntathir.MemoryStorage
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppStorage
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.core.highlight.QuranUserStore
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.prayer.PrayerCalculator
import com.aljaroudi.muntathir.core.prayer.PrayerMethod
import com.aljaroudi.muntathir.core.prayer.PrayerName
import com.aljaroudi.muntathir.core.progress.PrayerProgress
import com.aljaroudi.muntathir.core.progress.ProgressActivity
import com.aljaroudi.muntathir.core.progress.ProgressActivityKind
import com.aljaroudi.muntathir.data.StorageModule
import com.aljaroudi.muntathir.data.user.ProgressStore
import com.aljaroudi.muntathir.data.user.RoomUserRecords
import com.aljaroudi.muntathir.data.user.UserDataModule
import com.aljaroudi.muntathir.data.user.UserDatabase
import com.aljaroudi.muntathir.location.DeviceLocator
import com.aljaroudi.muntathir.location.LocationModule
import com.aljaroudi.muntathir.ui.components.Formats
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
import java.time.LocalDate

/** Swift `PrayerProgressUITests` with the progress fixture: totals per prayer, reader time and beads. */
@HiltAndroidTest
@UninstallModules(StorageModule::class, LocationModule::class, UserDataModule::class)
class ActivityTest {
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

    private val mecca = SavedLocation(21.4225, 39.8262, "Mecca", "SA", "Asia/Riyadh")

    @Before
    fun setUp() =
        runBlocking {
            user.reopen()
            for ((kind, amount) in listOf(
                ProgressActivityKind.QuranReading to 2700.0,
                ProgressActivityKind.HadithReading to 1200.0,
                ProgressActivityKind.SupplicationReading to 420.0,
                ProgressActivityKind.Tasbih to 1234.0,
            )) {
                progress.save(ProgressActivity(kind, amount))
            }
            // Prayer n (0-based) is on time on n + 1 days, like the iOS fixture.
            val today = LocalDate.now(mecca.zone)
            PrayerProgress.prayers.forEachIndexed { index, prayer ->
                for (offset in 0..index) {
                    val day = today.minusDays(offset.toLong())
                    val athan = PrayerCalculator.times(day, mecca, PrayerMethod.Jafari).first { it.name == prayer }.time
                    progress.save(PrayerProgress.snapshot(prayer, athan, mecca, PrayerMethod.Jafari))
                }
            }
            // One late Fajr on a day that is already on time doesn't add an outside-time day.
            val sunrise =
                PrayerCalculator
                    .times(today, mecca, PrayerMethod.Jafari)
                    .first {
                        it.name ==
                            PrayerName.Sunrise
                    }.time
            progress.save(PrayerProgress.snapshot(PrayerName.Fajr, sunrise, mecca, PrayerMethod.Jafari))
        }

    private fun waitFor(tag: String) =
        compose.waitUntil(15_000) { compose.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty() }

    private fun string(id: Int) = compose.activity.getString(id)

    private fun hasState(value: String) = SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, value)

    @Test
    fun showsPrayerReadingAndTasbihTotals() {
        compose.onNodeWithTag("tab-tools").performClick()
        compose.onNodeWithTag("prayer-progress").performClick()
        waitFor("progress-screen")
        val locale = compose.activity.resources.configuration.locales[0]
        val prayers = listOf(R.string.fajr, R.string.dhuhr, R.string.asr, R.string.maghrib, R.string.isha)
        val summary =
            prayers
                .mapIndexed { index, name -> "${string(name)}: ${Formats.number(index + 1, locale)}" }
                .joinToString(", ")
        compose.waitUntil(10_000) {
            compose
                .onAllNodes(
                    hasTestTag("progress-prayer-chart") and hasState(summary),
                ).fetchSemanticsNodes()
                .isNotEmpty()
        }
        compose.onNodeWithTag("progress-tasbih").assert(hasState(Formats.number(1234, locale)))
        compose.onNodeWithTag("progress-quranReading").assert(hasState(Formats.readDuration(2700.0, locale)))
        compose.onNodeWithTag("progress-hadithReading").assert(hasState(Formats.readDuration(1200.0, locale)))
        compose.onNodeWithTag("progress-supplicationReading").assert(hasState(Formats.readDuration(420.0, locale)))
        compose.onNodeWithTag("progress-bookmarks").assert(hasState(Formats.number(0, locale)))
        compose.onNodeWithTag("progress-highlights").assert(hasState(Formats.number(0, locale)))
        assert(compose.onAllNodes(hasTestTag("prayer-outsideTime-count")).fetchSemanticsNodes().isEmpty())
    }
}
