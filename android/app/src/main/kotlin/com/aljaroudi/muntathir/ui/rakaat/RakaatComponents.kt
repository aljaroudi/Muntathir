package com.aljaroudi.muntathir.ui.rakaat

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.RotateLeft
import androidx.compose.material.icons.automirrored.outlined.RotateRight
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.location.SavedLocation
import com.aljaroudi.muntathir.core.prayer.PrayerCalculator
import com.aljaroudi.muntathir.core.qibla.QiblaAlignment
import com.aljaroudi.muntathir.location.QiblaReading
import com.aljaroudi.muntathir.location.QiblaSensors
import java.time.ZoneId

/** The optional Qibla session's latest reading while [active]; it never asks for permission. */
@Composable
fun rememberQiblaReading(
    sensors: QiblaSensors,
    active: Boolean,
): QiblaReading? {
    val reading by produceState<QiblaReading?>(null, sensors, active) {
        value = null
        if (active) sensors.readings(optional = true).collect { value = it }
    }
    return reading
}

/** Swift `RakaatQiblaHint`: shown only with both a fix and a heading. Arrows stay left-to-right. */
@Composable
fun RakaatQiblaHint(
    reading: QiblaReading?,
    color: Color,
    modifier: Modifier = Modifier,
) {
    val fix = reading?.fix ?: return
    val heading = reading.heading ?: return
    val place = SavedLocation(fix.latitude, fix.longitude, "", "", ZoneId.systemDefault().id)
    val alignment = QiblaAlignment.of(PrayerCalculator.qibla(place), heading.degrees) ?: return
    val (icon, text) =
        when {
            alignment.isAligned(previously = false) -> Icons.Outlined.CheckCircle to R.string.aligned_with_kaaba
            alignment.error < 0 -> Icons.AutoMirrored.Outlined.RotateLeft to R.string.tilt_left
            else -> Icons.AutoMirrored.Outlined.RotateRight to R.string.tilt_right
        }
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
        Row(
            modifier.testTag("rakaat-qibla-hint"),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(20.dp))
            Text(
                stringResource(text),
                color = color,
                style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Medium),
            )
        }
    }
}

/** Swift `RakaatPlacementDiagram`: a prayer rug with the phone screen-up near the top, drawn left-to-right. */
@Composable
fun RakaatPlacementDiagram(modifier: Modifier = Modifier) {
    val accent = MaterialTheme.colorScheme.primary
    val foreground = MaterialTheme.colorScheme.onSurface
    Canvas(modifier.widthIn(max = 240.dp).fillMaxWidth().aspectRatio(240f / 260f)) {
        val scale = minOf(size.width / 240f, size.height / 260f)
        translate(left = (size.width - 240f * scale) / 2) {
            scale(scale, pivot = Offset.Zero) { drawRug(accent, foreground) }
        }
    }
}

private fun DrawScope.drawRug(
    accent: Color,
    foreground: Color,
) {
    fun box(
        x: Float,
        y: Float,
        width: Float,
        height: Float,
        radius: Float,
        color: Color,
        stroke: Float? = null,
    ) = drawRoundRect(
        color,
        Offset(x, y),
        Size(width, height),
        CornerRadius(radius),
        style = stroke?.let { Stroke(it) } ?: Fill,
    )

    box(44f, 15f, 152f, 230f, 8f, accent.copy(alpha = 0.12f))
    box(44f, 15f, 152f, 230f, 8f, accent, stroke = 2f)
    box(54f, 25f, 132f, 210f, 4f, accent.copy(alpha = 0.6f), stroke = 1f)
    val arch =
        Path().apply {
            moveTo(68f, 217f)
            lineTo(68f, 85f)
            quadraticTo(68f, 59f, 120f, 39f)
            quadraticTo(172f, 59f, 172f, 85f)
            lineTo(172f, 217f)
        }
    drawPath(arch, accent.copy(alpha = 0.6f), style = Stroke(2f))
    for (x in 54..186 step 11) {
        drawLine(accent, Offset(x.toFloat(), 8f), Offset(x.toFloat(), 15f), 2f, StrokeCap.Round)
        drawLine(accent, Offset(x.toFloat(), 245f), Offset(x.toFloat(), 252f), 2f, StrokeCap.Round)
    }
    rotate(180f, pivot = Offset(120f, 105.5f)) {
        box(103f, 73f, 34f, 65f, 6f, Color.Black)
        box(103f, 73f, 34f, 65f, 6f, foreground, stroke = 1f)
        box(106f, 81f, 28f, 49f, 2f, accent)
        drawCircle(Color.White, radius = 2f, center = Offset(120f, 77f))
    }
}
