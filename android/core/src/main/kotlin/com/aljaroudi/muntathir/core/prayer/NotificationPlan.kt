package com.aljaroudi.muntathir.core.prayer

import com.aljaroudi.muntathir.core.calendar.CalendarEngine
import com.aljaroudi.muntathir.core.calendar.IslamicEvent
import com.aljaroudi.muntathir.core.location.SavedLocation
import java.time.Instant

/** The preference fields notification planning reads (the full preferences model is P2.1). */
data class NotificationOptions(
    val method: PrayerMethod = PrayerMethod.Tehran,
    val imsakMinutes: Int = 10,
    val enabledPrayers: Set<PrayerName> = setOf(PrayerName.Fajr, PrayerName.Dhuhr, PrayerName.Maghrib),
    val calendarEventNotifications: Boolean = false,
)

data class ScheduledPrayer(
    val id: String,
    val name: PrayerName,
    val time: Instant,
)

data class ScheduledAlert(
    val id: String,
    val time: Instant,
    val prayer: PrayerName?,
    val events: List<IslamicEvent>,
)

/** What to schedule as alarms. Port of Swift `NotificationPlan`. */
object NotificationPlan {
    const val DAYS = 10
    const val BUDGET = 50

    /** Enabled prayer times over the next [DAYS] days, strictly after [now]. */
    fun make(
        now: Instant,
        options: NotificationOptions,
        location: SavedLocation,
    ): List<ScheduledPrayer> {
        val today = location.localDate(now)
        return (0 until DAYS)
            .flatMap { offset ->
                PrayerCalculator
                    .times(
                        today.plusDays(offset.toLong()),
                        location,
                        options.method,
                        options.imsakMinutes,
                    ).mapNotNull {
                        if (it.name !in options.enabledPrayers || it.time <= now) return@mapNotNull null
                        ScheduledPrayer("prayer.${it.time.epochSecond}.${it.name.id}", it.name, it.time)
                    }
            }.sortedBy { it.time }
    }

    /** The [BUDGET] soonest alerts, ties broken by id, so prayer and event alerts share the system limit. */
    fun nearest(alerts: List<ScheduledAlert>): List<ScheduledAlert> =
        alerts.sortedWith(compareBy<ScheduledAlert> { it.time }.thenBy { it.id }).take(BUDGET)

    /** One alert at each sunset preceding a (corrected) day with events; days without a sunset get none. */
    fun events(
        now: Instant,
        options: NotificationOptions,
        location: SavedLocation,
        engine: CalendarEngine,
        events: List<IslamicEvent>,
    ): List<ScheduledAlert> {
        if (!options.calendarEventNotifications) return emptyList()
        val settings = WidgetPrayerSettings(location, options.method, emptySet(), options.imsakMinutes)
        val today = engine.localDate(now)
        return (0 until DAYS).mapNotNull { offset ->
            val day = today.plusDays(offset.toLong())
            val sunset = settings.sunset(day)?.takeIf { it > now } ?: return@mapNotNull null
            val tomorrow = engine.resolve(day.plusDays(1))
            val matching =
                events
                    .filter {
                        it.month == tomorrow.month.month && it.day == tomorrow.day
                    }.sortedBy { it.id }
            if (matching.isEmpty()) return@mapNotNull null
            ScheduledAlert("event.${sunset.epochSecond}", sunset, null, matching)
        }
    }
}
