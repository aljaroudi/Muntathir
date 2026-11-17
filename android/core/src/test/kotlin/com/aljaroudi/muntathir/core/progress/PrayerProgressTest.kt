package com.aljaroudi.muntathir.core.progress

import com.aljaroudi.muntathir.core.app.AppTool
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.prayer.PrayerCalculator
import com.aljaroudi.muntathir.core.prayer.PrayerMethod
import com.aljaroudi.muntathir.core.prayer.PrayerName
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Ports `PrayerProgressTests`; the SwiftData persistence case is covered by the instrumented `ProgressStoreTest`.
class PrayerProgressTest {
    private val location = SavedLocation(21.4225, 39.8262, "Asia/Riyadh")
    private val day = Instant.ofEpochSecond(1_794_520_800)

    private fun times(
        instant: Instant,
        method: PrayerMethod = PrayerMethod.Jafari,
    ) = PrayerCalculator.times(instant.atZone(location.zone).toLocalDate(), location, method)

    private fun List<com.aljaroudi.muntathir.core.prayer.PrayerMoment>.time(name: PrayerName) =
        assertNotNull(firstOrNull { it.name == name }?.time)

    @Test
    fun selection() {
        assertEquals(listOf(PrayerName.Fajr), PrayerProgress.choices(2))
        assertEquals(listOf(PrayerName.Maghrib), PrayerProgress.choices(3))
        assertEquals(listOf(PrayerName.Dhuhr, PrayerName.Asr, PrayerName.Isha), PrayerProgress.choices(4))
        assertTrue(PrayerProgress.choices(1).isEmpty())
        assertTrue(AppTool.PrayerProgress in AppTool.entries)
    }

    @Test
    fun boundaries() {
        for (method in PrayerMethod.entries) {
            for (prayer in PrayerProgress.prayers) {
                val moments = times(day, method)
                val start =
                    moments.time(
                        when (prayer) {
                            PrayerName.Asr -> PrayerName.Dhuhr
                            PrayerName.Isha -> PrayerName.Maghrib
                            else -> prayer
                        },
                    )
                val end =
                    moments.time(
                        when (prayer) {
                            PrayerName.Fajr -> PrayerName.Sunrise
                            PrayerName.Dhuhr, PrayerName.Asr -> PrayerName.Sunset
                            else -> PrayerName.Midnight
                        },
                    )
                for ((instant, expected) in listOf(
                    start.minusSeconds(1) to PrayerTiming.OutsideTime,
                    start to PrayerTiming.OnTime,
                    start.plusSeconds(1) to PrayerTiming.OnTime,
                    end.minusSeconds(1) to PrayerTiming.OnTime,
                    end to PrayerTiming.OutsideTime,
                )) {
                    val record = PrayerProgress.snapshot(prayer, instant, location, method)
                    assertEquals(expected, record.timing, "$method $prayer $instant")
                    assertEquals(start, record.athan)
                    assertEquals(end, record.deadline)
                }
            }
        }
    }

    @Test
    fun previousEveningAndMissingTiming() {
        val midnight =
            day
                .atZone(location.zone)
                .toLocalDate()
                .atStartOfDay(location.zone)
                .toInstant()
        val record = PrayerProgress.snapshot(PrayerName.Isha, midnight, location, PrayerMethod.Jafari)
        val yesterday = midnight.atZone(location.zone).toLocalDate().minusDays(1)
        assertEquals(PrayerProgress.dayKey(yesterday), record.prayerDay)
        val previousMaghrib =
            PrayerCalculator.times(yesterday, location, PrayerMethod.Jafari).time(PrayerName.Maghrib)
        assertEquals(previousMaghrib, record.athan)
        val missing =
            PrayerProgress.snapshot(PrayerName.Fajr, day, null, PrayerMethod.Jafari, fallbackZone = ZoneOffset.UTC)
        assertEquals(PrayerTiming.Unavailable, missing.timing)
        assertEquals("Z", missing.timeZoneID)
        val unavailable =
            PrayerProgress.snapshot(PrayerName.Fajr, day, location, PrayerMethod.Jafari, calculate = { _, _, _ ->
                emptyList()
            })
        assertEquals(PrayerTiming.Unavailable, unavailable.timing)
    }

    @Test
    fun dstAndTravelKeepPrayerDay() {
        val newYork = SavedLocation(40.7128, -74.006, "America/New_York")
        for ((instant, expectedDay) in listOf(
            "2026-11-01T06:30:00Z" to "2026-10-31",
            "2026-03-08T07:30:00Z" to "2026-03-07",
        )) {
            val record = PrayerProgress.snapshot(PrayerName.Isha, Instant.parse(instant), newYork, PrayerMethod.Jafari)
            assertEquals(expectedDay, record.prayerDay)
            assertEquals("America/New_York", record.timeZoneID)
            val decoded = Json.decodeFromString<PrayerCompletion>(Json.encodeToString(record))
            assertEquals(record, decoded)
            assertTrue(expectedDay in PrayerProgress.days(PrayerName.Isha, listOf(decoded)))
        }
    }

    @Test
    fun completionUsesCalibrationAndOnlySavesOnce() {
        val sunrise = times(day).time(PrayerName.Sunrise)
        val ready = sunrise.minusSeconds(60)
        val snapshot = PrayerProgress.snapshot(PrayerName.Fajr, ready, location, PrayerMethod.Jafari)
        val session = PrayerSessionRecording()
        assertNull(session.update(calibrated = false, complete = false, failed = false, instant = ready) { snapshot })
        assertNull(session.snapshot)
        assertNull(session.update(calibrated = true, complete = false, failed = false, instant = ready) { snapshot })
        val completion =
            assertNotNull(
                session.update(calibrated = true, complete = true, failed = false, instant = sunrise) { null },
            )
        assertEquals(PrayerTiming.OnTime, completion.timing)
        assertEquals(ready, completion.startedAt)
        assertEquals(sunrise, completion.completedAt)
        assertNull(session.update(calibrated = true, complete = true, failed = false, instant = sunrise) { snapshot })
        val failed = PrayerSessionRecording()
        assertNull(failed.update(calibrated = true, complete = true, failed = true, instant = day) { snapshot })
        assertNull(failed.update(calibrated = true, complete = true, failed = false, instant = day) { snapshot })
        val other = PrayerSessionRecording()
        assertNull(other.update(calibrated = true, complete = true, failed = false, instant = day) { null })
    }

    @Test
    fun aggregationIsPerPrayerDateAndPositiveWins() {
        val moments = times(day)
        val onTime =
            PrayerProgress.snapshot(
                PrayerName.Fajr,
                moments.time(PrayerName.Fajr),
                location,
                PrayerMethod.Jafari,
            )
        val late =
            PrayerProgress.snapshot(
                PrayerName.Fajr,
                moments.time(PrayerName.Sunrise),
                location,
                PrayerMethod.Jafari,
            )
        val days = PrayerProgress.days(PrayerName.Fajr, listOf(late, onTime, onTime))
        assertEquals(1, days.size)
        assertEquals(PrayerTiming.OnTime, days[onTime.prayerDay])
        assertTrue(PrayerProgress.days(PrayerName.Isha, listOf(onTime)).isEmpty())
    }
}
