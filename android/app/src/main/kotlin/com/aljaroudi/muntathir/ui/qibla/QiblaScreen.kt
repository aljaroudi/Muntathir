package com.aljaroudi.muntathir.ui.qibla

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.icu.text.MeasureFormat
import android.icu.text.NumberFormat
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import android.icu.util.ULocale
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.LocationOff
import androidx.compose.material.icons.filled.RotateLeft
import androidx.compose.material.icons.filled.RotateRight
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleStartEffect
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.qibla.QiblaAlignment
import com.aljaroudi.muntathir.core.qibla.QiblaSession.Status
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.currentLocale
import java.util.Locale
import kotlin.math.abs

private val LOCATION_PERMISSIONS =
    arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)

/**
 * Swift `QiblaView`: its own precise session while the screen is visible and started (a fresh one after returning
 * from the background), the map or compass dial with the heading ring, the turn cue and haptics.
 */
@Composable
fun QiblaScreen(
    onBack: (() -> Unit)?,
    viewModel: QiblaViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val activity = LocalActivity.current
    LifecycleStartEffect(viewModel) {
        viewModel.start()
        onStopOrDispose { viewModel.stop() }
    }

    // Asked once per visit; afterwards the Settings state offers it again while the system still allows asking.
    var asked by rememberSaveable { mutableStateOf(false) }
    var asking by rememberSaveable { mutableStateOf(false) }
    var canAsk by rememberSaveable { mutableStateOf(true) }
    val permissions =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            asking = false
            canAsk = !context.isPrecise() &&
                activity != null &&
                ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.ACCESS_FINE_LOCATION)
            viewModel.start()
        }

    fun requestPrecise() {
        asking = true
        permissions.launch(LOCATION_PERMISSIONS)
    }
    LaunchedEffect(Unit) {
        if (!asked && !context.isPrecise()) {
            asked = true
            requestPrecise()
        }
    }

    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val lifecycleState by lifecycle.currentStateFlow.collectAsStateWithLifecycle()
    val resumed = lifecycleState.isAtLeast(Lifecycle.State.RESUMED)
    QiblaHaptics(
        if (resumed) {
            state.alignment?.feedback(
                state.aligned,
            ) ?: QiblaAlignment.Feedback.None
        } else {
            QiblaAlignment.Feedback.None
        },
    )

    val fix = state.reading.fix
    val bearing = state.bearing
    if (fix == null || bearing == null) {
        ScreenScaffold(R.string.qibla, onBack = onBack) { padding ->
            LocationRequired(
                status = if (asking) Status.Locating else state.reading.status,
                canAsk = canAsk,
                onAllowPrecise = ::requestPrecise,
                onOpenSettings = { context.openAppSettings() },
                onRetry = viewModel::start,
                modifier = Modifier.padding(padding),
            )
        }
        return
    }

    Box(Modifier.fillMaxSize()) {
        val heading = state.reading.heading?.degrees
        val description = stringResource(R.string.current_location_and_direction_to_the_kaaba)
        // Like iOS, the map and the dial are drawn left to right in every language.
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
            Box(
                Modifier
                    .fillMaxSize()
                    .testTag("qibla-map-ready")
                    .semantics { contentDescription = description },
                contentAlignment = Alignment.Center,
            ) {
                if (viewModel.mapConfig.enabled) {
                    QiblaGoogleMap(fix, state.aligned, Modifier.fillMaxSize())
                } else {
                    QiblaDial(bearing, heading, state.aligned, Modifier.fillMaxSize())
                }
                QiblaUserDot()
                if (heading != null) {
                    // The map is north-up, so the arrow turns; the dial turns instead, so the device points up.
                    QiblaHeadingRing(if (viewModel.mapConfig.enabled) heading else 0.0, state.aligned)
                }
            }
        }
        QiblaTopBar(onBack)
        AlignmentBadge(
            state.alignment,
            state.aligned,
            Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(start = 24.dp, end = 24.dp, bottom = 24.dp),
        )
    }
}

