package com.aljaroudi.muntathir.core.calendar

import java.time.Instant

/** Scroll targets and month state for the calendar screen. Port of Swift `CalendarScreen` statics. */
object CalendarTargets {
    fun monthID(month: HijriMonth) = "calendar-month-${month.year}-${month.month}"

    fun dayID(
        month: HijriMonth,
        day: Int,
    ) = "calendar-events-${month.year}-${month.month}-$day"

    fun jumpTarget(
        day: ResolvedDay,
        eventDays: List<Int>,
        engine: CalendarEngine,
    ): String {
        val length = engine.days(day.month).size
        val next = eventDays.filter { it >= day.day && it <= length }.minOrNull() ?: return monthID(day.month)
        return dayID(day.month, next)
    }

    /** A future month is "expected" unless a confirmed start matches the engine's start. */
    fun isExpected(
        month: HijriMonth,
        now: Instant,
        engine: CalendarEngine,
        confirmations: List<MonthCorrection>,
    ): Boolean {
        if (month <= engine.resolve(now).month) return false
        return confirmations.none {
            it.month == month && it.provenance == DateProvenance.Confirmed &&
                it.start.toLocalDate() == engine.start(month)
        }
    }

    fun initialTarget(
        year: Int,
        currentMonth: HijriMonth,
        nextDay: ResolvedDay?,
    ): String {
        if (year != currentMonth.year) return monthID(HijriMonth(year, 1))
        if (nextDay == null || nextDay.month.year != year) return monthID(currentMonth)
        return dayID(nextDay.month, nextDay.day)
    }
}
