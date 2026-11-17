/*
 * Kotlin port of Adhan Swift 1.5.0 (https://github.com/batoulapps/adhan-swift), the library the iOS app
 * uses, so both platforms compute identical times. adhan2 (the Kotlin port) lacks Maghrib angles, the
 * Tehran preset and failable calculations.
 *
 * Copyright © 2018 Batoul Apps. All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */
package com.aljaroudi.muntathir.core.prayer.adhan

import com.aljaroudi.muntathir.core.roundedAwayFromZero
import java.time.Instant
import java.time.LocalDate
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.atan
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.tan

internal data class Coordinates(
    val latitude: Double,
    val longitude: Double,
)

internal enum class Madhab(
    val shadowLength: Double,
) {
    Shafi(1.0),
    Hanafi(2.0),
}

internal enum class HighLatitudeRule {
    MiddleOfTheNight,
    SeventhOfTheNight,
    TwilightAngle,
    ;

    companion object {
        fun recommended(coordinates: Coordinates) =
            if (coordinates.latitude >
                48
            ) {
                SeventhOfTheNight
            } else {
                MiddleOfTheNight
            }
    }
}

internal enum class Rounding { Nearest, Up, None }

internal enum class Shafaq { General, Ahmer, Abyad }

/** Minutes added to each time. */
internal data class PrayerAdjustments(
    val fajr: Int = 0,
    val sunrise: Int = 0,
    val dhuhr: Int = 0,
    val asr: Int = 0,
    val maghrib: Int = 0,
    val isha: Int = 0,
)

internal data class CalculationParameters(
    val method: CalculationMethod = CalculationMethod.Other,
    val fajrAngle: Double,
    val maghribAngle: Double? = null,
    val ishaAngle: Double,
    /** Minutes after Maghrib; used instead of [ishaAngle] when positive. */
    val ishaInterval: Int = 0,
    val madhab: Madhab = Madhab.Shafi,
    val highLatitudeRule: HighLatitudeRule? = null,
    val adjustments: PrayerAdjustments = PrayerAdjustments(),
    val rounding: Rounding = Rounding.Nearest,
    val shafaq: Shafaq = Shafaq.General,
    val methodAdjustments: PrayerAdjustments = PrayerAdjustments(),
) {
    /** Fractions of the night bounding Fajr and Isha. */
    fun nightPortions(coordinates: Coordinates): Pair<Double, Double> =
        when (highLatitudeRule ?: HighLatitudeRule.recommended(coordinates)) {
            HighLatitudeRule.MiddleOfTheNight -> 1.0 / 2 to 1.0 / 2
            HighLatitudeRule.SeventhOfTheNight -> 1.0 / 7 to 1.0 / 7
            HighLatitudeRule.TwilightAngle -> fajrAngle / 60 to ishaAngle / 60
        }
}

internal enum class CalculationMethod {
    MuslimWorldLeague,
    Egyptian,
    Karachi,
    UmmAlQura,
    Dubai,
    MoonsightingCommittee,
    NorthAmerica,
    Kuwait,
    Qatar,
    Singapore,
    Tehran,
    Turkey,
    Other,
    ;

    val params: CalculationParameters
        get() =
            when (this) {
                MuslimWorldLeague -> angles(18.0, 17.0, PrayerAdjustments(dhuhr = 1))
                Egyptian -> angles(19.5, 17.5, PrayerAdjustments(dhuhr = 1))
                Karachi -> angles(18.0, 18.0, PrayerAdjustments(dhuhr = 1))
                UmmAlQura -> CalculationParameters(this, fajrAngle = 18.5, ishaAngle = 0.0, ishaInterval = 90)
                Dubai -> angles(18.2, 18.2, PrayerAdjustments(sunrise = -3, dhuhr = 3, asr = 3, maghrib = 3))
                MoonsightingCommittee -> angles(18.0, 18.0, PrayerAdjustments(dhuhr = 5, maghrib = 3))
                NorthAmerica -> angles(15.0, 15.0, PrayerAdjustments(dhuhr = 1))
                Kuwait -> angles(18.0, 17.5)
                Qatar -> CalculationParameters(this, fajrAngle = 18.0, ishaAngle = 0.0, ishaInterval = 90)
                Singapore -> angles(20.0, 18.0, PrayerAdjustments(dhuhr = 1)).copy(rounding = Rounding.Up)
                Tehran -> CalculationParameters(this, fajrAngle = 17.7, maghribAngle = 4.5, ishaAngle = 14.0)
                Turkey -> angles(18.0, 17.0, PrayerAdjustments(sunrise = -7, dhuhr = 5, asr = 4, maghrib = 7))
                Other -> angles(0.0, 0.0)
            }

