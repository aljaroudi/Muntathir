package com.aljaroudi.muntathir.ui.tasbih

import android.os.Build
import android.provider.Settings
import android.view.HapticFeedbackConstants
import androidx.activity.compose.LocalActivity
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.tasbih.BeadPoint
import com.aljaroudi.muntathir.core.tasbih.TasbihBeadLoop
import com.aljaroudi.muntathir.core.tasbih.TasbihSession
import com.aljaroudi.muntathir.ui.components.Formats
import com.aljaroudi.muntathir.ui.components.ScreenScaffold
import com.aljaroudi.muntathir.ui.components.currentLocale
import kotlinx.coroutines.delay
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.roundToInt
import kotlin.math.tan
import kotlin.time.Duration.Companion.seconds

/**
 * Swift `TasbihView`. Leaving the screen (back, or switching away when Tasbih is a tab) starts the next visit at
 * zero, like iOS `onDisappear`; a configuration change or backgrounding keeps the round.
 */
@Composable
fun TasbihScreen(
    onBack: (() -> Unit)?,
    viewModel: TasbihViewModel = hiltViewModel(),
) {
    val session by viewModel.session.collectAsStateWithLifecycle()
    val activity = LocalActivity.current
    DisposableEffect(viewModel) {
        onDispose { if (activity?.isChangingConfigurations != true) viewModel.reset() }
    }
    TasbihContent(session, viewModel::advance, onBack)
}

@Composable
fun TasbihContent(
    session: TasbihSession,
    onAdvance: () -> Unit,
    onBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
    reduceMotion: Boolean = reducedMotion(),
) {
    ScreenScaffold(R.string.tasbih, modifier, onBack) { padding ->
        Box(Modifier.fillMaxSize().padding(padding).padding(24.dp), contentAlignment = Alignment.Center) {
            BeadStage(session, onAdvance, reduceMotion, Modifier.widthIn(max = 560.dp).fillMaxSize())
        }
    }
}

/** The count and phrase between the rear and front strands of the loop, which a downward pull advances. */
@Composable
private fun BeadStage(
    session: TasbihSession,
    onAdvance: () -> Unit,
    reduceMotion: Boolean,
    modifier: Modifier = Modifier,
) {
    val view = LocalView.current
    val current by rememberUpdatedState(session)
    val advance by rememberUpdatedState(onAdvance)
    val reduced by rememberUpdatedState(reduceMotion)
    var pull by remember { mutableFloatStateOf(0f) }
    var settling by remember { mutableStateOf(false) }
    // Every visit starts at zero with the hint; one restored mid-round (a configuration change) doesn't need it.
    var showingHint by remember { mutableStateOf(session.total == 0) }

    LaunchedEffect(Unit) {
        if (!showingHint) return@LaunchedEffect
        delay(4.seconds)
        showingHint = false
    }
    // Drags are ignored while the beads settle; counted on the frame clock so tests can drive it.
    LaunchedEffect(settling) {
        if (!settling) return@LaunchedEffect
        val start = withFrameMillis { it }
        do {
            val now = withFrameMillis { it }
        } while (now - start < SETTLE_MILLIS)
        settling = false
    }
    LifecycleEventEffect(Lifecycle.Event.ON_PAUSE) {
        pull = 0f
        settling = false
    }

    fun settle() {
        settling = !reduced
        pull = 0f
    }

    fun count() {
        val previous = current
        val next = previous.advanced()
        if (next.total == previous.total) return
        view.performHapticFeedback(
            if (next.phrase ==
                previous.phrase
            ) {
                HapticFeedbackConstants.CLOCK_TICK
            } else {
                confirm()
            },
        )
        advance()
        showingHint = false
    }

    val target = session.total + if (reduceMotion) 0f else pull
    val phase = remember { Animatable(target) }
    LaunchedEffect(target) {
        if (settling && !reduceMotion) {
            phase.animateTo(target, tween(SETTLE_ANIMATION_MILLIS, easing = EaseOut))
        } else {
            phase.snapTo(target)
        }
    }

    val locale = currentLocale()
    val label = stringResource(R.string.count_one_bead)
    val state =
        "${session.phrase} ${Formats.number(session.count, locale)} / ${Formats.number(session.target, locale)}"

    BoxWithConstraints(modifier) {
        val width = constraints.maxWidth.toFloat()
        val height = constraints.maxHeight.toFloat()
        Canvas(Modifier.fillMaxSize().blur(3.dp, BlurredEdgeTreatment.Unbounded).alpha(REAR_ALPHA)) {
            drawBeads(phase.value, front = false)
        }
        Column(
            Modifier.align(Alignment.Center),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            BeadCount(session.total, reduceMotion)
            if (session.complete) {
                Icon(
                    Icons.Filled.Check,
                    contentDescription = stringResource(R.string.count_complete),
                    modifier = Modifier.size(48.dp).testTag("tasbih-complete"),
                    tint = MaterialTheme.colorScheme.primary,
                )
            } else {
                Text(
                    session.phrase,
                    modifier = Modifier.padding(horizontal = 16.dp).testTag("tasbih-phrase"),
                    style = MaterialTheme.typography.displaySmall,
                    textAlign = TextAlign.Center,
                )
            }
        }
        Canvas(Modifier.fillMaxSize()) { drawBeads(phase.value, front = true) }
        Box(
            Modifier
                .fillMaxSize()
                .semantics {
                    if (session.complete) {
                        hideFromAccessibility()
                    } else {
                        contentDescription = label
                        stateDescription = state
                        role = Role.Button
                        onClick {
                            if (!settling && !current.complete) {
                                count()
                                settle()
                            }
                            true
                        }
                    }
                }.testTag("tasbih-beads")
                .pointerInput(Unit) {
                    detectPull(
                        onPull = { dx, dy ->
                            if (!settling && !current.complete) pull = TasbihSession.pullProgress(dx, dy)
                        },
                        onRelease = { dx, dy ->
                            if (!settling && !current.complete) {
                                if (TasbihSession.acceptsPull(dx, dy)) count()
                                settle()
                            } else if (pull != 0f) {
                                settle()
                            }
                        },
                        onCancel = { if (pull != 0f) settle() },
                    )
                },
        )
        if (showingHint) SwipeHint(width, height, reduceMotion, Modifier.align(AbsoluteAlignment.TopLeft))
    }
}

