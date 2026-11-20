package com.aljaroudi.muntathir.core.app

import com.aljaroudi.muntathir.core.calendar.MonthOffset
import com.aljaroudi.muntathir.core.prayer.PrayerMethod
import com.aljaroudi.muntathir.core.prayer.PrayerName
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Notification sound choice. [System] is the platform default; the rest are bundled clips named after [id]. */
@Serializable
enum class PrayerAlertSound(
    val id: String,
) {
    @SerialName("system")
    System("system"),

    @SerialName("chime")
    Chime("chime"),

    @SerialName("bell")
    Bell("bell"),

    @SerialName("alhalwachi")
    Alhalwachi("alhalwachi"),

    @SerialName("aliMulla")
    AliMulla("aliMulla"),

    @SerialName("alsarraf")
    Alsarraf("alsarraf"),

    @SerialName("silent")
    Silent("silent"),
}

/**
 * Backed-up user preferences, stored as `preferences.v1` in the JSON shape of Swift `Preferences`, without the
 * saved city (the location is a device-only GPS fix in [DeviceState]). Every key is optional on decode; unknown
 * keys are dropped.
 */
@Serializable
data class Preferences(
    val prayerMethod: PrayerMethod = PrayerMethod.Tehran,
    val imsakMinutes: Int = 10,
    val enabledPrayers: Set<PrayerName> = setOf(PrayerName.Fajr, PrayerName.Dhuhr, PrayerName.Maghrib),
    /** Weather isn't ported; kept so restored iOS-shaped data round-trips. */
    val showFeelsLikeTemperature: Boolean = false,
    /** Today shows prayer times as a sideways-scrolling row of cards instead of a list. */
    val horizontalPrayerTimes: Boolean = false,
    val announcementNotifications: Boolean = false,
    /** No Android UI: channel importance is a system setting. Kept for the shared shape. */
    val timeSensitiveNotifications: Boolean = true,
    val notificationSound: PrayerAlertSound = PrayerAlertSound.Chime,
    val sunsetSound: PrayerAlertSound = PrayerAlertSound.System,
    val otherTimesSound: PrayerAlertSound = PrayerAlertSound.System,
    val calendarEventNotifications: Boolean = false,
    @Serializable(with = ShortcutsSerializer::class)
    val tabShortcuts: List<AppTool> = listOf(AppTool.Calendar),
    val monthOffsets: List<MonthOffset> = emptyList(),
    val hiddenPrayers: Set<PrayerName> = emptySet(),
) {
    fun sound(time: PrayerName): PrayerAlertSound =
        when {
            time.isPrayer -> notificationSound
            time == PrayerName.Sunset -> sunsetSound
            else -> otherTimesSound
        }

    fun isVisible(prayer: PrayerName): Boolean = prayer.isVisible(hiddenPrayers)

    val isValid: Boolean
        get() = MonthOffset.isValid(monthOffsets)

    /** Applies the decode-time rules Swift enforces: Imsak bounds and shortcut normalization. */
    fun normalized(): Preferences =
        copy(
            imsakMinutes = imsakMinutes.coerceIn(IMSAK_RANGE),
            tabShortcuts = AppTool.normalized(tabShortcuts.map { it.id }),
        )

    fun encode(): String = json.encodeToString(this)

    companion object {
        val IMSAK_RANGE = 0..120

        private val json =
            Json {
                ignoreUnknownKeys = true
                encodeDefaults = true
                explicitNulls = false
            }

        /** Decodes a stored blob; throws on malformed JSON. Callers fall back to defaults when invalid. */
        fun decode(text: String): Preferences = json.decodeFromString<Preferences>(text).normalized()

        /** The stored blob when it decodes and validates, else `null`. */
        fun decodeValid(text: String): Preferences? = runCatching { decode(text) }.getOrNull()?.takeIf { it.isValid }
    }
}
