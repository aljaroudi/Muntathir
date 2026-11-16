package com.aljaroudi.muntathir.ui.reader

import android.graphics.Color
import com.aljaroudi.muntathir.core.highlight.HighlightColor

/** Swatches close to the iOS system colors the palette uses. */
private val swatches =
    mapOf(
        HighlightColor.Yellow to 0xFFFFCC00,
        HighlightColor.Green to 0xFF34C759,
        HighlightColor.Blue to 0xFF007AFF,
        HighlightColor.Pink to 0xFFFF2D55,
        HighlightColor.Purple to 0xFFAF52DE,
        HighlightColor.Orange to 0xFFFF9500,
        HighlightColor.Red to 0xFFFF3B30,
        HighlightColor.Mint to 0xFF00C7BE,
        HighlightColor.Teal to 0xFF30B0C7,
        HighlightColor.Cyan to 0xFF32ADE6,
        HighlightColor.Indigo to 0xFF5856D6,
        HighlightColor.Brown to 0xFFA2845E,
    ).mapValues { it.value.toInt() }

/**
 * An opaque pastel behind highlighted text: 28% of the swatch over white (light) or black (dark), as on iOS,
 * so text keeps its normal color and contrast.
 */
fun highlightBackground(
    color: HighlightColor,
    dark: Boolean,
    highContrast: Boolean = false,
): Int {
    val swatch = swatches.getValue(color)
    val fraction = if (highContrast) 0.22f else 0.28f
    val base = if (dark) 0f else 1 - fraction

    fun channel(value: Int) = ((base + value / 255f * fraction) * 255).toInt().coerceIn(0, 255)
    return Color.rgb(channel(Color.red(swatch)), channel(Color.green(swatch)), channel(Color.blue(swatch)))
}
