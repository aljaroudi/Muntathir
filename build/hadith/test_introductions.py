import sqlite3
import unittest

import build as builder


class IntroductionTests(unittest.TestCase):
    def test_first_introduction_per_title_preserves_numbering(self):
        db = sqlite3.connect(':memory:')
        db.executescript('''
            CREATE TABLE book(id TEXT, collection_id TEXT, sort_order INTEGER);
            CREATE TABLE introduction(id INTEGER, book_id TEXT, sort_order INTEGER);
            CREATE TABLE hadith_reading(hadith_id INTEGER, display_number INTEGER);
            INSERT INTO book VALUES ('v1','istibsar',0),('v2','istibsar',1),('other','other',2);
            INSERT INTO introduction VALUES (5,'v1',0),(6,'v1',1),(7,'v2',0),(8,'other',0);
            INSERT INTO hadith_reading VALUES (100,1),(101,2);
        ''')
        builder.retain_first_introductions(db)
        self.assertEqual(db.execute('SELECT id FROM introduction ORDER BY id').fetchall(), [(5,), (8,)])
        self.assertEqual(db.execute('SELECT * FROM hadith_reading').fetchall(), [(100, 1), (101, 2)])
        db.close()
