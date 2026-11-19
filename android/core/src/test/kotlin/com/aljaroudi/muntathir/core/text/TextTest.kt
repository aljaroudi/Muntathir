package com.aljaroudi.muntathir.core.text

import com.aljaroudi.muntathir.core.highlight.HighlightRange
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

// Ports `SearchRelevanceTests`, `HadithTextTests` and the HighlightRange cases of `QuranUserStoreTests`.
// Styling is asserted as `TextStyle` spans rather than SwiftUI attributes.
class TextTest {
    @Test
    fun hiddenMarksPreserveLettersPauseSignsStylesAndSourceSelections() {
        val prefix = "🌙 أ آ أ آ ۖ "
        val marked = "رَّحۡمَٰنࣰ"
        val original = StyledText(prefix + marked).styled(prefix.length, prefix.length + marked.length, TextStyle.Match)
        val display = ArabicDisplay(original)
        assertEquals(prefix + "رحمن", display.text.text)
        val sourceRange = TextRange(prefix.length, marked.length)
        val visibleRange = TextRange(prefix.length, 4)
        assertEquals(visibleRange, display.displayRange(sourceRange))
        assertEquals(sourceRange, display.sourceRange(visibleRange))
        assertEquals(listOf(TextSpan(prefix.length, visibleRange.end, TextStyle.Match)), display.text.spans)
    }

    @Test
    fun exactAndProximityPrecedeBroaderMatches() {
        val terms = QuranSearchText.terms("acts mercy")
        val exact = SearchRelevance.score("acts mercy", terms)!!
        val near = SearchRelevance.score("acts of mercy", terms)!!
        val far = SearchRelevance.score("acts described in many other words before mercy", terms)!!
        assertTrue(exact < near)
        assertTrue(near < far)
        assertNull(SearchRelevance.score("mercy", terms))
    }

    @Test
    fun conservativeCorrections() {
        assertEquals(2, SearchRelevance.score("intentions", listOf("intentinos"))?.tier)
        assertNull(SearchRelevance.score("cat", listOf("bat")))
        assertEquals(2, SearchRelevance.score("acts of mercy", listOf("acts", "mercy", "parents"))?.tier)
        assertNull(SearchRelevance.score("mercy", listOf("acts", "mercy", "parents")))
    }

    @Test
    fun arabicNormalizationPreservesExactPriority() {
        assertEquals(
            0,
            SearchRelevance
                .score(
                    "إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ",
                    QuranSearchText.terms("انما الاعمال بالنيات"),
                )?.tier,
        )
    }

    @Test
    fun numericReferencesMatchArabicOnlyText() {
        assertEquals(0, SearchRelevance.score("1:1 بِسْمِ اللَّهِ", QuranSearchText.terms("1:1"))?.tier)
        assertNull(SearchRelevance.score("1:1 بِسْمِ اللَّهِ", listOf("mercy")))
    }

    @Test
    fun queryParsing() {
        assertEquals(listOf("انما", "الاعمال"), QuranSearchText.terms("إِنَّمَا، الأَعْمَالُ"))
        assertEquals(listOf("acts", "mercy"), QuranSearchText.terms("Acts \"mercy\"*"))
        assertEquals(12, QuranSearchText.number(" ١٢ "))
        assertNull(QuranSearchText.number("12a"))
        assertEquals(2 to 255, QuranSearchText.reference("2:255"))
        assertNull(QuranSearchText.reference("mercy"))
        assertFailsWith<InvalidReferenceException> { QuranSearchText.reference("115:1") }
        assertTrue(QuranSearchText.isSearchableVerse("بِسْمِ اللَّهِ الرَّحۡمَٰنࣰ"))
        assertFalse(QuranSearchText.isSearchableVerse("الم"))
    }

