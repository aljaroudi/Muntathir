package com.aljaroudi.muntathir.ui.reader

import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.espresso.Espresso
import androidx.test.platform.app.InstrumentationRegistry
import com.aljaroudi.muntathir.R
import com.aljaroudi.muntathir.core.highlight.HighlightColor
import com.aljaroudi.muntathir.core.highlight.ReadingHighlight
import com.aljaroudi.muntathir.ui.theme.MuntathirTheme
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.util.Collections

/** Closing the editor any way saves the latest note, one write at a time. */
class HighlightEditorTest {
    @get:Rule val compose = createComposeRule()

    private val highlight =
        ReadingHighlight(
            source = "1:2",
            isHadith = false,
            excerpt = "Praise",
            reference = "1:2",
            color = HighlightColor.Green,
        )

    /** What reached the store, in order: the note saved, or "deleted". */
    private val writes: MutableList<String> = Collections.synchronizedList(mutableListOf())

    /** Calls to `onSave` so far, including ones still running or that failed. */
    @Volatile private var saveCalls = 0

    @Volatile private var dismissed = false

    private fun string(id: Int) = InstrumentationRegistry.getInstrumentation().targetContext.getString(id)

    private fun open(save: suspend (call: Int) -> Unit = {}) {
        compose.setContent {
            MuntathirTheme {
                HighlightEditorSheet(
                    HighlightDraft(listOf(highlight), existing = true),
                    HighlightColor.entries,
                    onSave = { batch ->
                        val call = ++saveCalls
                        save(call)
                        writes += batch.single().note
                    },
                    onDelete = { writes += "deleted" },
                    onDismiss = { dismissed = true },
                )
            }
        }
        compose.waitForIdle()
    }

    private fun type(text: String) = compose.onNodeWithTag("highlight-note-editor").performTextInput(text)

    private fun back() {
        Espresso.closeSoftKeyboard()
        Espresso.pressBack()
    }

    private fun awaitDismissed() = compose.waitUntil(10_000) { dismissed }

    @Test
    fun backBeforeTheAutosavePauseSavesTheNote() {
        open()
        // Drive the clock by hand so the close lands inside the 400 ms pause.
        compose.mainClock.autoAdvance = false
        type("note")
        back()
        var elapsed = 0L
        while (!dismissed && elapsed < 390) {
            compose.mainClock.advanceTimeByFrame()
            elapsed += 16
            Thread.sleep(16)
        }
        assertTrue("closed within the pause", dismissed)
        compose.mainClock.autoAdvance = true
        assertEquals(listOf("note"), writes)
        assertEquals(1, saveCalls)
    }

    @Test
    fun backDuringASlowAutosaveWaitsThenSavesTheLatestNote() {
        val gate = CompletableDeferred<Unit>()
        open { if (it == 1) gate.await() }
        type("a")
        compose.waitUntil(10_000) { saveCalls == 1 }
        type("b")
        back()
        compose.waitForIdle()
        // The close waits for the running autosave and takes no more input.
        assertEquals(1, saveCalls)
        assertFalse(dismissed)
        compose.onNodeWithTag("highlight-note-editor").assertIsNotEnabled()
        gate.complete(Unit)
        awaitDismissed()
        assertEquals(listOf("a", "ab"), writes)
    }

    @Test
    fun aFailedSaveCanBeRetried() {
        open { if (it == 1) error("offline") }
        type("note")
        back()
        compose.waitUntil(10_000) {
            compose.onAllNodes(hasText(string(R.string.retry))).fetchSemanticsNodes().isNotEmpty()
        }
        assertFalse(dismissed)
        compose.onNodeWithText(string(R.string.retry)).performClick()
        awaitDismissed()
        assertEquals(listOf("note"), writes)
    }

    @Test
    fun aFailedSaveCanBeDiscarded() {
        open { error("offline") }
        type("note")
        back()
        compose.waitUntil(10_000) {
            compose.onAllNodes(hasText(string(R.string.discard_changes))).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText(string(R.string.discard_changes)).performClick()
        awaitDismissed()
        assertEquals(emptyList<String>(), writes)
    }

    @Test
    fun aPendingAutosaveCannotRestoreADeletedHighlight() {
        val gate = CompletableDeferred<Unit>()
        open { if (it == 1) gate.await() }
        type("a")
        compose.waitUntil(10_000) { saveCalls == 1 }
        // Another pause is pending when Delete is confirmed.
        type("b")
        Espresso.closeSoftKeyboard()
        compose.onNodeWithTag("highlight-delete").performClick()
        compose.onNodeWithText(string(R.string.delete_highlight)).performClick()
        gate.complete(Unit)
        awaitDismissed()
        compose.mainClock.advanceTimeBy(1_000)
        compose.waitForIdle()
        assertEquals(listOf("a", "deleted"), writes)
        assertEquals(1, saveCalls)
    }
}
