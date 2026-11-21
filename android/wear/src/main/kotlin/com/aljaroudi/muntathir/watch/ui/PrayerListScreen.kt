package com.aljaroudi.muntathir.watch.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.TransformingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberTransformingLazyColumnState
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ColorScheme
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.Text
import androidx.wear.compose.material3.dynamicColorScheme
import androidx.wear.compose.material3.lazy.rememberTransformationSpec
import androidx.wear.compose.material3.lazy.transformedHeight
import androidx.wear.tooling.preview.devices.WearDevices
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.prayer.PrayerMethod
import com.aljaroudi.muntathir.core.prayer.PrayerName
import com.aljaroudi.muntathir.core.prayer.WidgetPrayerSettings
import com.aljaroudi.muntathir.core.wear.WatchCalendar
import com.aljaroudi.muntathir.core.wear.WatchSnapshot
import com.aljaroudi.muntathir.watch.Formats
import com.aljaroudi.muntathir.watch.R
import com.aljaroudi.muntathir.watch.title
import kotlinx.coroutines.delay
import java.time.Instant
import kotlin.time.Duration.Companion.milliseconds

/** The iOS Watch tint (`.mint`), unless the watch offers dynamic colors. */
private val Mint = Color(0xFF5CC9A3)

@Composable
fun WatchTheme(content: @Composable () -> Unit) {
    val scheme = dynamicColorScheme(LocalContext.current) ?: ColorScheme(primary = Mint)
    MaterialTheme(colorScheme = scheme, content = content)
}

/** What the store holds once read: the phone's last snapshot, or none yet. */
data class Stored(
    val snapshot: WatchSnapshot?,
)

/**
 * Swift `WatchPrayerView`: today's prayers with the next one highlighted, or how to sync from the phone.
 * [stored] is null while the saved snapshot is still being read.
 */
@Composable
fun PrayerListScreen(
    stored: Stored?,
    onOpenPhone: () -> Unit,
) {
    // Ticks at each minute, like Swift's `TimelineView(.periodic(by: 60))`.
    val now by produceState(Instant.now()) {
        while (true) {
            delay((60_000 - System.currentTimeMillis() % 60_000).milliseconds)
            value = Instant.now()
        }
    }
    val snapshot = stored?.snapshot
    val state = rememberTransformingLazyColumnState()
    // Rows shrink and fade toward the round edge instead of being clipped.
    val spec = rememberTransformationSpec()
    val locale = Formats.locale(LocalContext.current)
    AppScaffold {
        ScreenScaffold(scrollState = state) { padding ->
            TransformingLazyColumn(state = state, contentPadding = padding) {
                item { ListHeader { Text(stringResource(R.string.prayer_times)) } }
                val location = snapshot?.prayers?.location
                when {
                    stored == null -> {}

                    snapshot == null || location == null -> {
                        item { Message(stringResource(R.string.sync_from_phone)) }
                        item { Button(onClick = onOpenPhone) { Text(stringResource(R.string.open_on_phone)) } }
                    }

                    else -> {
                        val prayers = snapshot.prayers.prayers(now)
                        val next = snapshot.prayers.nextPrayer(now)
                        if (prayers.isEmpty()) {
                            item { Message(stringResource(R.string.prayer_times_unavailable_for_this_location_and_d)) }
                        }
                        items(prayers.size, key = { prayers[it].name }) { index ->
                            val prayer = prayers[index]
                            PrayerRow(
                                name = stringResource(prayer.name.title),
                                time = Formats.time(prayer.time, location.zone, locale),
                                isNext = prayer.time == next?.time,
                                modifier =
                                    Modifier
                                        .transformedHeight(this, spec)
                                        .graphicsLayer { with(spec) { applyContainerTransformation(scrollProgress) } },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PrayerRow(
    name: String,
    time: String,
    isNext: Boolean,
    modifier: Modifier = Modifier,
) {
    val color = if (isNext) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface
    Row(
        modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 6.dp)
            .clearAndSetSemantics { contentDescription = "$name $time" },
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(name, style = MaterialTheme.typography.titleMedium, color = color)
        Text(time, style = MaterialTheme.typography.bodyLarge, color = color)
    }
}

@Composable
private fun Message(text: String) {
    Text(
        text,
        Modifier.fillMaxWidth().padding(horizontal = 8.dp),
        style = MaterialTheme.typography.bodySmall,
        textAlign = TextAlign.Center,
    )
}

@Preview(device = WearDevices.LARGE_ROUND, showSystemUi = true)
@Composable
private fun PrayerListPreview() {
    val mecca = SavedLocation(21.4225, 39.8262, "Asia/Riyadh")
    val snapshot =
        WatchSnapshot(
            prayers = WidgetPrayerSettings(mecca, PrayerMethod.Tehran, setOf(PrayerName.Asr, PrayerName.Isha)),
            calendar = WatchCalendar(mecca.timeZoneID),
        )
    WatchTheme { PrayerListScreen(Stored(snapshot), onOpenPhone = {}) }
}

@Preview(device = WearDevices.SMALL_ROUND, showSystemUi = true)
@Composable
private fun WaitingForPhonePreview() {
    WatchTheme { PrayerListScreen(Stored(null), onOpenPhone = {}) }
}
