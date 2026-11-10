import importlib.util
import json
import hashlib
import sqlite3
import tempfile
import unittest
from unittest.mock import Mock, patch
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("hadith_build", HERE / "build.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class SupplicationAssetTests(unittest.TestCase):
    def test_split_preserves_ids_text_and_provenance(self):
        with tempfile.TemporaryDirectory() as folder, sqlite3.connect(":memory:") as db:
            builder.apply_schema(db, HERE / "schema.sql")
            for collection, number in [("openiti-Sahifa-Sajjadiyya", 101), ("other", 202)]:
                db.execute("INSERT INTO collection VALUES (?, 'كتاب', 'Book', 0)", (collection,))
                db.execute("INSERT INTO book(id,collection_id,sect,book_group,name_ar,name_en) VALUES (?,?,'shia','shia','كتاب','Book')", (collection, collection))
                db.execute("INSERT INTO chapter(id,book_id,chapter_idx,file_name,name_ar) VALUES (?,?,0,'edition','باب')", (number, collection))
                db.execute("INSERT INTO hadith(id,book_id,chapter_id,chapter_idx,id_in_book,arabic,url) VALUES (?,?,?,0,1,'دعاء كامل','edition#page')", (number, collection, number))
            output = Path(folder) / "supplications.db"
            self.assertEqual(builder.extract_supplications(db, output), 1)
            self.assertEqual(db.execute("SELECT id FROM hadith").fetchall(), [(202,)])
            with sqlite3.connect(output) as prayers:
                self.assertEqual(prayers.execute("SELECT id,arabic,url FROM hadith").fetchall(), [(101, 'دعاء كامل', 'edition#page')])
                self.assertEqual(prayers.execute("PRAGMA foreign_key_check").fetchall(), [])
                self.assertEqual(prayers.execute("SELECT count(*) FROM hadith_words WHERE hadith_words MATCH 'دعاء'").fetchone(), (1,))


class ArabicChapterTests(unittest.TestCase):
    def test_mapping_checks_content_and_preserves_existing_arabic(self):
        with tempfile.TemporaryDirectory() as directory, sqlite3.connect(":memory:") as db:
            builder.apply_schema(db, HERE / "schema.sql")
            db.execute("INSERT INTO collection VALUES ('book','كتاب','Book',0)")
            db.execute("INSERT INTO book(id,collection_id,sect,book_group,name_ar,name_en) VALUES ('book','book','shia','shia','كتاب','Book')")
            db.execute("INSERT INTO chapter(id,book_id,chapter_idx,file_name,name_en) VALUES (1,'book',0,'1.json','Chapter')")
            db.execute("INSERT INTO hadith(id,book_id,chapter_id,chapter_idx,id_in_book,arabic,url) VALUES (1,'book',1,0,1,'نص','source')")
            row = dict(book_id='book', chapter_idx=0, name_en='Chapter', name_ar='باب',
                       boundary_sha256=hashlib.sha256(json.dumps([('source', 'نص')], ensure_ascii=False).encode()).hexdigest())
            folder = Path(directory)
            (folder / 'arabic-chapters.json').write_text(json.dumps({'chapters': [row]}))
            with patch.object(builder, 'DATA', folder):
                before = db.execute('SELECT * FROM hadith').fetchall()
                builder.localize_chapters(db)
                self.assertEqual(db.execute('SELECT name_ar FROM chapter').fetchone(), ('باب',))
                self.assertEqual(db.execute('SELECT * FROM hadith').fetchall(), before)
                db.execute("UPDATE chapter SET name_ar='عنوان المصدر', name_en='Changed'")
                builder.localize_chapters(db)
                self.assertEqual(db.execute('SELECT name_ar FROM chapter').fetchone(), ('عنوان المصدر',))
                db.execute("UPDATE chapter SET name_ar=''")
                with self.assertRaisesRegex(ValueError, 'source changed'):
                    builder.localize_chapters(db)
                db.execute("UPDATE chapter SET name_en='Chapter'")
                db.execute("UPDATE hadith SET arabic='تغير النص'")
                with self.assertRaisesRegex(ValueError, 'source changed'):
                    builder.localize_chapters(db)

    def test_curated_mapping_has_unique_keys_and_source_provenance(self):
        rows = json.loads((HERE / 'data/arabic-chapters.json').read_text())['chapters']
        self.assertEqual(len(rows), 2156)
        self.assertEqual(len({(r['book_id'], r['chapter_idx']) for r in rows}), len(rows))
        self.assertTrue(all(r['source'] and r['name_ar'] and len(r['boundary_sha256']) == 64 for r in rows))


class OpenITITests(unittest.TestCase):
    def test_volume_boundaries_heading_continuations_and_commentary(self):
        text = '''######OpenITI#
#META#Header#End#
PageV01P001
### | مقدمة المؤلف
# مقدمة عربية
### || 1 - باب الماء
~~والطهارة
### $ 1 - أخبرني الراوي
~~عن الإمام ms0001
# قال المصنف: بيان الخبر
PageV01P002
### $ 2 - خبر آخر
PageV02P001
### || 1 - باب الزكاة
 أخبرني الراوي الثاني
~~بخبر الزكاة
'''
        rows = builder.parse_openiti(text, 'istibsar')
        self.assertEqual(len(rows), 4)
        self.assertEqual([r['volume'] for r in rows], [1, 1, 1, 2])
        self.assertEqual(rows[1]['title'], '1 - باب الماء والطهارة')
        self.assertIn('بيان الخبر', rows[1]['text'])
        self.assertEqual(rows[2]['page'], 'PageV01P002')
        self.assertTrue(all('PageV' not in r['text'] and 'ms0001' not in r['text'] for r in rows))

    def test_narration_embedded_in_heading_is_not_lost_or_duplicated(self):
        text = '''#META#Header#End#
PageV01P001
### || 12 - باب الماء 64 - 1 أخبرني الأول
~~بخبر كامل
# قال: جواب الخبر
### $ - 2 خبر ثان
### $ - 3 خبر ثالث
'''
        rows = builder.parse_openiti(text, 'istibsar')
        self.assertEqual(len(rows), 3)
        self.assertTrue(all(r['title'] == '12 - باب الماء' for r in rows))
        self.assertIn('أخبرني الأول بخبر كامل', rows[0]['text'])
        self.assertIn('جواب الخبر', rows[0]['text'])

    def test_mistagged_headings_and_heading_footnotes_are_not_narrations(self):
        text = '''#META#Header#End#
PageV02P001
### $ - باب الحجامة للمحرم
### $ - خبر الحجامة
##|| 181 - باب الأضحية
~~وما عرف به
### $ - خبر الأضحية
### || [42 - باب ربح المؤمن] (1)
### $ - خبر البيع
'''
        rows = builder.parse_openiti(text, 'istibsar')
        self.assertEqual([r['title'] for r in rows], ['باب الحجامة للمحرم', '181 - باب الأضحية وما عرف به', '42 - باب ربح المؤمن'])
        self.assertTrue(all(r['text'].startswith('خبر') for r in rows))

    def test_sahifa_keeps_intro_and_whole_prayer_but_excludes_editorial_notes(self):
        text = '''#META#Header#End#
### |EDITOR|
# مادة الناشر
### | [مقدمة]
# مقدمة عربية
### | (1) [التحميد لله]
# أول الدعاء
PageV00P023
~~بقية الدعاء ms14
# آخر الدعاء
### |EDITOR|
# مادة ختامية
#####ENDNOTES#
# حاشية
'''
        rows = builder.parse_openiti(text, 'sahifa')
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[1]['title'], '(1) التحميد لله')
        self.assertIn('آخر الدعاء', rows[1]['text'])
        self.assertNotIn('مادة', str(rows))
        self.assertNotIn('حاشية', str(rows))


