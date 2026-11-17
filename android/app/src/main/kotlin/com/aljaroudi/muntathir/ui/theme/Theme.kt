package com.aljaroudi.muntathir.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

// Brand colors match the iOS accent and app icon.
private val Emerald = Color(0xFF0D664F)
private val EmeraldLight = Color(0xFF5CC9A3)
private val DeepEmerald = Color(0xFF082F2B)
private val Sand = Color(0xFFDCC18A)
private val Ivory = Color(0xFFF5F0DF)

private val LightColors =
    lightColorScheme(
        primary = Emerald,
        onPrimary = Color.White,
        primaryContainer = Color(0xFFB4EFD6),
        onPrimaryContainer = DeepEmerald,
        tertiary = Color(0xFF7A5F25),
        tertiaryContainer = Sand,
        surface = Color(0xFFFBFAF4),
        background = Color(0xFFFBFAF4),
    )

private val DarkColors =
    darkColorScheme(
        primary = EmeraldLight,
        onPrimary = DeepEmerald,
        primaryContainer = Color(0xFF0A4F3E),
        onPrimaryContainer = Color(0xFFB4EFD6),
        tertiary = Sand,
        onTertiary = Color(0xFF3F2E00),
        surface = Color(0xFF0E1513),
        background = Color(0xFF0E1513),
        onSurface = Ivory,
    )

/** Dynamic color on Android 12+, brand emerald elsewhere (and when [dynamicColor] is false). */
@Composable
fun MuntathirTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit,
) {
    val colors =
        when {
            dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                val context = LocalContext.current
                if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
            }

            darkTheme -> {
                DarkColors
            }

            else -> {
                LightColors
            }
        }
    MaterialTheme(colorScheme = colors, typography = Typography, content = content)
}
