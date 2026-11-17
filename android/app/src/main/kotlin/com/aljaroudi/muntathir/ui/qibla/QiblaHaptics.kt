package com.aljaroudi.muntathir.ui.qibla

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.content.getSystemService
import com.aljaroudi.muntathir.core.qibla.QiblaAlignment
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

/**
 * Swift `QiblaView`'s `.task(id: feedback)`: one success haptic on entering alignment, otherwise pulses that grow
 * stronger and faster within 60°. Pass [QiblaAlignment.Feedback.None] when the screen isn't resumed.
 */
@Composable
fun QiblaHaptics(feedback: QiblaAlignment.Feedback) {
    val view = LocalView.current
    val context = LocalContext.current
    val vibrator = remember(context) { context.vibrator() }
    LaunchedEffect(feedback) {
        if (feedback == QiblaAlignment.Feedback.Aligned) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
            } else {
                vibrator?.vibrate(VibrationEffect.createOneShot(SUCCESS_MS, VibrationEffect.DEFAULT_AMPLITUDE))
            }
            return@LaunchedEffect
        }
        val pulse = feedback.pulse ?: return@LaunchedEffect
        val device = vibrator ?: return@LaunchedEffect
        val amplitude =
            if (device.hasAmplitudeControl()) {
                (pulse.intensity * 255).roundToInt().coerceIn(1, 255)
            } else {
                VibrationEffect.DEFAULT_AMPLITUDE
            }
        while (true) {
            delay((pulse.interval * 1000).toLong())
            device.vibrate(VibrationEffect.createOneShot(PULSE_MS, amplitude))
        }
    }
}

private const val SUCCESS_MS = 30L
private const val PULSE_MS = 20L

private fun Context.vibrator(): Vibrator? {
    val vibrator =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService<VibratorManager>()?.defaultVibrator
        } else {
            getSystemService<Vibrator>()
        }
    return vibrator?.takeIf { it.hasVibrator() }
}
