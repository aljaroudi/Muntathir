package com.aljaroudi.muntathir.ui.reader

import android.graphics.Typeface
import android.util.TypedValue
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.res.ResourcesCompat
import com.aljaroudi.muntathir.R

/** Swift `ReadingTextStyle`: Arabic 28 sp and body 17 sp, scaled by the reading size, with 1.75 line height. */
object ReadingTextStyle {
    const val ARABIC_SP = 28f
    const val BODY_SP = 17f
    const val LINE_HEIGHT = 1.75f

    fun arabicSize(percent: Int) = ARABIC_SP * percent / 100f

    fun bodySize(percent: Int) = BODY_SP * percent / 100f
}

/** Styles a [HighlightTextView] for reading: [sizeSp] text with the reading line height. */
fun HighlightTextView.applyReadingStyle(
    sizeSp: Float,
    typeface: Typeface?,
) {
    setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
    this.typeface = typeface
    val lineHeight =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP,
            sizeSp * ReadingTextStyle.LINE_HEIGHT,
            resources.displayMetrics,
        )
    // Fixed line height for Latin and Arabic alike (setLineHeight needs API 28).
    val natural = paint.getFontMetricsInt(null)
    setLineSpacing(maxOf(0f, lineHeight - natural), 1f)
}

/** The KFGQPC Hafs typeface for Quran text in platform views. */
@Composable
fun quranTypeface(): Typeface? {
    val context = LocalContext.current
    return remember { ResourcesCompat.getFont(context, R.font.qpc_hafs) }
}
