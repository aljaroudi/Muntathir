package com.aljaroudi.muntathir.core.wear

import com.aljaroudi.muntathir.core.prayer.PrayerMoment
import com.aljaroudi.muntathir.core.prayer.WidgetPrayerSettings
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** A value that holds from [start] (inclusive) to [end] (exclusive). */
data class Span<T>(
    val start: Instant,
    val end: Instant,
    val value: T,
)

/**
 * Timeline entries for watch complications and the tile, which (like WidgetKit on watchOS, Swift
 * `WatchProvider.getTimeline`) render ahead of time instead of being woken at every boundary.
 */
object WatchTimeline {
    /** Consecutive spans over which the next prayer stays the same, starting at [from]. */
    fun nextPrayers(
        settings: WidgetPrayerSettings,
        from: Instant,
        count: Int = 10,
    ): List<Span<PrayerMoment>> {
        val spans = mutableListOf<Span<PrayerMoment>>()
        var cursor = from
        while (spans.size < count) {
            val next = settings.nextPrayer(cursor) ?: break
            spans += Span(cursor, next.time, next)
            cursor = next.time
        }
        return spans
    }

    /** Local days in [zone], the first from [from] to the next midnight. */
    fun days(
        zone: ZoneId,
        from: Instant,
        count: Int = 3,
    ): List<Span<LocalDate>> {
        var start = from
        var day = from.atZone(zone).toLocalDate()
        return List(count) {
            val end = day.plusDays(1).atStartOfDay(zone).toInstant()
            Span(start, end, day).also {
                start = end
                day = day.plusDays(1)
            }
        }
    }
}
