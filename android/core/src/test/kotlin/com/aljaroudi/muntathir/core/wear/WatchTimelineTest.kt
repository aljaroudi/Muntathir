package com.aljaroudi.muntathir.core.wear

import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.prayer.PrayerMethod
import com.aljaroudi.muntathir.core.prayer.PrayerName
import com.aljaroudi.muntathir.core.prayer.WidgetPrayerSettings
import java.time.LocalDate
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class WatchTimelineTest {
    private val mecca = SavedLocation(21.4225, 39.8262, "Asia/Riyadh")

    @Test
    fun nextPrayerSpansAreContiguousAndSkipHiddenTimes() {
        val settings = WidgetPrayerSettings(mecca, PrayerMethod.Tehran, setOf(PrayerName.Asr, PrayerName.Isha))
        val from = LocalDate.of(2026, 10, 18).atStartOfDay(mecca.zone).toInstant()
        val spans = WatchTimeline.nextPrayers(settings, from, count = 6)
        assertEquals(6, spans.size)
        assertEquals(from, spans.first().start)
        for ((left, right) in spans.zipWithNext()) assertEquals(left.end, right.start)
        for (span in spans) {
            assertEquals(span.end, span.value.time)
            assertEquals(settings.nextPrayer(span.start), span.value)
            assertTrue(span.value.name.isPrayer && span.value.name !in settings.hiddenPrayers)
        }
    }

    @Test
    fun withoutLocationThereAreNoPrayerSpans() {
        val settings = WidgetPrayerSettings(null, PrayerMethod.Tehran)
        assertTrue(
            WatchTimeline
                .nextPrayers(
                    settings,
                    LocalDate.of(2026, 1, 1).atStartOfDay(ZoneId.of("UTC")).toInstant(),
                ).isEmpty(),
        )
    }

    @Test
    fun daysEndAtLocalMidnightsAcrossDaylightSaving() {
        val zone = ZoneId.of("Europe/London")
        val from =
            LocalDate
                .of(2026, 3, 28)
                .atTime(15, 0)
                .atZone(zone)
                .toInstant()
        val days = WatchTimeline.days(zone, from)
        assertEquals(
            listOf(LocalDate.of(2026, 3, 28), LocalDate.of(2026, 3, 29), LocalDate.of(2026, 3, 30)),
            days.map {
                it.value
            },
        )
        assertEquals(from, days.first().start)
        for (span in days) {
            assertEquals(
                span.value
                    .plusDays(1)
                    .atStartOfDay(zone)
                    .toInstant(),
                span.end,
            )
        }
    }
}
