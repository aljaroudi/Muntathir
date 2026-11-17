package com.aljaroudi.muntathir.core.qibla

import com.aljaroudi.muntathir.core.qibla.QiblaSession.Fix
import com.aljaroudi.muntathir.core.qibla.QiblaSession.Heading
import com.aljaroudi.muntathir.core.qibla.QiblaSession.Status
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Ports the platform-free cases of `QiblaLocationTests`, `QiblaAccuracyTests` and `RakaatQiblaTests`. Map scale,
// geodesic drawing and permission prompts are checked on device (P5.1).
class QiblaSessionTest {
    private val now = 1_000.0

    private fun fix(
        accuracy: Double = 5.0,
        age: Double = 0.0,
        latitude: Double = 24.7,
    ) = Fix(latitude, 46.7, accuracy, now - age)

    @Test
    fun rejectsPoorAccuracy() {
        for (accuracy in listOf(-1.0, 20.001, Double.NaN, Double.POSITIVE_INFINITY)) {
            assertFalse(QiblaSession.accepts(fix(accuracy), since = now, now = now), "$accuracy")
        }
        for (accuracy in listOf(0.0, 20.0)) assertTrue(QiblaSession.accepts(fix(accuracy), since = now, now = now))
    }

    @Test
    fun rejectsCachedFutureStaleAndInvalidFixes() {
        assertFalse(QiblaSession.accepts(fix(age = 1.0), since = now, now = now))
        assertFalse(QiblaSession.accepts(fix(age = -1.0), since = now, now = now))
        assertFalse(QiblaSession.accepts(fix(age = 15.01), since = now - 30, now = now))
        assertTrue(QiblaSession.accepts(fix(age = 15.0), since = now - 30, now = now))
        assertFalse(QiblaSession.accepts(fix(latitude = 91.0), since = now, now = now))
    }

    @Test
    fun preciseAuthorizationExpiryAndRecovery() {
        val session = QiblaSession()
        session.start(now)
        session.receive(listOf(fix()), precise = false, now = now)
        assertNull(session.fix)
        assertEquals(Status.Settings, session.status)
        session.receive(listOf(fix()), precise = true, now = now)
        assertEquals(Status.Ready, session.status)
        session.refresh(now + 16)
        assertNull(session.fix)
        assertEquals(Status.Failed, session.status)
        session.receive(listOf(fix(age = -16.0)), precise = true, now = now + 16)
        assertEquals(Status.Ready, session.status)
        session.receive(listOf(fix(age = -16.0)), precise = false, now = now + 16)
        assertNull(session.fix)
    }

    @Test
    fun restartAndStopRejectEarlierCallbacks() {
        val session = QiblaSession()
        session.start(now)
        session.receive(listOf(fix()), precise = true, now = now)
        session.start(now + 1)
        assertNull(session.fix)
        session.receive(listOf(fix()), precise = true, now = now + 1)
        assertNull(session.fix)
        session.stop()
        session.receive(listOf(fix(age = -2.0)), precise = true, now = now + 2)
        assertNull(session.fix)
    }

    @Test
    fun denialAndFailureHideResults() {
        val session = QiblaSession()
        session.start(now)
        session.receive(listOf(fix()), precise = true, now = now)
        session.needsSettings()
        assertEquals(Status.Settings, session.status)
        assertNull(session.fix)
        session.start(now)
        session.fail()
        assertEquals(Status.Failed, session.status)
        assertNull(session.fix)
    }

    @Test
    fun timeoutAndRetry() {
        val session = QiblaSession()
        session.start(now)
        session.refresh(now + 30)
        assertEquals(Status.Failed, session.status)
        session.start(now + 31)
        assertEquals(Status.Locating, session.status)
        session.receive(listOf(fix(age = -31.0)), precise = true, now = now + 31)
        assertEquals(Status.Ready, session.status)
    }

    @Test
    fun headingAccuracyAndFreshness() {
        for (accuracy in listOf(-1.0, 10.001, Double.NaN, Double.POSITIVE_INFINITY)) {
            assertFalse(QiblaSession.acceptsHeading(Heading(90.0, accuracy, now), now))
        }
        for (accuracy in listOf(0.0, 5.0, 10.0)) {
            for (degrees in listOf(0.0, 90.0, 359.99)) {
                assertTrue(QiblaSession.acceptsHeading(Heading(degrees, accuracy, now), now))
            }
        }
        for (degrees in listOf(-1.0, 360.0, Double.NaN, Double.NEGATIVE_INFINITY)) {
            assertFalse(QiblaSession.acceptsHeading(Heading(degrees, 5.0, now), now))
        }
        assertFalse(QiblaSession.acceptsHeading(Heading(90.0, 5.0, now), now + 16))
    }

    @Test
    fun headingRecoversDegradesAndStops() {
        val session = QiblaSession()
        session.start(now)
        assertNull(session.heading)
        session.receiveHeading(Heading(90.0, 5.0, now), now)
        assertNotNull(session.heading)
        session.receiveHeading(Heading(90.0, 11.0, now), now)
        assertNull(session.heading)
        session.receiveHeading(Heading(90.0, 10.0, now), now)
        assertNotNull(session.heading)
        session.refresh(now + 16)
        assertNull(session.heading)
        session.receiveHeading(Heading(90.0, 5.0, now + 16), now + 16)
        session.stop()
        assertNull(session.heading)
        session.receiveHeading(Heading(90.0, 5.0, now + 17), now + 17)
        assertNull(session.heading)
    }

    @Test
    fun optionalModeAcceptsRecentCachedLocationButExpiresIt() {
        val session = QiblaSession(optional = true)
        val cached = fix(age = 10.0)
        session.start(now)
        session.receive(listOf(cached), precise = true, now = now)
        assertEquals(cached, session.fix)
        session.refresh(now + 6)
        assertNull(session.fix)
        session.receive(listOf(cached), precise = false, now = now)
        assertNull(session.fix)
    }
}
