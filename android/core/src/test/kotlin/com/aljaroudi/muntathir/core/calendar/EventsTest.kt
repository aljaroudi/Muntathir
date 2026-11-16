package com.aljaroudi.muntathir.core.calendar

import kotlinx.serialization.json.Json
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

// Ports `EventsTests` and the event half of `ContentTests`. The sunset case
// (`upcomingEventFollowsCorrectedDateAndSunsetBoundaries`) lives in prayer/EventSunsetTest.
// Not ported: `yearText` (localized "%lld AH", app resources) and daily verses (P2.4).
class EventsTest {
    private val library = EventLibrary.bundled()

    private fun event(
        id: String,
        month: Int,
        day: Int,
        title: Map<String, String> = mapOf("en" to id),
    ) = IslamicEvent(id, month, day, title)

    @Test
    fun allEventsAppearOnceInMonthAndDayOrder() {
        val events = library.events
        assertTrue(events.isNotEmpty())
        val sections = (1..12).map { EventLibrary.inMonth(it, events) }
        assertEquals(events.size, sections.flatten().size)
        assertEquals(events.map { it.id }.toSet(), sections.flatten().map { it.id }.toSet())
        sections.forEachIndexed { index, section ->
            assertTrue(section.all { it.month == index + 1 })
            assertEquals(section.map { it.day }.sorted(), section.map { it.day })
        }
    }

    @Test
    fun dayThirtyAndSameDaySourceOrderArePreserved() {
        val events = listOf(event("last", 2, 30), event("second", 2, 1), event("first", 2, 1), event("other", 3, 1))
        assertEquals(listOf("second", "first", "last"), EventLibrary.inMonth(2, events).map { it.id })
        assertTrue(EventLibrary.inMonth(1, events).isEmpty())
    }

    @Test
    fun upcomingEventUsesCivilMidnightWithoutSunset() {
        val engine = CalendarEngine(ZoneOffset.UTC)
        val date = engine.startOfDay(engine.start(HijriMonth(1448, 8)).plusDays(2))
        val earlier = date.minus(Duration.ofDays(2))
        val none: (java.time.LocalDate) -> Instant? = { null }
        assertEquals(
            EventTiming.Countdown(Duration.ofSeconds(172_800)),
            library.upcomingEvent(earlier, engine, none)?.timing,
        )
        assertEquals(EventTiming.Tomorrow, library.upcomingEvent(date.minusSeconds(1), engine, none)?.timing)
        assertEquals(EventTiming.Today, library.upcomingEvent(date, engine, none)?.timing)
        val nextDay = date.plus(Duration.ofDays(1))
        assertEquals(
            "husayn-birth",
            library
                .upcomingEvent(nextDay.minusSeconds(1), engine, none)
                ?.events
                ?.first()
                ?.id,
        )
        assertEquals(
            "abbas-birth",
            library
                .upcomingEvent(nextDay, engine, none)
                ?.events
                ?.first()
                ?.id,
        )
    }

    @Test
    fun eventTitlesUseSharedContent() {
        val fitr = library.events.first { it.id == "fitr" }
        for ((tag, expected) in listOf(
            "en-US" to "Eid al-Fitr",
            "ar-SA" to "عيد الفطر",
            "fr-CA" to "Aïd al-Fitr",
            "zh-Hans" to "开斋节",
            "zh-Hant" to "開齋節",
            "zh-TW" to "開齋節",
        )) {
            assertEquals(expected, fitr.title(Locale.forLanguageTag(tag)), tag)
        }
    }

    @Test
    fun eventTitlesUseArabicAcrossRegions() {
        val event = event("test", 1, 1, mapOf("ar" to "عنوان", "en" to "Title"))
        for (tag in listOf(
            "ar",
            "ar-SA",
            "ar-AE",
            "ar-EG",
        )) {
            assertEquals("عنوان", event.title(Locale.forLanguageTag(tag)))
        }
    }

    @Test
    fun missingEventTranslationFallsBackToEnglish() {
        val event = event("test", 1, 1, mapOf("en" to "Title"))
        for (tag in listOf(
            "fr-CA",
            "ar-SA",
            "zh-Hant",
            "ko-KR",
        )) {
            assertEquals("Title", event.title(Locale.forLanguageTag(tag)))
        }
    }

    @Test
    fun eventMetadataSurvivesCoding() {
        val original = IslamicEvent("husayn-death", 1, 10, mapOf("en" to "Martyrdom of Imam Husayn"), year = 61)
        assertEquals(original, Json.decodeFromString<IslamicEvent>(Json.encodeToString(original)))
        val beforeHijra =
            IslamicEvent("prophet-birth", 3, 17, mapOf("en" to "Birth"), year = -53, linkedFigureIDs = listOf("p"))
        assertEquals(beforeHijra, Json.decodeFromString<IslamicEvent>(Json.encodeToString(beforeHijra)))
        assertEquals(listOf("p"), beforeHijra.figureIDs)
    }

    @Test
    fun bundledEventsAreCompleteAndUnique() {
        val events = library.events
        assertTrue(events.size >= 30)
        for (event in events) {
            for (language in listOf("en", "ar")) {
                val title = event.title(Locale.forLanguageTag(language))
                assertFalse(title == event.id || title.isBlank(), event.id)
            }
        }
        assertEquals(events.size, events.map { it.id }.toSet().size)
    }
}
