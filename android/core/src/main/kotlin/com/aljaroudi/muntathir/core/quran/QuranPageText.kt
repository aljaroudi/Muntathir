package com.aljaroudi.muntathir.core.quran

import com.aljaroudi.muntathir.core.highlight.HighlightRange
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.core.text.QuranSearchText
import com.aljaroudi.muntathir.core.text.TextRange
import com.aljaroudi.muntathir.core.text.graphemes

/** Maps QPC display words on a mushaf page to the unchanged Tanzil text that saved highlights use. */
class QuranPageText(
    page: QuranPage,
    surahs: List<QuranSurah>,
) {
    data class Word(
        val display: TextRange,
        /** Verse id, "surah:verse". */
        val source: String,
        /** The word in the Tanzil verse text; `null` for verse-number markers. */
        val canonical: TextRange?,
    )

    data class Line(
        val range: TextRange,
        val kind: QuranPage.Line.Kind,
        val centered: Boolean,
    )

    val text: String
    val words: List<Word>
    val lines: List<Line>
    val verses: Map<String, Ayah> = page.verses.values.associateBy { it.id }

    init {
        val builder = StringBuilder()
        val words = mutableListOf<Word>()
        val lines = mutableListOf<Line>()
        val canonical = page.verses.mapValues { canonicalWords(it.value) }
        for (line in page.lines) {
            lines.lastOrNull()?.let { previous ->
                val justified = { kind: QuranPage.Line.Kind, centered: Boolean ->
                    kind == QuranPage.Line.Kind.Ayah &&
                        !centered
                }
                // Adjacent justified lines join with a line separator so selection flows like one paragraph.
                builder.append(
                    if (justified(previous.kind, previous.centered) &&
                        justified(line.kind, line.centered)
                    ) {
                        ' '
                    } else {
                        '\n'
                    },
                )
            }
            val start = builder.length
            when (line.kind) {
                QuranPage.Line.Kind.SurahName -> {
                    builder.append("سُورَةُ ").append(
                        surahs
                            .firstOrNull {
                                it.id ==
                                    line.surah
                            }?.arabic
                            .orEmpty(),
                    )
                }

                QuranPage.Line.Kind.Basmallah -> {
                    builder.append("بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ")
                }

                QuranPage.Line.Kind.Ayah -> {
                    line.words.forEachIndexed { offset, word ->
                        if (offset > 0) builder.append(' ')
                        val range = TextRange(builder.length, word.text.length)
                        builder.append(word.text)
                        val verse = page.verses[word.index] ?: return@forEachIndexed
                        words += Word(range, verse.id, canonical[word.index]?.getOrNull(word.word - 1))
                    }
                }
            }
            lines += Line(TextRange.of(start, builder.length), line.kind, line.centered)
        }
        text = builder.toString()
        this.words = words
        this.lines = lines
    }

    /** Verse ids touched by [selection], in page order. */
    fun sources(selection: List<TextRange>): List<String> = selectedWords(selection).map { it.source }.distinct()

    fun canHighlight(selection: List<TextRange>): Boolean = selectedWords(selection).any { it.canonical != null }

    /** One highlight per selected verse, with ranges in its Tanzil text (block "arabic"). */
    fun highlights(selection: List<TextRange>): List<ReadingHighlight> =
        sources(selection).mapNotNull { source ->
            val verse = verses[source] ?: return@mapNotNull null
            val mapped =
                selectedWords(selection).filter { it.source == source }.flatMap { word ->
                    val canonical = word.canonical ?: return@flatMap emptyList()
                    selection.mapNotNull { map(it, word.display, text, canonical, verse.text) }
                }
            val ranges = merged(mapped, canonicalWords(verse)).mapNotNull { HighlightRange.of(it, verse.text) }
            if (ranges.isEmpty()) return@mapNotNull null
            ReadingHighlight(
                source = source,
                isHadith = false,
                block = "arabic",
                ranges = ranges,
                excerpt = ranges.joinToString(" … ") { it.quote },
                reference = source,
            )
        }

    /** Where a saved highlight appears on this page. */
    fun displayRanges(highlight: ReadingHighlight): List<TextRange> {
        val verse = verses[highlight.source]
        if (highlight.isHadith || verse == null) return emptyList()
        val canonical = highlight.ranges(verse.text, "arabic")
        val verseWords = words.filter { it.source == highlight.source }
        val matching =
            verseWords.flatMap { word ->
                if (highlight.block == null) return@flatMap listOf(word.display)
                val range = word.canonical ?: return@flatMap emptyList()
                canonical.mapNotNull { map(it, range, verse.text, word.display, text) }
            }
        return merged(matching, verseWords.map { it.display })
    }

    private fun selectedWords(selection: List<TextRange>) =
        words.filter { word ->
            selection.any {
                word.display.intersects(it)
            }
        }

    companion object {
        /** Word ranges in a Tanzil verse: tokens with a letter other than tatweel (standalone pause marks aren't words). */
        fun canonicalWords(verse: Ayah): List<TextRange> {
            val ranges =
                tokens(verse.text)
                    .filter { range ->
                        verse.text.substring(range.location, range.end).codePoints().anyMatch {
                            Character.isLetter(it) && it != 0x0640
                        }
                    }.toMutableList()
            // QPC joins إِل ياسين into one word; Tanzil keeps the two source words.
            if (verse.id == "37:130" && ranges.size == 4) {
                ranges[2] = ranges[2].union(ranges[3])
                ranges.removeAt(3)
            }
            return ranges
        }

        /** Runs of non-whitespace (Unicode, like Swift `\S`); Android's ICU regex has no `(?U)` flag. */
        private fun tokens(text: String): List<TextRange> {
            val ranges = mutableListOf<TextRange>()
            var start = -1
            var index = 0
            while (index <= text.length) {
                val space =
                    index == text.length ||
                        text.codePointAt(index).let { Character.isWhitespace(it) || Character.isSpaceChar(it) }
                if (space && start >= 0) {
                    ranges += TextRange.of(start, index)
                    start = -1
                } else if (!space && start < 0) {
                    start = index
                }
                index += if (index < text.length) Character.charCount(text.codePointAt(index)) else 1
            }
            return ranges
        }

        /**
         * Maps [selection] within word [source] of [sourceText] onto word [target] of [targetText]: whole words
         * map whole; partial selections align character by character when both spellings normalize alike,
         * otherwise fall back to the whole target word.
         */
        private fun map(
            selection: TextRange,
            source: TextRange,
            sourceText: String,
            target: TextRange,
            targetText: String,
        ): TextRange? {
            val start = maxOf(selection.location, source.location)
            val end = minOf(selection.end, source.end)
            if (end <= start) return null
            val intersection = TextRange.of(start, end)
            if (intersection == source) return target
            val from = letters(sourceText, source)
            val to = letters(targetText, target)
            if (from.isEmpty() || from.map { it.first } != to.map { it.first }) return target
            val selected =
                from
                    .zip(to)
                    .filter { (letter, _) ->
                        letter.second.intersects(intersection)
                    }.map { it.second.second }
            if (selected.isEmpty()) return target
            return selected.first().union(selected.last())
        }

        private fun letters(
            text: String,
            range: TextRange,
        ): List<Pair<String, TextRange>> =
            graphemes(text, range.location, range.end).mapNotNull { character ->
                val key = QuranSearchText.normalize(text.substring(character.location, character.end)).trim()
                if (key.isEmpty()) null else key to character
            }

        /** Merges adjacent selected words, including their whitespace, without bridging unselected words. */
        private fun merged(
            ranges: List<TextRange>,
            words: List<TextRange>,
        ): List<TextRange> {
            val result = mutableListOf<TextRange>()
            for (range in ranges.sortedBy { it.location }) {
                val last = result.lastOrNull()
                if (last != null) {
                    val gap = TextRange(last.end, maxOf(0, range.location - last.end))
                    if (words.none { it.intersects(gap) }) {
                        result[result.lastIndex] = last.union(range)
                        continue
                    }
                }
                result += range
            }
            return result
        }
    }
}
