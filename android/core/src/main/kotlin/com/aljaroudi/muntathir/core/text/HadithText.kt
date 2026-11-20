package com.aljaroudi.muntathir.core.text

import com.aljaroudi.muntathir.core.text.QuranSearchText.fold
import org.commonmark.ext.gfm.strikethrough.Strikethrough
import org.commonmark.ext.gfm.strikethrough.StrikethroughExtension
import org.commonmark.node.AbstractVisitor
import org.commonmark.node.BlockQuote
import org.commonmark.node.BulletList
import org.commonmark.node.Code
import org.commonmark.node.CustomNode
import org.commonmark.node.Emphasis
import org.commonmark.node.FencedCodeBlock
import org.commonmark.node.HardLineBreak
import org.commonmark.node.Heading
import org.commonmark.node.HtmlBlock
import org.commonmark.node.HtmlInline
import org.commonmark.node.IndentedCodeBlock
import org.commonmark.node.Link
import org.commonmark.node.ListItem
import org.commonmark.node.Node
import org.commonmark.node.OrderedList
import org.commonmark.node.Paragraph
import org.commonmark.node.SoftLineBreak
import org.commonmark.node.StrongEmphasis
import org.commonmark.node.Text
import org.commonmark.parser.Parser

/** One block of hadith text: a paragraph, heading, list item or quote. */
data class HadithParagraph(
    val text: StyledText,
    val heading: Int? = null,
    /** "•" for bullets, "3." for ordered items. */
    val marker: String? = null,
    val quoted: Boolean = false,
)

/** Markdown hadith text, prepared once per item so views never reparse while scrolling. */
object HadithText {
    /** FTS `highlight()` markers around stem matches. */
    const val START_MARKER = ""
    const val END_MARKER = ""

    private val parser = Parser.builder().extensions(listOf(StrikethroughExtension.create())).build()

    /** CommonMark blocks, as Foundation renders them: soft breaks become spaces, code spans keep their text. */
    fun markdown(source: String): List<HadithParagraph> = MarkdownRenderer().render(parser.parse(source))

    /** [markdown] with search matches styled: FTS [marked] spans, or literal [terms] matches. */
    fun highlighted(
        source: String,
        terms: List<String> = emptyList(),
        marked: Boolean = false,
    ): List<HadithParagraph> =
        markdown(source).map { paragraph ->
            val text =
                when {
                    marked -> {
                        markMatches(paragraph.text)
                    }

                    terms.isNotEmpty() -> {
                        SearchMatch.ranges(paragraph.text.text, terms).fold(paragraph.text) { text, range ->
                            text.styled(range.location, range.end, TextStyle.Match, TextStyle.Strong)
                        }
                    }

                    else -> {
                        paragraph.text
                    }
                }
            paragraph.copy(text = text)
        }

    /** Paragraph texts joined by single newlines, for previews. */
    fun flattened(paragraphs: List<HadithParagraph>): StyledText = StyledText.join(paragraphs.map { it.text }, "\n")

    /**
     * The reader's text: paragraphs joined by blank lines, with list markers and quote bars inline.
     * Saved highlight ranges are UTF-16 offsets into this string, so it must stay stable.
     */
    fun canonical(paragraphs: List<HadithParagraph>): StyledText =
        StyledText.join(
            paragraphs.map { paragraph ->
                val prefix = (paragraph.marker?.let { "$it " } ?: "") + if (paragraph.quoted) "│ " else ""
                StyledText(prefix) + paragraph.text
            },
            "\n\n",
        )

    /** Slices FTS-marked source by unmarked code point positions, keeping markers balanced at the edges. */
    fun markedSlice(
        source: String,
        range: IntRange,
    ): String {
        val result = StringBuilder()
        var position = 0
        var highlighted = false
        var opened = false
        source.codePoints().forEach { scalar ->
            when (scalar) {
                0xE000 -> {
                    highlighted = true
                }

                0xE001 -> {
                    highlighted = false
                }

                else -> {
                    if (position in range) {
                        if (highlighted != opened) {
                            result.append(if (highlighted) START_MARKER else END_MARKER)
                            opened = highlighted
                        }
                        result.appendCodePoint(scalar)
                    }
                    position += 1
                }
            }
        }
        if (opened) result.append(END_MARKER)
        return result.toString()
    }