    private fun angles(
        fajr: Double,
        isha: Double,
        adjustments: PrayerAdjustments = PrayerAdjustments(),
    ) = CalculationParameters(this, fajrAngle = fajr, ishaAngle = isha, methodAdjustments = adjustments)
}

/** Times are in seconds since the epoch, like Swift `Date`, until rounded into [Instant]s. */
internal class PrayerTimes private constructor(
    val fajr: Instant,
    val sunrise: Instant,
    val dhuhr: Instant,
    val asr: Instant,
    val maghrib: Instant,
    val isha: Instant,
) {
    companion object {
        /** `null` when the sun never reaches the required angles, as Swift's failable initializer. */
        fun calculate(
            coordinates: Coordinates,
            date: LocalDate,
            parameters: CalculationParameters,
        ): PrayerTimes? {
            val solarTime = SolarTime.of(date, coordinates) ?: return null
            val tomorrowSolarTime = SolarTime.of(date.plusDays(1), coordinates) ?: return null
            val sunrise = solarTime.sunrise
            val sunset = solarTime.sunset
            val dhuhr = solarTime.transit
            val asr = solarTime.afternoon(parameters.madhab.shadowLength)
            val night = tomorrowSolarTime.sunrise - sunset
            val (fajrPortion, ishaPortion) = parameters.nightPortions(coordinates)
            val moonsighting = parameters.method == CalculationMethod.MoonsightingCommittee
            val dayOfYear = date.dayOfYear

            var fajr = solarTime.timeForSolarAngle(-parameters.fajrAngle, afterTransit = false)
            // Special case for moonsighting committee above latitude 55.
            if (moonsighting && coordinates.latitude >= 55) fajr = sunrise - night / 7
            val safeFajr =
                if (moonsighting) {
                    Astronomical.seasonAdjustedMorningTwilight(coordinates.latitude, dayOfYear, date.year, sunrise)
                } else {
                    sunrise - fajrPortion * night
                }
            if (fajr == null || fajr < safeFajr) fajr = safeFajr

            val isha =
                if (parameters.ishaInterval > 0) {
                    sunset + parameters.ishaInterval * 60.0
                } else {
                    var angled = solarTime.timeForSolarAngle(-parameters.ishaAngle, afterTransit = true)
                    if (moonsighting && coordinates.latitude >= 55) angled = sunset + night / 7
                    val safeIsha =
                        if (moonsighting) {
                            Astronomical.seasonAdjustedEveningTwilight(
                                coordinates.latitude,
                                dayOfYear,
                                date.year,
                                sunset,
                                parameters.shafaq,
                            )
                        } else {
                            sunset + ishaPortion * night
                        }
                    if (angled == null || angled > safeIsha) safeIsha else angled
                }

            var maghrib = sunset
            parameters.maghribAngle?.let { angle ->
                val candidate = solarTime.timeForSolarAngle(-angle, afterTransit = true)
                // Maghrib is considered safe if it falls between sunset and isha.
                if (candidate != null && sunset < candidate && isha > candidate) maghrib = candidate
            }
            if (asr == null) return null

            val custom = parameters.adjustments
            val preset = parameters.methodAdjustments

            fun final(
                time: Double,
                minutes: Int,
            ) = rounded(time + minutes * 60.0, parameters.rounding)
            return PrayerTimes(
                fajr = final(fajr, custom.fajr + preset.fajr),
                sunrise = final(sunrise, custom.sunrise + preset.sunrise),
                dhuhr = final(dhuhr, custom.dhuhr + preset.dhuhr),
                asr = final(asr, custom.asr + preset.asr),
                maghrib = final(maghrib, custom.maghrib + preset.maghrib),
                isha = final(isha, custom.isha + preset.isha),
            )
        }

        /** Swift `Date.roundedMinute`: whole seconds (fractions dropped) rounded to a minute. */
        private fun rounded(
            seconds: Double,
            rounding: Rounding,
        ): Instant {
            val whole = floor(seconds).toLong()
            val second = Math.floorMod(whole, 60L)
            val minute = whole - second
            return Instant.ofEpochSecond(
                when (rounding) {
                    Rounding.Nearest -> minute + if ((second / 60.0).roundedAwayFromZero() > 0) 60 else 0
                    Rounding.Up -> minute + if (ceil(second / 60.0) > 0) 60 else 0
                    Rounding.None -> whole
                },
            )
        }
    }
}