/** Over the map: no bar background, like iOS's hidden toolbar background, with a scrim for legibility. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun QiblaTopBar(onBack: (() -> Unit)?) {
    TopAppBar(
        title = { Text(stringResource(R.string.qibla)) },
        navigationIcon = {
            if (onBack != null) {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                }
            }
        },
        colors =
            TopAppBarDefaults.topAppBarColors(
                containerColor = Color.Transparent,
                titleContentColor = Color.White,
                navigationIconContentColor = Color.White,
            ),
        modifier =
            Modifier.background(
                Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.55f), Color.Transparent)),
            ),
    )
}

@Composable
private fun AlignmentBadge(
    alignment: QiblaAlignment?,
    aligned: Boolean,
    modifier: Modifier = Modifier,
) {
    val locale = currentLocale()
    Surface(
        modifier,
        shape = MaterialTheme.shapes.extraLarge,
        color = MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.92f),
        tonalElevation = 3.dp,
    ) {
        Row(
            Modifier
                .semantics(mergeDescendants = true) {}
                .then(if (aligned) Modifier.testTag("qibla-aligned") else Modifier)
                .padding(horizontal = 20.dp, vertical = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val style = MaterialTheme.typography.titleMedium
            when {
                aligned -> {
                    Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = QiblaGreen)
                    Text(stringResource(R.string.aligned_with_kaaba), style = style)
                }

                alignment != null -> {
                    val left = alignment.error < 0
                    // Counterclockwise for left in every language, as on iOS.
                    @Suppress("DEPRECATION")
                    Icon(if (left) Icons.Filled.RotateLeft else Icons.Filled.RotateRight, contentDescription = null)
                    Text(stringResource(if (left) R.string.turn_left else R.string.turn_right), style = style)
                    Text(degrees(abs(alignment.error), locale), style = style)
                }

                else -> {
                    Icon(Icons.Filled.LocationOff, contentDescription = null)
                    Text(stringResource(R.string.compass_unavailable), style = style)
                }
            }
        }
    }
}

/** Swift's narrow `Measurement<UnitAngle>` with no fraction digits, e.g. "37°". */
private fun degrees(
    value: Double,
    locale: Locale,
): String {
    val number = NumberFormat.getInstance(locale).apply { maximumFractionDigits = 0 }
    return MeasureFormat
        .getInstance(ULocale.forLocale(locale), MeasureFormat.FormatWidth.NARROW, number)
        .format(Measure(Math.round(value), MeasureUnit.DEGREE))
}

/** Swift's `ContentUnavailableView` for a missing fix. */
@Composable
private fun LocationRequired(
    status: Status,
    canAsk: Boolean,
    onAllowPrecise: () -> Unit,
    onOpenSettings: () -> Unit,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier.fillMaxSize().padding(24.dp).testTag("qibla-location-required"),
        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            Icons.Outlined.LocationOn,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            stringResource(R.string.precise_location_required),
            style = MaterialTheme.typography.titleLarge,
            textAlign = TextAlign.Center,
        )
        Text(
            stringResource(
                when (status) {
                    Status.Settings -> R.string.allow_location_access_and_precise_location_in_se
                    Status.Failed -> R.string.could_not_get_a_precise_current_location_try_aga
                    else -> R.string.finding_your_precise_current_location
                },
            ),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.widthIn(max = 400.dp),
        )
        if (status == Status.Locating || status == Status.Ready) {
            CircularProgressIndicator()
        } else {
            if (status == Status.Settings) {
                // Android 12+ offers upgrading approximate access to precise from this prompt.
                if (canAsk) Button(onClick = onAllowPrecise) { Text(stringResource(R.string.allow_precise_location)) }
                FilledTonalButton(onClick = onOpenSettings) { Text(stringResource(R.string.open_settings)) }
            }
            TextButton(onClick = onRetry) { Text(stringResource(R.string.retry)) }
        }
    }
}

private fun Context.isPrecise(): Boolean =
    ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED

private fun Context.openAppSettings() {
    startActivity(
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
    )
}