class AdditionalBooksTests(unittest.TestCase):
    def test_edition_number_is_the_index_and_not_part_of_the_text(self):
        for label in ("3 وَ- مَتْنُ الْحَدِيثِ", "4 - مَتْنُ الْحَدِيثِ", "3ـ مَتْنُ الْحَدِيثِ", "14ـ 5ـ مَتْنُ الْحَدِيثِ"):
            self.assertEqual(builder.strip_narration_label(label), "مَتْنُ الْحَدِيثِ")
        self.assertEqual(builder.strip_narration_label("مَتْنٌ بِلَا رَقْمٍ"), "مَتْنٌ بِلَا رَقْمٍ")

    def test_kafi_original_names_require_matching_source_boundaries(self):
        mapping = json.loads((HERE / 'data/kafi-chapters.json').read_text())['books']
        self.assertEqual(sum(len(chapters) for chapters in mapping.values()), 37)
        self.assertEqual(sum(bool(row['name_ar']) for chapters in mapping.values() for row in chapters.values()), 37)
        with sqlite3.connect(':memory:') as db:
            builder.apply_schema(db, HERE / 'schema.sql')
            db.execute("INSERT INTO collection VALUES ('alkafi', 'الكافي', 'Al-Kafi', 0)")
            chapter_id = 0
            for book_id, chapters in mapping.items():
                db.execute("INSERT INTO book (id,collection_id,sect,book_group,name_ar,name_en) VALUES (?,'alkafi','shia','shia','الكافي','Al-Kafi')", (book_id,))
                for index, (file_name, row) in enumerate(chapters.items()):
                    chapter_id += 1
                    db.execute('INSERT INTO chapter(id,book_id,chapter_idx,file_name,name_en) VALUES (?,?,?,?,?)',
                               (chapter_id, book_id, index, file_name, row['name_en']))
                    for number, url in enumerate((row['first_url'], row['last_url']), 1):
                        db.execute('INSERT INTO hadith(id,book_id,chapter_id,chapter_idx,id_in_book,url) VALUES (?,?,?,?,?,?)',
                                   (chapter_id * 2 + number, book_id, chapter_id, index, number, url))
            before = db.execute('SELECT * FROM hadith ORDER BY id').fetchall()
            output = StringIO()
            with redirect_stdout(output):
                builder.localize_kafi_chapters(db)
            self.assertEqual(output.getvalue().count('unresolved Arabic chapter'), 0)
            self.assertEqual(db.execute('SELECT count(*) FROM chapter WHERE name_ar <> ? ', ('',)).fetchone()[0], 37)
            self.assertEqual(db.execute('SELECT * FROM hadith ORDER BY id').fetchall(), before)
            self.assertEqual(db.execute("SELECT name_ar FROM chapter WHERE book_id='alkafi-1' AND file_name='5.json'").fetchone()[0], 'كتاب الحجة')
            # A new upstream Arabic name wins; changed English or boundary metadata stays unresolved.
            db.execute("UPDATE chapter SET name_ar = 'اسم المصدر' WHERE id = 1")
            db.execute("UPDATE chapter SET name_ar = '', name_en = 'Changed' WHERE id = 2")
            db.execute("UPDATE chapter SET name_ar = '' WHERE id = 3")
            db.execute("UPDATE hadith SET url = 'changed' WHERE chapter_id = 3")
            with redirect_stdout(StringIO()):
                builder.localize_kafi_chapters(db)
            self.assertEqual(db.execute('SELECT name_ar FROM chapter WHERE id <= 3 ORDER BY id').fetchall(), [('اسم المصدر',), ('',), ('',)])

    def test_localization_preserves_collection_titles_and_volume_names(self):
        with sqlite3.connect(":memory:") as db:
            builder.apply_schema(db, HERE / "schema.sql")
            db.executemany("INSERT INTO collection VALUES (?, ?, '', 0)", [
                ('alkafi', 'الكافي'), ('uyun-rida', 'عيون أخبار الرضا'), ('bukhari', 'source')])
            db.executemany("INSERT INTO book (id, collection_id, sect, book_group, name_ar, name_en) VALUES (?, ?, 'shia', 'shia', '', '')", [
                ('alkafi-1', 'alkafi'), ('alkafi-2', 'alkafi'),
                ('uyun-rida-1', 'uyun-rida'), ('uyun-rida-2', 'uyun-rida'), ('bukhari', 'bukhari')])
            builder.localize_books(db)
            titles = dict(db.execute('SELECT id, name_ar FROM collection'))
            self.assertEqual(titles['alkafi'], 'الكافي')
            self.assertEqual(titles['uyun-rida'], 'عيون أخبار الرضا')
            self.assertEqual(titles['bukhari'], db.execute("SELECT name_ar FROM book WHERE id = 'bukhari'").fetchone()[0])
            rows = db.execute("SELECT id, collection_id, name_ar FROM book WHERE id IN ('alkafi-1', 'alkafi-2', 'uyun-rida-1', 'uyun-rida-2') ORDER BY id").fetchall()
            self.assertEqual(rows, [
                ('alkafi-1', 'alkafi', 'الجزء ١'),
                ('alkafi-2', 'alkafi', 'الجزء ٢'),
                ('uyun-rida-1', 'uyun-rida', 'الجزء ١'),
                ('uyun-rida-2', 'uyun-rida', 'الجزء ٢')])

    def test_partition_precedence_overlap_volumes_and_verbatim_text(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            db = sqlite3.connect(":memory:")
            builder.apply_schema(db, HERE / "schema.sql")
            db.execute("INSERT INTO collection VALUES ('alkafi', 'الكافي', 'Al-Kafi', 0)")
            db.execute("INSERT INTO book (id,collection_id,sect,book_group,name_ar,name_en) VALUES ('alkafi-1','alkafi','shia','shia','الكافي','Al-Kafi')")
            metadata = []
            for file, book, volume in [(1, 'Al-Kafi-Volume-1-Kulayni', 1), (34, 'Man-La-Yahduruh-al-Faqih-Volume-1-Saduq', 1), (35, 'Man-La-Yahduruh-al-Faqih-Volume-2-Saduq', 2)]:
                metadata.append(dict(bookId=book, BookName='Book', author='Author', volume=volume))
                rows = [dict(id=1, bookId=book, categoryId=1, chapterInCategoryId=1, category='Category', chapter='Chapter',
                             englishText='A **bold** passage\n\n[Link](https://example.com)', arabicText='نَصٌّ', URL='source',
                             gradingsFull=[dict(author=dict(name_en='Ali Akbar al-Ghaffari'), grade_ar='صحيح')])]
                (folder / f'{file}.json').write_text(json.dumps(rows))
            (folder / 'BookNames.json').write_text(json.dumps(metadata))
            (folder / 'allBooks.json').write_text('This older aggregate must never be loaded')
            self.assertEqual(builder.load_additional_books(folder, db), 2)
            self.assertEqual(db.execute('SELECT count(*) FROM collection').fetchone()[0], 2)
            self.assertEqual(db.execute('SELECT count(*) FROM hadith').fetchone()[0], 2)
            self.assertEqual(db.execute('SELECT english_text FROM hadith LIMIT 1').fetchone()[0], rows[0]['englishText'])
            self.assertEqual(db.execute('SELECT count(*) FROM hadith_grading').fetchone()[0], 0)
            self.assertEqual(db.execute('SELECT count(*) FROM grader').fetchone()[0], 0)
            self.assertEqual(db.execute('SELECT hadith_count FROM chapter').fetchall(), [(1,), (1,)])
            db.executemany('INSERT INTO hadith_en(rowid,text) VALUES (?,?)', db.execute('SELECT id,text FROM hadith_english_content').fetchall())
            highlighted = db.execute("SELECT highlight(hadith_en,0,'[',']') FROM hadith_en WHERE hadith_en MATCH 'passages'").fetchone()[0]
            self.assertIn('[passage]', highlighted)

    def test_four_filters_base_books_and_combines_with_sittah(self):
        for sittah in (False, True):
            with self.subTest(sittah=sittah), sqlite3.connect(":memory:") as db:
                builder.apply_schema(db, HERE / "schema.sql")
                source = Mock()
                source.read_json.return_value = {
                    "sunni": {"the_9_books": [{"id": "bukhari"}, {"id": "malik"}],
                              "forties": [], "other_books": []},
                    "shia": [{"id": "alkafi-1"}, {"id": "al-amali-saduq"}],
                }
                source.exists.return_value = False
                builder.load_books_chapters_hadiths(
                    source, db, builder.RefResolver(), sittah=sittah, four=True)
                expected = {"bukhari", "alkafi-1"} | (set() if sittah else {"malik"})
                self.assertEqual({r[0] for r in db.execute("SELECT id FROM book")}, expected)

    def test_only_six_books_import_gradings(self):
        with sqlite3.connect(":memory:") as db:
            builder.apply_schema(db, HERE / "schema.sql")
            books = [*sorted(builder.SITTAH_BOOKS), "malik", "alkafi-1"]
            metadata = dict(sunni=dict(the_9_books=[dict(id=b, graded=True) for b in books[:-1]],
                                       forties=[], other_books=[]),
                            shia=[dict(id="alkafi-1", graded=True)])
            source = Mock()
            source.exists.return_value = True

            def read(path):
                if path == "books.json":
                    return metadata
                if path.endswith("index.json"):
                    return [dict(file="1.json")]
                if path.endswith("grades.json"):
                    return {"1": "Sahih"}
                return [dict(id=1, idInBook=1, grade="Sahih",
                             gradingsFull=[dict(grade_ar="صحيح")])]

            source.read_json.side_effect = read
            builder.load_books_chapters_hadiths(source, db, builder.RefResolver())
            self.assertEqual({r[0] for r in db.execute(
                "SELECT DISTINCT h.book_id FROM hadith_grading g JOIN hadith h ON h.id=g.hadith_id")},
                builder.SITTAH_BOOKS)
            self.assertEqual({r[0] for r in db.execute("SELECT id FROM book WHERE graded=1")},
                             builder.SITTAH_BOOKS)
            grade_files = [call.args[0] for call in source.read_json.call_args_list
                           if call.args[0].endswith("grades.json")]
            self.assertEqual(len(grade_files), 6)

    def test_four_keeps_volumes_and_nahj_only(self):
        sources = ["Al-Kafi-Volume-1-Kulayni", "Man-La-Yahduruh-al-Faqih-Volume-2-Saduq",
                   "Tahdhib-al-Ahkam-Volume-4-Tusi", "Al-Istibsar-Volume-1-Tusi",
                   "Nahj-al-Balagha-Radi", "Al-Amali-Saduq"]
        with tempfile.TemporaryDirectory() as directory, sqlite3.connect(":memory:") as db:
            folder = Path(directory)
            builder.apply_schema(db, HERE / "schema.sql")
            metadata = []
            for number, book in enumerate(sources, 1):
                metadata.append(dict(bookId=book, BookName=book))
                (folder / f"{number}.json").write_text(json.dumps([
                    dict(id=1, bookId=book, arabicText="نص", englishText="Text")]))
            (folder / "BookNames.json").write_text(json.dumps(metadata))
            self.assertEqual(builder.load_additional_books(folder, db, four=True), 5)
            self.assertEqual({r[0] for r in db.execute("SELECT id FROM book")},
                             {"additional-" + book for book in sources[:-1]})

    def test_missing_export_is_not_silently_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            (folder / 'BookNames.json').write_text('[]')
            with self.assertRaisesRegex(ValueError, 'No numbered'):
                builder.load_additional_books(folder, sqlite3.connect(':memory:'))


class GradingTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.addCleanup(self.db.close)
        self.db.row_factory = sqlite3.Row
        builder.apply_schema(self.db, HERE / 'schema.sql')
        self.db.execute("INSERT INTO collection VALUES ('book', '', '', 0)")
        self.db.execute("INSERT INTO book(id,collection_id,sect,book_group,name_ar,name_en) VALUES ('book','book','shia','shia','','')")
        self.db.execute("INSERT INTO chapter(id,book_id,chapter_idx,file_name) VALUES (1,'book',0,'1.json')")
        self.db.execute("INSERT INTO hadith(id,book_id,chapter_id,chapter_idx,id_in_book) VALUES (1,'book',1,0,1)")
        self.importer = builder.GradingImporter(self.db)

    def records(self):
        return [dict(r) for r in self.db.execute('SELECT * FROM hadith_grading ORDER BY id')]

    def test_edited_book_and_author_names(self):
        self.db.execute("UPDATE book SET author = 'Original'")
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as directory, patch.object(builder, 'DATA', Path(directory)):
            (Path(directory) / 'books-and-authors.json').write_text(json.dumps(dict(books=[dict(id='book', name_ar='كتاب', author_ar='المؤلف', author_en='')])))
            builder.localize_books(self.db)
        row = self.db.execute('SELECT name_ar,author_ar,author FROM book').fetchone()
        self.assertEqual(tuple(row), ('كتاب', 'المؤلف', 'Original'))

    def test_legacy_and_summary_are_one_record(self):
        raw = 'Shaykh Baqir al-Behbudi:  صحيح  \n   - Book (8/320)'
        self.importer.add(1, dict(grade=raw, behbudiGrading=raw))
        rows = self.records()
        self.assertEqual(len(rows), 1)
        self.assertEqual((rows[0]['grader_id'], rows[0]['grade_ar'], rows[0]['reference_en']),
                         ('behbudi', 'صحيح', 'Book (8/320)'))
        self.assertEqual(rows[0]['original_text'], raw)

    def test_bilingual_and_alias_fallback_reconcile(self):
        structured = dict(author=dict(name_en='Shaykh Baqir al-Behbudi', name_ar='البهبودي'),
                          grade_en='Ṣaḥīḥ', grade_ar='صحيح', reference_en='Book, p. 34', reference_ar='كتاب')
        self.importer.add(1, dict(gradingsFull=[structured], behdudiGrading='صحيح', grade='Sahih'))
        rows = self.records()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['grader_id'], 'behbudi')
        self.assertEqual(rows[0]['grade_en'], 'Authentic')
        self.assertEqual(rows[0]['reference_ar'], 'كتاب')
        self.assertIn('Ṣaḥīḥ', rows[0]['original_text'])

    def test_same_grader_distinct_assessments_and_references_survive(self):
        records = [dict(author=dict(name_en='behbudi'), grade_ar=g, reference_en=r)
                   for g, r in [('حسن أو موثق', 'Book 1'), ('ضعيف', 'Book 1'), ('ضعيف', 'Book 2')]]
        self.importer.add(1, dict(gradingsFull=records + [records[0]]))
        self.assertEqual(len(self.records()), 3)
        self.assertEqual(self.records()[0]['grade_ar'], 'حسن أو موثق')

    def test_exact_duplicates_win_over_partial_matches(self):
        records = [dict(author=dict(name_en='ghaffari'), grade_ar='صحيح', reference_en=ref)
                   for ref in ('Book 1', 'Book 2', '', 'Book 1')]
        self.importer.add(1, dict(gradingsFull=records))
        self.assertEqual(len(self.records()), 3)

    def test_unrecognized_objects_without_judgments_are_retained(self):
        self.importer.add(1, dict(gradingsFull=[dict(raw='first'), dict(raw='second')]))
        self.assertEqual(len(self.records()), 2)
        self.assertTrue(all(r['status'] == 'unparsed' for r in self.records()))

    def test_no_grader_and_coverage_are_separate(self):
        self.importer.add(1, dict(grade='Da’if', behbudiGrading='لم يخرجه'))
        coverage, judgment = self.records()
        self.assertEqual((coverage['status'], coverage['grade_ar'], coverage['grade_en']), ('not_included', '', ''))
        self.assertIsNone(judgment['grader_id'])
        self.assertEqual((judgment['grade_en'], judgment['grade_ar']), ('Weak', 'ضعيف'))

    def test_external_objects_keep_attribution_and_raw(self):
        external = dict(grade_en='sahih', grade_ar='إسناده صحيح', raw='إسناده صحيح', source='Book 1')
        self.importer.add(1, dict(grade='Sahih'), [('mohseni', external)])
        row = next(r for r in self.records() if r['grader_id'] == 'mohseni')
        self.assertEqual(row['reference_en'], 'Book 1')
        self.assertIn(external['raw'], row['original_text'])
        self.assertEqual(row['grade_en'], 'Authentic')
        self.assertEqual(row['grade_ar'], 'إسناده صحيح')

    def test_unrecognized_retained_and_reported(self):
        self.importer.add(1, dict(grade='1819', gradingsFull=[dict(raw='no judgment')]))
        self.assertEqual(len(self.records()), 2)
        self.assertTrue(all(r['status'] == 'unparsed' for r in self.records()))
        self.assertEqual(sum(self.importer.unparsed.values()), 2)
        self.assertTrue(all(not r['grade_ar'] and not r['grade_en'] for r in self.records()))
        self.assertEqual({r['original_text'] for r in self.records()},
                         {'1819', json.dumps(dict(raw='no judgment'), ensure_ascii=False, sort_keys=True)})

    def test_ambiguous_summary_does_not_merge_scholars(self):
        self.importer.add(1, dict(behbudiGrading='صحيح', mohseniGrading='صحيح', grade='صحيح'))
        self.assertEqual(len(self.records()), 3)
        self.assertEqual({r['grader_id'] for r in self.records()}, {'behbudi', 'mohseni', None})

    def test_other_graders_are_ignored(self):
        self.importer.add(1, dict(
            majlisiGrading='صحيح',
            grade='Allamah Baqir al-Majlisi: صحيح',
            gradingsFull=[dict(author=dict(name_en='majlisi'), grade_ar='صحيح')],
        ), [('arnaut', 'Sahih')])
        self.assertEqual(self.records(), [])

    def test_unnamed_structured_assessment_is_not_dropped(self):
        self.importer.add(1, dict(gradingsFull=[dict(grade_ar='مجهول', reference_en='Book')]))
        row, = self.records()
        self.assertIsNone(row['grader_id'])
        self.assertEqual(row['grade_ar'], 'مجهول')
        self.assertEqual(self.db.execute('PRAGMA user_version').fetchone()[0], 7)
        self.assertEqual(self.db.execute('PRAGMA foreign_key_check').fetchall(), [])


