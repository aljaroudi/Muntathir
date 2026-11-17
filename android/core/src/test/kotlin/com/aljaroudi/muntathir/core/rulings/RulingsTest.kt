package com.aljaroudi.muntathir.core.rulings

import com.aljaroudi.muntathir.core.Fixtures
import com.aljaroudi.muntathir.core.assets.AssetPack
import com.aljaroudi.muntathir.core.hadith.HadithDatabaseException
import com.aljaroudi.muntathir.core.hadith.HadithFixture
import com.aljaroudi.muntathir.core.highlight.RulingID
import com.aljaroudi.muntathir.core.sql.JdbcDriver
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.runBlocking
import org.junit.Assume.assumeTrue
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.util.Locale
import kotlin.system.measureTimeMillis
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Port of Swift `RulingsTests`, with Swift's `RulingsFixture`. */
class RulingsTest {
    private val directory: File = Files.createTempDirectory("rulings").toFile()
    private val fixture = File(directory, "rulings.db").also(::rulingsFixture)

    @AfterTest
    fun cleanUp() {
        directory.deleteRecursively()
    }

    private fun reader(file: File = fixture) = RulingsReader(JdbcDriver).also { runBlocking { it.install(file) } }

    @Test
    fun scopeAndStableReferences() =
        runBlocking<Unit> {
            val reader = reader()
            val found = reader.questions("sistani", "ar", "الصلاة")
            assertEquals(1, found.size)
            val id = RulingID("sistani", "ar", "42")
            assertEquals(id, found.first().id)
            assertEquals("جواب آخر", reader.questions("shirazi", "ar", "الصلاة").first().answer)
            assertTrue(reader.questions("sistani", "en", "الصلاة").isEmpty())
            assertTrue(reader.questions("sistani", "ar", "\" OR nope").isEmpty())
            assertEquals("نص أصلي", reader.question(id)?.answer)
            assertEquals("https://example.org/1", reader.question(id)?.source)
            val sections = reader.sections(id)
            assertEquals(listOf("الصلاة"), sections.map { it.title })
            assertEquals(listOf(id), reader.questions("sistani", "ar", sections.first()).map { it.id })
            assertTrue(reader.questions("sistani", "en", sections.first()).isEmpty())
            val sample = reader.questions("shirazi", "ar")
            assertEquals(listOf(RulingID("shirazi", "ar", "42")), sample.map { it.id })
            assertTrue(reader.sections(sample.first().id).isEmpty())
            val cancelled = async(start = CoroutineStart.LAZY) { reader.questions("sistani", "ar", "الصلاة") }
            cancelled.cancel()
            assertFailsWith<CancellationException> { cancelled.await() }
        }

    @Test
    fun languageMustBeAvailable() {
        val persian = RulingsLanguage("fa", "فارسی", rightToLeft = true)
        assertNull(RulingsReader.preferredLanguage(null, Locale.forLanguageTag("ar-SA"), listOf(persian)))
        assertEquals("fa", RulingsReader.preferredLanguage("fa", Locale.forLanguageTag("ar"), listOf(persian)))
        assertEquals("fa", RulingsReader.preferredLanguage("en", Locale.forLanguageTag("fa-IR"), listOf(persian)))
    }

    @Test
    fun downloadRetryRelaunchAndRemoval() =
        runBlocking<Unit> {
            val pack = FakePack(directory)
            val store = RulingsAssetStore(pack, RulingsReader(JdbcDriver))
            pack.installed = false
            store.refresh()
            assertEquals(RulingsStatus.Missing, store.state.value.status)
            pack.failing = true
            store.download()
            assertEquals(RulingsStatus.Failed, store.state.value.status)
            pack.failing = false
            pack.downloading = true
            store.refresh()
            assertEquals(RulingsStatus.Downloading, store.state.value.status)
            store.download()
            assertEquals(RulingsStatus.Ready, store.state.value.status)
            val relaunch = RulingsAssetStore(pack, RulingsReader(JdbcDriver))
            relaunch.refresh()
            assertEquals(RulingsStatus.Ready, relaunch.state.value.status)
            assertEquals(2, relaunch.reader.authorities().size)
            pack.failing = true
            store.remove()
            assertTrue(store.state.value.storageError)
            assertEquals(RulingsStatus.Ready, store.state.value.status)
            pack.failing = false
            store.remove()
            assertEquals(RulingsStatus.Missing, store.state.value.status)
            assertFailsWith<HadithDatabaseException> { store.reader.authorities() }
            store.download()
            assertEquals(RulingsStatus.Ready, store.state.value.status)
        }

