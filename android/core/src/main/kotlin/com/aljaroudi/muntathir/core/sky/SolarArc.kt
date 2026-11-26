package com.aljaroudi.muntathir.core.sky

import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.prayer.PrayerMoment
import com.aljaroudi.muntathir.core.prayer.PrayerName
import java.time.Instant

data class SolarArcMarker(
    val name: PrayerName,
    val progress: Double,
    val elevation: Double,
    val state: State,
) {
    enum class State { Past, Future, Upcoming }

    companion object {
        /** Pass the same visible schedule as the prayer card. An off-path next time stays off-path. */
        fun make(
            prayers: List<PrayerMoment>,
            now: Instant,
            location: SavedLocation,
        ): List<SolarArcMarker> {
            val next = prayers.filter { it.time > now }.minByOrNull { it.time }?.name
            return prayers.mapNotNull { prayer ->
                val solar =
                    SolarPosition.calculate(prayer.time, location.latitude, location.longitude)
                        ?: return@mapNotNull null
                // Rounded schedule times still belong exactly at the sunrise/sunset endpoints.
                val progress =
                    when (prayer.name) {
                        PrayerName.Sunrise -> 0.0
                        PrayerName.Sunset -> 1.0
                        else -> solar.daylightProgress
                    } ?: return@mapNotNull null
                val onHorizon = prayer.name == PrayerName.Sunrise || prayer.name == PrayerName.Sunset
                val state =
                    when {
                        prayer.time <= now -> State.Past
                        prayer.name == next -> State.Upcoming
                        else -> State.Future
                    }
                SolarArcMarker(prayer.name, progress, if (onHorizon) 0.0 else solar.elevation, state)
            }
        }
    }
}

data class ArcRect(
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double,
) {
    val maxX: Double get() = x + width
    val maxY: Double get() = y + height
}

data class ArcPoint(
    val x: Double,
    val y: Double,
)

/**
 * A stable path in both Arabic and English, matching the sky as seen facing the sun: left to right in the
 * northern hemisphere, [mirrored] (right to left) in the southern. Progress sets x; elevation uses a fixed
 * 0–90° scale.
 */
object SolarArcLayout {
    fun point(
        progress: Double,
        elevation: Double,
        bounds: ArcRect,
        mirrored: Boolean = false,
    ) = ArcPoint(
        x = bounds.x + bounds.width * progress.coerceIn(0.0, 1.0).let { if (mirrored) 1 - it else it },
        y = bounds.maxY - bounds.height * (elevation.coerceIn(0.0, 90.0) / 90),
    )
}
