package com.aljaroudi.muntathir.ui.settings

import android.content.Intent
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppModel
import com.aljaroudi.muntathir.core.app.AppState
import com.aljaroudi.muntathir.core.app.PrayerAlertSound
import com.aljaroudi.muntathir.core.prayer.PrayerMethod
import com.aljaroudi.muntathir.core.prayer.PrayerName
import com.aljaroudi.muntathir.notifications.AlarmScheduler
import com.aljaroudi.muntathir.notifications.Notifier
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.SectionFooter
import com.aljaroudi.muntathir.ui.components.SectionHeader
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.components.rememberNotificationPermission
import com.aljaroudi.muntathir.ui.components.title
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/** Which notification switch asked for permission, so the answer applies to the right one. */
enum class AlertTarget { Prayer, Announcements, Events }

data class SystemPermissions(
    val notifications: Boolean = true,
    val exactAlarms: Boolean = true,
)

@HiltViewModel
class SettingsViewModel
    @Inject
    constructor(
        private val model: AppModel,
        private val notifier: Notifier,
        private val scheduler: AlarmScheduler,
    ) : ViewModel() {
        val state: StateFlow<AppState> = model.state

        private val mutablePermissions = MutableStateFlow(SystemPermissions())
        val permissions: StateFlow<SystemPermissions> = mutablePermissions.asStateFlow()

        /** Re-read on every resume: both are changed in system Settings. */
        fun refreshPermissions() {
            mutablePermissions.value = SystemPermissions(notifier.canPost, scheduler.canScheduleExact)
        }

        fun soundUri(sound: PrayerAlertSound): Uri? = notifier.soundUri(sound)

        private fun update(
            change: (com.aljaroudi.muntathir.core.app.Preferences) -> com.aljaroudi.muntathir.core.app.Preferences,
        ) = viewModelScope.launch { model.update(change) }

        fun setMethod(method: PrayerMethod) = update { it.copy(prayerMethod = method) }

        fun setImsak(minutes: Int) = update { it.copy(imsakMinutes = minutes.coerceIn(IMSAK_STEPPER)) }

        fun setVisible(
            prayer: PrayerName,
            visible: Boolean,
        ) = update { it.copy(hiddenPrayers = if (visible) it.hiddenPrayers - prayer else it.hiddenPrayers + prayer) }

        fun setPrayerSound(sound: PrayerAlertSound) = update { it.copy(notificationSound = sound) }

        fun setSunsetSound(sound: PrayerAlertSound) = update { it.copy(sunsetSound = sound) }

        fun setOtherSound(sound: PrayerAlertSound) = update { it.copy(otherTimesSound = sound) }

        fun setAlert(
            prayer: PrayerName,
            enabled: Boolean,
            allowed: Boolean,
        ) = viewModelScope.launch { model.setPrayer(prayer, enabled, allowed) }

        fun setAnnouncements(enabled: Boolean) = update { it.copy(announcementNotifications = enabled) }

        fun setEvents(enabled: Boolean) = update { it.copy(calendarEventNotifications = enabled) }

        companion object {
            /** Swift's stepper range (decode still accepts up to 120). */
            val IMSAK_STEPPER = 0..30
        }
    }

/** Navigation out of Settings; detail screens open in the list-detail pane on wide windows. */
class SettingsLinks(
    val onTabs: () -> Unit = {},
    val onHighlightColors: () -> Unit = {},
    val onDownloads: () -> Unit = {},
    val onLocation: () -> Unit = {},
    val onMonthAdjustments: () -> Unit = {},
    val onCredits: () -> Unit = {},
)