if __name__ == '__main__':
    unittest.main()


class ShippingSchemaTests(unittest.TestCase):
    def test_default_is_reader_only_and_experiment_requires_opt_in(self):
        self.assertFalse(builder.parse_args([]).experimental_morphology)
        self.assertTrue(builder.parse_args(['--experimental-morphology']).experimental_morphology)
        with sqlite3.connect(':memory:') as db:
            builder.apply_schema(db, HERE / 'schema.sql')
            names = {r[0] for r in db.execute('SELECT name FROM sqlite_master')}
            self.assertTrue({'hadith', 'hadith_grading', 'hadith_fts', 'hadith_en'} <= names)
            self.assertFalse({'word_form', 'root', 'narrator', 'concordance', 'hadith_relation'} & names)
            self.assertEqual([r[1] for r in db.execute('PRAGMA table_info(hadith_words)')], ['text'])
            builder.build_fts(db)
            builder.apply_schema(db, HERE / 'experimental-morphology.sql')
            self.assertEqual(db.execute('SELECT count(*) FROM word_form').fetchone()[0], 0)


class IntroductionTests(unittest.TestCase):
    def test_unnumbered_collection_chapters_are_not_introductions(self):
        for kind, heading, numbered in [
            ('wasail', '# 1 - باب الصلاة', '# [12345] 1 - رواية'),
            ('bihar', '### || باب 4', '# 1 - رواية'),
        ]:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as folder, sqlite3.connect(':memory:') as db:
                root = Path(folder)
                edition = '1104Author.Book.Test-ara1'
                path = root / '1104Author' / '1104Author.Book' / edition
                path.parent.mkdir(parents=True)
                path.write_text('#META#Header#End#\n# مقدمة المؤلف\nPageV01P001\n'
                                + heading + '\n# خبر طويل غير مرقم\nPageV01P002\n'
                                + heading + '\n' + numbered + '\nPageV01P003\n'
                                + '# خاتمة الكتاب\n# نص الخاتمة\nPageV02P001\n')
                records = builder.parse_collection(path.read_text(), kind)
                self.assertEqual([r['number'] for r in records], [0, 0, 12345 if kind == 'wasail' else 1, 0])
                (root / 'openiti-editions.json').write_text(json.dumps({'editions': {kind: {
                    'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                    'reading_entries': 4, 'entries_by_volume': {'1': 3, '2': 1},
                }}}))
                builder.apply_schema(db, HERE / 'schema.sql')
                with patch.object(builder, 'DATA', root), patch.object(builder, 'OPENITI_EDITIONS', {kind: edition}):
                    builder.load_openiti_books(db, root)
                self.assertEqual(db.execute('SELECT arabic FROM introduction').fetchall(), [('مقدمة المؤلف',)])
                # Skipping the preface must not resequence legacy source identities.
                self.assertEqual(db.execute('SELECT id,id_in_book,arabic FROM hadith ORDER BY id').fetchall(),
                                 [(2, 2, records[1]['text']), (3, 3, records[2]['text']), (4, 1, records[3]['text'])])
                self.assertEqual(db.execute('SELECT hadith_count FROM chapter ORDER BY id').fetchall(), [(0,), (1,), (1,), (1,)])

    def test_continuous_text_is_separate_and_metadata_preserves_source_identity(self):
        with sqlite3.connect(':memory:') as db:
            builder.apply_schema(db, HERE / 'schema.sql')
            db.execute("INSERT INTO collection VALUES ('additional-Al-Istibsar-Tusi','كتاب','Book',0)")
            db.execute("INSERT INTO book(id,collection_id,sect,book_group,name_ar,name_en) VALUES ('v1','additional-Al-Istibsar-Tusi','shia','shia','كتاب','Book')")
            db.execute("INSERT INTO chapter(id,book_id,chapter_idx,file_name) VALUES (1,'v1',1,'edition')")
            db.execute("INSERT INTO hadith(id,book_id,chapter_id,chapter_idx,id_in_book,arabic) VALUES (2,'v1',1,1,2,'نص الرواية')")
            before = db.execute('SELECT * FROM hadith').fetchall()
            builder.add_introduction(db, 'v1', None, 'Opening', 'النص الأول')
            builder.add_introduction(db, 'v1', None, 'Heading', 'النص الثاني')
            builder.build_reading_metadata(db)
            self.assertEqual(db.execute('SELECT * FROM hadith').fetchall(), before)
            self.assertEqual(db.execute('SELECT arabic FROM introduction').fetchall(), [('النص الأول\n\nHeading\n\nالنص الثاني',)])
            self.assertEqual(db.execute('SELECT * FROM hadith_reading').fetchall(), [(2, 2, 1)])
            self.assertEqual(builder.reading_words('', '**Two** [words](https://example.com)'), 2)

    def test_supplication_extraction_carries_introductions_and_reading_metadata(self):
        with tempfile.TemporaryDirectory() as folder, sqlite3.connect(':memory:') as db:
            builder.apply_schema(db, HERE / 'schema.sql')
            book = 'openiti-Sahifa-Sajjadiyya'
            db.execute("INSERT INTO collection VALUES (?, 'كتاب', 'Book', 0)", (book,))
            db.execute("INSERT INTO book(id,collection_id,sect,book_group,name_ar,name_en) VALUES (?,?,'shia','shia','كتاب','Book')", (book, book))
            db.execute("INSERT INTO chapter(id,book_id,chapter_idx,file_name) VALUES (1,?,1,'edition')", (book,))
            db.execute("INSERT INTO hadith(id,book_id,chapter_id,chapter_idx,id_in_book,arabic) VALUES (2,?,1,1,2,'دعاء كامل')", (book,))
            builder.add_introduction(db, book, None, 'Introduction', 'مقدمة كاملة')
            builder.build_reading_metadata(db)
            output = Path(folder) / 'supplications.db'
            self.assertEqual(builder.extract_supplications(db, output), 1)
            with sqlite3.connect(output) as result:
                self.assertEqual(result.execute('SELECT arabic FROM introduction').fetchall(), [('مقدمة كاملة',)])
                self.assertEqual(result.execute('SELECT * FROM hadith_reading').fetchall(), [(2, 2, 2)])
                self.assertEqual(result.execute('PRAGMA foreign_key_check').fetchall(), [])
            self.assertEqual(db.execute('SELECT count(*) FROM introduction').fetchone(), (0,))

    def test_kafi_introduction_does_not_shift_existing_narrations(self):
        with sqlite3.connect(':memory:') as db:
            builder.apply_schema(db, HERE / 'schema.sql')
            source = Mock()
            source.exists.return_value = True
            metadata = dict(sunni=dict(the_9_books=[], forties=[], other_books=[]), shia=[dict(id='alkafi-1')])
            data = {
                'books.json': metadata,
                'shia/alkafi-1/index.json': [dict(file='1.json', name_en='Introduction', count=1), dict(file='2.json', name_en='Chapter', count=1)],
                'shia/alkafi-1/1.json': [dict(id=1, arabic='نص المقدمة', english='Introduction text')],
                'shia/alkafi-1/2.json': [dict(id=2, idInBook=2, arabic='نص الرواية', english='Narration text')],
            }
            source.read_json.side_effect = data.__getitem__
            self.assertEqual(builder.load_books_chapters_hadiths(source, db, builder.RefResolver()), (0, 1))
            self.assertEqual(db.execute('SELECT arabic,english FROM introduction').fetchall(), [('نص المقدمة', 'Introduction text')])
            self.assertEqual(db.execute('SELECT id_in_book,source_id,arabic FROM hadith').fetchall(), [(1, 2, 'نص الرواية')])
            self.assertEqual(db.execute('SELECT chapter_idx,file_name FROM chapter').fetchall(), [(1, '2.json')])
