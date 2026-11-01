import importlib.util
import json
import sqlite3
import tempfile
import unittest
from unittest.mock import Mock
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("hadith_build", HERE / "build.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class AdditionalBooksTests(unittest.TestCase):
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
                ('alkafi-1', 'alkafi', 'الكافي — الجزء الأول'),
                ('alkafi-2', 'alkafi', 'الكافي — الجزء الثاني'),
                ('uyun-rida-1', 'uyun-rida', 'عيون أخبار الرضا ١'),
                ('uyun-rida-2', 'uyun-rida', 'عيون أخبار الرضا ٢')])

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
            self.assertEqual(db.execute('SELECT grade_ar FROM hadith_grading LIMIT 1').fetchone()[0], 'صحيح')
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
        self.assertEqual(self.db.execute('PRAGMA user_version').fetchone()[0], 6)
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