internal object Qibla {
    private val makkah = Coordinates(21.4225241, 39.8261818)

    /** Degrees from true north. Equation from "Spherical Trigonometry For the use of colleges and schools" page 50. */
    fun direction(coordinates: Coordinates): Double {
        val longitudeDelta = radians(makkah.longitude) - radians(coordinates.longitude)
        val term1 = sin(longitudeDelta)
        val term2 = cos(radians(coordinates.latitude)) * tan(radians(makkah.latitude))
        val term3 = sin(radians(coordinates.latitude)) * cos(longitudeDelta)
        return unwound(degrees(atan2(term1, term2 - term3)))
    }
}

internal class SolarTime private constructor(
    private val date: LocalDate,
    private val observer: Coordinates,
    private val solar: SolarCoordinates,
    private val previous: SolarCoordinates,
    private val next: SolarCoordinates,
    private val approximateTransit: Double,
    val transit: Double,
    val sunrise: Double,
    val sunset: Double,
) {
    fun timeForSolarAngle(
        angle: Double,
        afterTransit: Boolean,
    ): Double? =
        settingHour(date, correctedHourAngle(observer, solar, previous, next, approximateTransit, angle, afterTransit))

    fun afternoon(shadowLength: Double): Double? {
        val tangent = abs(observer.latitude - solar.declination)
        val inverse = shadowLength + tan(radians(tangent))
        return timeForSolarAngle(degrees(atan(1.0 / inverse)), afterTransit = true)
    }

    companion object {
        private const val SOLAR_ALTITUDE = -50.0 / 60.0

        fun of(
            date: LocalDate,
            coordinates: Coordinates,
        ): SolarTime? {
            // Calculations occur at 0h0m UTC.
            val julianDay = Astronomical.julianDay(date.year, date.monthValue, date.dayOfMonth)
            val previous = SolarCoordinates(julianDay - 1)
            val solar = SolarCoordinates(julianDay)
            val next = SolarCoordinates(julianDay + 1)
            val m0 =
                Astronomical.approximateTransit(
                    coordinates.longitude,
                    solar.apparentSiderealTime,
                    solar.rightAscension,
                )
            val transitHours =
                Astronomical.correctedTransit(
                    m0,
                    coordinates.longitude,
                    solar.apparentSiderealTime,
                    solar.rightAscension,
                    previous.rightAscension,
                    next.rightAscension,
                )
            val transit = settingHour(date, transitHours) ?: return null
            val sunrise =
                settingHour(date, correctedHourAngle(coordinates, solar, previous, next, m0, SOLAR_ALTITUDE, false))
                    ?: return null
            val sunset =
                settingHour(date, correctedHourAngle(coordinates, solar, previous, next, m0, SOLAR_ALTITUDE, true))
                    ?: return null
            return SolarTime(date, coordinates, solar, previous, next, m0, transit, sunrise, sunset)
        }

        private fun correctedHourAngle(
            coordinates: Coordinates,
            solar: SolarCoordinates,
            previous: SolarCoordinates,
            next: SolarCoordinates,
            m0: Double,
            angle: Double,
            afterTransit: Boolean,
        ) = Astronomical.correctedHourAngle(
            m0,
            angle,
            coordinates,
            afterTransit,
            solar.apparentSiderealTime,
            solar.rightAscension,
            previous.rightAscension,
            next.rightAscension,
            solar.declination,
            previous.declination,
            next.declination,
        )

        /** Swift `DateComponents.settingHour` + `Calendar.date(from:)` in UTC, as epoch seconds. */
        private fun settingHour(
            date: LocalDate,
            value: Double,
        ): Double? {
            if (!value.isFinite() || value == 0.0 || abs(value) < java.lang.Double.MIN_NORMAL) return null
            val hours = floor(value)
            val minutes = floor((value - hours) * 60)
            val seconds = floor((value - (hours + minutes / 60)) * 60 * 60)
            return date.toEpochDay() * 86_400.0 + hours * 3600 + minutes * 60 + seconds
        }
    }
}

