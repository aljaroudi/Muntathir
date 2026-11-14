import sqlite3
import tempfile
import unittest
from pathlib import Path
from compact import compact
from build import apply_schema

class CompactTests(unittest.TestCase):
    def test_preserves_content_and_only_word_indexes(self):
        with tempfile.TemporaryDirectory() as folder:
            source, target = Path(folder)/'source.db', Path(folder)/'compact.db'
            with sqlite3.connect(source) as db:
                apply_schema(db, Path(__file__).with_name('schema.sql'))
                db.executescript("""
                INSERT INTO collection VALUES('b','كتاب','Book',0);
                INSERT INTO book(id,collection_id,sect,book_group,name_ar,name_en) VALUES('b','b','sunni','other_books','كتاب','Book');
                INSERT INTO chapter(id,book_id,chapter_idx,file_name) VALUES(1,'b',0,'1.json');
                INSERT INTO hadith(id,book_id,chapter_id,chapter_idx,id_in_book,arabic,english_text) VALUES(1,'b',1,0,1,'انما الاعمال','actions intentions');
                """)
            before = source.read_bytes()
            compact(source, target)
            self.assertEqual(source.read_bytes(), before)
            with sqlite3.connect(target) as db:
                self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0], 8)
                self.assertEqual(db.execute("SELECT rowid FROM hadith_en WHERE hadith_en MATCH '\"intentions\"'").fetchall(), [(1,)])
                self.assertEqual(db.execute("SELECT rowid FROM hadith_en WHERE hadith_en MATCH '\"intent\"'").fetchall(), [])
                self.assertFalse(db.execute("SELECT name FROM sqlite_master WHERE name IN ('hadith_fts','hadith_partial')").fetchall())
            with self.assertRaises(ValueError): compact(source, target)
