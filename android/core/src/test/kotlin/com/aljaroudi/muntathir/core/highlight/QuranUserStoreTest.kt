package com.aljaroudi.muntathir.core.highlight

import com.aljaroudi.muntathir.core.text.TextRange
import kotlinx.coroutines.runBlocking
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Port of Swift `QuranUserStoreTests` (the store logic; Room itself is covered on device). */
class QuranUserStoreTest {
    private class MemoryRecords : UserRecords {
        val tables = mutableMapOf<UserRecords.Table, MutableMap<String, StoredRecord>>()
        var failWrites = false

        override suspend fun all(table: UserRecords.Table) = tables[table]?.values?.toList().orEmpty()

        override suspend fun write(
            table: UserRecords.Table,
            rows: List<StoredRecord>,
        ) {
            if (failWrites) throw IOException("Disk full")
            val stored = tables.getOrPut(table) { mutableMapOf() }
            rows.forEach { stored[it.recordID] = it }
        }
    }

    private var clock = 1_000L

    private fun store(
        records: UserRecords = MemoryRecords(),
        installation: String = "device",
    ) = QuranUserStore(records, { installation }, { clock }).also { runBlocking { it.reopen() } }

    private fun highlight(
        source: String = "1:1",
        note: String = "",
        isHadith: Boolean = false,
    ) = ReadingHighlight(source = source, isHadith = isHadith, excerpt = "excerpt", reference = source, note = note)

    @Test
    fun multiVerseHighlightsSaveTogetherAndRejectInvalidBatches(): Unit =
        runBlocking {
            val store = store()
            val first = highlight("1:1")
            val second = highlight("1:2")
            store.save(listOf(first, second).map { it.copy(color = HighlightColor.Blue, note = "shared") })
            assertEquals(2, store.highlights.value.size)
            assertTrue(store.highlights.value.all { it.color == HighlightColor.Blue && it.note == "shared" })
            assertFailsWith<QuranUserStoreException> {
                store.save(listOf(first.copy(note = "changed"), highlight(source = "")))
            }
            assertEquals("shared", store.highlights(first.source).single().note)
            assertFailsWith<QuranUserStoreException> { store.save(listOf(highlight().copy(block = "arabic"))) }
        }

    @Test
    fun multipleHighlightsKeepNotesAndSeparateQuranFromHadith() =
        runBlocking {
            val records = MemoryRecords()
            val store = store(records)
            val first = highlight(note = "First thought")
            store.save(listOf(first))
            store.save(listOf(highlight(note = "Another thought")))
            store.save(listOf(highlight(note = "Hadith", isHadith = true)))
            assertEquals(2, store.highlights("1:1").size)
            assertEquals(1, store.highlights("1:1", isHadith = true).size)
            store.delete(first)
            assertEquals(listOf("Another thought"), store.highlights("1:1").map { it.note })
            assertTrue(records.all(UserRecords.Table.Highlights).any { it.itemID == first.id && it.isTombstone })
            // Whitespace-only notes are saved empty.
            store.save(listOf(highlight(source = "2:1", note = "  \n")))
            assertEquals("", store.highlights("2:1").single().note)
        }

    @Test
    fun syncUsesStableTieBreakAndLocalEditsBeatImportedState() =
        runBlocking {
            val records = MemoryRecords()
            val item = highlight(note = "imported")
            for (recordID in listOf("z", "a")) {
                records.write(
                    UserRecords.Table.Highlights,
                    listOf(StoredRecord(recordID, item.id, "other", encode(item.copy(note = recordID)), 100, false)),
                )
            }
            val store = store(records)
            assertEquals(
                "z",
                store.highlights.value
                    .single()
                    .note,
            )
            clock = 50
            store.save(listOf(item.copy(note = "edited")))
            assertEquals(
                "edited",
                store.highlights.value
                    .single()
                    .note,
            )
            assertTrue(
                store.highlights.value
                    .single()
                    .modifiedAt > 100,
            )
            store.delete(item)
            assertTrue(store.highlights.value.isEmpty())
            // This installation wrote one row of its own and reused it.
            assertEquals(1, records.all(UserRecords.Table.Highlights).count { it.installationID == "device" })
        }

    @Test
    fun failedSaveAndDeleteRollBackAndCanRetry() =
        runBlocking {
            val records = MemoryRecords()
            val store = store(records)
            val item = highlight(note = "saved")
            store.save(listOf(item))
            records.failWrites = true
            assertFailsWith<IOException> { store.save(listOf(item.copy(note = "draft"))) }
            assertEquals(
                "saved",
                store.highlights.value
                    .single()
                    .note,
            )
            assertFailsWith<IOException> { store.delete(item) }
            assertEquals(1, store.highlights.value.size)
            records.failWrites = false
            store.save(listOf(item.copy(note = "draft")))
            assertEquals(
                "draft",
                store.highlights.value
                    .single()
                    .note,
            )
        }

    @Test
    fun highlightsSurviveReopening() =
        runBlocking {
            val records = MemoryRecords()
            store(records).save(listOf(highlight(note = "kept").copy(color = HighlightColor.Purple)))
            val reopened = store(records)
            assertEquals(
                HighlightColor.Purple,
                reopened.highlights.value
                    .single()
                    .color,
            )
            assertEquals(
                "kept",
                reopened.highlights.value
                    .single()
                    .note,
            )
        }

