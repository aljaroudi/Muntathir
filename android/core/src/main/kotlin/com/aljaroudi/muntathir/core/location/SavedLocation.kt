package com.aljaroudi.muntathir.core.location

import kotlinx.serialization.Serializable
import java.time.DateTimeException
import java.time.ZoneId
import java.time.ZoneOffset

@Serializable
data class SavedLocation(
    val latitude: Double,
    val longitude: Double,
    val name: String,
    val countryCode: String,
    val timeZoneID: String,
) {
    /** The location's zone, falling back to UTC when the identifier is unknown. */
    val zone: ZoneId get() = zoneOrNull() ?: ZoneOffset.UTC

    val hasValidCoordinates: Boolean
        get() = latitude.isFinite() && longitude.isFinite() && latitude in -90.0..90.0 && longitude in -180.0..180.0

    val hasValidZone: Boolean get() = zoneOrNull() != null

    val isValid: Boolean get() = hasValidCoordinates && hasValidZone && name.isNotEmpty()

    private fun zoneOrNull(): ZoneId? =
        try {
            ZoneId.of(timeZoneID)
        } catch (_: DateTimeException) {
            null
        }
}
