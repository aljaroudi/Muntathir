package com.aljaroudi.muntathir

import android.app.Activity
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import com.aljaroudi.muntathir.assets.AssetPackBackend
import com.aljaroudi.muntathir.assets.ContentPack
import com.aljaroudi.muntathir.assets.PackStatus
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf
import java.io.File

/**
 * Serves fixture packs from [root] instead of Play: [download] installs a pack's fixture at once, packs without a
 * fixture fail. iOS `HadithUITestFixture`.
 */
class FakeAssetPackBackend(
    private val root: File,
    private val fixtures: Map<ContentPack, (File) -> Unit>,
) : AssetPackBackend {
    private val installed = mutableSetOf<ContentPack>()
    var downloads = 0
        private set

    private fun folder(pack: ContentPack) = File(root, pack.packName)

    override fun assets(pack: ContentPack): File? = folder(pack).takeIf { pack in installed }

    override suspend fun status(pack: ContentPack): PackStatus =
        assets(pack)?.let { PackStatus.Installed(it) } ?: PackStatus.NotInstalled

    override fun updates(pack: ContentPack): Flow<PackStatus> =
        flowOf(if (pack in installed) PackStatus.Installed(folder(pack)) else PackStatus.Failed(-1))

    override suspend fun download(pack: ContentPack): PackStatus {
        downloads++
        val build = fixtures[pack] ?: return PackStatus.Failed(-1)
        val file = File(folder(pack), pack.database).apply { parentFile?.mkdirs() }
        file.delete()
        build(file)
        installed += pack
        return PackStatus.Installed(folder(pack))
    }

    override suspend fun confirm(activity: Activity) = true

    override suspend fun remove(pack: ContentPack) {
        installed -= pack
        folder(pack).deleteRecursively()
    }

    companion object {
        /** Swift `HadithUITestFixture` (v8): one book with 105 narrations and one supplication. */
        fun hadith(file: File) {
            BundledSQLiteDriver().open(file.absolutePath).use { db ->
                val arabic = "نص تجريبي لاختبار عرض الحديث وحفظ موضع القراءة. ".repeat(35)
                val english = "Sample text for testing reading position and image sharing. ".repeat(35)
                """
                PRAGMA application_id = 1230262606;
                PRAGMA user_version = 8;
                CREATE TABLE collection(id TEXT PRIMARY KEY, name_ar TEXT, name_en TEXT, sort_order INTEGER);
                CREATE TABLE book(id TEXT PRIMARY KEY, collection_id TEXT, name_ar TEXT, name_en TEXT, sort_order INTEGER, author TEXT, author_ar TEXT);
                CREATE TABLE chapter(id INTEGER PRIMARY KEY, book_id TEXT, chapter_idx INTEGER, file_name TEXT, name_ar TEXT, name_en TEXT, hadith_count INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE hadith(id INTEGER PRIMARY KEY, book_id TEXT, chapter_id INTEGER, id_in_book INTEGER, source_id INTEGER, arabic TEXT, english_narrator TEXT, english_text TEXT);
                CREATE TABLE introduction(id INTEGER PRIMARY KEY, book_id TEXT, chapter_id INTEGER, title TEXT, arabic TEXT, english TEXT, url TEXT, sort_order INTEGER);
                CREATE TABLE hadith_reading(hadith_id INTEGER PRIMARY KEY, words INTEGER, display_number INTEGER);
                CREATE TABLE grader(id TEXT PRIMARY KEY, name_ar TEXT, name_en TEXT);
                CREATE TABLE hadith_grading(id INTEGER PRIMARY KEY, hadith_id INTEGER, grader_id TEXT, grade_ar TEXT, grade_en TEXT, reference_ar TEXT, reference_en TEXT, status TEXT, original_text TEXT);
                CREATE VIRTUAL TABLE hadith_words USING fts5(text, content='');
                CREATE VIEW hadith_english_content AS SELECT id, trim(english_narrator || ' ' || english_text) AS text FROM hadith;
                CREATE VIRTUAL TABLE hadith_en USING fts5(text, content='hadith_english_content', content_rowid='id', tokenize='porter unicode61');
                INSERT INTO collection VALUES ('bukhari','كتاب الاختبار','Test book',0);
                INSERT INTO book VALUES ('bukhari','bukhari','كتاب الاختبار','Test book',0,'Test author','مؤلف الاختبار');
                INSERT INTO chapter VALUES (1,'bukhari',0,'1.json','باب الاختبار','Test chapter',105);
                WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x < 105)
                INSERT INTO hadith SELECT x,'bukhari',1,x,x,'$arabic','Test narrator','$english' FROM n;
                UPDATE hadith SET arabic = 'الأعمال بالنيات', english_text = 'Actions are judged by intentions.' WHERE id = 105;
                INSERT INTO introduction VALUES (1,'bukhari',NULL,'Test introduction','مقدمة الكتاب. نص مستقل عن الأحاديث.','A separate introduction, outside narration numbering.','',0);
                INSERT INTO grader VALUES ('majlisi','المجلسي','al-Majlisi');
                INSERT INTO hadith_grading VALUES (1,105,'majlisi','صحيح','Sahih','','','judgment','');
                INSERT INTO collection VALUES ('openiti-Sahifa-Sajjadiyya','كتاب الدعاء التجريبي','Test supplications',1);
                INSERT INTO book VALUES ('openiti-Sahifa-Sajjadiyya','openiti-Sahifa-Sajjadiyya','كتاب الدعاء التجريبي','Test supplications',1,'Test author','مؤلف الاختبار');
                INSERT INTO chapter VALUES (2,'openiti-Sahifa-Sajjadiyya',1,'2.json','دعاء تجريبي','Test supplication',1);
                INSERT INTO hadith VALUES (106,'openiti-Sahifa-Sajjadiyya',2,2,2,'نص تجريبي لاختبار حفظ الدعاء والبحث في المحفوظات.','','Sample text for testing saved supplications.');
                INSERT INTO hadith_reading SELECT id, CASE WHEN id=105 THEN 2 ELSE 280 END, id_in_book FROM hadith;
                INSERT INTO hadith_words(rowid,text) SELECT id,arabic FROM hadith;
                INSERT INTO hadith_en(hadith_en) VALUES('rebuild');
                """.trimIndent()
                    .split(";\n")
                    .map { it.trim().removeSuffix(";") }
                    .filter { it.isNotEmpty() }
                    .forEach(db::execSQL)
            }
        }
    }
}
