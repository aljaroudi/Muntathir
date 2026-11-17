package com.aljaroudi.muntathir.core.calendar

import java.time.Duration
import java.time.LocalDate
import java.time.ZoneId
import java.time.chrono.HijrahDate
import java.time.temporal.ChronoField
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Ports `CalendarTests` (MuntathirTests.swift). Not ported: `countdownText` (formatter, app),
// `supportedLanguagesAreBundled` (iOS bundles), Widget/Watch round trips in
// `sourceRelativeOffsetsPreserveBoundaries` (P6/P8), AppModel persistence in
// `monthOffsetPersistenceMigrationAndConflictRejection` (P2.1; the offset validation is covered here).
class CalendarEngineTest {
    private val zone = ZoneId.of("Asia/Riyadh")
    private val month = HijriMonth(1448, 1)
    private val events = EventLibrary.bundled()

    private fun correction(
        month: HijriMonth,
        start: LocalDate,
        provenance: DateProvenance = DateProvenance.Manual,
        sourceID: String? = null,
    ) = MonthCorrection(month, CivilDate.of(start), provenance, sourceID)

    @Test
    fun ummAlQuraTableCoversSupportedYearsWithValidLengths() {
        val coverage = UmmAlQura.coverage
        assertTrue(coverage.start <= HijriMonth(1350, 1) && coverage.endInclusive >= HijriMonth(1500, 12))
        var cursor = coverage.start
        while (cursor <= coverage.endInclusive) {
            assertTrue(UmmAlQura.length(cursor) in 29..30, "$cursor")
            assertEquals(cursor, UmmAlQura.month(UmmAlQura.start(cursor)))
            assertEquals(cursor, UmmAlQura.month(UmmAlQura.start(cursor.advanced(1)).minusDays(1)))
            cursor = cursor.advanced(1)
        }
        assertEquals(LocalDate.of(2026, 6, 16), UmmAlQura.start(month))
    }

    @Test
    fun hijrahChronologyDifferencesAreReportedNotAsserted() {
        // The embedded Apple table is authoritative; this only reports how far the JDK's copy drifts.
        val differing =
            (0 until 151 * 12).map { HijriMonth(1350, 1).advanced(it) }.filter {
                val jdk = HijrahDate.from(UmmAlQura.start(it))
                jdk.get(ChronoField.DAY_OF_MONTH) != 1
            }
        println("HijrahChronology month starts differing from Apple: ${differing.size}")
    }

    @Test
    fun nextEventUsesCorrectedCivilDays() {
        for (id in listOf("Asia/Riyadh", "America/New_York")) {
            val engine = CalendarEngine.withOffsets(ZoneId.of(id), listOf(MonthOffset(month, 1)))
            val eventDates =
                (0..13)
                    .flatMap {
                        engine.days(
                            month.advanced(it),
                        )
                    }.filter { events.events(engine.resolve(it)).isNotEmpty() }
            for (date in eventDates.take(20)) {
                assertEquals(date, events.nextEventDate(date, engine))
                val tomorrow = date.plusDays(1)
                eventDates.firstOrNull { it >= tomorrow }?.let {
                    assertEquals(
                        it,
                        events.nextEventDate(tomorrow, engine),
                    )
                }
                val before = date.minusDays(2)
                if (events.nextEventDate(before, engine) == date) assertEquals(2, engine.distance(before, date))
            }
        }
    }

    @Test
    fun nextEventCrossesYearBoundary() {
        val engine = CalendarEngine(zone)
        val lastDay = engine.days(HijriMonth(1448, 12)).last()
        val next = events.nextEventDate(lastDay.plusDays(1), engine)!!
        assertEquals(1449, engine.resolve(next).month.year)
    }

    @Test
    fun baselineAndManualPrecedence() {
        val base = CalendarEngine(zone)
        val moved = base.start(month).plusDays(1)
        val confirmed = correction(month, base.start(month), DateProvenance.Confirmed, "example")
        val manual = correction(month, moved)
        val engine = CalendarEngine(zone, manual = listOf(manual), confirmed = listOf(confirmed))
        assertEquals(1, engine.resolve(moved).day)
        assertEquals(DateProvenance.Manual, engine.resolve(moved).provenance)
        assertEquals(2, base.resolve(moved).day)
        val ashura = moved.plusDays(9)
        assertEquals(10, engine.resolve(ashura).day)
        assertTrue(events.events(engine.resolve(ashura)).any { it.id == "husayn-death" })
    }

