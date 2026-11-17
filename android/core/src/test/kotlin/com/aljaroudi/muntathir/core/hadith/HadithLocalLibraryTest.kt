package com.aljaroudi.muntathir.core.hadith

import com.aljaroudi.muntathir.core.sql.JdbcDriver
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import java.io.File
import java.nio.file.Files
import kotlin.math.abs
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Port of Swift `HadithLocalLibraryTests`. */
class HadithLocalLibraryTest {
    private val root: File = Files.createTempDirectory("library").toFile()
    private val fixtures = mutableListOf<HadithFixture>()

    @AfterTest
    fun cleanUp() {
        root.deleteRecursively()
        fixtures.forEach(HadithFixture::remove)
    }

    private fun fixture(count: Int) = HadithFixture(count).also { fixtures += it }

    private val library = HadithLocalLibrary(root, JdbcDriver)
    private val reader = HadithReader(JdbcDriver)

    private suspend fun installed() = library.books().filter { it.installed }

    @Test
    fun removalReclaimsSpaceAndRestorationPreservesOtherChoices() =
        runBlocking<Unit> {
            val fixture = fixture(600)
            reader.commit(library.prepare(fixture.file), library.file)
            val before = library.file.length()
            val books = installed()
            assertEquals(2, books.size)
            assertTrue(books.all { (it.estimatedBytes ?: 0) > 0 })
            assertTrue(abs(books.sumOf { it.estimatedBytes ?: 0 } - before) <= 2)
            val source = reader.source(1)!!
            reader.commit(library.prepare(library.file, removing = "merged"), library.file)
            val after = library.file.length()
            assertTrue(after < before)
            val retained = library.books()
            assertNull(retained.first { it.id == "merged" }.estimatedBytes)
            assertEquals(after, retained.first { it.id == "other" }.estimatedBytes)
            assertNull(reader.resolve(source))
            assertEquals(listOf("other"), reader.catalog().map { it.id })
            assertTrue(reader.page(HadithRequest("intentions")).rows.isEmpty())
            assertEquals(listOf(100_001), reader.page(HadithRequest("نص")).rows.map { it.id })
            assertEquals(2, library.books().size)
            reader.commit(library.prepare(library.file, removing = "other"), library.file)
            assertTrue(reader.catalog().isEmpty())
            reader.commit(library.prepare(fixture.file, restoring = "merged"), library.file)
            assertEquals(listOf("merged"), installed().map { it.id })
            assertEquals(
                "v1",
                reader
                    .detail(1)
                    .narration.source
                    ?.book,
            )
            assertEquals(1, reader.resolve(source))
            assertEquals(HadithReader.PAGE_SIZE, reader.page(HadithRequest("intentions")).rows.size)
            assertEquals(HadithReader.PAGE_SIZE, reader.page(HadithRequest("الأعمال")).rows.size)
            val relaunched = HadithLocalLibrary(root, JdbcDriver)
            assertEquals(listOf("merged"), relaunched.books().filter { it.installed }.map { it.id })
        }

    @Test
    fun estimatesIncludeDependentTranslationContent() =
        runBlocking<Unit> {
            reader.commit(library.prepare(fixture(2).file), library.file)
            val before = library.books()
            val beforeOther = before.first { it.id == "other" }.estimatedBytes!!
            HadithFixture.script(
                library.file,
                """
                CREATE TABLE translation(hadith_id INTEGER, text BLOB);
                INSERT INTO translation VALUES(100001, zeroblob(100000));
                """,
            )
            val after = library.books()
            val afterOther = after.first { it.id == "other" }.estimatedBytes!!
            assertTrue(
                afterOther.toDouble() / after.sumOf { it.estimatedBytes ?: 0 } >
                    beforeOther.toDouble() / before.sumOf { it.estimatedBytes ?: 0 },
            )
        }

    @Test
    fun cancelledPreparationKeepsTheCurrentLibrary() =
        runBlocking<Unit> {
            reader.commit(library.prepare(fixture(2).file), library.file)
            val cancelled = async(start = CoroutineStart.LAZY) { library.prepare(library.file, removing = "merged") }
            cancelled.cancel()
            assertFailsWith<CancellationException> { cancelled.await() }
            assertEquals(1, reader.detail(1).narration.id)
            assertEquals(2, installed().size)
        }

    @Test
    fun failedReplacementPreservesReadableLibrary() =
        runBlocking<Unit> {
            reader.commit(library.prepare(fixture(2).file), library.file)
            val corrupt = File(root, "corrupt.db").apply { writeText("invalid") }
            assertFailsWith<Exception> { library.prepare(corrupt) }
            assertEquals(1, reader.detail(1).narration.id)
            assertEquals(2, installed().size)
            assertFalse(root.list().orEmpty().any { it.startsWith("staging-") })
        }
}
