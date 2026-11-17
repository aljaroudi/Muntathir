package com.aljaroudi.muntathir.core.rakaat

import com.aljaroudi.muntathir.core.rakaat.RakaatCapture.Camera
import com.aljaroudi.muntathir.core.rakaat.RakaatCapture.Step
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

// The frame pipeline of Swift `RakaatCamera.process`; the detector itself is covered in SessionsTest.
class RakaatCaptureTest {
    private var time = 0.0

    private fun RakaatCapture.next(
        light: Double,
        camera: Camera,
    ): Step {
        time += 0.1
        return frame(light, time, camera)
    }

    @Test
    fun skipsFramesCloserThan95Milliseconds() {
        val capture = RakaatCapture(2)
        assertIs<Step.Publish>(capture.frame(0.5, 1.0, Camera.Adjusting))
        assertEquals(Step.Skip, capture.frame(0.5, 1.05, Camera.Adjusting))
        assertIs<Step.Publish>(capture.frame(0.5, 1.1, Camera.Adjusting))
    }

    @Test
    fun locksOnceSettledAndIgnoresFramesBeforeTheLock() {
        val capture = RakaatCapture(2)
        assertIs<Step.Publish>(capture.next(0.5, Camera.Adjusting))
        assertIs<Step.Lock>(capture.next(0.5, Camera.Settled))
        // Still settled but not yet locked: nothing reaches the detector.
        repeat(20) { assertEquals(RakaatUpdate(), (capture.next(0.5, Camera.Settled) as Step.Publish).update) }
        var last: Step = Step.Skip
        repeat(12) { last = capture.next(0.5, Camera.Locked) }
        assertTrue((last as Step.Publish).update.calibrated)
    }

    @Test
    fun countsToCompletionAndFinishes() {
        val capture = RakaatCapture(2)
        capture.next(0.5, Camera.Settled)
        repeat(12) { capture.next(0.5, Camera.Locked) }
        val steps = mutableListOf<Step>()
        repeat(4) {
            repeat(8) { steps += capture.next(0.05, Camera.Locked) }
            repeat(8) { steps += capture.next(0.5, Camera.Locked) }
        }
        assertEquals(
            listOf(Step.Finish(RakaatUpdate(4, calibrated = true, complete = true))),
            steps.filterIsInstance<Step.Finish>(),
        )
        assertTrue(steps.any { it == Step.Publish(RakaatUpdate(3, calibrated = true)) })
        assertEquals(Step.Skip, capture.next(0.5, Camera.Locked))
    }

    @Test
    fun darknessFailsPreparation() {
        val capture = RakaatCapture(2)
        var last: Step = Step.Skip
        while (last !is Step.Finish && time < 8) last = capture.next(0.01, Camera.Adjusting)
        assertEquals(Step.Finish(RakaatUpdate(failure = RakaatPreparation.Failure.TooDark)), last)
    }

    @Test
    fun timeoutAndLockFailureEndTheCapture() {
        val expired = RakaatCapture(2)
        expired.next(0.5, Camera.Adjusting)
        assertTrue(expired.started)
        assertEquals(
            Step.Finish(RakaatUpdate(failure = RakaatPreparation.Failure.Unstable)),
            expired.expirePreparation(),
        )
        assertEquals(Step.Skip, expired.next(0.5, Camera.Adjusting))

        val unlocked = RakaatCapture(2)
        assertIs<Step.Lock>(unlocked.next(0.5, Camera.Settled))
        assertEquals(Step.Finish(null), unlocked.lockFailed())

        val calibrated = RakaatCapture(2)
        calibrated.next(0.5, Camera.Settled)
        repeat(12) { calibrated.next(0.5, Camera.Locked) }
        assertEquals(Step.Skip, calibrated.expirePreparation())
    }
}