@Composable
private fun BeadCount(
    total: Int,
    reduceMotion: Boolean,
) {
    val locale = currentLocale()
    AnimatedContent(
        targetState = total,
        modifier = Modifier.clipToBounds(),
        transitionSpec = {
            if (reduceMotion) {
                EnterTransition.None togetherWith ExitTransition.None
            } else {
                val spec = tween<Float>(COUNT_ANIMATION_MILLIS, easing = EaseOut)
                (slideInVertically(tween(COUNT_ANIMATION_MILLIS, easing = EaseOut)) { -it } + fadeIn(spec)) togetherWith
                    (slideOutVertically(tween(COUNT_ANIMATION_MILLIS, easing = EaseOut)) { it } + fadeOut(spec))
            }
        },
        contentAlignment = Alignment.Center,
        label = "count",
    ) { value ->
        Text(
            Formats.number(TasbihSession(value).count, locale),
            modifier = Modifier.testTag("tasbih-count"),
            style = MaterialTheme.typography.displaySmall.copy(fontFeatureSettings = "tnum"),
        )
    }
}

/** A hand over the front strand that pulls down for the first seconds of a visit. */
@Composable
private fun SwipeHint(
    width: Float,
    height: Float,
    reduceMotion: Boolean,
    modifier: Modifier = Modifier,
) {
    val bounce: State<Float>? =
        if (reduceMotion) {
            null
        } else {
            rememberInfiniteTransition(label = "hint").animateFloat(
                initialValue = 0f,
                targetValue = 0f,
                animationSpec =
                    infiniteRepeatable(
                        keyframes {
                            durationMillis = 2000
                            0f at 0 using EaseInOut
                            HINT_TRAVEL at 1300
                            HINT_TRAVEL at 1600
                            0f at 1601
                        },
                    ),
                label = "hint",
            )
        }
    Icon(
        Icons.Filled.TouchApp,
        contentDescription = stringResource(R.string.pull_a_bead_down_to_count),
        modifier =
            modifier
                // The loop is drawn the same way in both layout directions, so the hand is placed absolutely.
                .absoluteOffset {
                    val half = HINT_SIZE.toPx() / 2
                    val travel = (bounce?.value ?: 0f).dp.toPx()
                    IntOffset(
                        (width / 2 + height * 0.11f - half).roundToInt(),
                        (height * 0.35f - half + travel).roundToInt(),
                    )
                }.size(HINT_SIZE)
                .background(MaterialTheme.colorScheme.surfaceContainerHigh, CircleShape)
                .padding(12.dp)
                .testTag("tasbih-swipe-hint"),
        tint = MaterialTheme.colorScheme.onSurface,
    )
}

/**
 * Reports a drag's translation in dp from the touch-down point once it has moved [MIN_DRAG], then its release or
 * cancellation. Taps are left alone.
 */
