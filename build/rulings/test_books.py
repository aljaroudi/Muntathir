import json
import sqlite3
import unittest
from unittest.mock import patch

import books
from build import SCHEMA, add_books, check_books
from treatise import page_entries


class BookTests(unittest.TestCase):
    def test_html_and_api_numbering(self):
        markup = '<div class="book-text">تمهيد<br>المسألة ۱۲۳: نص [1]<br>السؤال ٤: سؤال؟<br>الجواب: جواب</div>'
        notes = '<div class="book-footnote">[1] هامش</div>'
        rows = books.parse_page(markup + notes, "الطهارة")
        self.assertEqual([(r["number"], r["kind"]) for r in rows], [(0, "intro"), (123, "rule"), (4, "qa")])
        self.assertEqual(rows[1]["body"], "نص [1]")
        self.assertEqual(rows[1]["footnotes"], [dict(label="[1]", body="هامش", chapter=False)])
        self.assertEqual(rows[2]["prompt"], "سؤال؟")
        url, api = page_entries('<input id="estefta_body_Book" value="المسألة ۱۲۳: نص"><a href="?ShareTreatise=9&amp;langs=AR">', "باب", "AR")
        self.assertEqual(api[0]["number"], 123)
        self.assertTrue(url.endswith("ShareTreatise=9&langs=AR"))

    def test_parenthesized_notes_belong_to_the_ruling_that_cites_them(self):
        page = ('<div class="book-text">[ 1180 ] مسألة 1 : النص (18) ثم (19).<br>'
                '[ 1181 ] مسألة 2 : النص (20).</div><div class="book-footnote">'
                '(18)(بذهاب الحمرة المشرقية) : شرح<br>تكملة<br>(19)(كما عليه جماعة) : وهو الاقوى.'
                '<br>(20) هامش آخر<br>(21) هامش للفصل</div>')
        rows, notes = books.parse_page(page, "الفصل", separate_notes=True)
        self.assertEqual([owners for _, _, owners in notes], [[0], [0], [1], []])
        self.assertEqual([label for label, _, _ in notes], ["(18)", "(19)", "(20)", "(21)"])
        self.assertIn("تكملة", notes[0][1])
        self.assertNotIn("تكملة", rows[0]["body"])

    def test_heading_only_is_chapter_introduction(self):
        rows = books.parse_page('<div class="book-text"></div>', "Glossary")
        self.assertEqual([(e["kind"], e["number"], e["body"]) for e in rows], [("intro", 0, "Glossary")])

    def test_quoted_marker(self):
        rows = books.entries('Question: Is the label literal?\nAnswer: The label reads “Question:” here.', "Q&A")
        self.assertEqual(len(rows), 1)
        self.assertIn("“Question:”", rows[0]["body"])
        with self.assertRaises(ValueError):
            books.entries('Question: Who?', "Q&A")

    def test_failed_chapter_preserves_complete_edition(self):
        db = sqlite3.connect(":memory:")
        pages = {"/english/book/fatwa/": '<a href="/english/book/1/">Book</a><a href="/files/book.pdf">PDF</a>',
                 "/english/book/1/": '<a href="/english/book/1/2/">Chapter</a>',
                 "/english/book/1/2/": '<div class="book-text">Ruling 2. Body</div>'}
        def get(client, url):
            from sistani import Fetch
            return Fetch(200, url, pages[url.removeprefix(books.ORIGIN)])
        with patch.object(books, "fetch_retry", get):
            self.assertFalse(books.crawl(db, ["english"], None))
            before = db.execute("SELECT chapters FROM book_edition").fetchone()
            pages["/english/book/1/2/"] = "<html>Error</html>"
            self.assertTrue(books.crawl(db, ["english"], None))
            self.assertEqual(before, db.execute("SELECT chapters FROM book_edition").fetchone())
        db.row_factory = sqlite3.Row
        out = sqlite3.connect(":memory:")
        out.executescript(SCHEMA)
        out.execute("INSERT INTO authority VALUES ('sistani','ع','Sistani',1)")
        add_books(db, out)
        self.assertEqual(out.execute("SELECT kind,prompt,body FROM entry").fetchone(), ("rule",None,"Body"))
        self.assertEqual(out.execute("SELECT number,printed_label FROM placement").fetchone(), (2,"Ruling 2."))
        self.assertFalse(out.execute("PRAGMA foreign_key_check").fetchall())
        self.assertTrue(json.loads(before[0])[0]["raw"])

    def test_book_references_are_deterministic_and_unique(self):
        db = sqlite3.connect(":memory:")
        pages = {"/english/book/fatwa/": '<a href="/english/book/1/">Book</a>',
                 "/english/book/1/": '<a href="/english/book/1/2/">Chapter</a>',
                 "/english/book/1/2/": '<div class="book-text">Ruling 2. Body<br>Ruling 2. Body</div>'}
        def get(client, url):
            from sistani import Fetch
            return Fetch(200, url, pages[url.removeprefix(books.ORIGIN)])
        with patch.object(books, "fetch_retry", get):
            books.crawl(db, ["english"], None)
        db.row_factory = sqlite3.Row

        def build():
            out = sqlite3.connect(":memory:")
            out.executescript(SCHEMA)
            out.execute("INSERT INTO authority VALUES ('sistani','ع','Sistani',1)")
            add_books(db, out)
            check_books(out)
            return out.execute("SELECT authority_code,language_code,site_id,kind,context FROM entry ORDER BY id").fetchall()
        first = build()
        self.assertEqual(first, build())
        ids = [row[:3] for row in first]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(all(row[2].startswith("book:") for row in first))
        # Repeated printed labels in one chapter stay distinct through a numeric suffix.
        self.assertEqual(len(first), 2)
        self.assertTrue(first[1][2].endswith(".2"))
        self.assertTrue(first[0][4].endswith("Chapter"))


if __name__ == "__main__":
    unittest.main()
