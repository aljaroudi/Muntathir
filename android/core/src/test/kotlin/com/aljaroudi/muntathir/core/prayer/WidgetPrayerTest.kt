package com.aljaroudi.muntathir.core.prayer

import com.aljaroudi.muntathir.core.location.SavedLocation
import java.time.Instant
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Ports `WidgetPrayerTests`, `CompactWidgetTests` and `LockScreenPrayerTests`. Not ported: App Group storage
// (`sharedSettingsRoundTripAndOnlyReloadOnChange`, P6.1), countdown formatting and widget bundles (iOS-only).
class WidgetPrayerTest {
    private val mecca = SavedLocation(21.4225, 39.8262, "Asia/Riyadh")

    private fun midnight(date: LocalDate): Instant = date.atStartOfDay(mecca.zone).toInstant()

    @Test
    fun hiddenPrayersAndNextDayRollover() {
        val settings = WidgetPrayerSettings(mecca, PrayerMethod.Tehran, setOf(PrayerName.Asr, PrayerName.Isha))
        val day = LocalDate.of(2026, 10, 18)
        val prayers = settings.prayers(day)
        assertEquals(
            listOf(
                PrayerName.Imsak,
                PrayerName.Fajr,
                PrayerName.Sunrise,
                PrayerName.Dhuhr,
                PrayerName.Sunset,
                PrayerName.Maghrib,
                PrayerName.Midnight,
            ),
            prayers.map { it.name },
        )
        val maghrib = prayers.first { it.name == PrayerName.Maghrib }
        val next = settings.nextPrayer(maghrib.time)!!
        assertEquals(PrayerName.Fajr, next.name)
        assertEquals(day.plusDays(1), next.time.atZone(mecca.zone).toLocalDate())
        val dates = settings.timelineDates(midnight(day))
        assertEquals(dates.sorted(), dates)
        assertTrue(maghrib.time in dates)
        assertTrue(midnight(day.plusDays(1)) in dates)
    }

    @Test
    fun countdownTimelineHasMinuteUpdatesAndNonemptyUpcomingPrayers() {
        val settings = WidgetPrayerSettings(mecca, PrayerMethod.Tehran, setOf(PrayerName.Asr, PrayerName.Isha))
        val start = midnight(LocalDate.of(2026, 10, 18)).plusSeconds(20 * 3600 + 17)
        val dates = settings.timelineDates(start)
        val nextMinute = Math.floorDiv(start.epochSecond, 60L) * 60 + 60
        for (minute in 0 until 360) assertTrue(Instant.ofEpochSecond(nextMinute + minute * 60L) in dates)
        for (date in dates) {
            assertNotNull(settings.nextPrayer(date))
            assertTrue(settings.upcomingPrayers(date).isNotEmpty())
        }
    }

    @Test
    fun missingLocationDoesNotInventTimes() {
        val settings = WidgetPrayerSettings(null, PrayerMethod.Tehran)
        assertTrue(settings.prayers(Instant.now()).isEmpty())
        assertNull(settings.nextPrayer(Instant.now()))
        assertNull(settings.sunset(LocalDate.now()))
    }

    @Test
    fun upcomingPrayersAreLimitedAndRollIntoTomorrow() {
        val hidden = setOf(PrayerName.Sunrise, PrayerName.Asr, PrayerName.Sunset, PrayerName.Isha, PrayerName.Midnight)
        val settings = WidgetPrayerSettings(mecca, PrayerMethod.Tehran, hidden)
        val date = midnight(LocalDate.of(2026, 10, 18)).plusSeconds(20 * 3600)
        val upcoming = settings.upcomingPrayers(date)
        assertEquals(listOf(PrayerName.Fajr, PrayerName.Dhuhr, PrayerName.Maghrib), upcoming.map { it.name })
        assertTrue(upcoming.all { it.time > date })
        assertEquals(2, settings.upcomingPrayers(date, limit = 2).size)
        assertTrue(settings.upcomingPrayers(date, limit = 0).isEmpty())
    }

    @Test
    fun exactPrayerBoundaryAdvancesToNextPrayer() {
        val settings = WidgetPrayerSettings(mecca, PrayerMethod.Tehran, setOf(PrayerName.Asr, PrayerName.Isha))
        val fajr = settings.prayers(LocalDate.of(2026, 10, 19)).first { it.name == PrayerName.Fajr }
        assertEquals(PrayerName.Fajr, settings.nextPrayer(fajr.time.minusSeconds(1))?.name)
        assertEquals(PrayerName.Dhuhr, settings.nextPrayer(fajr.time)?.name)
    }

    @Test
    fun nextChangeIsTheEarliestOfPrayerSunsetAndMidnight() {
        val settings = WidgetPrayerSettings(mecca, PrayerMethod.Tehran, setOf(PrayerName.Asr, PrayerName.Isha))
        val day = LocalDate.of(2026, 10, 18)
        val prayers = settings.prayers(day)
        val dhuhr = prayers.first { it.name == PrayerName.Dhuhr }.time
        val sunset = settings.sunset(day)!!
        val maghrib = prayers.first { it.name == PrayerName.Maghrib }.time
        // Morning: the next prayer (Dhuhr) comes first.
        assertEquals(dhuhr, settings.nextChange(dhuhr.minusSeconds(3600), mecca.zone))
        // After Dhuhr (Asr hidden), sunset turns the daily ayah over before Tehran's Maghrib.
        assertTrue(sunset < maghrib)
        assertEquals(sunset, settings.nextChange(dhuhr, mecca.zone))
        assertEquals(maghrib, settings.nextChange(sunset, mecca.zone))
        // After Maghrib (Isha hidden), the date changes at midnight before Fajr.
        assertEquals(midnight(day.plusDays(1)), settings.nextChange(maghrib, mecca.zone))
    }

    @Test
    fun nextChangeWithoutLocationIsMidnight() {
        val settings = WidgetPrayerSettings(null, PrayerMethod.Tehran)
        val day = LocalDate.of(2026, 10, 18)
        assertEquals(midnight(day.plusDays(1)), settings.nextChange(midnight(day).plusSeconds(60), mecca.zone))
    }
}
