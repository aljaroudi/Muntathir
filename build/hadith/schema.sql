-- Hadith reader database; experimental morphology is opt-in.

PRAGMA application_id = 1230262606;
PRAGMA user_version = 7;
PRAGMA page_size = 4096;
PRAGMA foreign_keys = ON;

CREATE TABLE collection (
  id TEXT NOT NULL PRIMARY KEY,
  name_ar TEXT NOT NULL,
  name_en TEXT NOT NULL,
  sort_order INTEGER NOT NULL
) STRICT;

CREATE TABLE book (
  id TEXT NOT NULL PRIMARY KEY,
  collection_id TEXT NOT NULL REFERENCES collection (id),
  sect TEXT NOT NULL CHECK (sect IN ('sunni', 'shia')),
  book_group TEXT NOT NULL CHECK (
    book_group IN ('the_9_books', 'forties', 'other_books', 'shia')
  ),
  name_ar TEXT NOT NULL,
  name_en TEXT NOT NULL,
  author TEXT,
  author_ar TEXT NOT NULL DEFAULT '',
  died INTEGER,
  graded INTEGER NOT NULL DEFAULT 0 CHECK (graded IN (0, 1)),
  volume INTEGER,
  siglum TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0
) STRICT;

CREATE INDEX book_collection ON book (collection_id);

CREATE TABLE chapter (
  id INTEGER PRIMARY KEY,
  book_id TEXT NOT NULL REFERENCES book (id),
  chapter_idx INTEGER NOT NULL,
  file_name TEXT NOT NULL,
  name_ar TEXT NOT NULL DEFAULT '',
  name_en TEXT NOT NULL DEFAULT '',
  hadith_count INTEGER NOT NULL DEFAULT 0,
  UNIQUE (book_id, chapter_idx)
) STRICT;

CREATE TABLE hadith (
  id INTEGER PRIMARY KEY,
  book_id TEXT NOT NULL REFERENCES book (id),
  chapter_id INTEGER NOT NULL REFERENCES chapter (id),
  chapter_idx INTEGER NOT NULL,
  id_in_book INTEGER NOT NULL,
  source_id INTEGER,
  arabic TEXT NOT NULL DEFAULT '',
  english_narrator TEXT NOT NULL DEFAULT '',
  english_text TEXT NOT NULL DEFAULT '',
  url TEXT NOT NULL DEFAULT '',
  UNIQUE (book_id, chapter_idx, id_in_book)
) STRICT;

CREATE INDEX hadith_book_iib ON hadith (book_id, id_in_book);
CREATE INDEX hadith_chapter ON hadith (chapter_id);

-- Introductions have their own identity and never participate in narration navigation.
CREATE TABLE introduction (
  id INTEGER PRIMARY KEY,
  book_id TEXT NOT NULL REFERENCES book (id),
  chapter_id INTEGER REFERENCES chapter (id),
  title TEXT NOT NULL DEFAULT '',
  arabic TEXT NOT NULL DEFAULT '',
  english TEXT NOT NULL DEFAULT '',
  url TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0
) STRICT;
CREATE INDEX introduction_book ON introduction(book_id);

-- Source numbers remain immutable; only the displayed sequence excludes introductions.
CREATE TABLE hadith_reading (
  hadith_id INTEGER PRIMARY KEY REFERENCES hadith (id),
  words INTEGER NOT NULL DEFAULT 0,
  display_number INTEGER
) STRICT;

CREATE TABLE grader (
  id TEXT NOT NULL PRIMARY KEY,
  name_ar TEXT NOT NULL DEFAULT '',
  name_en TEXT NOT NULL DEFAULT ''
) STRICT;

CREATE TABLE hadith_grading (
  id INTEGER PRIMARY KEY,
  hadith_id INTEGER NOT NULL REFERENCES hadith (id),
  grader_id TEXT REFERENCES grader (id),
  grade_ar TEXT NOT NULL DEFAULT '',
  grade_en TEXT NOT NULL DEFAULT '',
  reference_ar TEXT NOT NULL DEFAULT '',
  reference_en TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL CHECK (status IN ('judgment', 'not_included', 'unparsed')),
  original_text TEXT NOT NULL,
  CHECK (status != 'judgment' OR grade_ar != '' OR grade_en != ''),
  CHECK (status = 'judgment' OR (grade_ar = '' AND grade_en = ''))
) STRICT;

CREATE UNIQUE INDEX hadith_grading_identity ON hadith_grading (
  hadith_id, coalesce(grader_id, ''), grade_ar, grade_en, reference_ar, reference_en, status,
  CASE WHEN status = 'unparsed' THEN original_text ELSE '' END
);

-- Contentless FTS mirrors apple/.../quran.db conventions.
CREATE VIRTUAL TABLE hadith_words USING fts5 (
  text,
  content = '',
  tokenize = 'unicode61 remove_diacritics 2',
  prefix = '2 3'
);

CREATE VIRTUAL TABLE hadith_words_vocab USING fts5vocab (hadith_words, col);

CREATE VIRTUAL TABLE hadith_fts USING fts5 (
  text,
  content = '',
  tokenize = 'trigram remove_diacritics 1'
);

CREATE VIEW hadith_english_content AS
SELECT id, trim(english_narrator || ' ' || english_text) AS text FROM hadith;

CREATE VIRTUAL TABLE hadith_en USING fts5 (
  text,
  content = 'hadith_english_content',
  content_rowid = 'id',
  tokenize = 'porter unicode61 remove_diacritics 2'
);
