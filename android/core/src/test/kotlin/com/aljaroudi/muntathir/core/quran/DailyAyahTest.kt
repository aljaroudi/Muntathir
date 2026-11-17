package com.aljaroudi.muntathir.core.quran

import com.aljaroudi.muntathir.core.Fixtures
import com.aljaroudi.muntathir.core.calendar.CalendarEngine
import com.aljaroudi.muntathir.core.calendar.CivilDate
import com.aljaroudi.muntathir.core.calendar.DateProvenance
import com.aljaroudi.muntathir.core.calendar.HijriMonth
import com.aljaroudi.muntathir.core.calendar.MonthCorrection
import com.aljaroudi.muntathir.core.calendar.ResolvedDay
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.prayer.PrayerCalculator
import com.aljaroudi.muntathir.core.prayer.PrayerMethod
import com.aljaroudi.muntathir.core.prayer.PrayerName
import com.aljaroudi.muntathir.core.prayer.WidgetPrayerSettings
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Ports `DailyVerseScheduleTests` (widget timelines are P6.1).
class DailyAyahTest {
    private val idsJson = Fixtures.repository("apple/Muntathir/Resources/quran-daily-ids.json").readText()
    private val daily = DailyAyah.load(idsJson, QuranTestDatabase::verses)

    @Test
    fun completeScheduleMapsEveryHijriDateByArrayPosition() {
        val ids =
            kotlinx.serialization.json.Json
                .decodeFromString<List<Int>>(idsJson)
        val records = QuranTestDatabase.verses(ids.toSet())
        assertEquals(360, ids.size)
        for (month in 1..12) {
            for (day in 1..30) {
                val resolved = ResolvedDay(HijriMonth(1448, month), day, DateProvenance.Calculated)
                assertEquals(records[ids[(month - 1) * 30 + day - 1]]?.id, daily.verse(resolved)?.id)
            }
        }
        assertEquals("89:1", records[ids[0]]?.id)
        assertEquals("26:108", records[ids[319]]?.id)
        assertEquals(ids[318], ids[319])
        assertEquals("114:3", records[ids[359]]?.id)
    }

    @Test
    fun rotationFollowsCorrectedIslamicDate() {
        val baseline = CalendarEngine(ZoneOffset.UTC)
        val month = HijriMonth(1448, 5)
        val date = baseline.start(month).plusDays(1)
        val corrected =
            CalendarEngine(
                ZoneOffset.UTC,
                manual = listOf(MonthCorrection(month, CivilDate.of(date), DateProvenance.Manual)),
            )
        val instant = corrected.startOfDay(date)
        val verse = daily.verse(instant, corrected)!!
        assertEquals(daily.verse(corrected.resolve(date))?.id, verse.id)
        assertEquals(daily.verse(baseline.startOfDay(baseline.start(month)), baseline)?.id, verse.id)
        assertEquals(verse.id, daily.verse(instant.plusSeconds(86_399), corrected)?.id)
    }

    @Test
    fun sunsetSelectsNextHijriDayAndKeepsItThroughMidnight() {
        for (zoneID in listOf("Asia/Riyadh", "America/New_York")) {
            val zone = ZoneId.of(zoneID)
            val engine = CalendarEngine(zone)
            val riyadh = zoneID == "Asia/Riyadh"
            val location =
                SavedLocation(if (riyadh) 24.7136 else 40.7128, if (riyadh) 46.6753 else -74.006, zoneID)
            val prayers = WidgetPrayerSettings(location, PrayerMethod.Jafari, setOf(PrayerName.Sunset))
            for (offset in 0L until 3L) {
                val date = LocalDate.of(2026, 3, 7).plusDays(offset)
                val sunset = prayers.sunset(date)!!
                val maghrib =
                    PrayerCalculator
                        .times(date, location, PrayerMethod.Jafari)
                        .first {
                            it.name ==
                                PrayerName.Maghrib
                        }.time
                assertTrue(sunset < maghrib)
                assertEquals(sunset, WidgetPrayerSettings(location, PrayerMethod.UmmAlQura).sunset(date))
                val current = engine.resolve(date)
                val next = engine.resolve(date.plusDays(1))
                assertEquals(current.day, DailyAyah.verseDay(sunset.minusSeconds(1), engine, prayers).day)
                val tomorrow = engine.startOfDay(date.plusDays(1))
                for (instant in listOf(sunset, sunset.plusSeconds(1), tomorrow, tomorrow.plusSeconds(1))) {
                    val resolved = DailyAyah.verseDay(instant, engine, prayers)
                    assertEquals(next.month to next.day, resolved.month to resolved.day)
                    assertEquals(daily.verse(next)?.id, daily.verse(instant, engine, prayers)?.id)
                }
            }
        }
    }

