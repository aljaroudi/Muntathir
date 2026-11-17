package com.aljaroudi.muntathir.core.qibla

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.pow
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class QiblaGeometryTest {
    @Test
    fun addsDeclinationAndWrapsIntoOneTurn() {
        assertEquals(93.5, QiblaGeometry.trueHeading(90.0, 3.5)!!, 1e-9)
        assertEquals(355.0, QiblaGeometry.trueHeading(2.0, -7.0)!!, 1e-9)
        assertEquals(5.0, QiblaGeometry.trueHeading(358.0, 7.0)!!, 1e-9)
        // getOrientation reports -180..180.
        assertEquals(270.0, QiblaGeometry.trueHeading(-90.0, 0.0)!!, 1e-9)
        assertEquals(0.0, QiblaGeometry.trueHeading(-0.0, 0.0))
        assertEquals(0.0, QiblaGeometry.trueHeading(360.0, 0.0))
        assertEquals(0.0, QiblaGeometry.trueHeading(-1e-15, 0.0)!!, 1e-9)
        assertNull(QiblaGeometry.trueHeading(Double.NaN, 0.0))
        assertNull(QiblaGeometry.trueHeading(10.0, Double.POSITIVE_INFINITY))
    }

    @Test
    fun everyHeadingIsAcceptedBySession() {
        for (azimuth in -720..720 step 15) {
            val degrees = QiblaGeometry.trueHeading(azimuth.toDouble(), 2.25)!!
            val heading = QiblaSession.Heading(degrees, 5.0, 0.0)
            assert(QiblaSession.acceptsHeading(heading, now = 0.0)) { "$azimuth → $degrees" }
        }
    }

    @Test
    fun headingAccuracyPrefersTheSensorEstimate() {
        assertEquals(4.0, QiblaGeometry.headingAccuracy(4 * PI / 180, 0)!!, 1e-9)
        assertEquals(5.0, QiblaGeometry.headingAccuracy(-1.0, QiblaGeometry.STATUS_HIGH))
        assertEquals(10.0, QiblaGeometry.headingAccuracy(null, QiblaGeometry.STATUS_MEDIUM))
        assertNull(QiblaGeometry.headingAccuracy(null, 1))
        assertNull(QiblaGeometry.headingAccuracy(Double.NaN, 0))
    }

    @Test
    fun zoomFitsAboutOneHundredFiftyMetersAcrossTheWidth() {
        for (latitude in listOf(0.0, 21.4, 24.7136, 51.5, -33.9)) {
            for (width in listOf(360.0, 411.0, 840.0)) {
                val zoom = QiblaGeometry.zoom(latitude, width)
                val metersPerPoint = 40_075_016.686 / 256 * cos(latitude * PI / 180) / 2.0.pow(zoom)
                assertEquals(150.0, metersPerPoint * width, 1e-6, "$latitude, $width")
            }
        }
        assertEquals(18.67, QiblaGeometry.zoom(0.0, 400.0), 0.01)
        // Wider screens zoom in less; higher latitudes zoom out.
        assert(QiblaGeometry.zoom(0.0, 800.0) > QiblaGeometry.zoom(0.0, 400.0))
        assert(QiblaGeometry.zoom(60.0, 400.0) < QiblaGeometry.zoom(0.0, 400.0))
        assertEquals(21.0, QiblaGeometry.zoom(0.0, 0.0))
        assertEquals(21.0, QiblaGeometry.zoom(0.0, 1e9))
    }

    @Test
    fun needleIsTheBearingRelativeToTheHeading() {
        assertEquals(0.0, QiblaGeometry.relativeBearing(244.0, 244.0))
        assertEquals(154.0, QiblaGeometry.relativeBearing(244.0, 90.0), 1e-9)
        assertEquals(350.0, QiblaGeometry.relativeBearing(10.0, 20.0), 1e-9)
    }
}
