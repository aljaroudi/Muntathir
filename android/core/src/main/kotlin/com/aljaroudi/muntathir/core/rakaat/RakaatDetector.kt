package com.aljaroudi.muntathir.core.rakaat

/**
 * Counts sujood from front-camera luminance (0…1, about 10 samples per second): covering the camera in
 * sujood darkens it. Port of Swift `RakaatDetector`; the CameraX producer is P5.2.
 */
class RakaatDetector(
    val target: Int,
) {
    init {
        require(target in 2..4) { "target must be 2…4" }
    }

    var sujoodCount = 0
        private set

    /** Calibrated uncovered light, or `null` while calibrating. */
    var baseline: Double? = null
        private set

    private val samples = ArrayDeque<Pair<Double, Double>>()
    private var transitionStart: Double? = null
    private var covered = false
    private var lastTime: Double? = null

    val rakaat: Int get() = sujoodCount / 2

    val complete: Boolean get() = sujoodCount >= target * 2

    fun sample(
        light: Double,
        time: Double,
    ) {
        if (complete || !light.isFinite() || light !in 0.0..1.0 || !time.isFinite()) return
        lastTime?.let { last ->
            if (time <= last) return
            if (time - last > MAX_GAP) {
                transitionStart = null
                samples.clear()
            }
        }
        lastTime = time
        val baseline = baseline
        if (baseline == null) {
            calibrate(light, time)
            return
        }
        val transitioning = if (covered) light >= baseline * UNCOVERED else light <= baseline * COVERED
        if (transitioning) {
            val start = transitionStart ?: time.also { transitionStart = it }
            if (time - start >= HOLD) {
                covered = !covered
                if (covered) sujoodCount += 1
                transitionStart = null
            }
        } else {
            transitionStart = null
            if (!covered && light >= baseline * UNCOVERED) this.baseline = baseline * 0.995 + light * 0.005
        }
    }

    private fun calibrate(
        light: Double,
        time: Double,
    ) {
        samples.addLast(time to light)
        samples.removeAll { time - it.first > 1.2 }
        val first = samples.firstOrNull() ?: return
        if (time - first.first < 1 || samples.size < 8) return
        val lights = samples.map { it.second }
        val mean = lights.average()
        val spread = lights.max() - lights.min()
        if (mean < MIN_LIGHT || spread > mean * 0.15) return
        baseline = mean
        samples.clear()
    }

    companion object {
        const val MIN_LIGHT = 0.08
        const val MAX_GAP = 0.3
        const val HOLD = 0.5
        const val COVERED = 0.4
        const val UNCOVERED = 0.7
    }
}

/** Reports why calibration hasn't succeeded, after a 5 s countdown. Port of Swift `RakaatPreparation`. */
class RakaatPreparation {
    enum class Failure { TooDark, Unstable }

    private var darkSince: Double? = null
    private var lastTime: Double? = null

    fun sample(
        light: Double,
        elapsed: Double,
    ): Failure? {
        if (!light.isFinite() || light !in 0.0..1.0 || !elapsed.isFinite() || elapsed < 5) return null
        val last = lastTime
        if (last != null && elapsed <= last) return null
        if (last != null && elapsed - last > RakaatDetector.MAX_GAP) darkSince = null
        lastTime = elapsed
        if (light < RakaatDetector.MIN_LIGHT) {
            val since = darkSince ?: elapsed.also { darkSince = it }
            if (elapsed - since >= 1) return Failure.TooDark
        } else {
            darkSince = null
        }
        return if (elapsed >= 10) Failure.Unstable else null
    }
}
