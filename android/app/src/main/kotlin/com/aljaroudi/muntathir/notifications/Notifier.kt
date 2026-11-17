package com.aljaroudi.muntathir.notifications

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.LocaleList
import android.provider.Settings
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.aljaroudi.muntathir.MainActivity
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.Announcer
import com.aljaroudi.muntathir.core.app.PrayerAlertSound
import com.aljaroudi.muntathir.core.app.Preferences
import com.aljaroudi.muntathir.core.feed.Announcement
import com.aljaroudi.muntathir.core.prayer.PrayerName
import com.aljaroudi.muntathir.core.prayer.ScheduledAlert
import com.aljaroudi.muntathir.ui.components.notificationBody
import com.aljaroudi.muntathir.ui.components.title
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Posts Muntathir's notifications. Port of Swift `NotificationService` content: one channel per category, and
 * prayer channels versioned by sound because a channel's sound can't change after creation.
 */
@Singleton
class Notifier
    @Inject
    constructor(
        @param:ApplicationContext private val context: Context,
    ) : Announcer {
        private val manager = NotificationManagerCompat.from(context)

        /** Strings in the per-app language; below API 33 the application context doesn't carry it. */
        private fun localized(): Context {
            val locales = AppCompatDelegate.getApplicationLocales()
            if (locales.isEmpty) return context
            val configuration =
                Configuration(context.resources.configuration).apply {
                    setLocales(LocaleList.forLanguageTags(locales.toLanguageTags()))
                }
            return context.createConfigurationContext(configuration)
        }

        val canPost: Boolean
            get() =
                manager.areNotificationsEnabled() &&
                    (
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                            PackageManager.PERMISSION_GRANTED
                    )

        /** Creates the channels for the current sounds and removes channels for sounds no longer chosen. */
        fun ensureChannels(preferences: Preferences) {
            val strings = localized()
            val system = context.getSystemService(NotificationManager::class.java)
            system.createNotificationChannelGroup(
                NotificationChannelGroup(GROUP_TIMES, strings.getString(R.string.prayer_times)),
            )
            val wanted =
                listOf(
                    timeChannel(Category.Prayers, preferences.notificationSound, strings),
                    timeChannel(Category.Sunset, preferences.sunsetSound, strings),
                    timeChannel(Category.Other, preferences.otherTimesSound, strings),
                )
            wanted.forEach(system::createNotificationChannel)
            val kept = wanted.map { it.id }.toSet()
            system.notificationChannels
                .filter { channel ->
                    Category.entries.any { channel.id.startsWith("${it.prefix}.") } &&
                        channel.id !in kept
                }.forEach { system.deleteNotificationChannel(it.id) }
            system.createNotificationChannel(
                NotificationChannel(
                    EVENTS,
                    strings.getString(R.string.calendar_events),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    setSound(null, null)
                    enableVibration(false)
                },
            )
            system.createNotificationChannel(
                NotificationChannel(
                    ANNOUNCEMENTS,
                    strings.getString(R.string.month_confirmations),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }

        private fun timeChannel(
            category: Category,
            sound: PrayerAlertSound,
            strings: Context,
        ) = NotificationChannel(
            channelID(category, sound),
            strings.getString(category.title),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            group = GROUP_TIMES
            val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build()
            when (sound) {
                PrayerAlertSound.Silent -> setSound(null, null)
                PrayerAlertSound.System -> setSound(Settings.System.DEFAULT_NOTIFICATION_URI, attributes)
                else -> setSound(soundUri(sound), attributes)
            }
        }

        fun soundUri(sound: PrayerAlertSound): Uri? =
            when (sound) {
                PrayerAlertSound.Silent -> {
                    null
                }

                PrayerAlertSound.System -> {
                    Settings.System.DEFAULT_NOTIFICATION_URI
                }

                else -> {
                    Uri
                        .Builder()
                        .scheme(ContentResolver.SCHEME_ANDROID_RESOURCE)
                        .authority(context.packageName)
                        .appendPath("raw")
                        .appendPath(sound.id.lowercase())
                        .build()
                }
            }

        /** Swift `NotificationService.content(for:)` / `eventContent`. */
        fun post(
            alert: ScheduledAlert,
            preferences: Preferences,
        ) {
            if (!canPost) return
            ensureChannels(preferences)
            val strings = localized()
            val prayer = alert.prayer
            val builder =
                if (prayer != null) {
                    NotificationCompat
                        .Builder(context, channelID(Category.of(prayer), preferences.sound(prayer)))
                        .setContentTitle(
                            strings.getString(if (prayer.isPrayer) R.string.time_for_prayer else prayer.title),
                        ).setContentText(strings.getString(prayer.notificationBody))
                        .setGroup("prayer.${prayer.id}")
                        .setCategory(NotificationCompat.CATEGORY_REMINDER)
                        .setPriority(NotificationCompat.PRIORITY_HIGH)
                } else {
                    val locale = strings.resources.configuration.locales[0] ?: Locale.getDefault()
                    NotificationCompat
                        .Builder(context, EVENTS)
                        .setContentTitle(strings.getString(R.string.this_evening))
                        .setContentText(alert.events.joinToString(" · ") { it.title(locale) })
                        .setGroup("calendar.events")
                        .setSilent(true)
                }
            notify(alert.id, builder.setWhen(alert.time.toEpochMilli()).setShowWhen(true))
        }

        /** Swift `NotificationService.announce`, one confirmed month at a time; the model records deliveries. */
        override suspend fun post(announcement: Announcement): Boolean {
            if (!canPost) return false
            ensureChannelsWithoutPreferences()
            val strings = localized()
            notify(
                "announcement.${announcement.id}.${announcement.revision}",
                NotificationCompat
                    .Builder(context, ANNOUNCEMENTS)
                    .setContentTitle(strings.getString(R.string.month_confirmed))
                    .setContentText(announcement.sourceID),
            )
            return true
        }

        private fun ensureChannelsWithoutPreferences() {
            val system = context.getSystemService(NotificationManager::class.java)
            if (system.getNotificationChannel(ANNOUNCEMENTS) == null) ensureChannels(Preferences())
        }

        @android.annotation.SuppressLint("MissingPermission") // canPost checks it.
        private fun notify(
            id: String,
            builder: NotificationCompat.Builder,
        ) {
            val open =
                PendingIntent.getActivity(
                    context,
                    0,
                    Intent(
                        context,
                        MainActivity::class.java,
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                    PendingIntent.FLAG_IMMUTABLE,
                )
            manager.notify(
                id,
                0,
                builder
                    .setSmallIcon(R.drawable.ic_notification)
                    .setColor(ContextCompat.getColor(context, R.color.brand))
                    .setContentIntent(open)
                    .setAutoCancel(true)
                    .build(),
            )
        }

        enum class Category(
            val prefix: String,
            val title: Int,
        ) {
            Prayers("prayers", R.string.prayers),
            Sunset("sunset", R.string.sunset),
            Other("other", R.string.other_times),
            ;

            companion object {
                fun of(time: PrayerName): Category =
                    when {
                        time.isPrayer -> Prayers
                        time == PrayerName.Sunset -> Sunset
                        else -> Other
                    }
            }
        }

        companion object {
            const val GROUP_TIMES = "times"
            const val EVENTS = "events.v1"
            const val ANNOUNCEMENTS = "announcements.v1"

            /** Channel sounds are immutable, so the sound is part of the id: `prayers.chime.v1`. */
            fun channelID(
                category: Category,
                sound: PrayerAlertSound,
            ) = "${category.prefix}.${sound.id}.v1"
        }
    }

@Module
@InstallIn(SingletonComponent::class)
interface NotificationsModule {
    @Binds
    fun announcer(notifier: Notifier): Announcer
}
