package com.aljaroudi.muntathir.core.calendar

import com.aljaroudi.muntathir.core.calendar.CalendarException.Kind
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.abs

/**
 * Hijri calendar on the Umm al-Qura baseline with confirmed and manual month starts.
 * Port of Swift `CalendarEngine`; days are [LocalDate]s in [zone] (Swift used local-midnight `Date`s).
 */
class CalendarEngine(
    val zone: ZoneId,
    manual: List<MonthCorrection> = emptyList(),
    confirmed: List<MonthCorrection> = emptyList(),
) {
    val corrections: Map<HijriMonth, MonthCorrection>
    private val anchors: List<HijriMonth>

    init {
        val rows = mutableMapOf<HijriMonth, MonthCorrection>()
        // Manual rows are applied last, so they win over confirmed rows for the same month.
        for (list in listOf(confirmed, manual)) {
            val seen = mutableSetOf<HijriMonth>()
            for (row in list) {
                if (!row.month.isValid ||
                    row.start.toLocalDate() == null ||
                    row.provenance == DateProvenance.Calculated ||
                    !seen.add(row.month)
                ) {
                    throw CalendarException(Kind.InvalidDate)
                }
                rows[row.month] = row
            }
        }
        corrections = rows
        anchors = rows.keys.sorted()
        for ((left, right) in anchors.zipWithNext()) {
            val days = distance(anchorStart(left), anchorStart(right))
            val months = right.index - left.index
            if (days !in 29 * months..30 * months) throw CalendarException(Kind.ConflictingMonths)
        }
        // Limit corrections to nearby baseline starts, preventing mislabeled years or unbounded searches.
        for (month in anchors) {
            if (abs(distance(baselineStart(month), anchorStart(month))) > 7) throw CalendarException(Kind.InvalidDate)
        }
    }

    private fun anchorStart(month: HijriMonth): LocalDate = corrections.getValue(month).start.toLocalDate()!!

    fun distance(
        from: LocalDate,
        to: LocalDate,
    ): Int = ChronoUnit.DAYS.between(from, to).toInt()

    fun localDate(instant: Instant): LocalDate = instant.atZone(zone).toLocalDate()

    fun startOfDay(date: LocalDate): Instant = date.atStartOfDay(zone).toInstant()

    fun baselineStart(month: HijriMonth): LocalDate = UmmAlQura.start(month)

    fun baselineLength(month: HijriMonth): Int = UmmAlQura.length(month)

    fun start(month: HijriMonth): LocalDate {
        corrections[month]?.let { return it.start.toLocalDate()!! }
        val previous = anchors.lastOrNull { it < month } ?: return startBeforeFirstAnchor(month)
        var cursor = previous
        var date = anchorStart(previous)
        val next = anchors.firstOrNull { it > previous }
        while (cursor < month) {
            var length = baselineLength(cursor)
            if (next != null && cursor < next) {
                val remaining = next.index - cursor.index - 1
                val days = distance(date, anchorStart(next))
                length = minOf(maxOf(length, days - 30 * remaining), days - 29 * remaining)
            } else {
                val gap = distance(date, baselineStart(cursor.advanced(1)))
                if (gap in 29..30) length = gap
            }
            date = date.plusDays(length.toLong())
            cursor = cursor.advanced(1)
        }
        return date
    }

    /** Walks back from the first later anchor, preferring baseline starts that keep 29–30 day months. */
    private fun startBeforeFirstAnchor(month: HijriMonth): LocalDate {
        val next = anchors.firstOrNull { it > month } ?: return baselineStart(month)
        var cursor = next
        var end = anchorStart(next)
        while (cursor > month) {
            cursor = cursor.advanced(-1)
            val candidate = baselineStart(cursor)
            end = if (distance(candidate, end) in 29..30) candidate else end.minusDays(baselineLength(cursor).toLong())
        }
        return end
    }

    fun resolve(date: LocalDate): ResolvedDay {
        var month = UmmAlQura.month(date)
        while (date < start(month)) month = month.advanced(-1)
        while (date >= start(month.advanced(1))) month = month.advanced(1)
        val correction = corrections[month]
        return ResolvedDay(
            month = month,
            day = distance(start(month), date) + 1,
            provenance = correction?.provenance ?: DateProvenance.Calculated,
            sourceID = correction?.sourceID,
        )
    }

    fun resolve(instant: Instant): ResolvedDay = resolve(localDate(instant))

    fun days(month: HijriMonth): List<LocalDate> {
        val start = start(month)
        return (0 until distance(start, start(month.advanced(1)))).map { start.plusDays(it.toLong()) }
    }

    companion object {
        /** Applies source-relative [offsets] on top of [confirmed] starts. Swift `init(timeZone:offsets:confirmed:)`. */
        fun withOffsets(
            zone: ZoneId,
            offsets: List<MonthOffset>,
            confirmed: List<MonthCorrection> = emptyList(),
        ): CalendarEngine {
            if (!MonthOffset.isValid(offsets)) throw CalendarException(Kind.InvalidDate)
            val source = CalendarEngine(zone, confirmed = confirmed)
            val manual =
                offsets.filter { it.days != 0 }.map {
                    MonthCorrection(
                        month = it.month,
                        start = CivilDate.of(source.start(it.month).minusDays(it.days.toLong())),
                        provenance = DateProvenance.Manual,
                    )
                }
            return CalendarEngine(zone, manual = manual, confirmed = confirmed)
        }
    }
}
