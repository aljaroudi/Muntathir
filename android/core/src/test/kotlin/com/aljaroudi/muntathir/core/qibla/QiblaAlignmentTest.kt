package com.aljaroudi.muntathir.core.qibla

import com.aljaroudi.muntathir.core.qibla.QiblaAlignment.Feedback
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Ports `QiblaAlignmentTests`. `QiblaAccuracyTests`/`QiblaLocationTests` cover CoreLocation and land with P5.1.
class QiblaAlignmentTest {
    private fun alignment(
        bearing: Double,
        heading: Double = 0.0,
    ) = QiblaAlignment.of(bearing, heading)!!

    @Test
    fun shortestTurnAcrossNorth() {
        assertEquals(4.0, alignment(2.0, 358.0).error)
        assertEquals(-4.0, alignment(358.0, 2.0).error)
        assertEquals(-180.0, alignment(180.0, 0.0).error)
    }

    @Test
    fun alignmentHysteresis() {
        assertTrue(alignment(5.0).isAligned(previously = false))
        val edge = alignment(8.0)
        assertFalse(edge.isAligned(previously = false))
        assertTrue(edge.isAligned(previously = true))
        assertFalse(alignment(8.01).isAligned(previously = true))
    }

    @Test
    fun feedbackStrengthAndSilence() {
        val far = alignment(61.0).feedback(aligned = false)
        assertEquals(Feedback.None, far)
        assertNull(far.pulse)
        val gentle = alignment(60.0).feedback(aligned = false)
        val medium = alignment(30.0).feedback(aligned = false)
        val strong = alignment(10.0).feedback(aligned = false)
        assertEquals(listOf(Feedback.Gentle, Feedback.Medium, Feedback.Strong), listOf(gentle, medium, strong))
        assertTrue(gentle.pulse!!.intensity < medium.pulse!!.intensity)
        assertTrue(medium.pulse!!.intensity < strong.pulse!!.intensity)
        assertTrue(gentle.pulse!!.interval > strong.pulse!!.interval)
        val aligned = alignment(3.0).feedback(aligned = true)
        assertEquals(Feedback.Aligned, aligned)
        assertNull(aligned.pulse)
    }

    @Test
    fun invalidReadingsNeverGuide() {
        for (value in listOf(Double.NaN, Double.POSITIVE_INFINITY, -1.0, 360.0)) {
            assertNull(QiblaAlignment.of(value, 0.0))
            assertNull(QiblaAlignment.of(0.0, value))
        }
    }
}
