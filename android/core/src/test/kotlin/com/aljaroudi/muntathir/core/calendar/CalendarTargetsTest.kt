package com.aljaroudi.muntathir.core.calendar

import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

// Ports the CalendarScreen static-helper tests from MuntathirTests.swift.
class CalendarTargetsTest {
    @Test
    fun futureCalendarDatesRequireMatchingConfirmation() {
        for (id in listOf("Asia/Riyadh", "America/New_York")) {
            val zone = ZoneId.of(id)
            val base = CalendarEngine(zone)
            val month = HijriMonth(1449, 1)
            val now = base.startOfDay(base.start(month).minusDays(2))
            val confirmation =
                MonthCorrection(month, CivilDate.of(base.start(month)), DateProvenance.Confirmed, "example")
            assertTrue(CalendarTargets.isExpected(month, now, base, emptyList()))
            val confirmed = CalendarEngine(zone, confirmed = listOf(confirmation))
            assertFalse(CalendarTargets.isExpected(month, now, confirmed, listOf(confirmation)))
            val manual = CalendarEngine.withOffsets(zone, listOf(MonthOffset(month, 1)), listOf(confirmation))
            assertTrue(CalendarTargets.isExpected(month, now, manual, listOf(confirmation)))
            assertTrue(CalendarTargets.isExpected(month, now, manual, emptyList()))
            assertFalse(CalendarTargets.isExpected(month, manual.startOfDay(manual.start(month)), manual, emptyList()))
            assertFalse(CalendarTargets.isExpected(month.advanced(-1), now, base, emptyList()))
        }
    }

    @Test
    fun calendarInitialPositionStaysInsideSelectedYear() {
        val month = HijriMonth(1448, 12)
        val next = ResolvedDay(month, 18, DateProvenance.Calculated)
        val nextYear = ResolvedDay(month.advanced(1), 2, DateProvenance.Calculated)
        assertEquals("calendar-events-1448-12-18", CalendarTargets.initialTarget(1448, month, next))
        assertEquals("calendar-month-1448-12", CalendarTargets.initialTarget(1448, month, nextYear))
        assertEquals("calendar-month-1448-12", CalendarTargets.initialTarget(1448, month, null))
        assertEquals("calendar-month-1447-1", CalendarTargets.initialTarget(1447, month, next))
    }

    @Test
    fun calendarJumpUsesNextEventOrMonthHeading() {
        val engine = CalendarEngine(ZoneId.of("Asia/Riyadh"))
        val month = HijriMonth(1448, 9)
        val day = ResolvedDay(month, 2, DateProvenance.Calculated)
        assertEquals("calendar-events-1448-9-5", CalendarTargets.jumpTarget(day, listOf(1, 10, 5), engine))
        assertEquals("calendar-events-1448-9-2", CalendarTargets.jumpTarget(day, listOf(1, 2, 5), engine))
        assertEquals("calendar-month-1448-9", CalendarTargets.jumpTarget(day, listOf(1, 31), engine))
        assertEquals("calendar-month-1448-9", CalendarTargets.jumpTarget(day, emptyList(), engine))
        assertNotEquals(CalendarTargets.dayID(month, 1), CalendarTargets.dayID(month.advanced(1), 1))
    }
}
