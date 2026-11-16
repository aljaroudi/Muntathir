package com.aljaroudi.muntathir.core.prayer

import com.aljaroudi.muntathir.core.app.Preferences
import com.aljaroudi.muntathir.core.calendar.CalendarEngine
import com.aljaroudi.muntathir.core.calendar.EventLibrary
import com.aljaroudi.muntathir.core.calendar.EventTiming
import com.aljaroudi.muntathir.core.calendar.HijriMonth
import com.aljaroudi.muntathir.core.calendar.IslamicEvent
import com.aljaroudi.muntathir.core.calendar.MonthOffset
import com.aljaroudi.muntathir.core.location.SavedLocation
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

// Ports the logic of `PrayerPreferencesTests` and the sunset case of `EventsTests`. Preferences JSON migration
// lives in `PreferencesTest`; Watch round trips are P8.
class NotificationPlanTest {
    private val mecca = SavedLocation(21.4225, 39.8262, "Mecca", "SA", "Asia/Riyadh")

    private fun midnight(
        date: LocalDate,
        location: SavedLocation = mecca,
    ): Instant = date.atStartOfDay(location.zone).toInstant()

    @Test
    fun imsakOffsetReachesScheduleWidgetsAndNotifications() {
        val day = LocalDate.of(2026, 10, 18)
        for (minutes in listOf(0, 10, 25, 120)) {
            val settings = WidgetPrayerSettings(mecca, PrayerMethod.Tehran, emptySet(), minutes)
            val times = settings.prayers(day)
            val imsak = times.first { it.name == PrayerName.Imsak }
            val fajr = times.first { it.name == PrayerName.Fajr }
            assertEquals(Duration.ofMinutes(minutes.toLong()), Duration.between(imsak.time, fajr.time))
            val options =
                Preferences(
                    prayerMethod = PrayerMethod.Tehran,
                    imsakMinutes = minutes,
                    enabledPrayers = setOf(PrayerName.Imsak),
                )
            val plan = NotificationPlan.make(midnight(day), options, mecca)
            assertEquals(PrayerName.Imsak, plan.first().name)
            assertEquals(imsak.time, plan.first().time)
            assertEquals(PrayerName.Fajr, settings.nextPrayer(midnight(day))?.name)
        }
        val clamped = WidgetPrayerSettings(mecca, PrayerMethod.Tehran, emptySet(), 999).prayers(day)
        assertEquals(
            Duration.ofMinutes(120),
            Duration.between(
                clamped.first { it.name == PrayerName.Imsak }.time,
                clamped
                    .first {
                        it.name ==
                            PrayerName.Fajr
                    }.time,
            ),
        )
    }

    @Test
    fun calendarOffsetsNeverChangePrayers() {
        // Offsets live in the calendar engine; prayer math only sees the Umm al-Qura baseline.
        val now = midnight(LocalDate.of(2026, 10, 18))
        val options = Preferences(prayerMethod = PrayerMethod.UmmAlQura)
        val before = NotificationPlan.make(now, options, mecca)
        for (days in -2..2) {
            CalendarEngine.withOffsets(mecca.zone, listOf(MonthOffset(HijriMonth(1448, 9), days)))
            assertEquals(before, NotificationPlan.make(now, options, mecca))
        }
    }

    @Test
    fun eventRemindersUseCorrectedTomorrowAtSunsetAndCombineEvents() {
        val now = midnight(LocalDate.of(2026, 10, 18))
        val base = CalendarEngine(mecca.zone)
        val month = base.resolve(now).month
        val engine = CalendarEngine.withOffsets(mecca.zone, listOf(MonthOffset(month, 1)))
        val tomorrow = engine.resolve(LocalDate.of(2026, 10, 19))
        val events = listOf("b", "a").map { IslamicEvent(it, tomorrow.month.month, tomorrow.day, mapOf("en" to it)) }
        val options = Preferences()
        assertTrue(NotificationPlan.events(now, options, mecca, engine, events).isEmpty())
        val enabled = options.copy(calendarEventNotifications = true)
        val plan = NotificationPlan.events(now, enabled, mecca, engine, events)
        assertEquals(1, plan.size)
        assertEquals(listOf("a", "b"), plan.first().events.map { it.id })
        val sunset = WidgetPrayerSettings(mecca, enabled.prayerMethod).sunset(LocalDate.of(2026, 10, 18))!!
        assertEquals(sunset, plan.first().time)
        assertTrue(NotificationPlan.events(sunset, enabled, mecca, engine, events).isEmpty())
        assertNotEquals(sunset, NotificationPlan.events(now, enabled, mecca, base, events).firstOrNull()?.time)
    }

