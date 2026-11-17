package com.aljaroudi.muntathir.core.rakaat

/** What the tracker shows: Swift `RakaatCamera.Update` without the preview image. */
data class RakaatUpdate(
    val count: Int = 0,
    val calibrated: Boolean = false,
    val complete: Boolean = false,
    val failure: RakaatPreparation.Failure? = null,
)

/**
 * Swift `RakaatCamera.process` without the camera. Frames arrive at about 10 per second with their luminance and
 * the camera's 3A state; once the camera has settled it asks for exposure and white balance to be locked, and only
 * frames captured under that lock reach the [RakaatDetector]. Not thread-safe.
 */
class RakaatCapture(
    target: Int,
) {
    /** The camera's auto-exposure, white balance and focus for one frame. */
    enum class Camera { Adjusting, Settled, Locked }

    sealed interface Step {
        /** Too close to the previous frame, or the capture has finished. */
        data object Skip : Step

        data class Publish(
            val update: RakaatUpdate,
        ) : Step

        /** Publish [update], then lock exposure (and white balance and focus) and call [lockFailed] if that fails. */
        data class Lock(
            val update: RakaatUpdate,
        ) : Step

        /** The last update (if any); the capture is over. Without a final update the camera simply stopped. */
        data class Finish(
            val update: RakaatUpdate?,
        ) : Step
    }

    private val detector = RakaatDetector(target)
    private val preparation = RakaatPreparation()
    private var firstTime: Double? = null
    private var lastTime = Double.NEGATIVE_INFINITY
    private var lockRequested = false

    var finished = false
        private set

    /** Whether a frame has arrived, so the preparation timeout should be running. */
    val started: Boolean get() = firstTime != null

    private val current: RakaatUpdate
        get() = RakaatUpdate(detector.sujoodCount, detector.baseline != null, detector.complete)

    /** [light] is the frame's mean luminance (0…1) and [time] its capture time in seconds. */
    fun frame(
        light: Double,
        time: Double,
        camera: Camera,
    ): Step {
        if (finished || time - lastTime < MIN_INTERVAL) return Step.Skip
        lastTime = time
        val first = firstTime ?: time.also { firstTime = it }
        if (detector.baseline == null) {
            preparation.sample(light, time - first)?.let { return finish(RakaatUpdate(failure = it)) }
        }
        if (!lockRequested) {
            // Keep the preview live while the camera settles, before measuring the baseline.
            if (camera == Camera.Adjusting) return Step.Publish(current)
            lockRequested = true
            return Step.Lock(current)
        }
        // Frames that predate the lock would skew the baseline.
        if (camera != Camera.Locked) return Step.Publish(current)
        detector.sample(light, time)
        return if (detector.complete) finish(current) else Step.Publish(current)
    }

    /** Exposure can't be locked, so the shadow can't be measured reliably. */
    fun lockFailed(): Step = if (finished) Step.Skip else finish(null)

    /** Ten seconds after the first frame; a stalled capture must not leave calibration waiting for another frame. */
    fun expirePreparation(): Step =
        if (finished ||
            detector.baseline != null
        ) {
            Step.Skip
        } else {
            finish(RakaatUpdate(failure = RakaatPreparation.Failure.Unstable))
        }

    private fun finish(update: RakaatUpdate?): Step {
        finished = true
        return Step.Finish(update)
    }

    companion object {
        const val MIN_INTERVAL = 0.095
        const val PREPARATION_TIMEOUT_MILLIS = 10_000L
    }
}
