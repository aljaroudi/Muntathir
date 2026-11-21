package com.aljaroudi.muntathir.core.wear

import com.aljaroudi.muntathir.core.app.AppState
import com.aljaroudi.muntathir.core.calendar.CalendarEngine
import com.aljaroudi.muntathir.core.calendar.MonthCorrection
import com.aljaroudi.muntathir.core.calendar.MonthOffset
import com.aljaroudi.muntathir.core.prayer.WidgetPrayerSettings
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.DateTimeException
import java.time.ZoneId

/** The calendar inputs the watch needs to resolve the same Hijri day as the phone (see `AppState.engine`). */
@Serializable
data class WatchCalendar(
    val timeZoneID: String,
    val monthOffsets: List<MonthOffset> = emptyList(),
    val confirmed: List<MonthCorrection> = emptyList(),
) {
    val zone: ZoneId get() = ZoneId.of(timeZoneID)

    /** Throws when the zone or the corrections are invalid. */
    fun engine(): CalendarEngine = CalendarEngine.withOffsets(zone, monthOffsets, confirmed)
}

/**
 * Everything the watch shows, sent by the phone over the Data Layer and cached on the watch, which then calculates
 * offline. Port of Swift `WatchSettings`.
 */
@Serializable
data class WatchSnapshot(
    val version: Int = VERSION,
    val prayers: WidgetPrayerSettings,
    val calendar: WatchCalendar,
) {
    fun encode(): ByteArray = json.encodeToString(serializer(), this).encodeToByteArray()

    companion object {
        const val VERSION = 1

        /** Data Layer path of the snapshot item. */
        const val PATH = "/settings/v1"

        private val json = Json { ignoreUnknownKeys = true }

        /** Decodes and validates a transfer; anything unknown or invalid throws, so the last good snapshot stays. */
        fun decode(bytes: ByteArray): WatchSnapshot {
            val value = json.decodeFromString(serializer(), bytes.decodeToString())
            require(value.version == VERSION) { "Unsupported version ${value.version}" }
            require(value.prayers.location?.isValid ?: true) { "Invalid location" }
            try {
                value.calendar.engine()
            } catch (error: DateTimeException) {
                throw IllegalArgumentException("Invalid calendar zone", error)
            }
            return value
        }

        /** The phone's current state. Adjustments that don't build a calendar are dropped, as `AppState.engine` does. */
        fun from(state: AppState): WatchSnapshot {
            val adjusted =
                WatchCalendar(
                    state.zone.id,
                    state.preferences.monthOffsets,
                    state.confirmations.map { it.correction },
                )
            val calendar = if (runCatching { adjusted.engine() }.isSuccess) adjusted else WatchCalendar(state.zone.id)
            return WatchSnapshot(prayers = state.prayerSettings, calendar = calendar)
        }
    }
}
