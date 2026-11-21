package com.aljaroudi.muntathir.core.wear

import com.aljaroudi.muntathir.core.calendar.CalendarEngine
import com.aljaroudi.muntathir.core.calendar.HijriMonth
import com.aljaroudi.muntathir.core.calendar.MonthOffset
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.prayer.PrayerMethod
import com.aljaroudi.muntathir.core.prayer.PrayerName
import com.aljaroudi.muntathir.core.prayer.WidgetPrayerSettings
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

// Ports `WatchSettingsTests`. Storage (App Group defaults) is the watch module's DataStore, so the
// "keep last good snapshot" part is reduced to decode throwing; the store keeps its old value on failure.
class WatchSnapshotTest {
    private val mecca = SavedLocation(21.4225, 39.8262, "Asia/Riyadh")
    private val hidden = setOf(PrayerName.Asr, PrayerName.Isha)

    @Test
    fun snapshotRoundTripsAndInvalidTransfersThrow() {
        val month = HijriMonth(1448, 5)
        val snapshot =
            WatchSnapshot(
                prayers = WidgetPrayerSettings(mecca, PrayerMethod.Jafari, hidden),
                calendar = WatchCalendar(mecca.timeZoneID, monthOffsets = listOf(MonthOffset(month, -1))),
            )
        val restored = WatchSnapshot.decode(snapshot.encode())
        assertEquals(snapshot, restored)
        // A −1 offset starts the month a day later, so the baseline start is still the previous month.
        val start = CalendarEngine(mecca.zone).start(month).plusDays(1)
        assertEquals(
            1,
            restored.calendar
                .engine()
                .resolve(start)
                .day,
        )

        assertFailsWith<Exception> { WatchSnapshot.decode("bad".encodeToByteArray()) }
        assertFailsWith<Exception> { WatchSnapshot.decode(snapshot.copy(version = 99).encode()) }
        val noLocation = snapshot.copy(prayers = snapshot.prayers.copy(location = null))
        assertNull(WatchSnapshot.decode(noLocation.encode()).prayers.location)
    }

    @Test
    fun upcomingPrayersSkipHiddenTimesOnPhoneAndWatch() {
        val settings = WidgetPrayerSettings(mecca, PrayerMethod.Tehran, hidden)
        val times = settings.prayers(LocalDate.of(2026, 10, 18))
        val dhuhr = times.first { it.name == PrayerName.Dhuhr }.time
        val maghrib = times.first { it.name == PrayerName.Maghrib }.time
        assertEquals(
            listOf(PrayerName.Maghrib, PrayerName.Fajr, PrayerName.Dhuhr),
            settings.upcomingPrayers(dhuhr).map { it.name },
        )
        val watch =
            WatchSnapshot.decode(
                WatchSnapshot(prayers = settings, calendar = WatchCalendar(mecca.timeZoneID)).encode(),
            )
        assertEquals(settings.nextPrayer(dhuhr), watch.prayers.nextPrayer(dhuhr))
        assertEquals(PrayerName.Fajr, watch.prayers.nextPrayer(maghrib)?.name)
    }

    @Test
    fun invalidLocationZoneAndCalendarAreRejected() {
        val valid =
            WatchSnapshot(
                prayers = WidgetPrayerSettings(mecca, PrayerMethod.Tehran),
                calendar = WatchCalendar(mecca.timeZoneID),
            )
        val badLocation = valid.copy(prayers = valid.prayers.copy(location = SavedLocation(100.0, 39.0, "Asia/Riyadh")))
        assertFailsWith<Exception> { WatchSnapshot.decode(badLocation.encode()) }
        assertFailsWith<Exception> { WatchSnapshot.decode(valid.copy(calendar = WatchCalendar("Not/AZone")).encode()) }
        val badOffset = WatchCalendar(mecca.timeZoneID, listOf(MonthOffset(HijriMonth(1448, 5), 5)))
        assertFailsWith<Exception> { WatchSnapshot.decode(valid.copy(calendar = badOffset).encode()) }
    }
}
