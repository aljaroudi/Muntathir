package com.aljaroudi.muntathir.ui.quran

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.text.Layout
import android.text.Spannable
import android.text.Spanned
import android.text.TextPaint
import android.text.style.AlignmentSpan
import android.text.style.LineHeightSpan
import android.text.style.ReplacementSpan
import com.aljaroudi.muntathir.core.quran.QuranPage
import com.aljaroudi.muntathir.core.quran.QuranPageText
import kotlin.math.roundToInt

/**
 * Swift `QuranMushafView` fitting: 15 equal lines, the widest line fits the width, and non-centered verse lines
 * are justified by widening their spaces. Each mushaf line is its own paragraph (line joins become `\n`, which
 * keeps every UTF-16 offset, so highlights and selection map unchanged).
 */
class MushafLayout(
    val page: QuranPageText,
    typeface: Typeface?,
    /** Text width in pixels. */
    width: Int,
    /** Text height in pixels, for 15 lines. */
    height: Int,
) {
    val lineHeight: Int = height / LINES
    val fontSize: Float
    val text: String

    /** Pixel width for each space in justified lines, keyed by offset. */
    private val spaces: Map<Int, Int>

    init {
        val chars = page.text.toCharArray()
        page.lines.drop(1).forEach { line -> chars[line.range.location - 1] = '\n' }
        text = String(chars)
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { this.typeface = typeface }
        paint.textSize = REFERENCE_SIZE
        val usable = (width - MARGIN).coerceAtLeast(1)
        val widest =
            page.lines.maxOfOrNull { paint.measureText(text, it.range.location, it.range.end) }?.takeIf { it > 0 } ?: 1f
        fontSize = minOf(REFERENCE_SIZE * usable / widest, lineHeight * MAX_FONT_FRACTION)
        paint.textSize = fontSize
        val spaceWidth = paint.measureText(" ")
        val result = mutableMapOf<Int, Int>()
        for (line in page.lines) {
            if (line.kind != QuranPage.Line.Kind.Ayah || line.centered) continue
            val offsets = (line.range.location until line.range.end).filter { text[it] == ' ' }
            if (offsets.isEmpty()) continue
            val glyphs = paint.measureText(text, line.range.location, line.range.end) - spaceWidth * offsets.size
            // Whole pixels per space, spreading the remainder so the line still fills the width exactly.
            val total = (usable - glyphs).coerceAtLeast(spaceWidth * offsets.size).roundToInt()
            offsets.forEachIndexed { index, offset ->
                result[offset] = total * (index + 1) / offsets.size - total * index / offsets.size
            }
        }
        spaces = result
    }

    /** Line alignment, justified spaces and the fixed line height. */
    fun decorate(spannable: Spannable) {
        for (line in page.lines) {
            if (line.kind != QuranPage.Line.Kind.Ayah || line.centered) {
                spannable.setSpan(
                    AlignmentSpan.Standard(Layout.Alignment.ALIGN_CENTER),
                    line.range.location,
                    line.range.end,
                    Spanned.SPAN_INCLUSIVE_EXCLUSIVE,
                )
            }
        }
        for ((offset, width) in spaces) {
            spannable.setSpan(SpaceSpan(width), offset, offset + 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        spannable.setSpan(FixedLineHeight(lineHeight), 0, spannable.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
    }

    companion object {
        const val LINES = 15
        private const val REFERENCE_SIZE = 100f
        private const val MAX_FONT_FRACTION = 0.6f

        /** Swift fits `width - 2`; a little more slack keeps rounding from wrapping a line. */
        private const val MARGIN = 4
    }
}

/** A space drawn [width] pixels wide. */
private class SpaceSpan(
    private val width: Int,
) : ReplacementSpan() {
    override fun getSize(
        paint: Paint,
        text: CharSequence?,
        start: Int,
        end: Int,
        fm: Paint.FontMetricsInt?,
    ): Int {
        fm?.let { paint.getFontMetricsInt(it) }
        return width
    }

    override fun draw(
        canvas: Canvas,
        text: CharSequence?,
        start: Int,
        end: Int,
        x: Float,
        top: Int,
        y: Int,
        bottom: Int,
        paint: Paint,
    ) = Unit
}

/** Every line exactly [height] pixels, with the glyphs centered vertically. */
private class FixedLineHeight(
    private val height: Int,
) : LineHeightSpan {
    override fun chooseHeight(
        text: CharSequence?,
        start: Int,
        end: Int,
        spanstartv: Int,
        lineHeight: Int,
        fm: Paint.FontMetricsInt,
    ) {
        val natural = fm.descent - fm.ascent
        val extra = height - natural
        fm.ascent -= extra - extra / 2
        fm.descent += extra / 2
        fm.top = fm.ascent
        fm.bottom = fm.descent
    }
}