    @Test
    fun bookmarksDeduplicateAndRemainSeparateFromHighlights() =
        runBlocking {
            val records = MemoryRecords()
            val store = store(records)
            val bookmark = ReadingBookmark("1:1", isHadith = false, excerpt = "e", reference = "1:1", createdAt = 5)
            store.save(bookmark)
            clock = 2_000
            store.save(bookmark.copy(createdAt = 9))
            store.save(ReadingBookmark("1:1", isHadith = true, excerpt = "e", reference = "Book 1"))
            assertEquals(2, store.bookmarks.value.size)
            assertEquals(5, store.bookmark("1:1")?.createdAt)
            assertTrue(store.highlights.value.isEmpty())
            store.delete(bookmark)
            assertNull(store.bookmark("1:1"))
            assertNotNull(store.bookmark("1:1", isHadith = true))
            assertTrue(records.all(UserRecords.Table.Bookmarks).any { it.itemID == bookmark.id && it.isTombstone })
        }

    @Test
    fun bookmarkFailuresRollBackAndCanRetry() =
        runBlocking {
            for (ruling in listOf(null, RulingID("sistani", "ar", "42"))) {
                val records = MemoryRecords()
                val store = store(records)
                val bookmark =
                    ReadingBookmark(
                        ruling?.siteID ?: "1:1",
                        isHadith = false,
                        excerpt = "e",
                        reference = "r",
                        ruling = ruling,
                    )
                records.failWrites = true
                assertFailsWith<IOException> { store.save(bookmark) }
                assertTrue(store.bookmarks.value.isEmpty())
                records.failWrites = false
                store.save(bookmark)
                records.failWrites = true
                assertFailsWith<IOException> { store.delete(bookmark) }
                assertEquals(1, store.bookmarks.value.size)
                records.failWrites = false
                store.delete(bookmark)
                assertTrue(store.bookmarks.value.isEmpty())
            }
        }

    @Test
    fun rulingsBookmarksKeepScopeAndValidateIdentity(): Unit =
        runBlocking {
            val legacy =
                ReadingBookmark.decode(
                    """{"source":"42","isHadith":false,"excerpt":"e","reference":"r","createdAt":0,"modifiedAt":0}""",
                )
            assertEquals("quran:42", legacy.id)
            assertEquals(ReadingBookmark.Kind.Quran, legacy.kind)
            val rulings =
                listOf(
                    RulingID("sistani", "ar", "42"),
                    RulingID("sistani", "en", "42"),
                    RulingID("khamenei", "ar", "42"),
                ).map { ReadingBookmark(it.siteID, false, "e", "r", ruling = it) }
            for (bookmark in rulings) {
                assertEquals(bookmark, ReadingBookmark.decode(bookmark.encode()))
                assertFalse("isHadith" in bookmark.encode())
            }
            assertEquals("ruling:7:sistani2:ar2:42", rulings[0].id)
            assertEquals(4, (rulings.map { it.id } + legacy.id).toSet().size)
            val store = store()
            assertFailsWith<QuranUserStoreException> { store.save(rulings[0].copy(source = "other")) }
            rulings.forEach { store.save(it) }
            store.save(legacy)
            store.delete(rulings[0])
            assertEquals(3, store.bookmarks.value.size)
            assertNotNull(store.bookmark("42"))
            assertNotNull(store.bookmark("42", ruling = rulings[1].ruling))
        }

    @Test
    fun rangesPreserveRepeatedTextAndWholeItemScope() {
        val text = "الله الله"
        val range = HighlightRange.of(TextRange(5, 4), text)!!
        val partial = highlight().copy(block = "arabic", ranges = listOf(range))
        assertEquals(listOf(TextRange(5, 4)), partial.ranges(text, "arabic"))
        assertEquals(emptyList(), partial.ranges(text, "en.qarai"))
        assertFalse(partial.isAvailable(mapOf("arabic" to "changed text")))
        assertEquals(listOf(TextRange(0, text.length)), highlight().ranges(text, "en.qarai"))
    }

    @Test
    fun unavailableStoreRejectsWrites(): Unit =
        runBlocking {
            val store = QuranUserStore(MemoryRecords(), { throw IOException("No identity") })
            store.reopen()
            assertTrue(store.unavailable.value)
            assertFailsWith<QuranUserStoreException> { store.save(listOf(highlight())) }
        }

    @Test
    fun savedSectionsGroupBySourceOrDayAndRankSearches() {
        val zone = java.time.ZoneOffset.UTC
        val day = 86_400_000L
        val entries =
            listOf(
                SavedEntry(highlight("2:255", note = "throne").copy(id = "A", createdAt = day, modifiedAt = 3 * day)),
                SavedEntry(highlight("2:255").copy(id = "B", createdAt = 2 * day, modifiedAt = 2 * day)),
                SavedEntry(
                    ReadingBookmark("1:1", false, "praise", "1:1", createdAt = 2 * day + 5, modifiedAt = 4 * day),
                ),
            )
        val bySource = SavedEntry.sections(entries, byDate = false, query = "", zone, "en", emptyMap())
        // Bookmarks group under their bookmark id, highlights under their source.
        assertEquals(listOf("quran:1:1", "quran:2:255"), bySource.map { it.id })
        assertTrue(bySource[0].entries.single().bookmark != null)
        assertEquals(listOf("highlight:A", "highlight:B"), bySource[1].entries.map { it.id })
        val byDate = SavedEntry.sections(entries, byDate = true, query = "", zone, "en", emptyMap())
        assertEquals(2, byDate.size)
        assertEquals(java.time.LocalDate.of(1970, 1, 3), byDate[0].date)
        assertEquals(listOf("bookmark:quran:1:1", "highlight:B"), byDate[0].entries.map { it.id })
        val search = SavedEntry.sections(entries, byDate = false, query = "throne", zone, "en", emptyMap())
        assertEquals(listOf("matches"), search.map { it.id })
        assertEquals(listOf("highlight:A"), search[0].entries.map { it.id })
    }

    private fun encode(highlight: ReadingHighlight) =
        kotlinx.serialization.json.Json
            .encodeToString(highlight)
}
