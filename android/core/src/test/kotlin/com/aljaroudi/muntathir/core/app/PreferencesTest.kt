package com.aljaroudi.muntathir.core.app

import com.aljaroudi.muntathir.core.calendar.HijriMonth
import com.aljaroudi.muntathir.core.calendar.MonthOffset
import com.aljaroudi.muntathir.core.prayer.PrayerMethod
import com.aljaroudi.muntathir.core.prayer.PrayerName
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Ports the Preferences coding cases of `PrayerPreferencesTests`, `TabPreferencesTests` and `PrayerAlertSoundTests`.
class PreferencesTest {
    @Test
    fun legacyCalendarChoicesAreIgnoredWithoutLosingAdjustments() {
        for (source in listOf("null", "\"government-SA\"", "\"legacy\"", "\"naked-eye-middle-east\"")) {
            val saved =
                Preferences.decode(
                    """{"selectedSourceID":$source,"monthOffsets":[{"month":{"year":1448,"month":1},"days":1}],"showFeelsLikeTemperature":true}""",
                )
            assertEquals(listOf(MonthOffset(HijriMonth(1448, 1), 1)), saved.monthOffsets)
            assertTrue(saved.showFeelsLikeTemperature)
            assertFalse("selectedSourceID" in saved.encode())
        }
    }

    @Test
    fun oldSettingsKeepChoicesAndDefaultNewFields() {
        val preferences =
            Preferences.decode(
                """{"prayerMethod":"tehran","asrRule":"hanafi","enabledPrayers":[],"hiddenPrayers":["asr"]}""",
            )
        assertEquals(PrayerMethod.Tehran, preferences.prayerMethod)
        assertTrue(preferences.enabledPrayers.isEmpty())
        assertEquals(10, preferences.imsakMinutes)
        assertEquals(setOf(PrayerName.Asr), preferences.hiddenPrayers)
        assertEquals(setOf(PrayerName.Fajr, PrayerName.Dhuhr, PrayerName.Maghrib), Preferences().enabledPrayers)
        val fresh = Preferences.decode("{}")
        assertEquals(PrayerMethod.Tehran, fresh.prayerMethod)
        assertEquals(setOf(PrayerName.Fajr, PrayerName.Dhuhr, PrayerName.Maghrib), fresh.enabledPrayers)
        assertFalse("asrRule" in preferences.encode())
    }

    @Test
    fun horizontalPrayerTimesDefaultsOffAndRoundTrips() {
        assertFalse(Preferences.decode("{}").horizontalPrayerTimes)
        assertTrue(Preferences.decode(Preferences(horizontalPrayerTimes = true).encode()).horizontalPrayerTimes)
    }

    @Test
    fun imsakPreferenceBoundsAreValidatedOnDecode() {
        assertEquals(0, Preferences.decode("""{"imsakMinutes":-5}""").imsakMinutes)
        assertEquals(120, Preferences.decode("""{"imsakMinutes":999}""").imsakMinutes)
    }

    @Test
    fun tabDefaultsAndExplicitEmptySelection() {
        assertEquals(listOf(AppTool.Calendar), Preferences().tabShortcuts)
        assertEquals(listOf(AppTool.Calendar), Preferences.decode("{}").tabShortcuts)
        assertTrue(Preferences.decode("""{"tabShortcuts":[]}""").tabShortcuts.isEmpty())
    }

    @Test
    fun unknownDuplicatesAndOverflowAreRemovedWithoutChangingOrder() {
        val preferences =
            Preferences.decode(
                """{"tabShortcuts":["future","events","events","today","hadith","quran","qibla","tools"]}""",
            )
        assertEquals(listOf(AppTool.Events, AppTool.Hadith, AppTool.Quran), preferences.tabShortcuts)
        assertEquals(preferences, Preferences.decode(preferences.encode()))
    }

    @Test
    fun roundTripsSharedNotificationSound() {
        val decoded = Preferences.decode("""{"enabledPrayers":["fajr"]}""")
        assertEquals(setOf(PrayerName.Fajr), decoded.enabledPrayers)
        assertTrue(decoded.timeSensitiveNotifications)
        assertEquals(PrayerAlertSound.Chime, decoded.notificationSound)
        val changed = decoded.copy(notificationSound = PrayerAlertSound.Bell, timeSensitiveNotifications = false)
        val saved = Preferences.decode(changed.encode())
        assertEquals(changed, saved)
        assertEquals(PrayerAlertSound.Bell, saved.notificationSound)
    }

    @Test
    fun legacyAdhanStaysOnPrayersOnly() {
        val encoded =
            Json
                .parseToJsonElement(
                    Preferences(notificationSound = PrayerAlertSound.Bell).encode(),
                ).jsonObject
        val legacy = JsonObject(encoded - setOf("sunsetSound", "otherTimesSound", "calendarEventNotifications"))
        val migrated = Preferences.decode(legacy.toString())
        assertEquals(PrayerAlertSound.Bell, migrated.notificationSound)
        assertEquals(PrayerAlertSound.System, migrated.sunsetSound)
        assertEquals(PrayerAlertSound.System, migrated.otherTimesSound)
        assertFalse(migrated.calendarEventNotifications)
        for (prayer in PrayerName.entries) {
            assertEquals(
                if (prayer.isPrayer) PrayerAlertSound.Bell else PrayerAlertSound.System,
                migrated.sound(prayer),
            )
        }
    }

    @Test
    fun encodesSwiftShape() {
        val keys = Json.parseToJsonElement(Preferences().encode()).jsonObject.keys
        assertEquals(
            setOf(
                "prayerMethod",
                "imsakMinutes",
                "enabledPrayers",
                "showFeelsLikeTemperature",
                "horizontalPrayerTimes",
                "announcementNotifications",
                "timeSensitiveNotifications",
                "notificationSound",
                "sunsetSound",
                "otherTimesSound",
                "calendarEventNotifications",
                "tabShortcuts",
                "monthOffsets",
                "hiddenPrayers",
            ),
            keys,
        )
    }

    @Test
    fun invalidBlobsFallBack() {
        assertNull(Preferences.decodeValid("broken"))
        assertNull(Preferences.decodeValid("""{"enabledPrayers":["dusk"]}"""))
        assertNull(Preferences.decodeValid("""{"monthOffsets":[{"month":{"year":1448,"month":1},"days":3}]}"""))
        val duplicate = """{"month":{"year":1448,"month":1},"days":1}"""
        assertNull(Preferences.decodeValid("""{"monthOffsets":[$duplicate,$duplicate]}"""))
    }
}
