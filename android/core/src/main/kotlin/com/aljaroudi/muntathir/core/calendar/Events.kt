package com.aljaroudi.muntathir.core.calendar

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.util.Locale

@Serializable
data class IslamicEvent(
    val id: String,
    val month: Int,
    val day: Int,
    val title: Map<String, String>,
    /** Optional Hijri year (AH). Negative values are before the Hijra. */
    val year: Int? = null,
    @SerialName("figure_ids") private val linkedFigureIDs: List<String>? = null,
) {
    val figureIDs: List<String> get() = linkedFigureIDs.orEmpty()

    fun title(locale: Locale): String {
        val language =
            when (val code = locale.language) {
                "" -> "en"

                "in" -> "id"

                // Legacy ISO code still returned on older Android releases.
                else -> code
            }
        val key = if (language == "zh") "zh-${chineseScript(locale)}" else language
        return title[key] ?: title["en"] ?: id
    }

    private fun chineseScript(locale: Locale): String =
        locale.script.ifEmpty {
            if (locale.country in setOf("TW", "HK", "MO")) "Hant" else "Hans"
        }
}

sealed interface EventTiming {
    data object Today : EventTiming

    data object Tonight : EventTiming

    data object Tomorrow : EventTiming

    data class Countdown(
        val duration: Duration,
    ) : EventTiming
}

data class UpcomingEvent(
    val events: List<IslamicEvent>,
    val timing: EventTiming,
)

/** Islamic events from `shared/events.json`. Port of the event half of Swift `ContentLibrary`. */
class EventLibrary(
    val events: List<IslamicEvent>,
) {
    fun events(day: ResolvedDay): List<IslamicEvent> =
        events.filter { it.month == day.month.month && it.day == day.day }

    fun nextEventDate(
        onOrAfter: LocalDate,
        engine: CalendarEngine,
    ): LocalDate? {
        if (events.isEmpty()) return null
        val month = engine.resolve(onOrAfter).month
        return (0..12)
            .asSequence()
            .mapNotNull { offset ->
                engine
                    .days(
                        month.advanced(offset),
                    ).firstOrNull { it >= onOrAfter && events(engine.resolve(it)).isNotEmpty() }
            }.firstOrNull()
    }

    /**
     * The next events and how to describe them. Days roll over at [sunset] (by civil day), or at
     * midnight when there is none.
     */
    fun upcomingEvent(
        instant: Instant,
        engine: CalendarEngine,
        sunset: (LocalDate) -> Instant?,
    ): UpcomingEvent? {
        val today = engine.localDate(instant)
        val tomorrow = today.plusDays(1)
        val todaySunset = sunset(today)
        val firstDay = if (instant >= (todaySunset ?: engine.startOfDay(tomorrow))) tomorrow else today
        val eventDate = nextEventDate(firstDay, engine) ?: return null
        val timing =
            when (eventDate) {
                today -> {
                    EventTiming.Today
                }

                tomorrow -> {
                    if (todaySunset == null) EventTiming.Tomorrow else EventTiming.Tonight
                }

                else -> {
                    val opening = sunset(eventDate.minusDays(1)) ?: engine.startOfDay(eventDate)
                    EventTiming.Countdown(Duration.between(instant, opening))
                }
            }
        return UpcomingEvent(events(engine.resolve(eventDate)), timing)
    }

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun decode(text: String) = EventLibrary(json.decodeFromString<List<IslamicEvent>>(text))

        /** Events bundled as a classpath resource. */
        fun bundled(): EventLibrary =
            decode(
                checkNotNull(EventLibrary::class.java.getResourceAsStream("/events.json")) { "Missing events.json" }
                    .use { it.readBytes().decodeToString() },
            )

        /** Events of one Hijri month in day order, keeping source order within a day. Swift `EventsView.events`. */
        fun inMonth(
            month: Int,
            events: List<IslamicEvent>,
        ): List<IslamicEvent> = events.filter { it.month == month }.sortedBy { it.day }
    }
}
