package com.aljaroudi.muntathir.notifications

import android.Manifest
import android.app.NotificationManager
import androidx.test.core.app.ApplicationProvider
import androidx.test.rule.GrantPermissionRule
import com.aljaroudi.muntathir.core.app.PrayerAlertSound
import com.aljaroudi.muntathir.core.app.Preferences
import com.aljaroudi.muntathir.core.calendar.IslamicEvent
import com.aljaroudi.muntathir.core.prayer.PrayerName
import com.aljaroudi.muntathir.core.prayer.ScheduledAlert
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.time.Instant

class NotifierTest {
    @get:Rule val permission: GrantPermissionRule = GrantPermissionRule.grant(Manifest.permission.POST_NOTIFICATIONS)

    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    private val notifier = Notifier(context)
    private val system = context.getSystemService(NotificationManager::class.java)

    @After
    fun clear() = system.cancelAll()

    @Test
    fun channelsFollowTheChosenSoundsAndOldOnesAreRemoved() {
        notifier.ensureChannels(Preferences(notificationSound = PrayerAlertSound.Bell))
        val bell = system.getNotificationChannel("prayers.bell.v1")
        assertEquals(notifier.soundUri(PrayerAlertSound.Bell), bell.sound)
        assertEquals(NotificationManager.IMPORTANCE_HIGH, bell.importance)
        assertNull(system.getNotificationChannel(Notifier.EVENTS).sound)

        notifier.ensureChannels(
            Preferences(notificationSound = PrayerAlertSound.Silent, sunsetSound = PrayerAlertSound.AliMulla),
        )
        assertNull(system.getNotificationChannel("prayers.bell.v1"))
        assertNull(system.getNotificationChannel("prayers.silent.v1").sound)
        assertEquals(
            notifier.soundUri(PrayerAlertSound.AliMulla),
            system.getNotificationChannel("sunset.aliMulla.v1").sound,
        )
    }

    @Test
    fun prayerAndEventAlertsPostOnTheirChannels() {
        val preferences = Preferences(notificationSound = PrayerAlertSound.Chime)
        val now = Instant.now()
        notifier.post(ScheduledAlert("prayer.1.fajr", now, PrayerName.Fajr, emptyList()), preferences)
        notifier.post(ScheduledAlert("prayer.1.sunrise", now, PrayerName.Sunrise, emptyList()), preferences)
        notifier.post(
            ScheduledAlert("event.1", now, null, listOf(IslamicEvent("a", 1, 1, mapOf("en" to "A")))),
            preferences,
        )
        // Posting is asynchronous; wait for all three to show up.
        val tags = setOf("prayer.1.fajr", "prayer.1.sunrise", "event.1")
        val deadline = System.currentTimeMillis() + 5_000
        while (!system.activeNotifications.map { it.tag }.containsAll(tags) && System.currentTimeMillis() < deadline) {
            Thread.sleep(50)
        }
        val posted = system.activeNotifications.associateBy { it.tag }
        assertEquals("prayers.chime.v1", posted.getValue("prayer.1.fajr").notification.channelId)
        assertEquals("other.system.v1", posted.getValue("prayer.1.sunrise").notification.channelId)
        assertEquals(Notifier.EVENTS, posted.getValue("event.1").notification.channelId)
        assertTrue(
            posted
                .getValue("prayer.1.fajr")
                .notification.extras
                .getString("android.title")!!
                .isNotEmpty(),
        )
    }
}
