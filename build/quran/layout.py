#!/usr/bin/env python3
"""Load Tanzil divisions and the QUL 15-line Madani layout with QPC Hafs word text into quran.db.

usage: layout.py quran-data.xml qpc-v1-15-lines.db qpc-hafs-word-by-word.db quran.db
"""

import sqlite3
import sys
import xml.etree.ElementTree as ET

metadata, layout, words, database = sys.argv[1:5]
db = sqlite3.connect(database)
db.execute("ATTACH ? AS layout", (layout,))
db.execute("ATTACH ? AS qpc", (words,))
index = {(s, a): i for i, s, a in db.execute('SELECT "index", sura, aya FROM quran')}

db.executescript("""
CREATE TABLE quran_divisions (kind TEXT, number INTEGER, start INTEGER NOT NULL, PRIMARY KEY (kind, number)) WITHOUT ROWID;
CREATE TABLE quran_sajdas (start INTEGER PRIMARY KEY, type TEXT NOT NULL);
CREATE TABLE quran_words_qpc ("index" INTEGER, word INTEGER, text TEXT NOT NULL, PRIMARY KEY ("index", word)) WITHOUT ROWID;
CREATE TABLE quran_lines (page INTEGER, line INTEGER, type TEXT NOT NULL, centered INTEGER NOT NULL, sura INTEGER NOT NULL,
  first_index INTEGER, first_word INTEGER, last_index INTEGER, last_word INTEGER, PRIMARY KEY (page, line)) WITHOUT ROWID;
ALTER TABLE quran ADD COLUMN page INTEGER;
ALTER TABLE quran ADD COLUMN juz INTEGER;

INSERT INTO quran_words_qpc SELECT q."index", w.word, w.text FROM qpc.words w JOIN quran q ON q.sura = w.surah AND q.aya = w.ayah;

-- surah_number is only set on title lines; ayah and basmala lines take the sura of their words or of the next line.
INSERT INTO quran_lines
SELECT p.page_number, p.line_number, p.line_type, p.is_centered,
  coalesce(nullif(p.surah_number, ''), f.surah, (SELECT min(w.surah) FROM layout.pages n JOIN qpc.words w ON w.id = n.first_word_id
    WHERE n.first_word_id != '' AND (n.page_number, n.line_number) > (p.page_number, p.line_number))),
  fq."index", f.word, lq."index", l.word
FROM layout.pages p
LEFT JOIN qpc.words f ON f.id = nullif(p.first_word_id, '') LEFT JOIN quran fq ON fq.sura = f.surah AND fq.aya = f.ayah
LEFT JOIN qpc.words l ON l.id = nullif(p.last_word_id, '') LEFT JOIN quran lq ON lq.sura = l.surah AND lq.aya = l.ayah;
""")

root = ET.parse(metadata).getroot()
for kind, tag in [("page", "page"), ("juz", "juz"), ("hizb", "quarter"), ("manzil", "manzil"), ("ruku", "ruku")]:
    db.executemany("INSERT INTO quran_divisions VALUES (?, ?, ?)",
                   [(kind, int(e.get("index")), index[int(e.get("sura")), int(e.get("aya"))]) for e in root.iter(tag)])
db.executemany("INSERT INTO quran_sajdas VALUES (?, ?)",
               [(index[int(e.get("sura")), int(e.get("aya"))], e.get("type")) for e in root.iter("sajda")])

db.executescript("""
UPDATE quran SET page = (SELECT min(page) FROM quran_lines WHERE quran."index" BETWEEN first_index AND last_index),
  juz = (SELECT max(number) FROM quran_divisions WHERE kind = 'juz' AND start <= quran."index");
CREATE INDEX quran_page ON quran (page);
""")
db.commit()
