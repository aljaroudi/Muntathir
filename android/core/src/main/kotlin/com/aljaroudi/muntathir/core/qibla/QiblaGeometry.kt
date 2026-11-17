package com.aljaroudi.muntathir.core.qibla

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.log2

/** Platform-free math behind the Qibla screen: true heading from the compass and the map scale. */
object QiblaGeometry {
    /** Same destination as Adhan's Qibla calculation. */
    const val KAABA_LATITUDE = 21.4225241
    const val KAABA_LONGITUDE = 39.8261818

    /** Meters across the map's width (Swift `QiblaMapView.updateRegion`). */
    const val MAP_SPAN_METERS = 150.0

    /** Web Mercator meters per point at zoom 0 on the equator (a 256-point world). */
    private const val EQUATOR_METERS_PER_POINT = 40_075_016.686 / 256

    /** `SensorManager.SENSOR_STATUS_ACCURACY_HIGH` and `_MEDIUM`. */
    const val STATUS_HIGH = 3
    const val STATUS_MEDIUM = 2

    /**
     * A magnetic azimuth (degrees, any range) plus the local [declination] (east positive) as a true heading in
     * 0..<360, or `null` when either is not finite.
     */
    fun trueHeading(
        azimuth: Double,
        declination: Double,
    ): Double? {
        val sum = azimuth + declination
        if (!sum.isFinite()) return null
        val degrees = ((sum % 360) + 360) % 360
        // `-0.0` and rounding up to exactly 360 both mean north.
        return if (degrees >= 360 || degrees == 0.0) 0.0 else degrees
    }

    /**
     * Heading error in degrees: the rotation vector's own estimate (`values[4]`, radians) when it reports one,
     * otherwise the sensor status (high → 5°, medium → 10°). `null` means the heading isn't trustworthy.
     */
    fun headingAccuracy(
        estimateRadians: Double?,
        status: Int,
    ): Double? =
        when {
            estimateRadians != null && estimateRadians.isFinite() && estimateRadians >= 0 -> estimateRadians * 180 / PI
            status == STATUS_HIGH -> 5.0
            status == STATUS_MEDIUM -> 10.0
            else -> null
        }

    /**
     * The map zoom at which [meters] span [widthPoints] (dp) at [latitude]: Google Maps draws a 256-dp world at
     * zoom 0, and Mercator shrinks meters by `cos(latitude)`.
     */
    fun zoom(
        latitude: Double,
        widthPoints: Double,
        meters: Double = MAP_SPAN_METERS,
        maxZoom: Double = 21.0,
    ): Double {
        if (widthPoints <= 0 || meters <= 0) return maxZoom
        val metersPerPoint = meters / widthPoints
        val scale = cos(latitude.coerceIn(-85.0, 85.0) * PI / 180)
        return log2(EQUATOR_METERS_PER_POINT * scale / metersPerPoint).coerceIn(0.0, maxZoom)
    }

    /** Where the Qibla needle points on a dial whose top is [heading]: 0..<360, clockwise. */
    fun relativeBearing(
        bearing: Double,
        heading: Double,
    ): Double = trueHeading(bearing, -heading) ?: 0.0
}
