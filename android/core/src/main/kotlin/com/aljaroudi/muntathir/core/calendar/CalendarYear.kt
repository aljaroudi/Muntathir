package com.aljaroudi.muntathir.core.calendar

import java.time.Instant
import java.time.LocalDate

/** A civil day in a Hijri month that has observances. */
data class CalendarEventDay(
    val date: LocalDate,
    val day: ResolvedDay,
    val events: List<IslamicEvent>,
) {
    val id: String get() = CalendarTargets.dayID(day.month, day.day)
}

data class CalendarMonthSection(
    val month: HijriMonth,
    /** A future month whose start isn't confirmed yet (Swift "Expected"). */
    val expected: Boolean,
    val days: List<CalendarEventDay>,
) {
    val id: String get() = CalendarTargets.monthID(month)
}

/** The calendar screen's year, as Swift `CalendarScreen` builds it per month section. */
object CalendarYear {
    const val FIRST = 1350
    const val LAST = 1500

    fun sections(
        year: Int,
        now: Instant,
        engine: CalendarEngine,
        library: EventLibrary,
        confirmations: List<MonthCorrection>,
    ): List<CalendarMonthSection> =
        (1..12).map { number ->
            val month = HijriMonth(year, number)
            val days =
                engine.days(month).mapNotNull { date ->
                    val day = engine.resolve(date)
                    library.events(day).takeIf { it.isNotEmpty() }?.let { CalendarEventDay(date, day, it) }
                }
            CalendarMonthSection(month, CalendarTargets.isExpected(month, now, engine, confirmations), days)
        }
}
