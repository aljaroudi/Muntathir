package com.aljaroudi.muntathir.notifications

import android.os.ParcelFileDescriptor
import androidx.test.platform.app.InstrumentationRegistry
import com.aljaroudi.muntathir.FakeLocator
import com.aljaroudi.muntathir.core.app.AppState
import com.aljaroudi.muntathir.core.app.DeviceState
import com.aljaroudi.muntathir.core.app.Preferences
import com.aljaroudi.muntathir.core.calendar.EventLibrary
import com.aljaroudi.muntathir.core.calendar.IslamicEvent
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** The one app alarm, read back from `dumpsys alarm`. */
class AlarmSchedulerTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val now = Instant.now().truncatedTo(ChronoUnit.SECONDS)
    private val day = Duration.ofHours(24)

    /** Prayer alerts off; only calendar alerts can plan anything. */
    private fun state(
        calendar: Boolean = true,
        located: Boolean = true,
    ) = AppState(
        Preferences(enabledPrayers = emptySet(), calendarEventNotifications = calendar),
        DeviceState(onboardingCompleted = true, liveLocation = if (located) FakeLocator.MECCA else null),
        emptyList(),
        0,
        ZoneId.of("Asia/Riyadh"),
    )

    private fun scheduler(events: List<IslamicEvent> = emptyList()) =
        AlarmScheduler(context, EventLibrary(events), Clock.fixed(now, ZoneId.of("UTC")))

    /** When the app's RTC_WAKEUP alarm is set for, or null if none is pending. */
    private fun alarm(): Instant? {
        val dump =
            ParcelFileDescriptor
                .AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand("dumpsys alarm"))
                .use { it.readBytes().decodeToString() }
        val pattern = Regex("""type 0 origWhen (\d+) whenElapsed -?\d+ ${Regex.escape(context.packageName)}\}""")
        val match = pattern.find(dump) ?: return null
        return Instant.ofEpochMilli(match.groupValues[1].toLong())
    }

    @After
    fun tearDown() = scheduler().schedule(state(calendar = false))

    @Test
    fun anEmptyWindowReplansADayLaterUntilTheNextEventIsInRange() {
        val state = state()
        // An event 12 days out: its eve's sunset is past the 10-day window.
        val target = state.engine.resolve(state.engine.localDate(now).plusDays(12))
        val scheduler = scheduler(listOf(IslamicEvent("test", target.month.month, target.day, emptyMap())))

        scheduler.schedule(state, now)
        assertEquals(now + day, alarm())
        // Each wake-up finds nothing due and plans again from its own time, as AlarmReceiver does.
        scheduler.schedule(state, now + day)
        assertEquals(now + day + day, alarm())
        scheduler.schedule(state, now + day + day)
        val event = scheduler.alerts(state, now + day + day).single()
        assertEquals(listOf("test"), event.events.map { it.id })
        assertEquals(event.time.truncatedTo(ChronoUnit.MILLIS), alarm())
    }

    @Test
    fun anEmptyPlanCancelsTheAlarmWithoutCalendarAlertsOrALocation() {
        val scheduler = scheduler()
        scheduler.schedule(state(), now)
        assertEquals(now + day, alarm())
        scheduler.schedule(state(calendar = false), now)
        assertNull(alarm())

        scheduler.schedule(state(), now)
        assertEquals(now + day, alarm())
        scheduler.schedule(state(located = false), now)
        assertNull(alarm())
    }
}