    @Test
    fun markdownPreservesParagraphsHeadingsListsAndLinks() {
        val paragraphs =
            HadithText.markdown(
                "# Heading\n\nA **bold** and *italic* [link](https://example.com).\n\n- one\n- two\n\n> quote",
            )
        assertEquals(5, paragraphs.size)
        assertEquals(1, paragraphs[0].heading)
        assertEquals("•", paragraphs[2].marker)
        assertTrue(paragraphs[4].quoted)
        assertTrue(paragraphs[1].text.has(TextStyle.Strong))
        assertTrue(paragraphs[1].text.has(TextStyle.Link("https://example.com")))
        assertTrue("Heading\nA bold" in HadithText.flattened(paragraphs).text)
        assertEquals("• one", HadithText.canonical(paragraphs).text.split("\n\n")[2])
    }

    @Test
    fun markdownMatchesFoundationFlattening() {
        // Soft breaks become spaces; backtick-quoted ʿayn pairs are code spans, as on iOS.
        assertEquals(
            "line one line two",
            HadithText
                .markdown("line one\nline two")
                .single()
                .text.text,
        )
        assertEquals(
            "Ibn Abbas and Kab said",
            HadithText
                .markdown("Ibn `Abbas and Ka`b said")
                .single()
                .text.text,
        )
        assertEquals(listOf("3.", "4."), HadithText.markdown("3. three\n4. four").map { it.marker })
        assertEquals(
            "an alt image and struck",
            HadithText
                .markdown("an ![alt](https://x.y/z.png) image and ~~struck~~")
                .single()
                .text.text,
        )
    }

    @Test
    fun arabicPreviewCentersLateMatchesAndKeepsDiacritics() {
        val source = "مقدمة طويلة ".repeat(100) + "**إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ**" + " خاتمة".repeat(100)
        val preview = HadithText.preview(source, QuranSearchText.terms("الاعمال"))
        assertTrue(preview.text.startsWith("… "))
        assertTrue("الأَعْمَالُ" in preview.text)
        assertTrue(graphemes(preview.text).size <= 264)
        assertFalse("**" in preview.text)
        assertEquals(
            "الأَعْمَالُ",
            preview.spans(TextStyle.Match).joinToString("") {
                preview.text.substring(it.start, it.end)
            },
        )
    }

    @Test
    fun markedEnglishPreviewPreservesMarkdownAndStemSpans() {
        val source =
            "Some introduction. ".repeat(100) +
                "**${HadithText.START_MARKER}believers${HadithText.END_MARKER}** have [faith](https://example.com)."
        val preview = HadithText.preview(source, marked = true)
        assertTrue("believers" in preview.text)
        assertFalse(HadithText.START_MARKER in preview.text)
        val match = preview.spans(TextStyle.Match).single()
        assertEquals("believers", preview.text.substring(match.start, match.end))
        assertTrue(preview.spans(TextStyle.Strong).any { it.start <= match.start && it.end >= match.end })
        assertTrue(preview.spans.any { it.style is TextStyle.Link })
    }

    @Test
    fun fullHighlightsKeepMarkdownAndNeverTruncate() {
        val source = "# Heading\n\n" + "مقدمة طويلة ".repeat(100) + "**الأَعْمَالُ**\n\n- خاتمة"
        val full = HadithText.highlighted(source, QuranSearchText.terms("الاعمال"))
        assertTrue(HadithText.flattened(full).length > 1000)
        assertEquals(1, full.first().heading)
        assertEquals("•", full.last().marker)
        assertTrue(full.any { it.text.has(TextStyle.Match) })
        val marked = "${HadithText.START_MARKER}narrator books${HadithText.END_MARKER} end"
        val narrator = HadithText.highlighted(HadithText.markedSlice(marked, 0 until 8), marked = true).single().text
        val body = HadithText.highlighted(HadithText.markedSlice(marked, 9 until 18), marked = true).single().text
        assertEquals("narrator", narrator.text)
        assertEquals("books end", body.text)
        assertTrue(narrator.has(TextStyle.Match))
        assertEquals(listOf(TextSpan(0, 5, TextStyle.Match)), body.spans(TextStyle.Match))
    }

