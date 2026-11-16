package com.aljaroudi.muntathir.ui.components

import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bedtime
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.LightMode
import androidx.compose.material.icons.outlined.NightsStay
import androidx.compose.material.icons.outlined.WbSunny
import androidx.compose.material.icons.outlined.WbTwilight
import androidx.compose.ui.graphics.vector.ImageVector
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.PrayerAlertSound
import com.aljaroudi.muntathir.core.prayer.PrayerMethod
import com.aljaroudi.muntathir.core.prayer.PrayerName

@get:StringRes
val PrayerMethod.title: Int
    get() =
        when (this) {
            PrayerMethod.Jafari -> R.string.jafari_qum
            PrayerMethod.Tehran -> R.string.jafari_tehran
            PrayerMethod.UmmAlQura -> R.string.umm_al_qura
        }

@get:StringRes
val PrayerName.title: Int
    get() =
        when (this) {
            PrayerName.Imsak -> R.string.imsak
            PrayerName.Fajr -> R.string.fajr
            PrayerName.Sunrise -> R.string.sunrise
            PrayerName.Dhuhr -> R.string.dhuhr
            PrayerName.Asr -> R.string.asr
            PrayerName.Sunset -> R.string.sunset
            PrayerName.Maghrib -> R.string.maghrib
            PrayerName.Isha -> R.string.isha
            PrayerName.Midnight -> R.string.midnight
        }

/** Swift `PrayerName.notificationBody`. */
@get:StringRes
val PrayerName.notificationBody: Int
    get() =
        when (this) {
            PrayerName.Fajr -> R.string.fajr_prayer
            PrayerName.Dhuhr -> R.string.dhuhr_prayer
            PrayerName.Asr -> R.string.asr_prayer
            PrayerName.Maghrib -> R.string.maghrib_prayer
            PrayerName.Isha -> R.string.isha_prayer
            else -> title
        }

/** Material counterparts of the iOS symbols (moonset, sun.horizon, sunrise, sun.max, …). */
val PrayerName.icon: ImageVector
    get() =
        when (this) {
            PrayerName.Imsak -> Icons.Outlined.NightsStay
            PrayerName.Fajr -> Icons.Outlined.WbTwilight
            PrayerName.Sunrise -> Icons.Outlined.WbTwilight
            PrayerName.Dhuhr -> Icons.Outlined.WbSunny
            PrayerName.Asr -> Icons.Outlined.LightMode
            PrayerName.Sunset -> Icons.Outlined.WbTwilight
            PrayerName.Maghrib -> Icons.Outlined.DarkMode
            PrayerName.Isha -> Icons.Outlined.NightsStay
            PrayerName.Midnight -> Icons.Outlined.Bedtime
        }

@get:StringRes
val PrayerAlertSound.title: Int
    get() =
        when (this) {
            PrayerAlertSound.System -> R.string.system_sound
            PrayerAlertSound.Chime -> R.string.chime
            PrayerAlertSound.Bell -> R.string.bell
            PrayerAlertSound.Alhalwachi -> R.string.alhalwachi
            PrayerAlertSound.AliMulla -> R.string.ali_mulla
            PrayerAlertSound.Alsarraf -> R.string.al_sarraf
            PrayerAlertSound.Silent -> R.string.silent
        }