    /** A short excerpt around the strongest match, for search results. */
    fun preview(
        source: String,
        terms: List<String> = emptyList(),
        marked: Boolean = false,
    ): StyledText =
        SearchMatch.preview(
            flattened(highlighted(source, terms, marked)),
            compact =
                terms.isNotEmpty() || marked,
        )

    private fun markMatches(original: StyledText): StyledText {
        var text = original
        while (true) {
            val start = text.text.indexOf(START_MARKER)
            val end = if (start < 0) -1 else text.text.indexOf(END_MARKER, start + 1)
            if (start < 0 || end < 0) return text
            text =
                text.styled(start + 1, end, TextStyle.Match, TextStyle.Strong).removing(end, end + 1).removing(
                    start,
                    start + 1,
                )
        }
    }
}

private class MarkdownRenderer : AbstractVisitor() {
    private val paragraphs = mutableListOf<HadithParagraph>()
    private val text = StringBuilder()
    private val spans = mutableListOf<TextSpan>()
    private var marker: String? = null
    private var quoted = false

    fun render(document: Node): List<HadithParagraph> {
        document.accept(this)
        return paragraphs
    }

    private fun block(
        heading: Int? = null,
        content: () -> Unit,
    ) {
        text.clear()
        spans.clear()
        content()
        paragraphs += HadithParagraph(StyledText(text.toString(), spans.toList()), heading, marker, quoted)
    }

    private fun styled(
        style: TextStyle,
        node: Node,
    ) {
        val start = text.length
        visitChildren(node)
        if (text.length > start) spans += TextSpan(start, text.length, style)
    }

    override fun visit(paragraph: Paragraph) = block { visitChildren(paragraph) }

    override fun visit(heading: Heading) = block(heading.level) { visitChildren(heading) }

    override fun visit(codeBlock: FencedCodeBlock) = block { text.append(codeBlock.literal.trimEnd('\n')) }

    override fun visit(codeBlock: IndentedCodeBlock) = block { text.append(codeBlock.literal.trimEnd('\n')) }

    override fun visit(htmlBlock: HtmlBlock) = block { text.append(htmlBlock.literal.trimEnd('\n')) }

    override fun visit(blockQuote: BlockQuote) {
        val previous = quoted
        quoted = true
        visitChildren(blockQuote)
        quoted = previous
    }

    override fun visit(listItem: ListItem) {
        val previous = marker
        val list = listItem.parent
        marker =
            if (list is OrderedList) {
                var index = 0
                var sibling = list.firstChild
                while (sibling != null && sibling !== listItem) {
                    index += 1
                    sibling = sibling.next
                }
                "${(list.markerStartNumber ?: 1) + index}."
            } else {
                "•"
            }
        visitChildren(listItem)
        marker = previous
    }

    override fun visit(bulletList: BulletList) = visitChildren(bulletList)

    override fun visit(orderedList: OrderedList) = visitChildren(orderedList)

    override fun visit(text: Text) {
        this.text.append(text.literal)
    }

    override fun visit(softLineBreak: SoftLineBreak) {
        text.append(' ')
    }

    override fun visit(hardLineBreak: HardLineBreak) {
        text.append('\n')
    }

    override fun visit(code: Code) {
        val start = text.length
        text.append(code.literal)
        spans += TextSpan(start, text.length, TextStyle.Code)
    }

    override fun visit(htmlInline: HtmlInline) {
        text.append(htmlInline.literal)
    }

    override fun visit(emphasis: Emphasis) = styled(TextStyle.Emphasis, emphasis)

    override fun visit(strongEmphasis: StrongEmphasis) = styled(TextStyle.Strong, strongEmphasis)

    override fun visit(link: Link) = styled(TextStyle.Link(link.destination), link)

    override fun visit(customNode: CustomNode) {
        if (customNode is Strikethrough) styled(TextStyle.Strikethrough, customNode) else visitChildren(customNode)
    }
}

