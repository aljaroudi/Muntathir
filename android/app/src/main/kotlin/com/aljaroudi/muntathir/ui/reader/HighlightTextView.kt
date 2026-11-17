package com.aljaroudi.muntathir.ui.reader

import android.content.Context
import android.content.res.Configuration
import android.graphics.Typeface
import android.text.Selection
import android.text.Spannable
import android.text.SpannableString
import android.text.Spanned
import android.text.style.BackgroundColorSpan
import android.text.style.StrikethroughSpan
import android.text.style.StyleSpan
import android.text.style.TypefaceSpan
import android.text.style.URLSpan
import android.text.style.UnderlineSpan
import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import androidx.appcompat.widget.AppCompatTextView
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
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

    private var rendered: Rendered? = null

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
        for (highlight in highlights.sortedWith(compareBy({ it.modifiedAt }, { it.id }))) {
            val background = highlightBackground(highlight.color, dark)
            for (range in rangesOf(highlight)) {
                spannable.setSpan(
                    BackgroundColorSpan(background),
                    range.location,
                    range.end,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                )
            }
        }
        setText(spannable, BufferType.SPANNABLE)
    }
}

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
