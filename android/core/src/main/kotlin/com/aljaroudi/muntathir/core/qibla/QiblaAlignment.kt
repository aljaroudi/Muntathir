package com.aljaroudi.muntathir.core.qibla

import kotlin.math.abs

/** Signed shortest turn from [heading] to the Qibla [bearing]. Port of Swift `QiblaAlignment`. */
@ConsistentCopyVisibility
data class QiblaAlignment private constructor(
    /** Degrees in -180..<180; positive means turn clockwise. */
    val error: Double,
) {
    enum class Feedback(
        /** Haptic intensity (0–1) and seconds between pulses; `null` is silent. */
        val pulse: Pulse?,
    ) {
        None(null),
        Gentle(Pulse(0.25, 1.0)),
        Medium(Pulse(0.55, 0.65)),
        Strong(Pulse(0.85, 0.35)),
        Aligned(null),
    }

    data class Pulse(
        val intensity: Double,
        val interval: Double,
    )

    /** Hysteresis prevents sensor jitter from repeating the success haptic. */
    fun isAligned(previously: Boolean): Boolean = abs(error) <= if (previously) RELEASE else LOCK

    fun feedback(aligned: Boolean): Feedback =
        when {
            aligned -> Feedback.Aligned
            abs(error) <= 10 -> Feedback.Strong
            abs(error) <= 30 -> Feedback.Medium
            abs(error) <= RAMP -> Feedback.Gentle
            else -> Feedback.None
        }

    companion object {
        const val LOCK = 5.0
        const val RELEASE = 8.0
        const val RAMP = 60.0

        /** `null` unless both angles are finite and in 0..<360. */
        fun of(
            bearing: Double,
            heading: Double,
        ): QiblaAlignment? {
            fun valid(value: Double) = value.isFinite() && value >= 0 && value < 360
            if (!valid(bearing) || !valid(heading)) return null
            return QiblaAlignment((bearing - heading + 540) % 360 - 180)
        }
    }
}
