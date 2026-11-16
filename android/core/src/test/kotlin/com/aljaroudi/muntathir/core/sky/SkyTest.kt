package com.aljaroudi.muntathir.core.sky

import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.prayer.PrayerMoment
import com.aljaroudi.muntathir.core.prayer.PrayerName
import java.time.Instant
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Ports `SolarPositionTests`, `MoonPositionTests` and `SolarArcMarkerTests`. Not ported: the retired
// tilt preference decode (P2.1) and NaN dates (an Instant can't be NaN).
class SkyTest {
    private fun at(value: String): Instant = Instant.parse(value)

    @Test
    fun matchesNRELReferenceExample() {
        // NREL SPA report example: 2003-10-17, 12:30:30 MST, 39.742476 N / 105.1786 W (zenith 50.11162°, azimuth 194.34024°).
        val sun = SolarPosition.calculate(at("2003-10-17T19:30:30Z"), 39.742476, -105.1786)!!
        assertTrue(abs(sun.apparentElevation - (90 - 50.11162)) < 0.05)
        assertTrue(abs(sun.azimuth - 194.34024) < 0.05)
        assertFalse(sun.isRising)
    }

    @Test
    fun polarSeasonsRemainFinite() {
        for (instant in listOf("2026-06-21T12:00:00Z", "2026-12-21T12:00:00Z")) {
            val north = SolarPosition.calculate(at(instant), 90.0, 0.0)!!
            val south = SolarPosition.calculate(at(instant), -90.0, 0.0)!!
            assertTrue(north.elevation.isFinite() && south.azimuth.isFinite())
            assertTrue(abs(north.elevation + south.elevation) < 0.001)
            assertTrue(abs(abs(north.elevation) - 23.44) < 0.1)
            assertEquals(instant.contains("06-21"), north.elevation > 0)
        }
    }

    @Test
    fun dateLineDoesNotChangeAnInstant() {
        val instant = at("2026-03-20T00:00:00Z")
        val east = SolarPosition.calculate(instant, 0.0, 180.0)!!
        val west = SolarPosition.calculate(instant, 0.0, -180.0)!!
        assertTrue(abs(east.elevation - west.elevation) < 0.00001)
        assertTrue(abs(east.azimuth - west.azimuth) < 0.00001)
        assertTrue(east.elevation > 87)
    }

    @Test
    fun sunriseIsEastAndSunsetIsWest() {
        val morning = SolarPosition.calculate(at("2026-03-20T06:07:00Z"), 0.0, 0.0)!!
        val evening = SolarPosition.calculate(at("2026-03-20T18:07:00Z"), 0.0, 0.0)!!
        assertTrue(abs(morning.azimuth - 90) < 1)
        assertTrue(abs(evening.azimuth - 270) < 1)
        assertTrue(abs(morning.elevation) < 1)
        assertTrue(morning.apparentElevation > morning.elevation)
        assertTrue(morning.isRising)
        assertFalse(evening.isRising)
    }

    @Test
    fun invalidInputsReturnNoSky() {
        val now = Instant.now()
        for ((latitude, longitude) in listOf(
            Double.NaN to 0.0,
            91.0 to 0.0,
            0.0 to Double.POSITIVE_INFINITY,
            0.0 to 181.0,
            0.0 to -181.0,
        )) {
            assertNull(SolarPosition.calculate(now, latitude, longitude))
            assertNull(MoonPosition.calculate(now, latitude, longitude))
        }
    }

    @Test
    fun daytimeProgressRunsFromLeftToRightAndDisappearsAtNight() {
        var previous = -1.0
        for (hour in 7..17) {
            val progress =
                SolarPosition
                    .calculate(
                        at("2026-03-20T%02d:00:00Z".format(hour)),
                        0.0,
                        0.0,
                    )!!
                    .daylightProgress!!
            assertTrue(progress > previous && progress in 0.0..1.0)
            previous = progress
        }
        val noon = SolarPosition.calculate(at("2026-03-20T12:07:00Z"), 0.0, 0.0)!!
        assertTrue(abs(noon.daylightProgress!! - 0.5) < 0.01)
        assertNull(SolarPosition.calculate(at("2026-03-20T00:00:00Z"), 0.0, 0.0)!!.daylightProgress)
    }