    @Test
    fun combinedNotificationBudgetKeepsNearestFifty() {
        val requests =
            (0 until 80).reversed().map {
                ScheduledAlert(
                    "$it",
                    Instant.ofEpochSecond(it.toLong()),
                    if (it % 2 ==
                        0
                    ) {
                        PrayerName.Fajr
                    } else {
                        null
                    },
                    emptyList(),
                )
            }
        val selected = NotificationPlan.nearest(requests)
        assertEquals(50, selected.size)
        assertEquals("0", selected.first().id)
        assertEquals("49", selected.last().id)
    }

    @Test
    fun alarmChainWalksPrayersAndEventRemindersInOrder() {
        val now = midnight(LocalDate.of(2026, 10, 18))
        val engine = CalendarEngine(mecca.zone)
        val tomorrow = engine.resolve(LocalDate.of(2026, 10, 19))
        val events = listOf(IslamicEvent("e", tomorrow.month.month, tomorrow.day, mapOf("en" to "E")))
        val options =
            Preferences(enabledPrayers = setOf(PrayerName.Fajr, PrayerName.Maghrib), calendarEventNotifications = true)
        val alerts = NotificationPlan.alerts(now, options, mecca, engine, events)
        assertEquals(alerts.sortedWith(compareBy({ it.time }, { it.id })), alerts)
        assertEquals(listOf(PrayerName.Fajr, null, PrayerName.Maghrib), alerts.take(3).map { it.prayer })
        // Each alarm asks for the alerts strictly after the one that just fired.
        var cursor = now
        val walked = mutableListOf<String>()
        repeat(6) {
            val next = NotificationPlan.alerts(cursor, options, mecca, engine, events).first()
            walked += next.id
            cursor = next.time
        }
        assertEquals(alerts.take(6).map { it.id }, walked)
        assertTrue(
            NotificationPlan.alerts(now, Preferences(enabledPrayers = emptySet()), mecca, engine, events).isEmpty(),
        )
    }

    @Test
    fun polarDatesWithoutSunsetDoNotInventEventTimes() {
        val polar = SavedLocation(78.2232, 15.6469, "Longyearbyen", "NO", "Arctic/Longyearbyen")
        val today = LocalDate.of(2026, 6, 21)
        val engine = CalendarEngine(polar.zone)
        val tomorrow = engine.resolve(today.plusDays(1))
        val events = listOf(IslamicEvent("test", tomorrow.month.month, tomorrow.day, mapOf("en" to "Test")))
        val options = Preferences(calendarEventNotifications = true)
        assertTrue(NotificationPlan.events(midnight(today, polar), options, polar, engine, events).isEmpty())
    }

    @Test
    fun eventRemindersUseLocationTimezone() {
        for (zone in listOf("America/New_York", "Asia/Riyadh")) {
            val place = SavedLocation(40.7128, -74.006, "Test", "US", zone)
            val today = LocalDate.of(2026, 11, 1)
            val engine = CalendarEngine(place.zone)
            val day = engine.resolve(today.plusDays(1))
            val events = listOf(IslamicEvent("test", day.month.month, day.day, mapOf("en" to "Test")))
            val options = Preferences(calendarEventNotifications = true)
            val alert = NotificationPlan.events(midnight(today, place), options, place, engine, events).first()
            assertEquals(WidgetPrayerSettings(place, options.prayerMethod).sunset(today), alert.time)
        }
    }

    @Test
    fun upcomingEventFollowsCorrectedDateAndSunsetBoundaries() {
        val month = HijriMonth(1448, 8)
        val engine = CalendarEngine.withOffsets(mecca.zone, listOf(MonthOffset(month, 1)))
        val date = engine.start(month).plusDays(2)
        val preceding = date.minusDays(1)
        val earlier = date.minusDays(2)
        val settings = WidgetPrayerSettings(mecca, PrayerMethod.Jafari, setOf(PrayerName.Sunset))
        val opening = settings.sunset(preceding)!!
        val closing = settings.sunset(date)!!
        val library = EventLibrary.bundled()
        for ((instant, timing) in listOf(
            midnight(earlier) to EventTiming.Countdown(Duration.between(midnight(earlier), opening)),
            midnight(preceding) to EventTiming.Tonight,
            opening.minusSeconds(1) to EventTiming.Tonight,
            opening to EventTiming.Tonight,
            midnight(date) to EventTiming.Today,
            closing.minusSeconds(1) to EventTiming.Today,
        )) {
            val event = library.upcomingEvent(instant, engine, settings::sunset)!!
            assertEquals(listOf("husayn-birth", "husayn-enter-mecca"), event.events.map { it.id }, "$instant")
            assertEquals(timing, event.timing, "$instant")
        }
        val next = library.upcomingEvent(closing, engine, settings::sunset)!!
        assertEquals(listOf("abbas-birth"), next.events.map { it.id })
        assertEquals(EventTiming.Tonight, next.timing)
    }
}