    @Test
    fun incompatibleAndCorruptFilesAreRejected() =
        runBlocking<Unit> {
            HadithFixture.script(fixture, "PRAGMA user_version=99;")
            assertFailsWith<HadithDatabaseException.Incompatible> { RulingsReader(JdbcDriver).install(fixture) }
            fixture.writeText("invalid")
            assertFailsWith<HadithDatabaseException> { RulingsReader(JdbcDriver).install(fixture) }
        }

    @Test
    fun repeatedReaderQueriesAndRemoval() =
        runBlocking<Unit> {
            val reader = reader()
            val millis =
                measureTimeMillis {
                    repeat(200) {
                        assertEquals(2, reader.languages("sistani").size)
                        assertEquals("Original answer", reader.question(RulingID("sistani", "en", "42"))?.answer)
                    }
                }
            println("Rulings 400 queries: $millis ms")
            reader.install(null)
            assertFailsWith<HadithDatabaseException> { reader.languages("sistani") }
            reader.install(fixture)
            assertEquals(2, reader.authorities().size)
        }

    @Test
    fun packagedRulingsOpenAndSearch() =
        runBlocking<Unit> {
            val file = Fixtures.repository("build/rulings/dist/rulings.db")
            assumeTrue("build/rulings/dist/rulings.db isn't built", file.isFile)
            val reader = reader(file)
            val authorities = reader.authorities()
            assertTrue(authorities.any { it.id == "sistani" })
            val language = reader.languages("sistani").first()
            assertTrue(reader.questions("sistani", language.id).isNotEmpty())
        }

    /** Swift `RulingsTestBackend`: the pack folder is the fixture's. */
    private class FakePack(
        private val folder: File,
    ) : AssetPack {
        var installed = false
        var failing = false
        var downloading = false

        override suspend fun localDirectory() = if (installed) folder else null

        override suspend fun isDownloading() = downloading

        override suspend fun download() {
            if (failing) throw IOException("Offline")
            installed = true
            downloading = false
        }

        override suspend fun remove() {
            if (failing) throw IOException("Can't remove")
            installed = false
        }

        override fun events() = emptyFlow<AssetPack.Event>()
    }

    companion object {
        /** Swift `RulingsFixture`. */
        fun rulingsFixture(file: File) =
            HadithFixture.script(
                file,
                """
                PRAGMA application_id=1179809601;
                PRAGMA user_version=1;
                CREATE TABLE authority(code TEXT, name_ar TEXT, name_en TEXT, sort_order INTEGER);
                INSERT INTO authority VALUES ('sistani','السيستاني','Sistani',1),('shirazi','الشيرازي','Shirazi',2);
                CREATE TABLE language(code TEXT, name TEXT, direction TEXT);
                INSERT INTO language VALUES ('ar','العربية','rtl'),('en','English','ltr');
                CREATE TABLE topic(id INTEGER PRIMARY KEY,authority_code TEXT,language_code TEXT,title TEXT,parent_id INTEGER,position INTEGER);
                INSERT INTO topic VALUES (1,'sistani','ar','الصلاة',NULL,1), (2,'sistani','ar','الفرائض',1,2),(3,'sistani','en','Worship',NULL,1), (4,'sistani','en','Fasting',3,2),(5,'sistani','en','Charity',NULL,3);
                CREATE TABLE question(id INTEGER PRIMARY KEY,authority_code TEXT,language_code TEXT,site_id TEXT,question TEXT,answer TEXT,url TEXT);
                INSERT INTO question VALUES (100,'sistani','ar','42','الصلاة','نص أصلي','https://example.org/1'), (200,'shirazi','ar','42','الصلاة','جواب آخر','https://example.org/2'), (300,'sistani','en','42','Prayer','Original answer','https://example.org/3'), (301,'sistani','en','43','Fasting','Fasting answer','https://example.org/4'), (302,'sistani','en','44','Charity','Charity answer','http://example.org/5');
                CREATE TABLE placement(topic_id INTEGER,question_id INTEGER,position INTEGER);
                INSERT INTO placement VALUES (1,100,1),(2,100,1),(3,300,1),(4,301,1),(5,302,1);
                CREATE VIRTUAL TABLE question_fts USING fts5(question,answer,content='question',content_rowid='id');
                INSERT INTO question_fts(rowid,question,answer) SELECT id,question,answer FROM question;
                """,
            )
    }
}
