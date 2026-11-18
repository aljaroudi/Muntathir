package com.aljaroudi.muntathir.ui.reader

import android.text.Selection
import android.text.Spannable
import android.text.Spanned
import android.text.style.BackgroundColorSpan
import androidx.activity.compose.setContent
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.aljaroudi.muntathir.core.highlight.HighlightRange
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.core.text.StyledText
import com.aljaroudi.muntathir.core.text.TextRange
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** P1.7 done-when: select → highlight → reopen restores the same UTF-16 ranges. */
class HighlightSelectionTest {
    @get:Rule val compose = createAndroidComposeRule<ReaderSpikeActivity>()

    private fun reader(): HighlightTextView =
        compose.activity.window.decorView
            .findViewWithTag(ReaderSpikeActivity.VIEW_TAG)

    private fun select(range: TextRange) {
        compose.runOnUiThread {
            val view = reader()
            Selection.setSelection(view.text as Spannable, range.location, range.end)
            assertTrue(view.highlightSelection())
        }
        compose.waitForIdle()
    }

    private fun backgrounds(): List<TextRange> {
        val text = reader().text as Spanned
        return text.getSpans(0, text.length, BackgroundColorSpan::class.java).map {
            TextRange.of(text.getSpanStart(it), text.getSpanEnd(it))
        }
    }

    @Test
    fun hiddenMarksKeepSelectionsAndHighlightPositionsWhenRestored() {
        val source = StyledText("بِسْمِ اللَّهِ")
        val showMarks = mutableStateOf(false)
        val saved = mutableStateOf(emptyList<ReadingHighlight>())
        compose.runOnUiThread {
            compose.activity.setContent {
                CompositionLocalProvider(LocalShowArabicDiacritics provides showMarks.value) {
                    ReaderText(
                        source,
                        ReaderSpikeActivity.BLOCK,
                        28f,
                        highlights = saved.value,
                        canHighlight = { true },
                        onHighlight = { selection ->
                            val range = requireNotNull(HighlightRange.of(selection.single(), source.text))
                            saved.value =
                                listOf(
                                    ReadingHighlight(
                                        source = "1:1",
                                        isHadith = false,
                                        block = ReaderSpikeActivity.BLOCK,
                                        ranges = listOf(range),
                                        excerpt = range.quote,
                                        reference = "1:1",
                                    ),
                                )
                        },
                        configure = { tag = ReaderSpikeActivity.VIEW_TAG },
                    )
                }
            }
        }
        compose.waitForIdle()
        val visible = TextRange(4, 4)
        select(visible)
        compose.runOnUiThread {
            assertEquals("اللَّهِ", saved.value.single().excerpt)
            assertEquals(listOf(visible), backgrounds())
            showMarks.value = true
        }
        compose.waitForIdle()
        compose.runOnUiThread {
            assertEquals(source.text, reader().text.toString())
            assertEquals(listOf(TextRange(source.text.indexOf(' ') + 1, "اللَّهِ".length)), backgrounds())
        }
    }

    @Test
    fun selectHighlightReopenRestoresTheSameRanges() {
        compose.runOnUiThread { compose.activity.store.clear() }
        compose.activityRule.scenario.recreate()
        compose.waitForIdle()
        val text = compose.activity.content.text
        // A word with diacritics, a selection across paragraphs (list marker included), and one ending after an emoji.
        val word = TextRange(text.indexOf("الأَعْمَالُ"), "الأَعْمَالُ".length)
        val crossing = TextRange.of(text.indexOf("نَوَى"), text.indexOf("Actions") + "Actions".length)
        val emoji = TextRange.of(text.indexOf("intentions"), text.indexOf("😀") + 2)
        val expected = listOf(word, crossing, emoji)
        expected.forEach(::select)
        assertEquals(
            expected,
            compose.activity.store.load().flatMap { highlight ->
                highlight.ranges.map { TextRange(it.location, it.length) }
            },
        )

        // Reopen: a new activity reads the saved highlights and draws them at the same offsets.
        compose.activityRule.scenario.recreate()
        compose.waitForIdle()
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        val restored = compose.activity.store.load()
        assertEquals(expected, restored.flatMap { highlight -> highlight.ranges(text, ReaderSpikeActivity.BLOCK) })
        assertEquals(
            expected.map { text.substring(it.location, it.end) },
            restored.flatMap { it.ranges }.map { it.quote },
        )
        compose.runOnUiThread { assertEquals(expected.toSet(), backgrounds().toSet()) }
    }
}
