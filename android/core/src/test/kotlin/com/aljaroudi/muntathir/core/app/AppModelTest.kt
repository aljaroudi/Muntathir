package com.aljaroudi.muntathir.core.app

import com.aljaroudi.muntathir.core.Fixtures
import com.aljaroudi.muntathir.core.calendar.CalendarEngine
import com.aljaroudi.muntathir.core.calendar.CalendarException
import com.aljaroudi.muntathir.core.calendar.CivilDate
import com.aljaroudi.muntathir.core.calendar.HijriMonth
import com.aljaroudi.muntathir.core.calendar.MonthOffset
import com.aljaroudi.muntathir.core.feed.Announcement
import com.aljaroudi.muntathir.core.feed.CalendarSource
import com.aljaroudi.muntathir.core.feed.CorrectionsFeed
import com.aljaroudi.muntathir.core.feed.Coverage
import com.aljaroudi.muntathir.core.feed.FeedClient
import com.aljaroudi.muntathir.core.feed.FeedResponse
import com.aljaroudi.muntathir.core.feed.SightingMethod
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.prayer.PrayerName
import kotlinx.coroutines.runBlocking
import java.nio.file.Files
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

// Ports the AppModel cases of `TabPreferencesTests` and `FeedClientTests` (stale responses, conflicts,
// incompatible adjustments), plus onboarding, live location and announcement delivery.
class AppModelTest {
    private class MemoryStorage(
        var preferences: Preferences? = null,
        var device: DeviceState = DeviceState(),
    ) : AppStorage {
        override suspend fun loadPreferences() = preferences

        override suspend fun savePreferences(preferences: Preferences) {
            this.preferences = preferences
        }

        override suspend fun loadDevice() = device

        override suspend fun saveDevice(state: DeviceState) {
            device = state
        }
    }

    private val riyadh = SavedLocation(24.0, 46.0, "Asia/Riyadh")
    private val london = SavedLocation(51.5, -0.1, "Europe/London")

    private fun row(
        id: String,
        month: HijriMonth,
        start: CivilDate,
    ) = Announcement(
        id,
        1,
        SightingMethod.NakedEye,
        CalendarSource.MIDDLE_EAST,
        Coverage(listOf("SA"), emptyList()),
        month,
        start,
    )

    @Test
    fun localChangesPersistAndNormalize() =
        runBlocking<Unit> {
            val storage = MemoryStorage()
            val model = AppModel.load(storage, systemZone = ZoneOffset.UTC)
            assertTrue(
                model.update {
                    it.copy(tabShortcuts = listOf(AppTool.Hadith, AppTool.Events, AppTool.Quran, AppTool.Qibla))
                },
            )
            assertEquals(
                listOf(AppTool.Hadith, AppTool.Events, AppTool.Quran),
                model.state.value.preferences.tabShortcuts,
            )
            assertEquals(
                model.state.value.preferences,
                AppModel
                    .load(storage)
                    .state.value.preferences,
            )
            assertEquals(1, model.state.value.revision)
        }

    @Test
    fun invalidChangesAreRejectedWithoutSaving() =
        runBlocking<Unit> {
            val storage = MemoryStorage()
            val model = AppModel.load(storage)
            assertFalse(model.update { it.copy(monthOffsets = listOf(MonthOffset(HijriMonth(1448, 1), 3))) })
            assertEquals(null, storage.preferences)
            assertEquals(0, model.state.value.revision)
        }

    @Test
    fun liveLocationStaysOnDevice() =
        runBlocking<Unit> {
            val storage = MemoryStorage()
            val model = AppModel.load(storage, systemZone = ZoneOffset.UTC)
            assertEquals(ZoneOffset.UTC, model.state.value.zone)
            assertFalse(model.completeOnboarding())
            assertFalse(model.applyLive(riyadh.copy(timeZoneID = "Nowhere/City")))
            assertTrue(model.applyLive(riyadh))
            assertEquals(riyadh, storage.device.liveLocation)
            assertEquals(riyadh.zone, model.state.value.zone)
            model.moveOnboarding(9)
            assertEquals(4, storage.device.onboardingStep)
            assertTrue(model.completeOnboarding())
            assertEquals(DeviceState(onboardingCompleted = true, liveLocation = riyadh), storage.device)
            // An invalid stored fix is dropped on load.
            storage.device = storage.device.copy(liveLocation = riyadh.copy(latitude = 99.0))
            assertEquals(
                null,
                AppModel
                    .load(storage)
                    .state.value.location,
            )
        }