private suspend fun PointerInputScope.detectPull(
    onPull: (dx: Double, dy: Double) -> Unit,
    onRelease: (dx: Double, dy: Double) -> Unit,
    onCancel: () -> Unit,
) {
    val minimum = MIN_DRAG.toPx()
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        var dragging = false
        try {
            while (true) {
                val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id }
                if (change == null) {
                    if (dragging) onCancel()
                    break
                }
                val translation = change.position - down.position
                if (!dragging && translation.getDistance() >= minimum) dragging = true
                val dx =
                    translation.x
                        .toDp()
                        .value
                        .toDouble()
                val dy =
                    translation.y
                        .toDp()
                        .value
                        .toDouble()
                if (!change.pressed) {
                    if (dragging) onRelease(dx, dy)
                    break
                }
                if (dragging) {
                    change.consume()
                    onPull(dx, dy)
                }
            }
        } catch (cancelled: CancellationException) {
            if (dragging) onCancel()
            throw cancelled
        }
    }
}

/** Draws one layer of Swift `TasbihBeadScene`: the beads and cord on its side of the loop, in perspective. */
private fun DrawScope.drawBeads(
    phase: Float,
    front: Boolean,
) {
    val focal = size.height / 2 / tan(FIELD_OF_VIEW / 2)

    fun scale(z: Float) = focal / (CAMERA_Z - z)

    fun project(point: BeadPoint) =
        Offset(
            size.width / 2 + point.x * scale(point.z),
            size.height / 2 - (point.y - CAMERA_Y) * scale(point.z),
        )

    var previous = TasbihBeadLoop.position(0f)
    for (index in 1..TasbihBeadLoop.CORD_SAMPLES) {
        val next = TasbihBeadLoop.position(index.toFloat() / TasbihBeadLoop.CORD_SAMPLES)
        val z = (previous.z + next.z) / 2
        val alpha = TasbihBeadLoop.opacity(z, front)
        if (alpha > 0f) {
            drawLine(
                CORD,
                project(previous),
                project(next),
                strokeWidth = 2 * TasbihBeadLoop.CORD_RADIUS * scale(z),
                cap = StrokeCap.Round,
                alpha = alpha,
            )
        }
        previous = next
    }
    val beads = List(TasbihBeadLoop.BEAD_COUNT) { it to TasbihBeadLoop.bead(it, phase) }.sortedBy { it.second.z }
    for ((index, point) in beads) {
        val alpha = TasbihBeadLoop.opacity(point.z, front)
        if (alpha <= 0f) continue
        val radius = TasbihBeadLoop.BEAD_RADIUS * scale(point.z)
        val center = project(point)
        val shades = BEAD_SHADES[index % BEAD_SHADES.size]
        // Lit from the upper left and front, like the scene's key light.
        val brush =
            Brush.radialGradient(
                0f to shades.light,
                0.45f to shades.base,
                1f to shades.dark,
                center = center + Offset(-0.35f * radius, -0.4f * radius),
                radius = 1.45f * radius,
            )
        drawCircle(brush, radius, center, alpha)
    }
}

private class BeadShades(
    val base: Color,
) {
    val light = lerp(base, Color(0xFFFFE3C2), 0.5f)
    val dark = lerp(base, Color.Black, 0.6f)
}

// Swift's bead material, a little lighter for every fourth bead.
private val BEAD_SHADES = List(4) { BeadShades(Color(0.43f + it * 0.025f, 0.24f + it * 0.025f, 0.12f + it * 0.025f)) }
private val CORD = Color(0.70f, 0.54f, 0.32f)

private const val CAMERA_Z = 3.2f
private const val CAMERA_Y = 0.025f

// 51.5° vertical field of view, in radians.
private const val FIELD_OF_VIEW = 0.898845f
private const val REAR_ALPHA = 0.8f
private const val SETTLE_MILLIS = 220L
private const val SETTLE_ANIMATION_MILLIS = 180
private const val COUNT_ANIMATION_MILLIS = 200
private const val HINT_TRAVEL = 56f
private val HINT_SIZE = 56.dp
private val MIN_DRAG = 8.dp

private fun confirm() =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        HapticFeedbackConstants.CONFIRM
    } else {
        HapticFeedbackConstants.LONG_PRESS
    }

/** Android's Remove animations (animator duration scale 0), standing in for iOS Reduce Motion. */
@Composable
private fun reducedMotion(): Boolean {
    val resolver = LocalContext.current.contentResolver
    return remember(resolver) {
        Settings.Global.getFloat(resolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}
