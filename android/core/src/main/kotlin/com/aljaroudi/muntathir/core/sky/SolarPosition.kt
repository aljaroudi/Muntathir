package com.aljaroudi.muntathir.core.sky

import java.time.Instant
import kotlin.math.PI
import kotlin.math.acos
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.tan

internal val Instant.unixSeconds: Double get() = epochSecond + nano / 1e9

data class SolarPosition(
    /** Degrees above the astronomical horizon, before atmospheric refraction. */
    val elevation: Double,
    /** Degrees above the horizon, including NOAA's standard atmospheric refraction. */
    val apparentElevation: Double,
    /** Degrees clockwise from true north. */
    val azimuth: Double,
    val isRising: Boolean,
    /** Sunrise = 0, solar noon = 0.5, sunset = 1; `null` while the sun is below the horizon. */
    val daylightProgress: Double?,
    val arc: Arc?,
) {
    /** The day's elevation curve, so the drawn path passes through the sun. */
    data class Arc(
        val base: Double,
        val amplitude: Double,
        val halfDayAngle: Double,
    ) {
        fun elevation(progress: Double): Double {
            val hourAngle = (progress.coerceIn(0.0, 1.0) * 2 - 1) * halfDayAngle
            return asin((base + amplitude * cos(hourAngle)).coerceIn(-1.0, 1.0)) * 180 / PI
        }
    }

    companion object {
        /** NOAA/Meeus: https://gml.noaa.gov/grad/solcalc/calcdetails.html. `null` for invalid input. */
        fun calculate(
            instant: Instant,
            latitude: Double,
            longitude: Double,
        ): SolarPosition? {
            if (!latitude.isFinite() || !longitude.isFinite() || latitude !in -90.0..90.0 ||
                longitude !in -180.0..180.0
            ) {
                return null
            }
            val seconds = instant.unixSeconds
            val t = (seconds / 86400 + 2_440_587.5 - 2_451_545) / 36525
            val meanLongitude = normalized(280.46646 + t * (36000.76983 + t * 0.0003032))
            val anomaly = radians(357.52911 + t * (35999.05029 - 0.0001537 * t))
            val eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
            val center =
                sin(anomaly) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
                    sin(2 * anomaly) * (0.019993 - 0.000101 * t) + sin(3 * anomaly) * 0.000289
            val omega = radians(125.04 - 1934.136 * t)
            val apparentLongitude = radians(meanLongitude + center - 0.00569 - 0.00478 * sin(omega))
            val obliquity =
                radians(
                    23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60 + 0.00256 * cos(omega),
                )
            val declination = asin(sin(obliquity) * sin(apparentLongitude))
            val y = tan(obliquity / 2).pow(2)
            val l = radians(meanLongitude)
            val equationOfTime =
                4 *
                    degrees(
                        y * sin(2 * l) - 2 * eccentricity * sin(anomaly) +
                            4 * eccentricity * y * sin(anomaly) * cos(2 * l) -
                            0.5 * y * y * sin(4 * l) - 1.25 * eccentricity * eccentricity * sin(2 * anomaly),
                    )
            val utcMinutes = (seconds % 86400) / 60
            val hourAngle = radians(normalized((utcMinutes + equationOfTime + 4 * longitude) / 4) - 180)
            val phi = radians(latitude)
            val altitude =
                asin((sin(phi) * sin(declination) + cos(phi) * cos(declination) * cos(hourAngle)).coerceIn(-1.0, 1.0))
            val elevation = degrees(altitude)
            val azimuth =
                normalized(
                    degrees(atan2(sin(hourAngle), cos(hourAngle) * sin(phi) - tan(declination) * cos(phi))) + 180,
                )
            val tangent = tan(altitude)
            val refraction =
                when {
                    elevation > 85 -> {
                        0.0
                    }

                    elevation > 5 -> {
                        (58.1 / tangent - 0.07 / tangent.pow(3) + 0.000086 / tangent.pow(5)) / 3600
                    }

                    elevation > -0.575 -> {
                        (
                            1735 +
                                elevation * (-518.2 + elevation * (103.4 + elevation * (-12.79 + elevation * 0.711)))
                        ) /
                            3600
                    }

                    else -> {
                        -20.772 / tangent / 3600
                    }
                }
            // Standard sunrise includes the solar radius and atmospheric refraction.
            val horizon = sin(radians(-0.833))
            val base = sin(phi) * sin(declination)
            val amplitude = cos(phi) * cos(declination)
            val arc: Arc?
            val progress: Double?
            when {
                base - amplitude >= horizon -> {
                    // Polar day has no sunrise or sunset; show progress through the full solar day.
                    arc = Arc(base, amplitude, PI)
                    progress = (hourAngle + PI) / (2 * PI)
                }

                base + amplitude <= horizon || elevation < -0.833 -> {
                    arc = null
                    progress = null
                }

                else -> {
                    val sunsetAngle = acos(((horizon - base) / amplitude).coerceIn(-1.0, 1.0))
                    arc = Arc(base, amplitude, sunsetAngle)
                    progress = ((hourAngle + sunsetAngle) / (2 * sunsetAngle)).coerceIn(0.0, 1.0)
                }
            }
            return SolarPosition(elevation, elevation + refraction, azimuth, hourAngle < 0, progress, arc)
        }

        private fun radians(degrees: Double) = degrees * PI / 180

        private fun degrees(radians: Double) = radians * 180 / PI

        /** Swift `truncatingRemainder` based; Kotlin `%` on doubles has the same semantics. */
        private fun normalized(angle: Double) = ((angle % 360) + 360) % 360
    }
}