    @Test
    fun setPrayerNeedsPermissionToEnable() =
        runBlocking<Unit> {
            val model = AppModel.load(MemoryStorage())
            assertFalse(model.setPrayer(PrayerName.Isha, enabled = true, notificationsAllowed = false))
            assertFalse(PrayerName.Isha in model.state.value.preferences.enabledPrayers)
            assertTrue(model.setPrayer(PrayerName.Isha, enabled = true))
            assertTrue(model.setPrayer(PrayerName.Fajr, enabled = false, notificationsAllowed = false))
            assertEquals(
                setOf(PrayerName.Dhuhr, PrayerName.Maghrib, PrayerName.Isha),
                model.state.value.preferences.enabledPrayers,
            )
        }

    @Test
    fun staleResponseCannotOverwriteChangedPreferences() =
        runBlocking<Unit> {
            val body = Fixtures.text("corrections-v1.json").encodeToByteArray()
            val folder = Files.createTempDirectory("app").toFile()
            lateinit var model: AppModel
            val client =
                FeedClient("https://example.invalid/feed.json", folder.resolve("cache.json")) { url, _ ->
                    model.update { it.copy(tabShortcuts = listOf(AppTool.Events)) }
                    FeedResponse(200, body, "fixture-v1", url)
                }
            model = AppModel.load(MemoryStorage(), client)
            model.applyLive(riyadh)
            assertFalse(model.refreshFeed())
            assertEquals(listOf(AppTool.Events), model.state.value.preferences.tabShortcuts)
            assertTrue(
                model.state.value.confirmations
                    .isEmpty(),
            )
            // Relaunch applies the cached feed, and an undisturbed refresh applies too.
            val restored = AppModel.load(MemoryStorage(device = DeviceState(liveLocation = riyadh)), client)
            assertEquals(
                CorrectionsFeed.decode(body.decodeToString()).announcements,
                restored.state.value.confirmations,
            )
            folder.deleteRecursively()
        }

    @Test
    fun conflictingRefreshPreservesLastAppliedCalendar() =
        runBlocking<Unit> {
            val model = AppModel.load(MemoryStorage())
            model.applyLive(london)
            val month = HijriMonth(1448, 1)
            val baseline = CalendarEngine(london.zone)
            val original = row("first", month, CivilDate.of(baseline.start(month)))
            model.receive(CorrectionsFeed(1, listOf(original)))
            model.correct(month, -2)
            val before =
                model.state.value.engine
                    .start(month)
            val next = row("next", month.advanced(1), CivilDate.of(baseline.start(month.advanced(1))))
            assertFailsWith<CalendarException> { model.receive(CorrectionsFeed(1, listOf(original, next))) }
            assertEquals(listOf(original), model.state.value.confirmations)
            assertEquals(
                before,
                model.state.value.engine
                    .start(month),
            )
            assertEquals(listOf(MonthOffset(month, -2)), model.state.value.preferences.monthOffsets)
            model.receive(CorrectionsFeed(1, emptyList()))
            assertTrue(
                model.state.value.confirmations
                    .isEmpty(),
            )
        }

    @Test
    fun incompatibleAdjustmentKeepsSavedCalendar() =
        runBlocking<Unit> {
            val model = AppModel.load(MemoryStorage())
            model.applyLive(riyadh)
            val base = CalendarEngine(riyadh.zone)
            val month = (1..12).map { HijriMonth(1448, it) }.first { base.baselineLength(it) == 29 }
            val next = month.advanced(1)
            val confirmed = row("thirty-day-month", next, CivilDate.of(base.start(next).plusDays(1)))
            model.receive(CorrectionsFeed(1, listOf(confirmed)))
            model.correct(next, -1)
            model.correct(month, -2)
            val saved = model.state.value.preferences
            assertFalse(
                model.update { prefs ->
                    prefs.copy(monthOffsets = prefs.monthOffsets.filter { it.month != next })
                },
            )
            assertEquals(saved, model.state.value.preferences)
            assertEquals(listOf(confirmed), model.state.value.confirmations)
            assertTrue(model.errors.replayCache.isEmpty()) // errors are events, not state
        }

    @Test
    fun announcementsAreDeliveredOncePerRevision() =
        runBlocking<Unit> {
            val posted = mutableListOf<String>()
            val storage =
                MemoryStorage(Preferences(announcementNotifications = true), DeviceState(liveLocation = riyadh))
            val now = CalendarEngine(riyadh.zone).startOfDay(java.time.LocalDate.of(2026, 11, 17))
            val model =
                AppModel.load(storage, announcer = {
                    posted += it.id
                    true
                }, clock = { now })
            val month =
                model.state.value.engine
                    .resolve(now)
                    .month
            val base = CalendarEngine(riyadh.zone)
            val rows =
                listOf(month, month.advanced(1), month.advanced(2)).map {
                    row("m${it.month}", it, CivilDate.of(base.start(it)))
                }
            model.receive(CorrectionsFeed(1, rows))
            model.receive(CorrectionsFeed(1, rows))
            assertEquals(rows.take(2).map { it.id }, posted)
            assertEquals(rows.take(2).map { "${it.id}.1" }.toSet(), storage.device.deliveredAnnouncements)
        }
}