    @Test
    fun arcKeepsSunWithinItsReservedBand() {
        val bounds = ArcRect(36.0, 24.0, 330.0, 100.0)
        assertEquals(ArcPoint(36.0, 124.0), SolarArcLayout.point(0.0, 0.0, bounds))
        assertEquals(ArcPoint(201.0, 24.0), SolarArcLayout.point(0.5, 90.0, bounds))
        assertTrue(abs(SolarArcLayout.point(1.0, 0.0, bounds).y - 124) < 0.001)
        for (step in 0..100) {
            val point = SolarArcLayout.point(step / 100.0, step.toDouble(), bounds)
            assertTrue(point.x in bounds.x..bounds.maxX && point.y in bounds.y..bounds.maxY)
        }
    }

    @Test
    fun heightUsesFixedDegreesIndependentlyOfProgress() {
        val bounds = ArcRect(36.0, 24.0, 330.0, 100.0)
        for (progress in listOf(0.0, 0.25, 0.5, 1.0)) {
            assertEquals(74.0, SolarArcLayout.point(progress, 45.0, bounds).y)
            assertEquals(124.0, SolarArcLayout.point(progress, -0.833, bounds).y)
            assertEquals(24.0, SolarArcLayout.point(progress, 100.0, bounds).y)
        }
        val sun = SolarArcLayout.point(0.5, 30.0, bounds)
        val moon = SolarArcLayout.point(0.5, 60.0, bounds)
        assertEquals(sun.x, moon.x)
        assertTrue(sun.y > moon.y)
    }

    @Test
    fun solarGuideMatchesPositionAcrossSeasonsAndLatitudes() {
        for (latitude in listOf(0.0, 24.7, 60.0, 90.0, -90.0)) {
            for (day in listOf("2026-03-20", "2026-06-21", "2026-12-21")) {
                for (hour in listOf(0, 6, 9, 12, 15, 18)) {
                    val sun = SolarPosition.calculate(at("%sT%02d:00:00Z".format(day, hour)), latitude, 0.0)!!
                    val progress = sun.daylightProgress
                    if (progress != null) {
                        val arc = assertNotNull(sun.arc)
                        assertTrue(abs(arc.elevation(progress) - sun.elevation) < 0.000001)
                        for (step in 0..60) assertTrue(arc.elevation(step / 60.0).isFinite())
                    } else {
                        assertNull(sun.arc)
                    }
                }
            }
        }
        val winter = SolarPosition.calculate(at("2026-12-21T12:00:00Z"), 60.0, 0.0)!!.arc!!
        assertTrue(winter.elevation(0.5) < 7)
        assertTrue(abs(winter.elevation(0.0) + 0.833) < 0.000001)
        assertTrue(abs(winter.elevation(1.0) + 0.833) < 0.000001)
    }

    @Test
    fun polarDayStaysVisibleAndPolarNightHasNoSun() {
        for (hour in listOf(0, 6, 12, 18)) {
            assertNotNull(
                SolarPosition.calculate(at("2026-06-21T%02d:00:00Z".format(hour)), 90.0, 0.0)!!.daylightProgress,
            )
            assertNull(SolarPosition.calculate(at("2026-12-21T%02d:00:00Z".format(hour)), 90.0, 0.0)!!.daylightProgress)
        }
    }

    @Test
    fun moonMatchesPublishedTopocentricExample() {
        // Schlyter's 1990-04-19 example at 60 N, 15 E: https://www.stjarnhimlen.se/comp/tutorial.html#9
        val moon = MoonPosition.calculate(at("1990-04-19T00:00:00Z"), 60.0, 15.0)!!
        assertTrue(abs(moon.elevation - -16.2247) < 0.05)
        assertTrue(abs(moon.azimuth - 101.7863) < 0.05)
        assertNull(moon.visibleProgress)
    }

    @Test
    fun moonMatchesIndependentPhaseFixtures() {
        // Fred Espenak's phase table: https://www.astropixels.com/almanac/almanac21/almanac2024gmt.html
        for ((instant, fraction) in listOf(
            "2024-04-08T18:21:00Z" to 0.0,
            "2024-04-15T19:13:00Z" to 0.5,
            "2024-04-23T23:49:00Z" to 1.0,
            "2024-04-02T03:15:00Z" to 0.5,
        )) {
            val moon = MoonPosition.calculate(at(instant), 21.4225, 39.8262)!!
            assertTrue(abs(moon.illuminatedFraction - fraction) < 0.005, instant)
            if (instant.contains("04-15")) assertTrue(moon.isWaxing)
            if (instant.contains("04-02")) assertFalse(moon.isWaxing)
        }
    }

