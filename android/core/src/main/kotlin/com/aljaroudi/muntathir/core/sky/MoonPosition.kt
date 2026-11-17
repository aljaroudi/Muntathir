package com.aljaroudi.muntathir.core.sky

import java.time.Instant
import kotlin.math.PI
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * Approximate lunar ephemeris for the decorative sky.
 * Orbital elements and perturbations: https://www.stjarnhimlen.se/comp/ppcomp.html
 * Angles are degrees; elevation is topocentric and geometric (no refraction).
 */
data class MoonPosition(
    val elevation: Double,
    val azimuth: Double,
    val illuminatedFraction: Double,
    val isWaxing: Boolean,
    /** Schematic rise → transit → set progress using the current declination, not a rise/set forecast. */
    val visibleProgress: Double?,
) {
    companion object {
        private const val RADIANS = PI / 180

        fun calculate(
            instant: Instant,
            latitude: Double,
            longitude: Double,
        ): MoonPosition? {
            if (!latitude.isFinite() || !longitude.isFinite() || latitude !in -90.0..90.0 ||
                longitude !in -180.0..180.0
            ) {
                return null
            }
            val days = instant.unixSeconds / 86400 + 2_440_587.5 - 2_451_543.5
            val solarPerigee = angle(282.9404 + 4.70935e-5 * days)
            val solarMean = angle(356.0470 + 0.9856002585 * days)
            val solarEccentricity = 0.016709 - 1.151e-9 * days
            val solarE = eccentricAnomaly(solarMean, solarEccentricity)
            val solarX = cos(solarE) - solarEccentricity
            val solarY = sqrt(1 - solarEccentricity * solarEccentricity) * sin(solarE)
            val solarLongitude = atan2(solarY, solarX) + solarPerigee

            val node = angle(125.1228 - 0.0529538083 * days)
            val inclination = angle(5.1454)
            val perigee = angle(318.0634 + 0.1643573223 * days)
            val mean = angle(115.3654 + 13.0649929509 * days)
            val eccentricity = 0.0549
            val eccentric = eccentricAnomaly(mean, eccentricity)
            val orbitalX = 60.2666 * (cos(eccentric) - eccentricity)
            val orbitalY = 60.2666 * sqrt(1 - eccentricity * eccentricity) * sin(eccentric)
            val orbitalAngle = atan2(orbitalY, orbitalX) + perigee
            var distance = hypot(orbitalX, orbitalY)
            val x = cos(node) * cos(orbitalAngle) - sin(node) * sin(orbitalAngle) * cos(inclination)
            val y = sin(node) * cos(orbitalAngle) + cos(node) * sin(orbitalAngle) * cos(inclination)
            val z = sin(orbitalAngle) * sin(inclination)
            var lunarLongitude = atan2(y, x)
            var lunarLatitude = atan2(z, hypot(x, y))
            val elongation = mean + perigee + node - solarMean - solarPerigee
            val latitudeArgument = mean + perigee
            // Principal solar perturbations of the lunar orbit, in degrees and Earth radii.
            val longitudeTerms =
                listOf(
                    -1.274 to mean - 2 * elongation,
                    0.658 to 2 * elongation,
                    -0.186 to solarMean,
                    -0.059 to 2 * mean - 2 * elongation,
                    -0.057 to mean - 2 * elongation + solarMean,
                    0.053 to mean + 2 * elongation,
                    0.046 to 2 * elongation - solarMean,
                    0.041 to mean - solarMean,
                    -0.035 to elongation,
                    -0.031 to mean + solarMean,
                    -0.015 to 2 * latitudeArgument - 2 * elongation,
                    0.011 to mean - 4 * elongation,
                )
            lunarLongitude += longitudeTerms.fold(0.0) { sum, (k, a) -> sum + k * sin(a) } * RADIANS
            val latitudeTerms =
                listOf(
                    -0.173 to latitudeArgument - 2 * elongation,
                    -0.055 to mean - latitudeArgument - 2 * elongation,
                    -0.046 to mean + latitudeArgument - 2 * elongation,
                    0.033 to latitudeArgument + 2 * elongation,
                    0.017 to 2 * mean + latitudeArgument,
                )
            lunarLatitude += latitudeTerms.fold(0.0) { sum, (k, a) -> sum + k * sin(a) } * RADIANS
            distance -= 0.58 * cos(mean - 2 * elongation) + 0.46 * cos(2 * elongation)

            val obliquity = angle(23.4393 - 3.563e-7 * days)
            val eclipticX = distance * cos(lunarLongitude) * cos(lunarLatitude)
            val eclipticY = distance * sin(lunarLongitude) * cos(lunarLatitude)
            val eclipticZ = distance * sin(lunarLatitude)
            val sidereal = angle(280.46061837 + 360.98564736629 * (days - 1.5) + longitude)
            val phi = latitude * RADIANS
            val geocentricLatitude = phi - angle(0.1924) * sin(2 * phi)
            val observerRadius = 0.99833 + 0.00167 * cos(2 * phi)
            // Subtract the observer's position before converting to the local horizon (lunar parallax).
            val equatorialX = eclipticX - observerRadius * cos(geocentricLatitude) * cos(sidereal)
            val equatorialY =
                eclipticY * cos(obliquity) - eclipticZ * sin(obliquity) -
                    observerRadius * cos(geocentricLatitude) * sin(sidereal)
            val equatorialZ =
                eclipticY * sin(obliquity) + eclipticZ * cos(obliquity) - observerRadius * sin(geocentricLatitude)
            val declination = atan2(equatorialZ, hypot(equatorialX, equatorialY))
            val rightAscension = atan2(equatorialY, equatorialX)
            val hourAngle = atan2(sin(sidereal - rightAscension), cos(sidereal - rightAscension))
            val base = sin(phi) * sin(declination)
            val amplitude = cos(phi) * cos(declination)
            val elevation = asin((base + amplitude * cos(hourAngle)).coerceIn(-1.0, 1.0)) / RADIANS
            val azimuth = atan2(sin(hourAngle), cos(hourAngle) * sin(phi) - tan(declination) * cos(phi)) / RADIANS + 180
            val progress =
                when {
                    elevation < 0 -> {
                        null
                    }

                    base - amplitude >= 0 -> {
                        (hourAngle + PI) / (2 * PI)
                    }

                    else -> {
                        val settingAngle = acos((-base / amplitude).coerceIn(-1.0, 1.0))
                        if (settingAngle >
                            0
                        ) {
                            ((hourAngle + settingAngle) / (2 * settingAngle)).coerceIn(0.0, 1.0)
                        } else {
                            0.5
                        }
                    }
                }
            val separation = acos((cos(lunarLatitude) * cos(lunarLongitude - solarLongitude)).coerceIn(-1.0, 1.0))
            val solarDistance = hypot(solarX, solarY) * 23454.8 // AU in Earth equatorial radii
            val phaseAngle = atan2(solarDistance * sin(separation), distance - solarDistance * cos(separation))
            return MoonPosition(
                elevation = elevation,
                azimuth = azimuth,
                illuminatedFraction = (1 + cos(phaseAngle)) / 2,
                isWaxing = sin(lunarLongitude - solarLongitude) >= 0,
                visibleProgress = progress,
            )
        }

        /** Keeps the sign of negative inputs, like Swift `truncatingRemainder`. */
        private fun angle(degrees: Double) = (degrees % 360) * RADIANS

        private fun eccentricAnomaly(
            mean: Double,
            eccentricity: Double,
        ): Double {
            var result = mean
            repeat(5) { result -= (result - eccentricity * sin(result) - mean) / (1 - eccentricity * cos(result)) }
            return result
        }
    }
}
