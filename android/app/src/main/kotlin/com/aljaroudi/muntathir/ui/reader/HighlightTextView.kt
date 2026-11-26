package com.aljaroudi.muntathir.ui.reader

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.Selection
import android.text.Spannable
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StrikethroughSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import android.text.style.URLSpan
import android.text.style.UnderlineSpan
import android.view.ActionMode
import android.view.GestureDetector
import android.view.Menu
import android.view.MenuItem
import android.view.MotionEvent
import androidx.appcompat.widget.AppCompatTextView
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.ViewCompat
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.core.text.StyledText
import com.aljaroudi.muntathir.core.text.TextRange
import com.aljaroudi.muntathir.core.text.TextStyle

/**
 * Selectable reader text with saved highlights and a "Highlight" action first in the selection menu.
 * A platform TextView keeps native selection handles, multi-line selection, and the floating toolbar.
 */
class HighlightTextView(
    context: Context,
) : AppCompatTextView(context) {
    /** Called with the selected UTF-16 range in [text]. */
    var onHighlight: (List<TextRange>) -> Unit = {}

    /** Whether the selection may be highlighted (e.g. it covers verse words, not only headings). */
    var canHighlight: (List<TextRange>) -> Boolean = { true }

    /** A tap on highlighted text: every highlight under the tap, newest first. */
    var onOpenHighlights: (List<ReadingHighlight>) -> Unit = {}

    /** TalkBack action label for a highlight (Swift: the note, else the excerpt, up to 60 characters). */
    var highlightLabel: (ReadingHighlight) -> String = { (it.note.ifBlank { it.excerpt }).take(60) }

    private var rendered: Rendered? = null
    private var drawn: List<Pair<ReadingHighlight, List<TextRange>>> = emptyList()
    private var colors: List<Int> = emptyList()
    private val actionIDs = mutableListOf<Int>()

    /** Highlight shapes for [shapesLayout], oldest first, paired with their background color. */
    private var shapes: List<Pair<Int, Path>> = emptyList()
    private var shapesLayout: Layout? = null
    private var shapesKey: Triple<Int, Int, Float>? = null
    private val highlightPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }

    private val taps =
        GestureDetector(
            context,
            object : GestureDetector.SimpleOnGestureListener() {
                override fun onSingleTapUp(event: MotionEvent): Boolean {
                    if (selection() != null) return false
                    val offset = getOffsetForPosition(event.x, event.y)
                    val hits = highlightsAt(offset)
                    if (hits.isEmpty()) return false
                    onOpenHighlights(hits)
                    return true
                }
            },
        )

    @SuppressLint("ClickableViewAccessibility") // TalkBack users get custom actions instead.
    override fun onTouchEvent(event: MotionEvent): Boolean = taps.onTouchEvent(event) || super.onTouchEvent(event)

    /** Every drawn highlight range, oldest highlight first. */
    fun highlightRanges(): List<TextRange> = drawn.flatMap { it.second }

    /** Highlights covering [offset], newest first (the one drawn on top). */
    fun highlightsAt(offset: Int): List<ReadingHighlight> =
        drawn
            .filter { (_, ranges) -> ranges.any { offset >= it.location && offset < it.end } }
            .map { it.first }
            .reversed()

    private data class Rendered(
        val text: StyledText,
        val highlights: List<ReadingHighlight>,
        val block: String,
        val dark: Boolean,
        val layoutKey: Any?,
    )

    init {
        setTextIsSelectable(true)
        customSelectionActionModeCallback =
            object : ActionMode.Callback {
                override fun onCreateActionMode(
                    mode: ActionMode,
                    menu: Menu,
                ): Boolean {
                    menu.add(Menu.NONE, R.string.dictionary_lookup, 1, R.string.dictionary_lookup)
                    if (selection()?.let { canHighlight(listOf(it)) } == true) {
                        menu.add(Menu.NONE, R.id.action_highlight, 0, R.string.highlight)
                    }
                    return true
                }

                override fun onPrepareActionMode(
                    mode: ActionMode,
                    menu: Menu,
                ) = false

                override fun onActionItemClicked(
                    mode: ActionMode,
                    item: MenuItem,
                ): Boolean {
                    if (item.itemId == R.string.dictionary_lookup) {
                        val range = selection() ?: return false
                        context.startActivity(
                            android.content
                                .Intent(
                                    context,
                                    com.aljaroudi.muntathir.ui.dictionary.DictionaryActivity::class.java,
                                ).putExtra(
                                    android.content.Intent.EXTRA_PROCESS_TEXT,
                                    text.substring(range.location, range.end),
                                ),
                        )
                        mode.finish()
                        return true
                    }
                    if (item.itemId != R.id.action_highlight) return false
                    highlightSelection()
                    mode.finish()
                    return true
                }

                override fun onDestroyActionMode(mode: ActionMode) = Unit
            }
    }

    /** The current selection, or `null` when nothing is selected. */
    fun selection(): TextRange? {
        val start = minOf(selectionStart, selectionEnd)
        val end = maxOf(selectionStart, selectionEnd)
        return if (start >= 0 && end > start) TextRange.of(start, end) else null
    }

    /** Highlights the current selection; what the menu action runs. */
    fun highlightSelection(): Boolean {
        val selection = selection()?.takeIf { canHighlight(listOf(it)) } ?: return false
        onHighlight(listOf(selection))
        (text as? Spannable)?.let { Selection.removeSelection(it) }
        return true
    }

    /**
     * Shows [text] with [highlights] for [block]. Oldest highlights are drawn first so the newest color wins.
     * [rangesOf] maps a highlight to display ranges (the mushaf maps verse text to page text). [decorate] adds
     * layout spans and must depend only on [layoutKey]. Unchanged input keeps the current selection.
     */
    fun render(
        text: StyledText,
        highlights: List<ReadingHighlight>,
        block: String,
        layoutKey: Any? = null,
        rangesOf: (ReadingHighlight) -> List<TextRange> = { it.ranges(text.text, block) },
        decorate: (Spannable) -> Unit = {},
    ) {
        val dark =
            resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        val next = Rendered(text, highlights, block, dark, layoutKey)
        if (next == rendered) return
        rendered = next
        val spannable = SpannableString(text.text)
        decorate(spannable)
        for (span in text.spans) {
            val style =
                when (val style = span.style) {
                    TextStyle.Strong -> StyleSpan(Typeface.BOLD)
                    TextStyle.Emphasis -> StyleSpan(Typeface.ITALIC)
                    TextStyle.Code -> TypefaceSpan("monospace")
                    TextStyle.Strikethrough -> StrikethroughSpan()
                    TextStyle.Match -> UnderlineSpan()
                    is TextStyle.Link -> URLSpan(style.url)
                }
            spannable.setSpan(style, span.start, span.end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        drawn =
            highlights
                .sortedWith(
                    compareBy({
                        it.modifiedAt
                    }, { it.id }),
                ).map { it to rangesOf(it) }
                .filter { it.second.isNotEmpty() }
        colors = drawn.map { (highlight, _) -> highlightBackground(highlight.color, dark) }
        updateAccessibilityActions()
        shapesLayout = null
        setText(spannable, BufferType.SPANNABLE)
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        val layout = layout
        if (layout != null && drawn.isNotEmpty()) {
            val key = Triple(layout.width, layout.height, textSize)
            if (shapesLayout !== layout || shapesKey != key) {
                shapes = drawn.mapIndexed { index, (_, ranges) -> colors[index] to highlightPath(layout, ranges) }
                shapesLayout = layout
                shapesKey = key
            }
            canvas.save()
            canvas.translate(totalPaddingLeft.toFloat(), totalPaddingTop.toFloat())
            for ((color, path) in shapes) {
                highlightPaint.color = color
                canvas.drawPath(path, highlightPaint)
            }
            canvas.restore()
        }
        super.onDraw(canvas)
    }

    /**
     * One band per line a range covers, a little shorter than the glyphs' ascent-to-descent, rounded only where
     * the range starts and ends so wrapped highlights read as one continuous mark.
     */
    private fun highlightPath(
        layout: Layout,
        ranges: List<TextRange>,
    ): Path {
        val path = Path()
        val scratch = Path()
        val bounds = RectF()
        val metrics = paint.fontMetrics
        val length = layout.text.length
        for (range in ranges) {
            val start = range.location.coerceIn(0, length)
            val end = range.end.coerceIn(start, length)
            if (start == end) continue
            val segments = mutableListOf<RectF>()
            for (line in layout.getLineForOffset(start)..layout.getLineForOffset(end)) {
                val segmentStart = maxOf(start, layout.getLineStart(line))
                val segmentEnd = minOf(end, layout.getLineVisibleEnd(line))
                if (segmentEnd <= segmentStart) continue
                scratch.reset()
                layout.getSelectionPath(segmentStart, segmentEnd, scratch)
                scratch.computeBounds(bounds, true)
                if (bounds.width() <= 0f) continue
                val baseline = layout.getLineBaseline(line).toFloat()
                val top = maxOf(layout.getLineTop(line).toFloat(), baseline + metrics.ascent)
                val bottom = minOf(layout.getLineBottom(line).toFloat(), baseline + metrics.descent)
                val inset = (bottom - top) * BAND_INSET
                segments += RectF(bounds.left, top + inset, bounds.right, bottom - inset)
            }
            val startsRtl = layout.isRtlCharAt(start)
            val endsRtl = layout.isRtlCharAt(end - 1)
            segments.forEachIndexed { index, rect ->
                val radius = rect.height() * CORNER_FRACTION
                // The start rounds the leading edge (right in RTL), the end the trailing one.
                val first = index == 0
                val last = index == segments.lastIndex
                val left = if ((first && !startsRtl) || (last && endsRtl)) radius else 0f
                val right = if ((first && startsRtl) || (last && !endsRtl)) radius else 0f
                val radii = floatArrayOf(left, left, right, right, right, right, left, left)
                path.addRoundRect(rect, radii, Path.Direction.CW)
            }
        }
        return path
    }

    /** Swift: one accessibility action per visible highlight, opening it. */
    private fun updateAccessibilityActions() {
        actionIDs.forEach { ViewCompat.removeAccessibilityAction(this, it) }
        actionIDs.clear()
        for ((highlight, _) in drawn.reversed()) {
            val label = context.getString(R.string.highlight_note) + ": " + highlightLabel(highlight)
            actionIDs +=
                ViewCompat.addAccessibilityAction(this, label) { _, _ ->
                    onOpenHighlights(listOf(highlight))
                    true
                }
        }
    }
}

/** Fraction of the glyph band trimmed from both the top and the bottom of a highlight. */
private const val BAND_INSET = 0.08f

/** Corner radius at a highlight's start and end, as a fraction of its height. */
private const val CORNER_FRACTION = 0.3f

/** Compose entry point for [HighlightTextView]. */
@Composable
fun HighlightText(
    text: StyledText,
    highlights: List<ReadingHighlight>,
    block: String,
    onHighlight: (List<TextRange>) -> Unit,
    modifier: Modifier = Modifier,
    canHighlight: (List<TextRange>) -> Boolean = { true },
    configure: HighlightTextView.() -> Unit = {},
) {
    AndroidView(
        factory = { context -> HighlightTextView(context).apply(configure) },
        update = { view ->
            view.onHighlight = onHighlight
            view.canHighlight = canHighlight
            view.render(text, highlights, block)
        },
        modifier = modifier,
    )
}