/** Swift `SettingsView`, without weather. */
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel,
    links: SettingsLinks,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val permissions by viewModel.permissions.collectAsStateWithLifecycle()
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { viewModel.refreshPermissions() }
    var pendingPrayer by rememberSaveable { mutableStateOf<PrayerName?>(null) }
    var pendingTarget by rememberSaveable { mutableStateOf<AlertTarget?>(null) }
    val requestPermission =
        rememberNotificationPermission { allowed ->
            viewModel.refreshPermissions()
            when (pendingTarget) {
                AlertTarget.Prayer -> pendingPrayer?.let { viewModel.setAlert(it, true, allowed) }
                AlertTarget.Announcements -> if (allowed) viewModel.setAnnouncements(true)
                AlertTarget.Events -> if (allowed) viewModel.setEvents(true)
                null -> Unit
            }
            pendingTarget = null
        }
    val enable: (AlertTarget, PrayerName?) -> Unit = { target, prayer ->
        pendingTarget = target
        pendingPrayer = prayer
        requestPermission()
    }
    val context = LocalContext.current
    val preview = rememberSoundPreview { viewModel.soundUri(it) }
    val preferences = state.preferences
    val locale = currentLocale()

    ScreenScaffold(R.string.settings, modifier, onBack) { padding ->
        LazyColumn(
            state = rememberLazyListState(),
            contentPadding = padding,
            modifier = Modifier.testTag("settings-list"),
        ) {
            item { AppLanguageRow() }
            item { LinkRow(stringResource(R.string.tabs), links.onTabs, "settings-tabs") }
            item { ReadingSizeRow() }
            item { HighlightColorsRow(links.onHighlightColors) }
            item { LinkRow(stringResource(R.string.downloads), links.onDownloads, "settings-downloads") }

            section(R.string.location)
            item {
                LinkRow(
                    stringResource(R.string.location),
                    links.onLocation,
                    "settings-location",
                    stringResource(if (state.location != null) R.string.device_location else R.string.not_selected),
                )
            }
            if (state.location != null) {
                item { SectionFooter(stringResource(R.string.device_location_stays_on_this_device)) }
            }

            section(R.string.prayer_calculations)
            item {
                ChoiceRow(
                    stringResource(R.string.method),
                    PrayerMethod.entries,
                    preferences.prayerMethod,
                    { stringResource(it.title) },
                    viewModel::setMethod,
                    "settings-method",
                )
            }
            item {
                StepperRow(
                    stringResource(R.string.imsak_before_fajr),
                    preferences.imsakMinutes,
                    SettingsViewModel.IMSAK_STEPPER,
                    Formats.number(preferences.imsakMinutes, locale),
                    viewModel::setImsak,
                )
            }
            item { SectionFooter(stringResource(R.string.imsak_is_a_precaution_before_calculated_fajr)) }

            section(R.string.calendar)
            item {
                LinkRow(
                    stringResource(R.string.month_adjustments),
                    links.onMonthAdjustments,
                    "settings-month-adjustments",
                )
            }

            section(R.string.visibility)
            items(PrayerName.entries, key = { "visible-${it.id}" }) { prayer ->
                SwitchRow(
                    stringResource(prayer.title),
                    checked = preferences.isVisible(prayer),
                    enabled = !prayer.isRequired,
                    tag = "visible-${prayer.id}",
                ) { viewModel.setVisible(prayer, it) }
            }
            item { SectionFooter(stringResource(R.string.hiding_a_time_does_not_change_its_notification_s)) }

            section(R.string.notifications)
            if (!permissions.notifications) {
                item { SectionFooter(stringResource(R.string.notifications_are_disabled_enable_them_in_system)) }
            }
            item {
                LinkRow(stringResource(R.string.system_notification_settings), {
                    context.startActivity(
                        Intent(
                            Settings.ACTION_APP_NOTIFICATION_SETTINGS,
                        ).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName),
                    )
                })
            }
            if (!permissions.exactAlarms && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                item {
                    LinkRow(stringResource(R.string.exact_alarms), {
                        context.startActivity(
                            Intent(
                                Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                Uri.fromParts("package", context.packageName, null),
                            ),
                        )
                    }, "settings-exact-alarms")
                }
                item { SectionFooter(stringResource(R.string.exact_alarms_footer)) }
            }
            item {
                SoundRow(
                    stringResource(R.string.prayers),
                    preferences.notificationSound,
                    preview,
                    viewModel::setPrayerSound,
                )
            }
            item {
                SoundRow(
                    stringResource(R.string.sunset),
                    preferences.sunsetSound,
                    preview,
                    viewModel::setSunsetSound,
                )
            }
            item {
                SoundRow(
                    stringResource(R.string.other_times),
                    preferences.otherTimesSound,
                    preview,
                    viewModel::setOtherSound,
                )
            }
            items(PrayerName.entries, key = { "alert-${it.id}" }) { prayer ->
                SwitchRow(
                    stringResource(prayer.title),
                    prayer in preferences.enabledPrayers,
                    tag = "alert-${prayer.id}",
                ) { on ->
                    if (on) enable(AlertTarget.Prayer, prayer) else viewModel.setAlert(prayer, false, true)
                }
            }

            section(R.string.announcement_notifications)
            item {
                SwitchRow(
                    stringResource(R.string.month_confirmations),
                    preferences.announcementNotifications,
                    tag = "settings-announcements",
                ) { on ->
                    if (on) enable(AlertTarget.Announcements, null) else viewModel.setAnnouncements(false)
                }
            }
            item { SectionFooter(stringResource(R.string.alerts_follow_published_month_announcements_afte)) }

            section(R.string.calendar_events)
            item {
                SwitchRow(
                    stringResource(R.string.calendar_events),
                    preferences.calendarEventNotifications,
                    tag = "settings-events",
                ) { on ->
                    if (on) enable(AlertTarget.Events, null) else viewModel.setEvents(false)
                }
            }
            item { SectionFooter(stringResource(R.string.silent_reminders_at_sunset_for_observances_begin)) }

            item { LinkRow(stringResource(R.string.sources_and_licenses), links.onCredits, "settings-credits") }
            item { SectionFooter(stringResource(R.string.settings_backup_footer), Modifier.padding(bottom = 24.dp)) }
        }
    }
}

