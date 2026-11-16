package com.aljaroudi.muntathir.core.quran

import com.aljaroudi.muntathir.core.highlight.HighlightRange
import com.aljaroudi.muntathir.core.text.TextRange
import com.aljaroudi.muntathir.core.text.substring
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

// Ports `QuranPageTextTests` against the bundled iOS quran.db.
class QuranPageTextTest {
    private val database = QuranTestDatabase

    private fun content(
        page: Int,
        surahs: List<QuranSurah> = emptyList(),
    ) = QuranPageText(database.page(page), surahs)

    @Test
    fun everyQPCWordMapsToCanonicalTextExceptVerseNumbers() {
        for (number in 1..QuranPage.COUNT) {
            val page = database.page(number)
            val content = QuranPageText(page, emptyList())
            val original = page.lines.flatMap { it.words }
            assertEquals(original.size, content.words.size, "page $number")
            for ((word, source) in content.words.zip(original)) {
                val verse = content.verses.getValue(word.source)
                assertEquals(source.text, content.text.substring(word.display))
                val isMarker = source.text.all { it.isDigit() }
                val canonical = word.canonical
                if (canonical != null) {
                    assertFalse(isMarker)
                    assertNotNull(HighlightRange.of(canonical, verse.text))
                } else {
                    assertTrue(isMarker, "Unmapped word on page $number: ${source.text}")
                }
            }
        }
    }

    @Test
    fun selectionCrossesLinesAndVersesAndKeepsSpaces() {
        val content = content(1)
        val first = content.words.first()
        val last = content.words.last { it.source == "1:2" && it.canonical != null }
        val highlights = content.highlights(listOf(first.display.union(last.display)))
        assertEquals(listOf("1:1", "1:2"), highlights.map { it.source })
        for (value in highlights) {
            val verse = content.verses.getValue(value.source)
            assertEquals(1, value.ranges.size)
            assertEquals(verse.text, value.ranges.first().quote)
            val rendered = content.displayRanges(value)
            assertEquals(1, rendered.size)
            assertTrue(' ' in content.text.substring(rendered[0]))
        }
    }

    @Test
    fun highlightEligibilityRequiresSelectedVerseText() {
        val content = content(1, database.surahs)
        val word = content.words.first { it.canonical != null }
        val marker = content.words.first { it.canonical == null }
        val heading = content.lines.first { it.kind == QuranPage.Line.Kind.SurahName }
        assertEquals("سُورَةُ " + database.surahs.first().arabic, content.text.substring(heading.range))
        assertFalse(content.canHighlight(emptyList()))
        assertFalse(content.canHighlight(listOf(heading.range)))
        assertFalse(content.canHighlight(listOf(marker.display)))
        assertFalse(content.canHighlight(listOf(TextRange(word.display.end, 1))))
        assertTrue(content.canHighlight(listOf(word.display)))
        assertTrue(content.canHighlight(listOf(heading.range, word.display, marker.display)))
        assertTrue(content.canHighlight(listOf(TextRange(word.display.location, 1))))
    }

    @Test
    fun disjointWordsDoNotHighlightTheWordBetweenThem() {
        val content = content(1)
        val words = content.words.filter { it.source == "1:1" && it.canonical != null }
        val highlight = content.highlights(listOf(words[0].display, words[2].display)).first()
        assertEquals(2, highlight.ranges.size)
        val ranges = content.displayRanges(highlight)
        assertEquals(2, ranges.size)
        assertTrue(ranges.none { it.intersects(words[1].display) })
    }

    @Test
    fun joinedSpellingMapsToBothCanonicalWords() {
        val content = content(database.page(37, 130))
        val word = content.words.last { it.source == "37:130" && it.canonical != null }
        val highlight = content.highlights(listOf(word.display)).first()
        assertEquals("إِل ياسينَ", highlight.excerpt)
        assertEquals(listOf(word.display), content.displayRanges(highlight))
    }

    @Test
    fun partialWordSelectionsRetainCharacterBoundariesAcrossDiacritics() {
        val content = content(1)
        val word = content.words.first { it.source == "1:1" && it.canonical != null }
        // "بِ": the first letter with its kasra.
        val selection = TextRange(word.display.location, 2)
        val saved = content.highlights(listOf(selection)).first()
        assertEquals("بِ", saved.excerpt)
        assertEquals(listOf(selection), content.displayRanges(saved))
    }

    @Test
    fun pageFragmentDoesNotSelectTheRestOfTheVerse() {
        val content = content(43)
        val first = content.words.first()
        val verse = content.verses.getValue(first.source)
        val highlight = content.highlights(listOf(first.display)).first()
        assertEquals(1, highlight.ranges.size)
        assertNotEquals(verse.text, highlight.excerpt)
        assertEquals(listOf(first.display), content.displayRanges(highlight))
        val marker = content.words.first { it.canonical == null }
        assertTrue(content.highlights(listOf(marker.display)).isEmpty())
        assertEquals(listOf(marker.source), content.sources(listOf(marker.display)))
    }
}