    @Test
    fun locationChangesMoonPositionButNotPhase() {
        val instant = at("2026-10-21T16:00:00Z")
        val mecca = MoonPosition.calculate(instant, 21.4225, 39.8262)!!
        val opposite = MoonPosition.calculate(instant, -21.4225, -140.1738)!!
        assertNotNull(mecca.visibleProgress)
        assertNull(opposite.visibleProgress)
        assertEquals(mecca.illuminatedFraction, opposite.illuminatedFraction)
        assertEquals(mecca.isWaxing, opposite.isWaxing)
    }

    @Test
    fun dailyMoonVisibilityAndProgressStayValid() {
        val start = at("2026-10-21T00:00:00Z")
        for (latitude in listOf(-90.0, -33.9, 0.0, 21.4, 90.0)) {
            for (hour in 0 until 48) {
                val instant = start.plusSeconds(hour * 3600L)
                val east = MoonPosition.calculate(instant, latitude, 180.0)!!
                val west = MoonPosition.calculate(instant, latitude, -180.0)!!
                assertTrue(east.elevation.isFinite() && east.azimuth.isFinite())
                assertTrue(abs(east.elevation - west.elevation) < 0.00001)
                assertEquals(east.elevation >= 0, east.visibleProgress != null)
                east.visibleProgress?.let { assertTrue(it in 0.0..1.0) }
            }
        }
    }

    private val equator = SavedLocation(0.0, 0.0, "Equator", "", "GMT")

    private fun time(hour: Int): Instant = Instant.ofEpochSecond(1_773_964_800L + hour * 3600L) // 2026-03-20 UTC

    @Test
    fun visibleScheduleDeterminesPastUpcomingAndFuture() {
        val prayers =
            listOf(
                PrayerMoment(PrayerName.Fajr, time(5)),
                PrayerMoment(PrayerName.Dhuhr, time(12)),
                PrayerMoment(PrayerName.Asr, time(15)),
                PrayerMoment(PrayerName.Isha, time(20)),
            )
        val markers = SolarArcMarker.make(prayers, time(10), equator)
        assertEquals(listOf(PrayerName.Dhuhr, PrayerName.Asr), markers.map { it.name })
        assertEquals(SolarArcMarker.State.Upcoming, markers.first().state)
        assertEquals(SolarArcMarker.State.Future, markers.last().state)
        val later = SolarArcMarker.make(prayers, time(12), equator)
        assertEquals(SolarArcMarker.State.Past, later.first().state)
        assertEquals(SolarArcMarker.State.Upcoming, later.last().state)
        assertTrue(markers[0].progress < markers[1].progress)
        assertEquals(SolarPosition.calculate(time(12), 0.0, 0.0)!!.elevation, markers[0].elevation)
        assertTrue(markers[0].elevation > markers[1].elevation)
    }

    @Test
    fun hiddenTimesAreAbsentAndNextOffPathDoesNotPromoteAnotherMarker() {
        val prayers = listOf(PrayerMoment(PrayerName.Fajr, time(5)), PrayerMoment(PrayerName.Asr, time(15)))
        val beforeDawn = SolarArcMarker.make(prayers, time(4), equator)
        assertEquals(listOf(PrayerName.Asr), beforeDawn.map { it.name })
        assertEquals(SolarArcMarker.State.Future, beforeDawn.first().state)
        assertEquals(SolarArcMarker.State.Upcoming, SolarArcMarker.make(prayers, time(10), equator).first().state)
    }

    @Test
    fun roundedHorizonTimesStayAtEndpoints() {
        val prayers = listOf(PrayerMoment(PrayerName.Sunrise, time(6)), PrayerMoment(PrayerName.Sunset, time(18)))
        val markers = SolarArcMarker.make(prayers, time(12), equator)
        assertEquals(listOf(0.0, 1.0), markers.map { it.progress })
        assertEquals(listOf(0.0, 0.0), markers.map { it.elevation })
        assertEquals(listOf(SolarArcMarker.State.Past, SolarArcMarker.State.Upcoming), markers.map { it.state })
        assertTrue(SolarArcMarker.make(emptyList(), time(12), equator).isEmpty())
    }
}
