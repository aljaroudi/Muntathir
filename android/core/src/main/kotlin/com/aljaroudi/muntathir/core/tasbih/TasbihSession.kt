package com.aljaroudi.muntathir.core.tasbih

import kotlin.math.abs

/** Tasbih of Fatima al-Zahra: 34 takbir, 33 tahmid, 33 tasbih. Port of Swift `TasbihSession`. */
data class TasbihSession(
    val total: Int = 0,
) {
    val phrase: String
        get() =
            when {
                total < 34 -> "الله أكبر"
                total < 67 -> "الحمد لله"
                else -> "سبحان الله"
            }

    val target: Int get() = if (total < 34) 34 else 33

    val count: Int
        get() =
            when {
                total < 34 -> total
                total < 67 -> total - 34
                else -> total - 67
            }

    val complete: Boolean get() = total == TOTAL

    fun advanced(): TasbihSession = if (complete) this else copy(total = total + 1)

    fun reset(): TasbihSession = TasbihSession()

    companion object {
        const val TOTAL = 100

        /** Drag distance (dp) that counts a bead, and the distance at which the pull is fully drawn. */
        const val ACCEPT_DISTANCE = 40.0
        const val FULL_DISTANCE = 80.0

        /** 0…1 for a downward drag that is more vertical than horizontal; 0 otherwise. */
        fun pullProgress(
            dx: Double,
            dy: Double,
        ): Float = if (dy > 0 && dy > abs(dx)) minOf(dy / FULL_DISTANCE, 1.0).toFloat() else 0f

        fun acceptsPull(
            dx: Double,
            dy: Double,
        ): Boolean = dy > ACCEPT_DISTANCE && dy > abs(dx)
    }
}