/** Angles are plain degrees. */
internal class SolarCoordinates(
    julianDay: Double,
) {
    /** The angle between the rays of the Sun and the plane of the Earth's equator. */
    val declination: Double

    /** Angular distance on the celestial equator from the vernal equinox to the hour circle. */
    val rightAscension: Double

    /** The hour angle of the vernal equinox. */
    val apparentSiderealTime: Double

    init {
        val t = Astronomical.julianCentury(julianDay)
        val l0 = Astronomical.meanSolarLongitude(t)
        val lp = Astronomical.meanLunarLongitude(t)
        val omega = Astronomical.ascendingLunarNodeLongitude(t)
        val lambda = radians(Astronomical.apparentSolarLongitude(t, l0))
        val theta0 = Astronomical.meanSiderealTime(t)
        val deltaPsi = Astronomical.nutationInLongitude(l0, lp, omega)
        val deltaEpsilon = Astronomical.nutationInObliquity(l0, lp, omega)
        val epsilon0 = Astronomical.meanObliquityOfTheEcliptic(t)
        val epsilonApparent = radians(Astronomical.apparentObliquityOfTheEcliptic(t, epsilon0))
        declination = degrees(asin(sin(epsilonApparent) * sin(lambda)))
        rightAscension = unwound(degrees(atan2(cos(epsilonApparent) * sin(lambda), cos(lambda))))
        apparentSiderealTime = theta0 + (((deltaPsi * 3600) * cos(radians(epsilon0 + deltaEpsilon))) / 3600)
    }
}

/** Equations from Jean Meeus, "Astronomical Algorithms". */
internal object Astronomical {
    fun meanSolarLongitude(t: Double) = unwound(280.4664567 + 36000.76983 * t + 0.0003032 * t.pow(2))

    fun meanLunarLongitude(t: Double) = unwound(218.3165 + 481267.8813 * t)

    fun ascendingLunarNodeLongitude(t: Double) =
        unwound(125.04452 - 1934.136261 * t + 0.0020708 * t.pow(2) + t.pow(3) / 450000)

    fun meanSolarAnomaly(t: Double) = unwound(357.52911 + 35999.05029 * t - 0.0001537 * t.pow(2))

    fun solarEquationOfTheCenter(
        t: Double,
        meanAnomaly: Double,
    ): Double {
        val m = radians(meanAnomaly)
        val term1 = (1.914602 - (0.004817 * t) - (0.000014 * t.pow(2))) * sin(m)
        val term2 = (0.019993 - (0.000101 * t)) * sin(2 * m)
        val term3 = 0.000289 * sin(3 * m)
        return term1 + term2 + term3
    }

    fun apparentSolarLongitude(
        t: Double,
        meanLongitude: Double,
    ): Double {
        val longitude = meanLongitude + solarEquationOfTheCenter(t, meanSolarAnomaly(t))
        val omega = 125.04 - (1934.136 * t)
        return unwound(longitude - 0.00569 - (0.00478 * sin(radians(omega))))
    }

    fun meanObliquityOfTheEcliptic(t: Double) =
        23.439291 - 0.013004167 * t - 0.0000001639 * t.pow(2) + 0.0000005036 * t.pow(3)

    fun apparentObliquityOfTheEcliptic(
        t: Double,
        meanObliquity: Double,
    ): Double {
        val o = 125.04 - (1934.136 * t)
        return meanObliquity + (0.00256 * cos(radians(o)))
    }

    fun meanSiderealTime(t: Double): Double {
        val jd = (t * 36525) + 2451545.0
        return unwound(280.46061837 + 360.98564736629 * (jd - 2451545) + 0.000387933 * t.pow(2) - t.pow(3) / 38710000)
    }

    fun nutationInLongitude(
        solarLongitude: Double,
        lunarLongitude: Double,
        ascendingNode: Double,
    ): Double {
        val term1 = (-17.2 / 3600) * sin(radians(ascendingNode))
        val term2 = (1.32 / 3600) * sin(2 * radians(solarLongitude))
        val term3 = (0.23 / 3600) * sin(2 * radians(lunarLongitude))
        val term4 = (0.21 / 3600) * sin(2 * radians(ascendingNode))
        return term1 - term2 - term3 + term4
    }