private fun LazyListScope.section(title: Int) = item { SectionHeader(stringResource(title)) }

@Composable
fun LinkRow(
    title: String,
    onClick: () -> Unit,
    tag: String? = null,
    value: String? = null,
) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = value?.let { { Text(it) } },
        trailingContent = { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null) },
        modifier =
            Modifier.selectable(selected = false, role = Role.Button, onClick = onClick).let {
                if (tag !=
                    null
                ) {
                    it.testTag(tag)
                } else {
                    it
                }
            },
    )
}

@Composable
private fun SwitchRow(
    title: String,
    checked: Boolean,
    enabled: Boolean = true,
    tag: String,
    onChange: (Boolean) -> Unit,
) {
    ListItem(
        headlineContent = { Text(title) },
        trailingContent = { Switch(checked = checked, onCheckedChange = null, enabled = enabled) },
        modifier =
            Modifier
                .toggleable(
                    checked,
                    enabled = enabled,
                    role = Role.Switch,
                    onValueChange = onChange,
                ).testTag(tag),
    )
}

@Composable
private fun StepperRow(
    title: String,
    value: Int,
    range: IntRange,
    display: String,
    onChange: (Int) -> Unit,
) {
    ListItem(
        headlineContent = { Text(title) },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                FilledTonalIconButton(onClick = {
                    onChange(value - 1)
                }, enabled = value > range.first) { Icon(Icons.Outlined.Remove, null) }
                Text(
                    display,
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(horizontal = 12.dp).testTag("imsak-minutes"),
                )
                FilledTonalIconButton(onClick = {
                    onChange(value + 1)
                }, enabled = value < range.last) { Icon(Icons.Outlined.Add, null) }
            }
        },
    )
}

@Composable
private fun <T> ChoiceRow(
    title: String,
    options: List<T>,
    selected: T,
    label: @Composable (T) -> String,
    onSelect: (T) -> Unit,
    tag: String,
    footer: @Composable ((T) -> Unit)? = null,
) {
    var open by remember { mutableStateOf(false) }
    LinkRow(title, { open = true }, tag, label(selected))
    if (open) {
        AlertDialog(
            onDismissRequest = { open = false },
            confirmButton = { TextButton(onClick = { open = false }) { Text(stringResource(R.string.done)) } },
            title = { Text(title) },
            text = {
                LazyColumn {
                    items(options) { option ->
                        ListItem(
                            headlineContent = { Text(label(option)) },
                            leadingContent = { RadioButton(selected = option == selected, onClick = null) },
                            trailingContent = footer?.let { { it(option) } },
                            colors =
                                androidx.compose.material3.ListItemDefaults.colors(
                                    containerColor = androidx.compose.ui.graphics.Color.Transparent,
                                ),
                            modifier =
                                Modifier.fillMaxWidth().selectable(
                                    option == selected,
                                    role = Role.RadioButton,
                                ) { onSelect(option) },
                        )
                    }
                }
            },
        )
    }
}

/** A sound choice; picking a sound previews it, as on iOS. */
@Composable
private fun SoundRow(
    title: String,
    selected: PrayerAlertSound,
    preview: (PrayerAlertSound) -> Unit,
    onSelect: (PrayerAlertSound) -> Unit,
) {
    ChoiceRow(
        title,
        PrayerAlertSound.entries,
        selected,
        { stringResource(it.title) },
        {
            onSelect(it)
            preview(it)
        },
        "sound-$title",
    )
}

/** Plays one sound at a time and stops when the screen leaves (Swift `stopPreview`). */
@Composable
private fun rememberSoundPreview(uri: (PrayerAlertSound) -> Uri?): (PrayerAlertSound) -> Unit {
    val context = LocalContext.current
    val player = remember { mutableStateOf<MediaPlayer?>(null) }
    val generation = remember { mutableIntStateOf(0) }
    DisposableEffect(Unit) {
        onDispose {
            player.value?.release()
            player.value = null
        }
    }
    return { sound ->
        player.value?.release()
        player.value = null
        generation.intValue++
        val source =
            if (sound ==
                PrayerAlertSound.System
            ) {
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            } else {
                uri(sound)
            }
        if (source != null) {
            player.value = runCatching { MediaPlayer.create(context, source)?.apply { start() } }.getOrNull()
        }
    }
}