    @Test
    fun allNeighboringMonthsRemainValid() {
        val base = CalendarEngine(zone)
        for (offset in listOf(-3, -1, 1, 3)) {
            val row = correction(month, base.start(month).plusDays(offset.toLong()))
            val engine = CalendarEngine(zone, manual = listOf(row))
            for (index in -12..12) {
                val candidate = month.advanced(index)
                assertTrue(engine.days(candidate).size in 29..30)
                assertEquals(candidate, engine.resolve(engine.start(candidate)).month)
                assertEquals(1, engine.resolve(engine.start(candidate)).day)
            }
        }
    }

    @Test
    fun rejectConflictingAnchorsAndInvalidDates() {
        val base = CalendarEngine(zone)
        val first = correction(month, base.start(month))
        val second = correction(month.advanced(1), base.start(month).plusDays(28))
        assertFailsWith<CalendarException> { CalendarEngine(zone, manual = listOf(first, second)) }
        assertNull(CivilDate(2026, 2, 30).toLocalDate())
    }

    @Test
    fun futureAnchorConverges() {
        val base = CalendarEngine(zone)
        val rows = listOf(month, month.advanced(4)).map { correction(it, base.start(it).plusDays(1)) }
        val engine = CalendarEngine(zone, manual = rows)
        assertTrue((0 until 5).all { engine.days(month.advanced(it)).size in 29..30 })
        assertEquals(DateProvenance.Calculated, engine.resolve(engine.start(month.advanced(2))).provenance)
    }

    @Test
    fun sourceRelativeOffsetsPreserveBoundaries() {
        val baseline = CalendarEngine(zone)
        val confirmation =
            correction(month, baseline.start(month).plusDays(1), DateProvenance.Confirmed, "naked-eye-middle-east")
        val source = CalendarEngine(zone, confirmed = listOf(confirmation))
        for (days in -2..2) {
            val engine = CalendarEngine.withOffsets(zone, listOf(MonthOffset(month, days)), listOf(confirmation))
            assertEquals(source.start(month).minusDays(days.toLong()), engine.start(month))
            assertEquals(1, engine.resolve(engine.start(month)).day)
            val expected = if (days == 0) DateProvenance.Confirmed else DateProvenance.Manual
            assertEquals(expected, engine.resolve(engine.start(month)).provenance)
            for (index in -12..12) {
                val candidate = month.advanced(index)
                assertTrue(engine.days(candidate).size in 29..30)
                assertEquals(candidate, engine.resolve(engine.start(candidate)).month)
            }
            // Widgets rebuild the engine from the manual rows alone.
            val manual = engine.corrections.values.filter { it.provenance == DateProvenance.Manual }
            assertEquals(engine.start(month), CalendarEngine(zone, manual, listOf(confirmation)).start(month))
        }
    }

    @Test
    fun monthOffsetValidationRejectsConflictsAndOutOfRange() {
        val month = HijriMonth(1448, 12)
        val saved = MonthOffset.replacing(emptyList(), month, -2)
        CalendarEngine.withOffsets(zone, saved)
        assertFailsWith<CalendarException> {
            CalendarEngine.withOffsets(zone, MonthOffset.replacing(saved, month.advanced(1), 2))
        }
        assertFailsWith<CalendarException> { CalendarEngine.withOffsets(zone, MonthOffset.replacing(saved, month, 3)) }
        val cleared = MonthOffset.replacing(saved, month, 0)
        assertTrue(cleared.isEmpty())
        assertEquals(CalendarEngine(zone).baselineStart(month), CalendarEngine.withOffsets(zone, cleared).start(month))
        assertFalse(MonthOffset.isValid(listOf(MonthOffset(month, 1), MonthOffset(month, 2))))
    }

    @Test
    fun manualCorrectionsResolveUntilReset() {
        // CalendarWidgetTests.correctionsSurviveSharingAndReset, without the UserDefaults round trip.
        val baseline = CalendarEngine(zone)
        val start = baseline.start(month).plusDays(1)
        val engine = CalendarEngine(zone, manual = listOf(correction(month, start)))
        assertEquals(ResolvedDay(month, 1, DateProvenance.Manual), engine.resolve(start))
        assertEquals(2, baseline.resolve(start).day)
    }

    @Test
    fun distanceIsCivilDaysAcrossDaylightSaving() {
        val engine = CalendarEngine(ZoneId.of("America/New_York"))
        val day = LocalDate.of(2026, 3, 8)
        assertEquals(1, engine.distance(day, day.plusDays(1)))
        assertEquals(Duration.ofHours(23), Duration.between(engine.startOfDay(day), engine.startOfDay(day.plusDays(1))))
        assertEquals(engine.resolve(day).month, engine.resolve(engine.startOfDay(day).plusSeconds(3600)).month)
    }
}