    @Test
    fun sunsetFollowsCorrectedMonthLengthsAndYearRollover() {
        val zone = ZoneId.of("Asia/Riyadh")
        val baseline = CalendarEngine(zone)
        val month = HijriMonth(1448, 1)
        val correction = MonthCorrection(month, CivilDate.of(baseline.start(month).plusDays(1)), DateProvenance.Manual)
        val engine = CalendarEngine(zone, manual = listOf(correction))
        val prayers =
            WidgetPrayerSettings(SavedLocation(24.7136, 46.6753, zone.id), PrayerMethod.Jafari)
        val lengths = mutableSetOf<Int>()
        for (offset in 0 until 13) {
            val nextMonth = month.advanced(offset)
            val preceding = engine.start(nextMonth).minusDays(1)
            val previous = engine.resolve(preceding)
            lengths += previous.day
            val boundary = prayers.sunset(preceding)!!
            val before = DailyAyah.verseDay(boundary.minusSeconds(1), engine, prayers)
            val after = DailyAyah.verseDay(boundary, engine, prayers)
            assertEquals(previous.month to previous.day, before.month to before.day)
            assertEquals(nextMonth to 1, after.month to after.day)
        }
        assertEquals(setOf(29, 30), lengths)
    }

    @Test
    fun missingOrUncalculableSunsetFallsBackToMidnight() {
        val engine = CalendarEngine(ZoneOffset.UTC)
        val instant = engine.startOfDay(LocalDate.of(2026, 3, 7)).plusSeconds(23 * 3600L)
        val invalid = SavedLocation(Double.NaN, 0.0, "GMT")
        for (location in listOf(null, invalid)) {
            val prayers = WidgetPrayerSettings(location, PrayerMethod.Jafari)
            assertNull(prayers.sunset(engine.localDate(instant)))
            assertEquals(engine.resolve(instant).day, DailyAyah.verseDay(instant, engine, prayers).day)
        }
    }

    @Test
    fun completeDatasetActivatesAndInvalidReferenceNeverFallsBack() {
        val engine = CalendarEngine(ZoneOffset.UTC)
        val start = engine.startOfDay(engine.start(HijriMonth(1448, 1)))
        val ids = (1..360).toList()

        fun load(list: List<Int>) =
            DailyAyah.load(
                kotlinx.serialization.json.Json
                    .encodeToString(list),
                QuranTestDatabase::verses,
            )
        assertEquals("1:1", load(ids).verse(start, engine)?.id)
        for (invalid in listOf(
            ids.dropLast(1),
            ids + 361,
            listOf(99_999) + ids.drop(1),
            listOf(0) + ids.drop(1),
            listOf(-1) + ids.drop(1),
            emptyList(),
        )) {
            assertNull(load(invalid).verse(start, engine))
        }
        assertNull(DailyAyah.load("invalid JSON", QuranTestDatabase::verses).verse(start, engine))
        assertNull(DailyAyah.load(null, QuranTestDatabase::verses).verse(start, engine))
    }

    @Test
    fun databaseContainsTheCompleteArabicQuran() {
        val verses = QuranTestDatabase.verses((1..6236).toSet())
        assertEquals(6236, verses.size)
        assertEquals("1:1", verses[1]?.id)
        assertEquals("114:6", verses[6236]?.id)
        assertTrue(QuranTestDatabase.verses(setOf(0, -1, 6237)).isEmpty())
    }
}
