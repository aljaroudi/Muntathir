package com.aljaroudi.muntathir.core.qibla

/**
 * The rules of Swift `QiblaLocationSession` without the platform: which fixes and headings count, when they expire,
 * and the status shown. Times are seconds on one clock (e.g. `SystemClock.elapsedRealtimeNanos() / 1e9`, which
 * `Location.elapsedRealtimeNanos` and `SensorEvent.timestamp` share).
 *
 * [optional] is the Rakaat tracker's hint: it never asks for permission and also accepts a fix up to
 * [MAX_AGE] seconds older than the session.
 */
class QiblaSession(
    val optional: Boolean = false,
) {
    enum class Status { Locating, Ready, Settings, Failed }

    data class Fix(
        val latitude: Double,
        val longitude: Double,
        /** Horizontal accuracy in meters. */
        val accuracy: Double,
        val time: Double,
    )

    data class Heading(
        /** Degrees from true north. */
        val degrees: Double,
        val accuracy: Double,
        val time: Double,
    )

    var status = Status.Locating
        private set
    var fix: Fix? = null
        private set
    var heading: Heading? = null
        private set
    var startedAt: Double? = null
        private set

    val isRunning: Boolean get() = startedAt != null

    fun start(now: Double) {
        stop()
        startedAt = now
        status = Status.Locating
    }

    fun stop() {
        startedAt = null
        fix = null
        heading = null
    }

    /** Location access is missing or approximate: hide everything until it changes. */
    fun needsSettings() {
        if (!isRunning) return
        fix = null
        heading = null
        status = Status.Settings
    }

    /** The provider failed (no GPS, location off). */
    fun fail() {
        if (!isRunning) return
        fix = null
        heading = null
        status = Status.Failed
    }

    /** New fixes; [precise] is false when only approximate location is granted. */
    fun receive(
        fixes: List<Fix>,
        precise: Boolean,
        now: Double,
    ) {
        val start = startedAt ?: return
        if (!precise) return needsSettings()
        val accepted = fixes.lastOrNull { accepts(it, since = earliest(start), now = now) }
        if (accepted != null) {
            fix = accepted
            status = Status.Ready
        } else {
            refresh(now)
        }
    }

    fun receiveHeading(
        reading: Heading,
        now: Double,
    ) {
        if (!isRunning) return
        heading = reading.takeIf { acceptsHeading(it, now) }
    }

    /** Drops the heading after the screen rotates, until the sensor reports in the new orientation. */
    fun resetHeading() {
        heading = null
    }

    /** Call about once a second: expires stale readings and times out a search. */
    fun refresh(now: Double) {
        val start = startedAt ?: return
        heading?.let { if (!acceptsHeading(it, now)) heading = null }
        fix?.let {
            if (!accepts(it, since = earliest(start), now = now)) {
                fix = null
                status = Status.Failed
            }
        }
        if (status == Status.Locating && now - start >= TIMEOUT) status = Status.Failed
    }

    private fun earliest(start: Double) = if (optional) start - MAX_AGE else start

    companion object {
        const val MAX_ACCURACY = 20.0
        const val MAX_AGE = 15.0
        const val MAX_HEADING_ERROR = 10.0
        const val TIMEOUT = 30.0

        fun accepts(
            fix: Fix,
            since: Double,
            now: Double,
        ): Boolean =
            fix.latitude.isFinite() && fix.longitude.isFinite() && fix.latitude in -90.0..90.0 &&
                fix.longitude in -180.0..180.0 && fix.accuracy.isFinite() && fix.accuracy in 0.0..MAX_ACCURACY &&
                fix.time >= since && (now - fix.time) in 0.0..MAX_AGE

        fun acceptsHeading(
            heading: Heading,
            now: Double,
        ): Boolean =
            heading.degrees.isFinite() && heading.degrees >= 0 && heading.degrees < 360 &&
                heading.accuracy.isFinite() && heading.accuracy in 0.0..MAX_HEADING_ERROR &&
                (now - heading.time) in 0.0..MAX_AGE
    }
}
