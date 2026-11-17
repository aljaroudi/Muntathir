package com.aljaroudi.muntathir.ui.reader

import android.graphics.Typeface
import android.view.View
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.viewinterop.AndroidView
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.core.text.StyledText
import com.aljaroudi.muntathir.core.text.TextRange

/** Selectable reader text at a reading size: a [HighlightTextView] with saved highlights for [block]. */
@Composable
fun ReaderText(
    text: StyledText,
    block: String,
    sizeSp: Float,
    modifier: Modifier = Modifier,
    typeface: Typeface? = null,
    rightToLeft: Boolean = false,
    highlights: List<ReadingHighlight> = emptyList(),
    onHighlight: (List<TextRange>) -> Unit = {},
    canHighlight: (List<TextRange>) -> Boolean = { false },
    configure: HighlightTextView.() -> Unit = {},
) {
    val color = LocalContentColor.current.toArgb()
    AndroidView(
        factory = { context ->
            HighlightTextView(context).apply {
                includeFontPadding = false
                configure()
            }
        },
        update = { view ->
            view.setTextColor(color)
            view.textDirection = if (rightToLeft) View.TEXT_DIRECTION_RTL else View.TEXT_DIRECTION_FIRST_STRONG
            view.textAlignment = View.TEXT_ALIGNMENT_VIEW_START
            view.layoutDirection = if (rightToLeft) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_INHERIT
            val style = sizeSp to typeface
            if (view.getTag(R.id.reading_style) != style) {
                view.setTag(R.id.reading_style, style)
                view.applyReadingStyle(sizeSp, typeface)
            }
            view.onHighlight = onHighlight
            view.canHighlight = canHighlight
            view.render(text, highlights, block)
        },
        modifier = modifier,
    )
}
