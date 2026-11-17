package com.aljaroudi.muntathir.core.location

import kotlinx.serialization.Serializable
import java.time.DateTimeException
import java.time.ZoneId
import java.time.ZoneOffset

/** The device's GPS fix for prayer times and its time zone. It has no name: the UI calls it "Device location". */
@Serializable
data class SavedLocation(
    val latitude: Double,
    val longitude: Double,
    val timeZoneID: String,
) {
    /** The location's zone, falling back to UTC when the identifier is unknown. */
    val zone: ZoneId get() = zoneOrNull() ?: ZoneOffset.UTC

    val hasValidCoordinates: Boolean
        get() = latitude.isFinite() && longitude.isFinite() && latitude in -90.0..90.0 && longitude in -180.0..180.0

    val hasValidZone: Boolean get() = zoneOrNull() != null

    val isValid: Boolean get() = hasValidCoordinates && hasValidZone

    private fun zoneOrNull(): ZoneId? =
        try {
            ZoneId.of(timeZoneID)
        } catch (_: DateTimeException) {
            null
        }
}
