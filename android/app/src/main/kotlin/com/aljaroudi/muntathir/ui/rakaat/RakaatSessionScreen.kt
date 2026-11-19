package com.aljaroudi.muntathir.ui.rakaat

import android.Manifest
import android.animation.ValueAnimator
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.compose.CameraXViewfinder
import androidx.camera.core.SurfaceRequest
import androidx.camera.viewfinder.core.ImplementationMode
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.NoPhotography
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.compose.currentStateAsState
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.app.AppTool
import com.aljaroudi.muntathir.core.rakaat.RakaatPreparation
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.currentLocale
import com.aljaroudi.muntathir.ui.navigation.RakaatSessionRoute
import com.aljaroudi.muntathir.ui.navigation.Route
import com.aljaroudi.muntathir.ui.navigation.ToolRoute
import com.aljaroudi.muntathir.ui.theme.MuntathirTheme

/**
 * Swift `RakaatSessionView`: asks for the camera, calibrates, then shows the rakaat count over a dimmed, blurred
 * front-camera preview. Leaving the screen or the app ends the session; an ended session stays ended.
 */
@Composable
fun RakaatSessionScreen(
    route: RakaatSessionRoute,
    open: (Route) -> Unit,
    onBack: () -> Unit,
    viewModel: RakaatSessionViewModel =
        hiltViewModel<RakaatSessionViewModel, RakaatSessionViewModel.Factory>(
            creationCallback = { it.create(route) },
        ),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val surface by viewModel.preview.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val activity = LocalActivity.current
    val view = LocalView.current
    val permission =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission(), viewModel::start)
    LaunchedEffect(Unit) {
        if (viewModel.permissionRequested) return@LaunchedEffect
        viewModel.permissionRequested = true
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            viewModel.start(true)
        } else {
            permission.launch(Manifest.permission.CAMERA)
        }
    }
    // Leaving the app or the screen ends the session; a configuration change keeps it.
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) {
        if (activity?.isChangingConfigurations != true) viewModel.end()
    }
    DisposableEffect(Unit) {
        val window = activity?.window
        val controller = window?.let { WindowCompat.getInsetsController(it, view) }
        val lightBars = controller?.isAppearanceLightStatusBars
        controller?.isAppearanceLightStatusBars = false
        onDispose {
            if (lightBars != null) controller?.isAppearanceLightStatusBars = lightBars
            if (activity?.isChangingConfigurations != true) viewModel.end()
        }
    }
    if (!state.ended) {
        // The phone lies flat, so keep the screen on and don't let it rotate under the count. Android 16+ ignores
        // the lock on large screens; a rotation there is a configuration change, which keeps the session.
        // Dim from the start, before the camera measures its baseline: changing screen light after calibration
        // would shift the measured light. Hiding the system bars keeps notification icons out of sight.
        DisposableEffect(Unit) {
            val window = activity?.window
            val keepOn = view.keepScreenOn
            val orientation = activity?.requestedOrientation
            val brightness = window?.attributes?.screenBrightness
            val controller = window?.let { WindowCompat.getInsetsController(it, view) }
            val barsBehavior = controller?.systemBarsBehavior
            view.keepScreenOn = true
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LOCKED
            window?.attributes = window.attributes.apply { screenBrightness = SESSION_BRIGHTNESS }
            controller?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller?.hide(WindowInsetsCompat.Type.systemBars())
            onDispose {
                view.keepScreenOn = keepOn
                if (orientation != null) activity?.requestedOrientation = orientation
                if (brightness != null) window.attributes = window.attributes.apply { screenBrightness = brightness }
                controller?.show(WindowInsetsCompat.Type.systemBars())
                if (barsBehavior != null) controller.systemBarsBehavior = barsBehavior
            }
        }
    }
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val reading =
        rememberQiblaReading(viewModel.qibla, active = state.preparing && lifecycle.isAtLeast(Lifecycle.State.RESUMED))
    val leave = {
        viewModel.end()
        onBack()
    }

    MuntathirTheme(darkTheme = true) {
        Box(Modifier.fillMaxSize().background(Color.Black).testTag("rakaat-prayer-screen")) {
            SessionBackground(state, surface.takeUnless { state.ended }, route.target)
            SessionScaffold(
                preparing = state.preparing,
                hint = { RakaatQiblaHint(reading, Color.White, Modifier.padding(16.dp)) },
                saveFailed = state.complete && state.saveFailed,
                onRetrySave = viewModel::retrySave,
                onBack = leave,
            ) {
                SessionContent(
                    state,
                    onTryAgain = leave,
                    onOpenSettings = {
                        context.startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", context.packageName, null),
                            ),
                        )
                    },
                    onTasbih = { open(ToolRoute(AppTool.Tasbih)) },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SessionScaffold(
    preparing: Boolean,
    hint: @Composable () -> Unit,
    saveFailed: Boolean,
    onRetrySave: () -> Unit,
    onBack: () -> Unit,
    content: @Composable () -> Unit,
) {
    Scaffold(
        containerColor = Color.Transparent,
        contentColor = Color.White,
        topBar = {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                TopAppBar(
                    title = { Text(stringResource(R.string.rakaat_tracker)) },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(
                                Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = stringResource(R.string.back),
                            )
                        }
                    },
                    colors =
                        TopAppBarDefaults.topAppBarColors(
                            containerColor = Color.Transparent,
                            titleContentColor = Color.White,
                            navigationIconContentColor = Color.White,
                        ),
                )
                if (preparing) hint()
            }
        },
        bottomBar = {
            if (saveFailed) {
                Surface(Modifier.fillMaxWidth()) {
                    Column(
                        Modifier.navigationBarsPadding().padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            stringResource(R.string.unable_to_save_or_load_prayer_history),
                            textAlign = TextAlign.Center,
                        )
                        TextButton(onClick = onRetrySave) { Text(stringResource(R.string.try_again)) }
                    }
                }
            }
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(32.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) { content() }
    }
}

