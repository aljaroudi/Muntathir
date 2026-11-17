package com.aljaroudi.muntathir.core.tasbih

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.sin
import kotlin.math.sqrt

/** A point in the bead scene: x to the right, y up, z toward the camera. */
data class BeadPoint(
    val x: Float,
    val y: Float,
    val z: Float,
)

/**
 * Geometry of Swift `TasbihBeadScene`: [BEAD_COUNT] beads spaced evenly around a capsule turned −60° about Y, so the
 * nearer strand descends as the rear one ascends while the phase grows.
 */
object TasbihBeadLoop {
    const val BEAD_COUNT = 33
    const val CORD_SAMPLES = 160
    const val RADIUS = 0.42f
    const val HALF_HEIGHT = 0.95f
    const val BEAD_RADIUS = 0.088f
    const val CORD_RADIUS = 0.012f
    val PERIMETER = 4 * HALF_HEIGHT + 2 * PI.toFloat() * RADIUS

    // A rotation of −π/3 about Y: x' = x cos θ + z sin θ, z' = −x sin θ + z cos θ (z is 0 on the capsule).
    private const val COS = 0.5f
    private val SIN = -sqrt(3f) / 2

    /** The point at [fraction] of the way around the loop (wrapped to 0…1), starting at the top of the near strand. */
    fun position(fraction: Float): BeadPoint {
        val distance = (fraction - floor(fraction)) * PERIMETER
        val straight = 2 * HALF_HEIGHT
        val arc = PI.toFloat() * RADIUS
        val x: Float
        val y: Float
        when {
            distance < straight -> {
                x = RADIUS
                y = HALF_HEIGHT - distance
            }

            distance < straight + arc -> {
                val angle = (distance - straight) / RADIUS
                x = RADIUS * cos(angle)
                y = -HALF_HEIGHT - RADIUS * sin(angle)
            }

            distance < 2 * straight + arc -> {
                x = -RADIUS
                y = -HALF_HEIGHT + distance - straight - arc
            }

            else -> {
                val angle = (distance - 2 * straight - arc) / RADIUS
                x = -RADIUS * cos(angle)
                y = HALF_HEIGHT + RADIUS * sin(angle)
            }
        }
        return BeadPoint(x * COS, y, -x * SIN)
    }

    /** Bead [index] when the loop has advanced by [phase] beads. */
    fun bead(
        index: Int,
        phase: Float,
    ): BeadPoint = position((index + phase) / BEAD_COUNT)

    /**
     * 0 on the rear strand, 1 on the front, smoothed around the loop's midpoint (Swift `updateDepth`) so beads
     * crossfade between the layers behind and in front of the count instead of jumping.
     */
    fun frontness(z: Float): Float {
        val progress = ((z + 0.12f) / 0.24f).coerceIn(0f, 1f)
        return progress * progress * (3 - 2 * progress)
    }

    /** One copy stays opaque throughout the crossfade, so the cord never shows through a bead. */
    fun opacity(
        z: Float,
        front: Boolean,
    ): Float {
        val frontness = frontness(z)
        return minOf(1f, 2 * if (front) frontness else 1 - frontness)
    }
}
