package com.aljaroudi.muntathir.ui.today

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.aljaroudi.muntathir.core.sky.ArcRect
import com.aljaroudi.muntathir.core.sky.MoonPosition
import com.aljaroudi.muntathir.core.sky.SolarArcLayout
import com.aljaroudi.muntathir.core.sky.SolarArcMarker
import com.aljaroudi.muntathir.core.sky.SolarPosition
import com.aljaroudi.muntathir.ui.components.icon
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.sin
import kotlin.math.sqrt

private data class Rgb(
    val r: Float,
    val g: Float,
    val b: Float,
) {
    fun mix(
        other: Rgb,
        t: Float,
    ) = Rgb(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)

    val color: Color get() = Color(r.coerceIn(0f, 1f), g.coerceIn(0f, 1f), b.coerceIn(0f, 1f))
}

private fun smoothstep(
    edge0: Float,
    edge1: Float,
    x: Float,
): Float {
    val t = ((x - edge0) / (edge1 - edge0)).coerceIn(0f, 1f)
    return t * t * (3 - 2 * t)
}

private fun fract(x: Float) = x - floor(x)

/**
 * Swift `TodaySky.metal` as a vertical gradient: colour depends only on the height above the horizon, so
 * sampling it every few dp matches the shader. [y] and [horizonY] are in dp.
 */
private fun skyColor(
    y: Float,
    elevation: Float,
    rising: Boolean,
    horizonY: Float,
): Rgb {
    val height = maxOf(horizonY - y, 0f)
    val horizon = exp(-height / 100f)
    val day = smoothstep(-8f, 8f, elevation)
    val twilight = smoothstep(-18f, -5f, elevation) * (1 - smoothstep(2f, 14f, elevation))
    val night = Rgb(0.009f, 0.018f, 0.055f).mix(Rgb(0.055f, 0.075f, 0.14f), horizon)
    val daylight = Rgb(0.085f, 0.32f, 0.64f).mix(Rgb(0.65f, 0.81f, 0.88f), horizon)
    val warm = Rgb(0.96f, 0.32f, 0.12f).mix(Rgb(0.87f, 0.46f, 0.45f), if (rising) 1f else 0f)
    val color = night.mix(daylight, day).mix(warm, twilight * horizon * 0.8f)
    val below = Rgb(0.008f, 0.014f, 0.025f).mix(Rgb(0.10f, 0.16f, 0.20f), day)
    return color.mix(below, smoothstep(horizonY, horizonY + 90, y))
}

/** Static star cells from the shader's hash (no animation or sensors). */
private fun DrawScope.stars(
    elevation: Float,
    horizonY: Float,
    scale: Float,
) {
    val visibility = 1 - smoothstep(-18f, -8f, elevation)
    if (visibility <= 0f) return
    val columns = (size.width / scale / 5).toInt() + 1
    val rows = (horizonY / 5).toInt() + 1
    for (row in 0 until rows) {
        val height = horizonY - row * 5 - 2.5f
        val alpha = visibility * smoothstep(0f, 70f, height) * 0.65f
        if (alpha <= 0f) continue
        for (column in 0 until columns) {
            val seed = fract(sin(column * 127.1f + row * 311.7f) * 43758.5453f)
            if (seed < 0.985f) continue
            drawCircle(
                Color.White.copy(alpha = alpha),
                radius = 0.16f * 5 * scale / 2,
                center =
                    Offset((column * 5 + 2.5f) * scale, (row * 5 + 2.5f) * scale),
            )
        }
    }
}

/** Decorative sky behind Today, always left to right and hidden from accessibility. */
@Composable
fun TodaySky(
    sun: SolarPosition,
    horizonY: Dp,
    modifier: Modifier = Modifier,
) {
    val elevation = sun.elevation.toFloat()
    Canvas(modifier.fillMaxSize().clearAndSetSemantics {}) {
        val horizon = horizonY.toPx() / density
        val heightDp = size.height / density
        val stops =
            (0..((heightDp / 6).toInt() + 1)).map { step ->
                val y = step * 6f
                (y / heightDp).coerceIn(0f, 1f) to skyColor(y, elevation, sun.isRising, horizon).color
            }
        drawRect(Brush.verticalGradient(*stops.toTypedArray()))
        stars(elevation, horizon, density)
    }
}