    fun nutationInObliquity(
        solarLongitude: Double,
        lunarLongitude: Double,
        ascendingNode: Double,
    ): Double {
        val term1 = (9.2 / 3600) * cos(radians(ascendingNode))
        val term2 = (0.57 / 3600) * cos(2 * radians(solarLongitude))
        val term3 = (0.10 / 3600) * cos(2 * radians(lunarLongitude))
        val term4 = (0.09 / 3600) * cos(2 * radians(ascendingNode))
        return term1 + term2 + term3 - term4
    }

    fun altitudeOfCelestialBody(
        observerLatitude: Double,
        declination: Double,
        localHourAngle: Double,
    ): Double {
        val term1 = sin(radians(observerLatitude)) * sin(radians(declination))
        val term2 = cos(radians(observerLatitude)) * cos(radians(declination)) * cos(radians(localHourAngle))
        return degrees(asin(term1 + term2))
    }

    fun approximateTransit(
        longitude: Double,
        siderealTime: Double,
        rightAscension: Double,
    ): Double {
        val lw = longitude * -1
        val m0 = normalized((rightAscension + lw - siderealTime) / 360, 1.0)
        // Near the International Date Line, normalization can pick the wrong calendar date; compare with a
        // longitude-based transit and shift by one cycle when they differ by more than half a day.
        val expected = normalized((12.0 - longitude / 15.0) / 24.0, 1.0)
        return when {
            m0 - expected > 0.5 -> m0 - 1.0
            expected - m0 > 0.5 -> m0 + 1.0
            else -> m0
        }
    }

    fun correctedTransit(
        m0: Double,
        longitude: Double,
        siderealTime: Double,
        rightAscension: Double,
        previousRightAscension: Double,
        nextRightAscension: Double,
    ): Double {
        val lw = longitude * -1
        val theta = unwound(siderealTime + (360.985647 * m0))
        val alpha = unwound(interpolateAngles(rightAscension, previousRightAscension, nextRightAscension, m0))
        val h = quadrantShifted(theta - lw - alpha)
        val deltaM = h / -360
        return (m0 + deltaM) * 24
    }

    fun correctedHourAngle(
        m0: Double,
        h0: Double,
        coordinates: Coordinates,
        afterTransit: Boolean,
        siderealTime: Double,
        rightAscension: Double,
        previousRightAscension: Double,
        nextRightAscension: Double,
        declination: Double,
        previousDeclination: Double,
        nextDeclination: Double,
    ): Double {
        val lw = coordinates.longitude * -1
        val latitude = radians(coordinates.latitude)
        val term1 = sin(radians(h0)) - (sin(latitude) * sin(radians(declination)))
        val term2 = cos(latitude) * cos(radians(declination))
        val hourAngle = degrees(acos(term1 / term2))
        val m = if (afterTransit) m0 + (hourAngle / 360) else m0 - (hourAngle / 360)
        val theta = unwound(siderealTime + (360.985647 * m))
        val alpha = unwound(interpolateAngles(rightAscension, previousRightAscension, nextRightAscension, m))
        val delta = interpolate(declination, previousDeclination, nextDeclination, m)
        val h = theta - lw - alpha
        val altitude = altitudeOfCelestialBody(coordinates.latitude, delta, h)
        val term3 = altitude - h0
        val term4 = 360 * cos(radians(delta)) * cos(latitude) * sin(radians(h))
        val deltaM = term3 / term4
        return (m + deltaM) * 24
    }

    fun interpolate(
        value: Double,
        previous: Double,
        next: Double,
        factor: Double,
    ): Double {
        val a = value - previous
        val b = next - value
        val c = b - a
        return value + ((factor / 2) * (a + b + (factor * c)))
    }

    fun interpolateAngles(
        value: Double,
        previous: Double,
        next: Double,
        factor: Double,
    ): Double {
        val a = unwound(value - previous)
        val b = unwound(next - value)
        val c = b - a
        return value + ((factor / 2) * (a + b + (factor * c)))
    }