    @Test
    fun quranPreviewCentersLiteralMatchWithoutParsingOrChangingSource() {
        val source = "مقدمة طويلة ".repeat(40) + "كُرْسِيُّهُ" + " خاتمة".repeat(40)
        val preview = SearchMatch.preview(SearchMatch.text(source, "كرسي"))
        assertTrue(preview.text.startsWith("… "))
        assertTrue("كُرْسِيُّهُ" in preview.text)
        assertTrue(preview.has(TextStyle.Match))
        assertEquals("**نص**", SearchMatch.text("**نص**", "نص").text)
    }

    @Test
    fun previewPrefersTheFullArabicPhrase() {
        val phrase = "من كنت مولاه فعلي"
        val source = "من قبل ".repeat(250) + phrase
        val preview = HadithText.preview(source, phrase.split(" "))
        assertTrue(phrase in preview.text)
        val filteredTerms = QuranSearchText.queryTerms(phrase)
        assertEquals(listOf("كنت", "مولاه", "فعلي"), filteredTerms)
        assertTrue(phrase in HadithText.preview(source, filteredTerms).text)
    }

    @Test
    fun previewBoundsAndUnmatchedTextAreSafe() {
        assertEquals("", HadithText.preview("").text)
        val snippet = HadithText.preview("**Hello**\n\nworld", listOf("absent"))
        assertEquals("Hello\nworld", snippet.text)
        assertFalse(snippet.has(TextStyle.Match))
        assertEquals(2, HadithText.preview("رحمة ورحمة", listOf("رحمه")).spans(TextStyle.Match).size)
    }

    @Test
    fun visibleBlocksPreferMatches() {
        val plain = StyledText("a")
        val matched = StyledText("b").styled(0, 1, TextStyle.Match)
        assertEquals(listOf(1), SearchMatch.visibleBlocks(listOf(plain, matched), 0))
        assertEquals(listOf(0), SearchMatch.visibleBlocks(listOf(plain, plain), 0))
        assertEquals(listOf(1), SearchMatch.visibleBlocks(listOf(StyledText(""), plain), 0))
    }

    @Test
    fun rangesPreserveRepeatedArabicTextAndRejectChangedSource() {
        val text = "بِسْمِ الله بِسْمِ الله"
        val start = text.lastIndexOf("بِسْمِ")
        val range = TextRange(start, "بِسْمِ".length)
        val selection = assertNotNull(HighlightRange.of(range, text))
        val value = ReadingHighlight("1:1", false, "arabic", listOf(selection), "بِسْمِ", "1:1")
        assertEquals(listOf(range), value.ranges(text, "arabic"))
        assertTrue(value.ranges(text, "en.qarai").isEmpty())
        assertFalse(value.isAvailable(mapOf("arabic" to "changed")))
        assertTrue(value.isAvailable(mapOf("arabic" to text)))
        assertNull(HighlightRange.of(TextRange(999, 1), text))
        assertNull(HighlightRange.of(TextRange(0, 0), text))
        // Surrogate pairs can't be split; canonically equivalent quotes still validate.
        assertNull(HighlightRange.of(TextRange(1, 1), "x😀"))
        assertNotNull(HighlightRange(0, 2, "é").validated("é"))
    }

    @Test
    fun multipleSelectionRangesAndWholeItemScope() {
        val text = "Arabic English العربية"
        val ranges =
            listOf(TextRange(0, 6), TextRange(text.indexOf("العربية"), "العربية".length)).map {
                HighlightRange.of(it, text)!!
            }
        val partial = ReadingHighlight("source", true, "english", ranges, "excerpt", "source")
        assertEquals(2, partial.ranges(text, "english").size)
        val whole = ReadingHighlight("source", true, excerpt = text, reference = "source")
        for (block in listOf("arabic", "english", "englishNarrator", "en.qarai")) {
            assertEquals(listOf(TextRange(0, text.length)), whole.ranges(text, block))
        }
    }
}