/** Swift `SolarArc`: a schematic daily path with the sun, moon and prayer markers. */
@Composable
fun SolarArc(
    sun: SolarPosition,
    moon: MoonPosition?,
    markers: List<SolarArcMarker>,
    modifier: Modifier = Modifier,
) {
    // The arc reads left to right in every language, like the iOS view.
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        BoxWithConstraints(modifier.clearAndSetSemantics {}) {
            val bounds =
                ArcRect(
                    36.0,
                    24.0,
                    (maxWidth.value - 72.0).coerceAtLeast(0.0),
                    (maxHeight.value - 60.0).coerceAtLeast(0.0),
                )
            val progress = sun.daylightProgress
            val arc = sun.arc
            Canvas(Modifier.fillMaxSize()) {
                if (arc != null && progress != null) {
                    val path = Path()
                    for (step in 0..60) {
                        val point = SolarArcLayout.point(step / 60.0, arc.elevation(step / 60.0), bounds)
                        val offset = Offset(point.x.toFloat() * density, point.y.toFloat() * density)
                        if (step == 0) path.moveTo(offset.x, offset.y) else path.lineTo(offset.x, offset.y)
                    }
                    drawPath(
                        path,
                        Color.White.copy(alpha = 0.18f),
                        style =
                            Stroke(
                                1.dp.toPx(),
                                pathEffect = PathEffect.dashPathEffect(floatArrayOf(2.dp.toPx(), 5.dp.toPx())),
                            ),
                    )
                }
            }
            val moonProgress = moon?.visibleProgress
            if (moon != null && moonProgress != null) {
                val point = SolarArcLayout.point(moonProgress, moon.elevation, bounds)
                MoonDisc(
                    moon.illuminatedFraction,
                    moon.isWaxing,
                    Modifier.centeredAt(point.x, point.y, 20.dp).alpha(
                        if (progress ==
                            null
                        ) {
                            0.9f
                        } else {
                            0.65f
                        },
                    ),
                )
            }
            if (progress != null) {
                val point = SolarArcLayout.point(progress, sun.elevation, bounds)
                SunDisc(sun.elevation < 10, Modifier.centeredAt(point.x, point.y, 30.dp))
                markers.forEach { marker ->
                    val at = SolarArcLayout.point(marker.progress, marker.elevation, bounds)
                    val upcoming = marker.state == SolarArcMarker.State.Upcoming
                    Icon(
                        marker.name.icon,
                        contentDescription = null,
                        tint = if (upcoming) Color(1f, 0.85f, 0.4f) else Color.White,
                        modifier =
                            Modifier
                                .centeredAt(at.x, at.y + 22, 16.dp)
                                .alpha(if (marker.state == SolarArcMarker.State.Past) 0.45f else 1f),
                    )
                }
            }
        }
    }
}

/** Places a [size] square centred on ([x], [y]) dp. */
private fun Modifier.centeredAt(
    x: Double,
    y: Double,
    size: Dp,
) = offset((x - size.value / 2).dp, (y - size.value / 2).dp).size(size)

@Composable
private fun SunDisc(
    warm: Boolean,
    modifier: Modifier,
) {
    val edge = if (warm) Color(1f, 0.72f, 0.34f) else Color(1f, 0.94f, 0.68f)
    Box(modifier) {
        // The halo overflows the disc; requiredSize keeps it centred.
        Canvas(Modifier.requiredSize(104.dp)) {
            drawCircle(
                Brush.radialGradient(
                    0f to Color.Transparent,
                    12f / 52 to Color(1f, 0.6f, 0f, 0.4f),
                    1f to Color.Transparent,
                    radius = 52.dp.toPx(),
                ),
            )
        }
        Canvas(Modifier.fillMaxSize()) {
            drawCircle(Brush.radialGradient(listOf(Color.White, edge), center = Offset.Zero, radius = 30.dp.toPx()))
        }
    }
}

/** Swift `MoonDisc`: lit limb plus terminator, waxing on the right. */
@Composable
private fun MoonDisc(
    fraction: Double,
    waxing: Boolean,
    modifier: Modifier,
) {
    Canvas(modifier) {
        val radius = size.minDimension / 2
        val center = Offset(size.width / 2, size.height / 2)
        val light = Path()
        for (step in 0..120) {
            val limb = step <= 60
            val y = if (limb) step / 30.0 - 1 else 3 - step / 30.0
            val x = sqrt(maxOf(0.0, 1 - y * y)) * (if (limb) 1.0 else 1 - 2 * fraction)
            val point =
                Offset(
                    center.x + ((if (waxing) x else -x) * radius).toFloat(),
                    center.y + (y * radius).toFloat(),
                )
            if (step == 0) light.moveTo(point.x, point.y) else light.lineTo(point.x, point.y)
        }
        light.close()
        drawPath(
            light,
            Brush.linearGradient(
                listOf(Color.White, Color(0.7f, 0.78f, 0.88f)),
                Offset.Zero,
                Offset(size.width, size.height),
            ),
        )
    }
}
