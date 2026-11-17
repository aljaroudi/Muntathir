package com.aljaroudi.muntathir.core.hadith

import com.aljaroudi.muntathir.core.sql.JdbcContentSql
import java.io.File
import java.nio.file.Files

/**
 * Port of Swift `HadithFixture`: a v8 library with collections `merged` (volumes `v1`, `v2`) and `other`, [count]
 * narrations in `merged` and one (id 100001, not yet indexed) in `other`.
 */
class HadithFixture(
    count: Int = 100_000,
    searchRows: String = "",
) {
    val file: File = Files.createTempFile("hadith-", ".db").toFile().also(File::delete)

    init {
        script(
            file,
            """
            PRAGMA application_id = 1230262606;
            PRAGMA user_version = 8;
            CREATE TABLE collection(id TEXT PRIMARY KEY, name_ar TEXT, name_en TEXT, sort_order INTEGER);
            CREATE TABLE book(id TEXT PRIMARY KEY, collection_id TEXT, name_ar TEXT, name_en TEXT, sort_order INTEGER, author TEXT DEFAULT 'Test Author', author_ar TEXT DEFAULT 'مؤلف');
            CREATE TABLE chapter(id INTEGER PRIMARY KEY, book_id TEXT, chapter_idx INTEGER, name_ar TEXT, name_en TEXT);
            CREATE TABLE hadith(id INTEGER PRIMARY KEY, book_id TEXT, chapter_id INTEGER, id_in_book INTEGER, arabic TEXT, english_narrator TEXT, english_text TEXT);
            CREATE TABLE introduction(id INTEGER PRIMARY KEY, book_id TEXT, chapter_id INTEGER, title TEXT, arabic TEXT, english TEXT, url TEXT, sort_order INTEGER);
            CREATE TABLE hadith_reading(hadith_id INTEGER PRIMARY KEY, words INTEGER, display_number INTEGER);
            CREATE TABLE grader(id TEXT PRIMARY KEY, name_ar TEXT, name_en TEXT);
            CREATE TABLE hadith_grading(id INTEGER PRIMARY KEY, hadith_id INTEGER, grader_id TEXT, grade_ar TEXT, grade_en TEXT, reference_ar TEXT, reference_en TEXT, status TEXT, original_text TEXT);
            CREATE INDEX hadith_book_iib ON hadith(book_id, id_in_book);
            CREATE INDEX hadith_chapter ON hadith(chapter_id);
            CREATE INDEX book_collection ON book(collection_id);
            CREATE VIRTUAL TABLE hadith_words USING fts5(text, root, lemma, content='', prefix='2 3');
            CREATE VIEW hadith_english_content AS SELECT id, trim(english_narrator || ' ' || english_text) AS text FROM hadith;
            CREATE VIRTUAL TABLE hadith_en USING fts5(text, content='hadith_english_content', content_rowid='id', tokenize='unicode61');
            INSERT INTO collection VALUES ('merged','كتاب','Book',0),('other','آخر','Other',1);
            INSERT INTO book(id,collection_id,name_ar,name_en,sort_order) VALUES ('v1','merged','المجلد الأول','Volume 1',0),('v2','merged','المجلد الثاني','Volume 2',1),('other','other','آخر','Other',2);
            INSERT INTO chapter VALUES (1,'v1',0,'باب','Chapter'),(2,'v2',0,'باب','Chapter'),(3,'other',0,'باب','Chapter');
            WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x < $count)
            INSERT INTO hadith SELECT x, CASE WHEN x <= 50000 THEN 'v1' ELSE 'v2' END,
              CASE WHEN x <= 50000 THEN 1 ELSE 2 END, (x-1)%50000+1,
              'الأعمال بالنيات' || printf('%0600d',0), 'Narrator', 'intentions ' || printf('%0600d',0) FROM n;
            $searchRows
            INSERT INTO hadith_words(rowid,text) SELECT id,CASE WHEN id >= 200000 THEN arabic ELSE 'الاعمال بالنيات intentions' END FROM hadith;
            INSERT INTO hadith_en(rowid,text) SELECT id,text FROM hadith_english_content;
            INSERT INTO hadith VALUES (100001,'other',3,1,'نص عربي','','');
            ALTER TABLE chapter ADD COLUMN hadith_count INTEGER NOT NULL DEFAULT 0;
            UPDATE chapter SET hadith_count = (SELECT count(*) FROM hadith WHERE chapter_id = chapter.id);
            ALTER TABLE chapter ADD COLUMN file_name TEXT NOT NULL DEFAULT '1.json';
            ALTER TABLE hadith ADD COLUMN source_id INTEGER;
            UPDATE hadith SET source_id = id_in_book;
            """,
        )
    }

    fun remove() {
        file.delete()
    }

    companion object {
        /** Runs `;`-terminated statements (one per line end) on a writable connection to [file]. */
        fun script(
            file: File,
            sql: String,
        ) {
            val statements =
                sql
                    .trimIndent()
                    .split(Regex(";\\s*\\n"))
                    .map { it.trim().removeSuffix(";") }
                    .filter { it.isNotEmpty() }
            if (!file.isFile) file.createNewFile()
            val connection = JdbcContentSql(file, readOnly = false).hold()
            try {
                statements.forEach { connection.execute(it, emptyList()) }
            } finally {
                connection.close()
            }
        }
    }
}