/** Temporary search styling. Source text and saved highlights stay unchanged. */
object SearchMatch {
    /** Ranges in [raw] matching any of [terms], ignoring diacritics, case and Arabic letter variants. */
    fun ranges(
        raw: String,
        terms: List<String>,
    ): List<TextRange> {
        if (terms.isEmpty()) return emptyList()
        // Match in a normalized copy, mapping each normalized unit back to its whole original character.
        val normalized = StringBuilder()
        val originals = mutableListOf<TextRange>()
        for (character in graphemes(raw)) {
            val key = fold(QuranSearchText.normalize(raw.substring(character)))
            normalized.append(key)
            repeat(key.length) { originals += character }
        }
        val searchable = normalized.toString()
        val result = mutableListOf<TextRange>()
        for (term in terms) {
            val key = fold(QuranSearchText.normalize(term))
            if (key.isEmpty()) continue
            var offset = 0
            while (offset < searchable.length) {
                val found = searchable.indexOf(key, offset)
                if (found < 0) break
                result += originals[found].union(originals[found + key.length - 1])
                offset = found + key.length
            }
        }
        return result
    }

    /** [raw] with literal matches of [query]; Quran text is never parsed as Markdown. */
    fun text(
        raw: String,
        query: String,
    ): StyledText =
        ranges(raw, QuranSearchText.queryTerms(query)).fold(StyledText(raw)) { text, range ->
            text.styled(range.location, range.end, TextStyle.Match)
        }

    /** Blocks to show in a result: those with matches, else [preferred], else the first non-empty one. */
    fun visibleBlocks(
        texts: List<StyledText>,
        preferred: Int,
    ): List<Int> {
        val matching = texts.indices.filter { texts[it].has(TextStyle.Match) }
        if (matching.isNotEmpty()) return matching
        if (preferred in texts.indices && texts[preferred].length > 0) return listOf(preferred)
        return listOfNotNull(texts.indices.firstOrNull { texts[it].length > 0 })
    }

    /**
     * About 160–260 characters around the strongest match, with "… " / " …" where text was cut. [compact] starts
     * near the matching word and prefers word boundaries; otherwise the excerpt starts 45 characters earlier.
     */
    fun preview(
        text: StyledText,
        compact: Boolean = false,
    ): StyledText {
        val characters = graphemes(text.text)
        val count = characters.size

        fun index(offset: Int) = characters.indexOfFirst { it.end > offset }.let { if (it < 0) count else it }

        fun whitespace(index: Int) =
            text.text.codePointAtOrNull(characters[index].location)?.let(::isWhitespace) == true

        fun newline(index: Int) = text.text.codePointAtOrNull(characters[index].location)?.let(::isNewline) == true

        var groupStart = 0
        var previousEnd = 0
        var bestStart = 0
        var score = 0
        var bestScore = 0
        val seen = mutableSetOf<String>()
        for (span in text.spans(TextStyle.Match).sortedBy { it.start }) {
            if (span.start < previousEnd) continue
            val word = fold(QuranSearchText.normalize(text.text.substring(span.start, span.end)))
            if (span.start - previousEnd > 3 || word in seen || seen.isEmpty()) {
                groupStart = span.start
                score = 0
                seen.clear()
            }
            seen += word
            score += word.length + 1
            if (score > bestScore) {
                bestScore = score
                bestStart = groupStart
            }
            previousEnd = span.end
        }
        val hit = index(bestStart)
        var start = maxOf(0, hit - if (compact) 12 else 45)
        if (compact) {
            var wordStart = hit
            while (wordStart > 0 && !whitespace(wordStart - 1)) wordStart -= 1
            start = maxOf(0, wordStart - 12)
            while (start in 1 until wordStart && !whitespace(start - 1)) start += 1
            if (hit - start > 100) start = maxOf(0, hit - 12)
            (hit - 1 downTo start).firstOrNull { newline(it) }?.let { start = it + 1 }
        }
        var end = minOf(count, start + if (compact) 160 else 260)
        if (compact && end < count) {
            // Prefer whole words, but keep unbroken source text within the existing preview budget.
            val limit = minOf(count, start + 260)
            var boundary = end
            while (boundary < limit && !whitespace(boundary)) boundary += 1
            if (boundary == count || (boundary < limit && whitespace(boundary))) end = boundary
        }

        fun offset(index: Int) = if (index < count) characters[index].location else text.length
        var result = text.slice(offset(start), offset(end))
        if (start > 0) result = StyledText("… ") + result
        if (end < count) result += " …"
        return result
    }
}
