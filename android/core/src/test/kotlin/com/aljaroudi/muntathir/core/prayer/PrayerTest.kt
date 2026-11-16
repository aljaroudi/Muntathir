package com.aljaroudi.muntathir.core.prayer

import com.aljaroudi.muntathir.core.Fixtures
import com.aljaroudi.muntathir.core.app.Preferences
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.prayer.adhan.CalculationMethod
import com.aljaroudi.muntathir.core.prayer.adhan.Coordinates
import com.aljaroudi.muntathir.core.prayer.adhan.HighLatitudeRule
import com.aljaroudi.muntathir.core.prayer.adhan.Madhab
import com.aljaroudi.muntathir.core.prayer.adhan.PrayerTimes
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

// Ports `PrayerTests`, `PrayerBoundaryTests` and `MeccaPrayerTests` (MuntathirTests.swift), plus the
// Adhan reference fixtures run directly against the Adhan port (iOS only checks Tehran).
class PrayerTest {
    @Serializable
    private class Fixture(
        val params: Params,
        val variance: Int? = null,
        val times: List<Map<String, String>>,
    ) {
        @Serializable
        class Params(
            val latitude: Double,
            val longitude: Double,
            val timezone: String,
            val method: String,
            val madhab: String,
            val highLatitudeRule: String,
        )
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val timeFormat = DateTimeFormatter.ofPattern("h:mm a", Locale.US)
    private val mecca = SavedLocation(21.4225, 39.8262, "Mecca", "SA", "Asia/Riyadh")
    private val riyadh = SavedLocation(24.7, 46.7, "Riyadh", "SA", "Asia/Riyadh")
    private val reference =
        listOf(
            PrayerName.Fajr,
            PrayerName.Sunrise,
            PrayerName.Dhuhr,
            PrayerName.Asr,
            PrayerName.Maghrib,
            PrayerName.Isha,
        )

    private fun fixture(name: String) = json.decodeFromString<Fixture>(Fixtures.text("$name.json"))

    private fun expected(
        row: Map<String, String>,
        prayer: PrayerName,
        zone: ZoneId,
    ): Instant {
        val day = LocalDate.parse(row.getValue("date"))
        return day.atTime(LocalTime.parse(row.getValue(prayer.id), timeFormat)).atZone(zone).toInstant()
    }

    private fun assertWithin(
        expected: Instant,
        actual: Instant,
        minutes: Int,
        message: String,
    ) = assertTrue(
        abs(Duration.between(expected, actual).seconds) <= minutes * 60L,
        "$message: expected $expected, was $actual",
    )

    @Test
    fun matchesTehranReferenceFixture() {
        val fixture = fixture("Tehran-Tehran")
        val location =
            SavedLocation(
                fixture.params.latitude,
                fixture.params.longitude,
                "Tehran-Tehran",
                "",
                fixture.params.timezone,
            )
        for (row in fixture.times) {
            val times = PrayerCalculator.times(LocalDate.parse(row.getValue("date")), location, PrayerMethod.Tehran)
            assertEquals(9, times.size)
            for (prayer in times.filter { it.name in reference }) {
                assertWithin(
                    expected(row, prayer.name, location.zone),
                    prayer.time,
                    maxOf(1, fixture.variance ?: 1),
                    "${row["date"]} ${prayer.name}",
                )
            }
        }
    }

    @Test
    fun adhanPortMatchesAllReferenceFixtures() {
        for (name in listOf("Tehran-Tehran", "Singapore-Singapore", "London-MoonsightingCommittee")) {
            val fixture = fixture(name)
            val p = fixture.params
            val zone = ZoneId.of(p.timezone)
            val coordinates = Coordinates(p.latitude, p.longitude)
            val parameters =
                CalculationMethod.valueOf(p.method).params.copy(
                    madhab = Madhab.valueOf(p.madhab),
                    highLatitudeRule = HighLatitudeRule.valueOf(p.highLatitudeRule),
                )
            for (row in fixture.times) {
                val times = PrayerTimes.calculate(coordinates, LocalDate.parse(row.getValue("date")), parameters)!!
                val actual = listOf(times.fajr, times.sunrise, times.dhuhr, times.asr, times.maghrib, times.isha)
                reference.zip(actual).forEach { (prayer, time) ->
                    assertWithin(
                        expected(row, prayer, zone),
                        time,
                        fixture.variance ?: 1,
                        "$name ${row["date"]} $prayer",
                    )
                }
            }
        }
    }

    @Test
    fun highLatitudeFailureIsHonest() {
        val polar = SavedLocation(89.0, 0.0, "Polar", "", "GMT")
        assertTrue(PrayerCalculator.times(LocalDate.of(2026, 6, 21), polar, PrayerMethod.Tehran).isEmpty())
    }

    @Test
    fun schedulesFuturePrayersOnly() {
        val now = LocalDate.of(2026, 10, 17).atStartOfDay(riyadh.zone).toInstant()
        val options = Preferences(enabledPrayers = setOf(PrayerName.Fajr, PrayerName.Maghrib))
        val plan = NotificationPlan.make(now, options, riyadh)
        assertTrue(plan.isNotEmpty() && plan.size <= 20)
        assertTrue(plan.all { it.time > now && it.name in options.enabledPrayers })
        assertEquals(plan.size, plan.map { it.id }.toSet().size)
        assertTrue(NotificationPlan.make(now, options.copy(enabledPrayers = emptySet()), riyadh).isEmpty())
    }

    @Test
    fun tehranMaghribIsAfterSunset() {
        for (day in listOf(LocalDate.of(2026, 1, 1), LocalDate.of(2026, 6, 1))) {
            val shia = PrayerCalculator.times(day, riyadh, PrayerMethod.Tehran).first { it.name == PrayerName.Maghrib }
            val sunset =
                PrayerCalculator.times(day, riyadh, PrayerMethod.UmmAlQura).first {
                    it.name ==
                        PrayerName.Maghrib
                }
            assertTrue(shia.time > sunset.time)
        }
    }

    @Test
    fun ramadanIshaUsesBaselineCalendar() {
        // 2026-03-01 is in Ramadan 1447; corrections never change prayer math.
        val times = PrayerCalculator.times(LocalDate.of(2026, 3, 1), riyadh, PrayerMethod.UmmAlQura)
        val maghrib = times.first { it.name == PrayerName.Maghrib }
        val isha = times.first { it.name == PrayerName.Isha }
        assertEquals(Duration.ofMinutes(120), Duration.between(maghrib.time, isha.time))
    }

    @Test
    fun todayInMeccaHasEveryPrayer() {
        for ((method, minute) in listOf(PrayerMethod.Jafari to 9, PrayerMethod.Tehran to 11)) {
            val prayers = PrayerCalculator.times(LocalDate.of(2026, 10, 17), mecca, method)
            assertEquals(PrayerName.entries, prayers.map { it.name })
            val maghrib = prayers.first { it.name == PrayerName.Maghrib }.time.atZone(mecca.zone)
            assertEquals(18, maghrib.hour)
            assertEquals(minute, maghrib.minute, "$method")
        }
    }

    @Test
    fun gpsWithoutPlaceNameStillCalculates() {
        val unnamed = mecca.copy(name = "", countryCode = "")
        assertEquals(9, PrayerCalculator.times(LocalDate.of(2026, 10, 17), unnamed, PrayerMethod.Tehran).size)
    }

    @Test
    fun midnightUsesSunsetAndNextFajr() {
        for (method in PrayerMethod.entries) {
            val today = PrayerCalculator.times(LocalDate.of(2026, 10, 18), mecca, method)
            val next = PrayerCalculator.times(LocalDate.of(2026, 10, 19), mecca, method)
            val sunset = today.first { it.name == PrayerName.Sunset }.time
            val midnight = today.first { it.name == PrayerName.Midnight }.time
            val fajr = next.first { it.name == PrayerName.Fajr }.time
            val expected = sunset.plus(Duration.between(sunset, fajr).dividedBy(2))
            assertTrue(abs(Duration.between(expected, midnight).seconds) <= 30)
            if (method !=
                PrayerMethod.UmmAlQura
            ) {
                assertTrue(sunset < today.first { it.name == PrayerName.Maghrib }.time)
            }
        }
        assertTrue(PrayerName.Sunset !in PrayerName.notifiable && PrayerName.Midnight !in PrayerName.notifiable)
    }

    @Test
    fun coreTimesCannotBeHidden() {
        val hidden = PrayerName.entries.toSet()
        assertEquals(
            listOf(PrayerName.Fajr, PrayerName.Dhuhr, PrayerName.Maghrib),
            PrayerName.entries.filter {
                it.isVisible(hidden)
            },
        )
        val widget = WidgetPrayerSettings(mecca, PrayerMethod.Tehran, hidden)
        assertEquals(
            listOf(
                PrayerName.Fajr,
                PrayerName.Dhuhr,
                PrayerName.Maghrib,
            ),
            widget.prayers(LocalDate.of(2026, 10, 18)).map {
                it.name
            },
        )
    }

    @Test
    fun qiblaIsTheInitialGreatCircleBearingToTheKaaba() {
        val kaaba = Math.toRadians(21.4225241) to Math.toRadians(39.8261818)
        for ((latitude, longitude) in listOf(
            40.7128 to -74.0059,
            24.7 to 46.7,
            37.7749 to -122.4194,
            -36.8485 to 174.7633,
            35.6895 to 139.6917,
        )) {
            val phi = Math.toRadians(latitude)
            val delta = kaaba.second - Math.toRadians(longitude)
            val y = sin(delta) * cos(kaaba.first)
            val x = cos(phi) * sin(kaaba.first) - sin(phi) * cos(kaaba.first) * cos(delta)
            val bearing = (Math.toDegrees(atan2(y, x)) + 360) % 360
            assertEquals(bearing, PrayerCalculator.qibla(SavedLocation(latitude, longitude, "", "", "UTC")), 1e-9)
        }
        assertEquals(58.48, PrayerCalculator.qibla(SavedLocation(40.7128, -74.0059, "New York", "US", "UTC")), 0.01)
    }
}
