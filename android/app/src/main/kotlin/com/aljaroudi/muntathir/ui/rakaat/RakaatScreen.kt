package com.aljaroudi.muntathir.ui.rakaat

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.prayer.PrayerName
import com.aljaroudi.muntathir.core.progress.PrayerProgress
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.components.title
import com.aljaroudi.muntathir.ui.navigation.RakaatSessionRoute
import com.aljaroudi.muntathir.ui.navigation.Route

/** Swift `RakaatTrackerView`: choose rakaat and prayer, then open a [RakaatSessionRoute]. */
@Composable
fun RakaatScreen(
    open: (Route) -> Unit,
    onBack: (() -> Unit)?,
    viewModel: RakaatSetupViewModel = hiltViewModel(),
) {
    var choosing by rememberSaveable { mutableStateOf<Int?>(null) }
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val reading = rememberQiblaReading(viewModel.qibla, active = lifecycle.isAtLeast(Lifecycle.State.RESUMED))
    val locale = currentLocale()
    ScreenScaffold(R.string.rakaat_tracker, onBack = onBack) { padding ->
        Box(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(padding)
                .padding(24.dp),
            contentAlignment = Alignment.TopCenter,
        ) {
            Column(
                Modifier.widthIn(max = 520.dp).fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        stringResource(R.string.choose_rakaat),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        for (number in 2..4) {
                            val label = stringResource(R.string.x_rakaat, number)
                            Button(
                                onClick = { choosing = number },
                                modifier =
                                    Modifier
                                        .weight(1f)
                                        .heightIn(min = 72.dp)
                                        .testTag("rakaat-target-$number")
                                        .semantics { contentDescription = label },
                            ) {
                                Text(Formats.number(number, locale), style = MaterialTheme.typography.displaySmall)
                            }
                        }
                    }
                }
                RakaatQiblaHint(reading, MaterialTheme.colorScheme.primary)
                Column(
                    Modifier
                        .fillMaxWidth()
                        .background(MaterialTheme.colorScheme.surfaceContainerHigh, RoundedCornerShape(24.dp))
                        .padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    RakaatPlacementDiagram()
                    Text(
                        stringResource(R.string.place_the_phone_screen_up_with_the_front_camera),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }
    choosing?.let { target ->
        PrayerChoice(target, onDismiss = { choosing = null }) { prayer ->
            choosing = null
            open(RakaatSessionRoute(target, prayer))
        }
    }
}

/** Swift's "Prayer" confirmation dialog: the obligatory prayers with [target] rakaat, or Other. */
@Composable
private fun PrayerChoice(
    target: Int,
    onDismiss: () -> Unit,
    onChoose: (PrayerName?) -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.prayer)) },
        text = {
            Column {
                for (prayer in PrayerProgress.choices(target)) {
                    ChoiceRow(stringResource(prayer.title), "rakaat-prayer-${prayer.id}") { onChoose(prayer) }
                }
                ChoiceRow(stringResource(R.string.other), "rakaat-prayer-other") { onChoose(null) }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun ChoiceRow(
    text: String,
    tag: String,
    onClick: () -> Unit,
) {
    ListItem(
        headlineContent = { Text(text) },
        modifier = Modifier.testTag(tag).clickable(onClick = onClick),
        colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
    )
}