    /** Truncating integer casts are intentional, as in the reference. */
    fun julianDay(
        year: Int,
        month: Int,
        day: Int,
        hours: Double = 0.0,
    ): Double {
        val y = if (month > 2) year else year - 1
        val m = if (month > 2) month else month + 12
        val d = day + (hours / 24)
        val a = y / 100
        val b = 2 - a + (a / 4)
        val i0 = (365.25 * (y + 4716)).toInt()
        val i1 = (30.6001 * (m + 1)).toInt()
        return i0 + i1 + d + b - 1524.5
    }

    fun julianCentury(julianDay: Double) = (julianDay - 2451545.0) / 36525

    fun isLeapYear(year: Int) = year % 4 == 0 && !(year % 100 == 0 && year % 400 != 0)

    /** Moonsighting Committee twilight from observational data. */
    fun seasonAdjustedMorningTwilight(
        latitude: Double,
        day: Int,
        year: Int,
        sunrise: Double,
    ): Double {
        val a = 75 + ((28.65 / 55.0) * abs(latitude))
        val b = 75 + ((19.44 / 55.0) * abs(latitude))
        val c = 75 + ((32.74 / 55.0) * abs(latitude))
        val d = 75 + ((48.10 / 55.0) * abs(latitude))
        val adjustment = seasonal(daysSinceSolstice(day, year, latitude).toDouble(), a, b, c, d)
        return sunrise + (adjustment * -60.0).roundedAwayFromZero()
    }

    fun seasonAdjustedEveningTwilight(
        latitude: Double,
        day: Int,
        year: Int,
        sunset: Double,
        shafaq: Shafaq,
    ): Double {
        val l = abs(latitude)
        val (a, b, c, d) =
            when (shafaq) {
                Shafaq.General -> {
                    listOf(
                        75 + ((25.60 / 55.0) * l),
                        75 + ((2.050 / 55.0) * l),
                        75 - ((9.210 / 55.0) * l),
                        75 + ((6.140 / 55.0) * l),
                    )
                }

                Shafaq.Ahmer -> {
                    listOf(
                        62 + ((17.40 / 55.0) * l),
                        62 - ((7.160 / 55.0) * l),
                        62 + ((5.120 / 55.0) * l),
                        62 + ((19.44 / 55.0) * l),
                    )
                }

                Shafaq.Abyad -> {
                    listOf(
                        75 + ((25.60 / 55.0) * l),
                        75 + ((7.160 / 55.0) * l),
                        75 + ((36.84 / 55.0) * l),
                        75 + ((81.84 / 55.0) * l),
                    )
                }
            }
        val adjustment = seasonal(daysSinceSolstice(day, year, latitude).toDouble(), a, b, c, d)
        return sunset + (adjustment * 60.0).roundedAwayFromZero()
    }

    private fun seasonal(
        dyy: Double,
        a: Double,
        b: Double,
        c: Double,
        d: Double,
    ): Double =
        when {
            dyy < 91 -> a + (b - a) / 91.0 * dyy
            dyy < 137 -> b + (c - b) / 46.0 * (dyy - 91)
            dyy < 183 -> c + (d - c) / 46.0 * (dyy - 137)
            dyy < 229 -> d + (c - d) / 46.0 * (dyy - 183)
            dyy < 275 -> c + (b - c) / 46.0 * (dyy - 229)
            else -> b + (a - b) / 91.0 * (dyy - 275)
        }

    fun daysSinceSolstice(
        dayOfYear: Int,
        year: Int,
        latitude: Double,
    ): Int {
        val southernOffset = if (isLeapYear(year)) 173 else 172
        val daysInYear = if (isLeapYear(year)) 366 else 365
        return if (latitude >= 0) {
            (dayOfYear + 10).let { if (it >= daysInYear) it - daysInYear else it }
        } else {
            (dayOfYear - southernOffset).let { if (it < 0) it + daysInYear else it }
        }
    }
}

private fun radians(degrees: Double) = (degrees * PI) / 180.0

private fun degrees(radians: Double) = (radians * 180.0) / PI

private fun normalized(
    value: Double,
    max: Double,
) = value - (max * floor(value / max))

private fun unwound(degrees: Double) = normalized(degrees, 360.0)

private fun quadrantShifted(degrees: Double): Double {
    if (degrees >= -180 && degrees <= 180) return degrees
    return degrees - (360 * (degrees / 360).roundedAwayFromZero())
}
