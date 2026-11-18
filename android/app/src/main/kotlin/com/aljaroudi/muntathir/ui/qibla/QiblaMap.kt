package com.aljaroudi.muntathir.ui.qibla

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.qibla.QiblaGeometry
import com.aljaroudi.muntathir.core.qibla.QiblaSession
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.MapStyleOptions
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.MapType
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.Polyline
import com.google.maps.android.compose.rememberCameraPositionState
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/** iOS `systemTeal` and `systemGreen`. */
internal val QiblaTeal = Color(0xFF30B0C7)
internal val QiblaGreen = Color(0xFF34C759)
private val DialBackground = Color(0xFF0F2422)

private val KAABA = LatLng(QiblaGeometry.KAABA_LATITUDE, QiblaGeometry.KAABA_LONGITUDE)

// Hybrid imagery keeps its labels; this hides business and landmark pins.
private const val NO_POIS =
    """[{"featureType":"poi","stylers":[{"visibility":"off"}]},""" +
        """{"featureType":"transit","stylers":[{"visibility":"off"}]}]"""

/**
 * Swift `QiblaMap`: a locked, north-up hybrid map centered on the fix at about 150 m across, with a geodesic line
 * to the Kaaba. Maps' own location layer stays off, so it never starts a second location stream.
 */
@Composable
fun QiblaGoogleMap(
    fix: QiblaSession.Fix,
    aligned: Boolean,
    modifier: Modifier = Modifier,
) {
    val tilesLoaded = remember(fix.latitude, fix.longitude) { mutableStateOf(false) }
    BoxWithConstraints(modifier.then(if (tilesLoaded.value) Modifier.testTag("qibla-map-loaded") else Modifier)) {
        val width = maxWidth.value.toDouble()
        val target = LatLng(fix.latitude, fix.longitude)

        fun position() = CameraPosition.fromLatLngZoom(target, QiblaGeometry.zoom(fix.latitude, width).toFloat())
        val camera = rememberCameraPositionState { position = position() }
        LaunchedEffect(target, width) { camera.position = position() }
        // Equal top and bottom padding keeps the camera on the screen center, under the ring overlay.
        val bars = WindowInsets.systemBars.asPaddingValues()
        val inset = maxOf(bars.calculateTopPadding(), bars.calculateBottomPadding())
        GoogleMap(
            modifier = Modifier.fillMaxSize(),
            cameraPositionState = camera,
            onMapLoaded = { tilesLoaded.value = true },
            contentPadding = PaddingValues(vertical = inset),
            properties =
                remember {
                    MapProperties(
                        mapType = MapType.HYBRID,
                        isMyLocationEnabled = false,
                        isBuildingEnabled = false,
                        isIndoorEnabled = false,
                        mapStyleOptions = MapStyleOptions(NO_POIS),
                    )
                },
            uiSettings =
                remember {
                    MapUiSettings(
                        compassEnabled = false,
                        indoorLevelPickerEnabled = false,
                        mapToolbarEnabled = false,
                        myLocationButtonEnabled = false,
                        rotationGesturesEnabled = false,
                        scrollGesturesEnabled = false,
                        scrollGesturesEnabledDuringRotateOrZoom = false,
                        tiltGesturesEnabled = false,
                        zoomControlsEnabled = false,
                        zoomGesturesEnabled = false,
                    )
                },
        ) {
            Polyline(
                points = listOf(target, KAABA),
                geodesic = true,
                color = if (aligned) QiblaGreen else QiblaTeal,
                width = with(LocalDensity.current) { 4.dp.toPx() },
            )
        }
    }
}

/**
 * Without a Maps key: a compass card that turns with the device ([heading] at the top), with N and a needle to the
 * Kaaba at [bearing]. North-up when there's no heading.
 */
@Composable
fun QiblaDial(
    bearing: Double,
    heading: Double?,
    aligned: Boolean,
    modifier: Modifier = Modifier,
) {
    val measurer = rememberTextMeasurer()
    val north = stringResource(R.string.compass_north)
    Canvas(modifier.background(DialBackground)) {
        val radius = min(size.width, size.height) * 0.4f
        val center = this.center
        rotate(-(heading ?: 0.0).toFloat(), center) {
            drawCircle(Color.White.copy(alpha = 0.35f), radius, center, style = Stroke(2.dp.toPx()))
            for (degree in 0 until 360 step 5) {
                val major = degree % 30 == 0
                val angle = Math.toRadians(degree.toDouble())
                val outer = radius
                val inner = radius - (if (major) 14.dp else 7.dp).toPx()

                fun point(r: Float) = Offset(center.x + r * sin(angle).toFloat(), center.y - r * cos(angle).toFloat())
                drawLine(
                    Color.White.copy(alpha = if (major) 0.8f else 0.4f),
                    point(inner),
                    point(outer),
                    strokeWidth = (if (major) 2.dp else 1.dp).toPx(),
                )
            }
            val label =
                measurer.measure(
                    north,
                    TextStyle(color = Color(0xFFFF6B5E), fontSize = 20.sp, fontWeight = FontWeight.Bold),
                )
            drawText(
                label,
                topLeft =
                    Offset(
                        center.x - label.size.width / 2f,
                        center.y - radius + 18.dp.toPx(),
                    ),
            )
            val angle = Math.toRadians(bearing)
            val tip = Offset(center.x + radius * sin(angle).toFloat(), center.y - radius * cos(angle).toFloat())
            val color = if (aligned) QiblaGreen else QiblaTeal
            drawLine(color, center, tip, strokeWidth = 4.dp.toPx(), cap = StrokeCap.Round)
            drawCircle(color, 7.dp.toPx(), tip)
        }
    }
}

/** The fix itself: Maps' location layer is off, and the map stays centered on the fix. */
@Composable
fun QiblaUserDot(modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(16.dp)
            .shadow(3.dp, CircleShape)
            .background(Color(0xFF0A84FF), CircleShape)
            .border(3.dp, Color.White, CircleShape),
    )
}

/** Swift's 76-pt ring with a north-arrow glyph turned to the device direction ([rotation], clockwise). */
@Composable
fun QiblaHeadingRing(
    rotation: Double,
    aligned: Boolean,
    modifier: Modifier = Modifier,
) {
    val description = stringResource(R.string.device_direction)
    Box(modifier.size(76.dp)) {
        Canvas(Modifier.fillMaxSize()) {
            val width = (if (aligned) 4.dp else 2.dp).toPx()
            drawCircle(
                Color.Black.copy(alpha = 0.35f),
                size.minDimension / 2 - width / 2,
                style =
                    Stroke(width + 2.dp.toPx()),
            )
            drawCircle(
                if (aligned) QiblaGreen else Color.White.copy(alpha = 0.6f),
                size.minDimension / 2 - width / 2,
                style = Stroke(width),
            )
        }
        Box(Modifier.fillMaxSize().rotate(rotation.toFloat())) {
            Icon(
                Icons.Filled.Navigation,
                contentDescription = null,
                tint = if (aligned) QiblaGreen else Color.White,
                modifier =
                    Modifier
                        .align(Alignment.Center)
                        .offset(y = (-28).dp)
                        .size(18.dp)
                        .testTag("qibla-heading-indicator")
                        .semantics { contentDescription = description },
            )
        }
    }
}
