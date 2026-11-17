package com.aljaroudi.muntathir.core.prayer

import com.aljaroudi.muntathir.core.location.SavedLocation
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Prayer settings shared with widgets and other surfaces. Port of Swift `WidgetPrayerSettings`. */
@Serializable
data class WidgetPrayerSettings(
    val location: SavedLocation?,
    val method: PrayerMethod,
    val hiddenPrayers: Set<PrayerName> = emptySet(),
    /** Minutes before Fajr; out-of-range values are clamped to 0…120 when used, as Swift clamps on init. */
    val imsakMinutes: Int = 10,
) {
    /** Plain sunset for the civil day [date]; always uses the Jafari run, so methods agree. */
    fun sunset(date: LocalDate): Instant? {
        val location = location?.takeIf { it.hasValidCoordinates && it.hasValidZone } ?: return null
        return PrayerCalculator
            .times(
                date,
                location,
                PrayerMethod.Jafari,
            ).firstOrNull { it.name == PrayerName.Sunset }
            ?.time
    }

    fun prayers(date: LocalDate): List<PrayerMoment> {
        val location = location ?: return emptyList()
        return PrayerCalculator.times(date, location, method, imsakMinutes).filter { it.name.isVisible(hiddenPrayers) }
    }

    fun prayers(instant: Instant): List<PrayerMoment> = location?.let { prayers(it.localDate(instant)) }.orEmpty()

    fun upcomingPrayers(
        after: Instant,
        limit: Int = 3,
    ): List<PrayerMoment> {
        val location = location ?: return emptyList()
        val today = location.localDate(after)
        return (prayers(today) + prayers(today.plusDays(1)))
            .filter { it.name.isPrayer && it.time > after }
            .sortedBy { it.time }
            .take(limit.coerceAtLeast(0))
    }

    /** The next prayer strictly after [after]; a prayer starting exactly now is already current. */
    fun nextPrayer(after: Instant): PrayerMoment? = upcomingPrayers(after, 1).firstOrNull()

    /**
     * The next instant any home screen surface changes after [after]: the next prayer passing (prayer widget),
     * sunset (the daily ayah turns over) or midnight in [zone] (dates). Android needs only this one boundary,
     * since the countdown runs on its own, where WidgetKit takes a [timelineDates] list.
     */
    fun nextChange(
        after: Instant,
        zone: ZoneId,
    ): Instant {
        val midnight =
            after
                .atZone(zone)
                .toLocalDate()
                .plusDays(1)
                .atStartOfDay(zone)
                .toInstant()
        val sunset =
            location?.let { place ->
                val today = place.localDate(after)
                listOf(today, today.plusDays(1)).firstNotNullOfOrNull { day -> sunset(day)?.takeIf { it > after } }
            }
        return listOfNotNull(midnight, nextPrayer(after)?.time, sunset).min()
    }

    /** Minute ticks for six hours plus local midnights and prayer times around [from], sorted. */
    fun timelineDates(from: Instant): List<Instant> {
        val location = location ?: return listOf(from)
        val dates = sortedSetOf(from)
        val nextMinute = Math.floorDiv(from.epochSecond, 60L) * 60 + 60
        for (minute in 0 until 360) dates += Instant.ofEpochSecond(nextMinute + minute * 60L)
        val today = location.localDate(from)
        for (offset in -1L until 3L) {
            val day = today.plusDays(offset)
            val midnight = day.atStartOfDay(location.zone).toInstant()
            if (midnight > from) dates += midnight
            for (prayer in prayers(day)) if (prayer.time > from) dates += prayer.time
        }
        return dates.toList()
    }
}

internal fun SavedLocation.localDate(instant: Instant): LocalDate = instant.atZone(zone).toLocalDate()
