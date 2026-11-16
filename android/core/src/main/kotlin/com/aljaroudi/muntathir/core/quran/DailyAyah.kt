package com.aljaroudi.muntathir.core.quran

import com.aljaroudi.muntathir.core.calendar.CalendarEngine
import com.aljaroudi.muntathir.core.calendar.ResolvedDay
import com.aljaroudi.muntathir.core.prayer.WidgetPrayerSettings
import kotlinx.serialization.json.Json
import java.time.Instant

/**
 * The verse of the day: 360 global verse indices by Hijri (month, day), advancing at sunset.
 * Port of the verse half of Swift `ContentLibrary`.
 */
class DailyAyah(
    /** Exactly [COUNT] verses, or empty when the schedule is incomplete. */
    val verses: List<Ayah>,
) {
    fun verse(day: ResolvedDay): Ayah? = verses.getOrNull(index(day))

    fun verse(
        instant: Instant,
        engine: CalendarEngine,
        prayers: WidgetPrayerSettings? = null,
    ): Ayah? = verse(verseDay(instant, engine, prayers))

    companion object {
        const val COUNT = 360

        /** Day 30 shares the slot of the next month's day 1, as on iOS. */
        fun index(day: ResolvedDay): Int = (day.month.month - 1) * 30 + day.day - 1

        /** The Hijri day whose verse shows at [instant]: tomorrow's once today's (Jafari) sunset has passed. */
        fun verseDay(
            instant: Instant,
            engine: CalendarEngine,
            prayers: WidgetPrayerSettings? = null,
        ): ResolvedDay {
            val date = engine.localDate(instant)
            val sunset = prayers?.sunset(date)
            return engine.resolve(if (sunset != null && instant >= sunset) date.plusDays(1) else date)
        }

        /**
         * Builds the schedule from `quran-daily-ids.json` and a verse lookup by global index. Any malformed,
         * short or unresolvable list disables the card instead of showing a wrong verse.
         */
        fun load(
            idsJson: String?,
            lookup: (Set<Int>) -> Map<Int, Ayah>,
        ): DailyAyah {
            val ids = ids(idsJson)
            return load(ids, if (ids.size == COUNT) lookup(ids.toSet()) else emptyMap())
        }

        /** The schedule's verse indices; empty when malformed. */
        fun ids(json: String?): List<Int> =
            json?.let { runCatching { Json.decodeFromString<List<Int>>(it) }.getOrNull() }.orEmpty()

        fun load(
            ids: List<Int>,
            records: Map<Int, Ayah>,
        ): DailyAyah =
            DailyAyah(if (ids.size == COUNT && ids.all { it in records }) ids.map(records::getValue) else emptyList())
    }
}