@Composable
private fun SessionContent(
    state: RakaatSessionState,
    onTryAgain: () -> Unit,
    onOpenSettings: () -> Unit,
    onTasbih: () -> Unit,
) {
    val failure = state.update?.failure
    val title = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
    val body = MaterialTheme.typography.bodyLarge.copy(textAlign = TextAlign.Center)
    when {
        failure != null -> {
            val dark = failure == RakaatPreparation.Failure.TooDark
            Icon(Icons.Outlined.WarningAmber, contentDescription = null, Modifier.size(40.dp))
            Text(
                stringResource(if (dark) R.string.too_dark_to_count_reliably else R.string.unable_to_calibrate),
                style = title,
            )
            Text(
                stringResource(
                    if (dark) {
                        R.string.increase_the_light_and_keep_the_camera_uncovered
                    } else {
                        R.string.keep_the_phone_still_in_steady_light_then_try_ag
                    },
                ),
                style = body,
            )
            OutlinedButton(onClick = onTryAgain) { Text(stringResource(R.string.try_again)) }
        }

        state.denied || state.failed -> {
            Icon(Icons.Outlined.NoPhotography, contentDescription = null, Modifier.size(40.dp))
            Text(stringResource(R.string.camera_unavailable), style = title)
            if (state.denied) {
                Text(stringResource(R.string.allow_camera_access_in_settings_to_count_sujood), style = body)
                OutlinedButton(onClick = onOpenSettings) { Text(stringResource(R.string.open_settings)) }
            } else {
                Text(stringResource(R.string.camera_capture_ended_start_a_new_session_to_try), style = body)
            }
        }

        state.preparing -> {
            CircularProgressIndicator(color = Color.White)
            Text(stringResource(R.string.keep_the_camera_uncovered_in_steady_light_while), style = body)
        }

        else -> {
            val label = stringResource(R.string.x_rakaat, state.rakaat)
            Box(
                Modifier.clearAndSetSemantics {
                    contentDescription = label
                    testTag = "rakaat-count"
                },
            ) {
                BasicText(
                    Formats.number(state.rakaat, currentLocale()),
                    style =
                        TextStyle(
                            color = Color.White,
                            fontSize = 136.sp,
                            fontFeatureSettings = "tnum",
                            textAlign = TextAlign.Center,
                            shadow = Shadow(Color.Black.copy(alpha = 0.6f), Offset.Zero, blurRadius = 16f),
                        ),
                    maxLines = 1,
                    autoSize = TextAutoSize.StepBased(minFontSize = 40.sp, maxFontSize = 136.sp),
                )
            }
            if (state.complete) {
                Button(onClick = onTasbih, modifier = Modifier.testTag("rakaat-complete")) {
                    Text(stringResource(R.string.start_tasbih), style = MaterialTheme.typography.titleMedium)
                }
            }
        }
    }
}

/**
 * The dimmed live preview, the lower-half scrim during sujood, the green milestone tint (multiplied, so it darkens
 * rather than adds light that could reflect into the camera) and the completion overlay.
 */
@Composable
private fun SessionBackground(
    state: RakaatSessionState,
    surface: SurfaceRequest?,
    target: Int,
) {
    val blurs = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
    val animates = remember { ValueAnimator.areAnimatorsEnabled() }
    val sujood by animateFloatAsState(
        if (state.showsSujoodProgress) 0.5f else 0f,
        if (animates) tween(700, easing = FastOutSlowInEasing) else snap(),
        label = "sujood",
    )
    val milestone = state.showsMilestoneTint(target)
    val complete = state.complete
    Box(
        Modifier
            .fillMaxSize()
            .clearAndSetSemantics {}
            .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen),
    ) {
        if (surface != null) {
            CameraXViewfinder(
                surfaceRequest = surface,
                // A TextureView, so the blur and blend modes apply to it.
                implementationMode = ImplementationMode.EMBEDDED,
                modifier = Modifier.fillMaxSize().then(if (blurs) Modifier.blur(24.dp) else Modifier),
            )
        }
        Canvas(Modifier.fillMaxSize()) {
            drawRect(Color.Black.copy(alpha = if (blurs) 0.5f else 0.7f))
            if (sujood > 0f) {
                val top = size.height * (1 - sujood)
                val scrim = Color.Black.copy(alpha = 0.45f)
                drawRect(
                    Brush.verticalGradient(
                        0f to Color.Transparent,
                        0.25f to scrim,
                        1f to scrim,
                        startY = top,
                        endY = size.height,
                    ),
                    topLeft = Offset(0f, top),
                    size = Size(size.width, size.height - top),
                )
            }
            if (milestone) drawRect(GREEN.copy(alpha = 0.65f), blendMode = BlendMode.Multiply)
            if (complete) drawRect(GREEN.copy(alpha = 0.32f))
        }
    }
}

/** Apple's system green. */
private val GREEN = Color(0xFF34C759)

/** The window brightness during a session; matches iOS's 20% cap. */
internal const val SESSION_BRIGHTNESS = 0.2f
