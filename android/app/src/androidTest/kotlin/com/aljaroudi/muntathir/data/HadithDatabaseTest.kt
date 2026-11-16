package com.aljaroudi.muntathir.data

import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import androidx.test.platform.app.InstrumentationRegistry
import com.aljaroudi.muntathir.core.text.QuranSearchText
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File

/** FTS5 through the bundled SQLite driver on a small database built from `build/hadith/schema.sql`. */
class HadithDatabaseTest {
    private lateinit var file: File

    @Before
    fun createDatabase() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        file = File(context.cacheDir, "hadith-test.db").also { it.delete() }
        BundledSQLiteDriver().open(file.absolutePath).use { db ->
            SCHEMA
                .split(";")
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .forEach(db::execSQL)
            db.execSQL("INSERT INTO collection VALUES ('kafi', 'الكافي', 'Al-Kafi', 1)")
            db.execSQL(
                "INSERT INTO book (id, collection_id, sect, book_group, name_ar, name_en) VALUES ('kafi-1', 'kafi', 'shia', 'shia', 'الكافي', 'Al-Kafi')",
            )
            db.execSQL("INSERT INTO chapter VALUES (1, 'kafi-1', 1, 'c1', '', '', 3)")
            val rows =
                listOf(
                    Triple(1, "إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ", "Actions are judged by intentions."),
                    Triple(2, "الأَعْمَالُ الصَّالِحَةُ وَالنِّيَّاتُ", "Good deeds and sincere intentions."),
                    Triple(3, "طَلَبُ الْعِلْمِ فَرِيضَةٌ", "Seeking knowledge is an obligation."),
                )
            for ((id, arabic, english) in rows) {
                db.execSQL(
                    "INSERT INTO hadith (id, book_id, chapter_id, chapter_idx, id_in_book, arabic, english_text) VALUES ($id, 'kafi-1', 1, 1, $id, '$arabic', '$english')",
                )
                // The Arabic index is contentless and stores normalized search keys, as build.py does.
                db.execSQL(
                    "INSERT INTO hadith_words (rowid, text) VALUES ($id, '${QuranSearchText.normalize(arabic)}')",
                )
            }
            db.execSQL("INSERT INTO hadith_en (hadith_en) VALUES ('rebuild')")
        }
    }

    @After
    fun deleteDatabase() {
        file.delete()
    }

    @Test
    fun opensAndSearchesArabicAndEnglishWithPhrasesFirst() {
        HadithDatabase.open(file).use { db ->
            assertEquals(8, db.userVersion)
            assertEquals(3L, db.count())
            // Typed without diacritics or hamza.
            assertEquals(listOf(HadithMatch(1, 0)), db.search("انما الاعمال"))
            assertEquals(listOf(HadithMatch(1, 0), HadithMatch(2, 0)), db.search("الاعمال"))
            assertEquals(listOf(HadithMatch(3, 0)), db.search("seeking KNOWLEDGE"))
            // Every word present but not as a phrase ranks after phrase matches.
            assertEquals(listOf(HadithMatch(1, 1)), db.search("intentions actions"))
            assertEquals(listOf(1L, 2L), db.search("intentions").map { it.id })
            // FTS syntax in user input stays literal.
            assertTrue(db.search("intentions\" OR \"knowledge").isEmpty())
            assertTrue(db.search("  ").isEmpty())
        }
    }

    @Test
    fun rejectsOtherDatabases() {
        BundledSQLiteDriver().open(file.absolutePath).use { it.execSQL("PRAGMA application_id = 1") }
        assertThrows(HadithDatabaseException::class.java) { HadithDatabase.open(file) }
        assertThrows(HadithDatabaseException::class.java) { HadithDatabase.open(File(file.parentFile, "missing.db")) }
    }

    private companion object {
        /** The tables search needs, verbatim from build/hadith/schema.sql. */
        const val SCHEMA = """
            PRAGMA application_id = 1230262606;
            PRAGMA user_version = 8;
            CREATE TABLE collection (
              id TEXT NOT NULL PRIMARY KEY, name_ar TEXT NOT NULL, name_en TEXT NOT NULL, sort_order INTEGER NOT NULL
            ) STRICT;
            CREATE TABLE book (
              id TEXT NOT NULL PRIMARY KEY,
              collection_id TEXT NOT NULL REFERENCES collection (id),
              sect TEXT NOT NULL CHECK (sect IN ('sunni', 'shia')),
              book_group TEXT NOT NULL CHECK (book_group IN ('the_9_books', 'forties', 'other_books', 'shia')),
              name_ar TEXT NOT NULL, name_en TEXT NOT NULL, author TEXT, author_ar TEXT NOT NULL DEFAULT '',
              died INTEGER, graded INTEGER NOT NULL DEFAULT 0 CHECK (graded IN (0, 1)), volume INTEGER, siglum TEXT,
              sort_order INTEGER NOT NULL DEFAULT 0
            ) STRICT;
            CREATE TABLE chapter (
              id INTEGER PRIMARY KEY, book_id TEXT NOT NULL REFERENCES book (id), chapter_idx INTEGER NOT NULL,
              file_name TEXT NOT NULL, name_ar TEXT NOT NULL DEFAULT '', name_en TEXT NOT NULL DEFAULT '',
              hadith_count INTEGER NOT NULL DEFAULT 0, UNIQUE (book_id, chapter_idx)
            ) STRICT;
            CREATE TABLE hadith (
              id INTEGER PRIMARY KEY, book_id TEXT NOT NULL REFERENCES book (id),
              chapter_id INTEGER NOT NULL REFERENCES chapter (id), chapter_idx INTEGER NOT NULL, id_in_book INTEGER NOT NULL,
              source_id INTEGER, arabic TEXT NOT NULL DEFAULT '', english_narrator TEXT NOT NULL DEFAULT '',
              english_text TEXT NOT NULL DEFAULT '', url TEXT NOT NULL DEFAULT '', UNIQUE (book_id, chapter_idx, id_in_book)
            ) STRICT;
            CREATE VIRTUAL TABLE hadith_words USING fts5 (text, content = '', tokenize = 'unicode61 remove_diacritics 2');
            CREATE VIEW hadith_english_content AS
              SELECT id, trim(english_narrator || ' ' || english_text) AS text FROM hadith;
            CREATE VIRTUAL TABLE hadith_en USING fts5 (
              text, content = 'hadith_english_content', content_rowid = 'id', tokenize = 'unicode61 remove_diacritics 2'
            )
        """
    }
}
