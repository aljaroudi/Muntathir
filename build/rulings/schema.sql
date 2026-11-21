-- Fatwa Q&A for more than one authority.
-- authority_code leads every primary key: search by authority first.
--
-- Sistani question: https://www.sistani.org/{language}/qa/{question_id}/
--   page_anchor_url is the section page plus #question_id.
-- Shirazi question: https://alshirazi.org/estefta?ShareEstefta={id}&langs={language}
--   That is the link the site itself publishes. Topic pages are the catalog.
-- Khorasani question: https://wahidkhorasani.com/qna/{slug}
-- Hakeem question: https://www.alhakeem.com/{language}/question/{id}
-- Najafi question: https://www.alnajafy.com/list/mainnews-{page}-1-677-{category}-1.html#{id}
--   Questions have no page of their own; the URL is the category page plus #id.
-- Fayadh question: the WordPress permalink from https://{language}.alfayadh.org/wp-json/wp/v2/question
-- Al-Rohani question: https://alrohani.org/index.php?act=qa&action=view&id={id}
-- Rohani question: https://www.rohani.ir/{language}/idetail/{id}/x
-- Muhammad al-Shirazi question: https://www.alshirazi.com/rflo/alestiftaatalmarjeyeh/{chapter}.htm
--   Static pages without anchors; the URL is the chapter page.

PRAGMA application_id = 1364218708;
PRAGMA user_version = 2;
PRAGMA page_size = 4096;

CREATE TABLE IF NOT EXISTS authority (
  code TEXT NOT NULL PRIMARY KEY,
  name_ar TEXT NOT NULL,
  name_en TEXT NOT NULL,
  base_url TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  note TEXT NOT NULL DEFAULT ''
) STRICT;

INSERT INTO authority (code, name_ar, name_en, base_url, sort_order, note)
VALUES
  (
    'sistani',
    'السيد علي السيستاني',
    'Ali al-Husayni al-Sistani',
    'https://www.sistani.org/',
    1,
    'Question URL redirects to the section page fragment.'
  ),
  (
    'shirazi',
    'السيد صادق الشيرازي',
    'Sadiq al-Husayni al-Shirazi',
    'https://alshirazi.org/',
    2,
    'Question URL is the site share link (?ShareEstefta=&langs=).'
  ),
  (
    'khorasani',
    'الشيخ الوحيد الخراساني',
    'Sheikh al-Wahid al-Khorasani',
    'https://wahidkhorasani.com/',
    3,
    'Question URL is https://wahidkhorasani.com/qna/{slug}. Arabic and English locales exist but currently have no Q&A.'
  ),
  (
    'hakeem',
    'السيد محمد سعيد الحكيم',
    'Muhammad Saeed al-Tabatabai al-Hakeem',
    'https://www.alhakeem.com/',
    4,
    'Question URL is https://www.alhakeem.com/{language}/question/{id}. Persian uses Arabic category ids; Urdu currently has no Q&A.'
  ),
  (
    'najafi',
    'الشيخ بشير النجفي',
    'Bashir al-Najafi',
    'https://www.alnajafy.com/',
    5,
    'Arabic only (site la=1). Question URL is the category page plus #{id}; the site has no per-question page.'
  ),
  (
    'fayadh',
    'الشيخ إسحاق الفياض',
    'Ishaq al-Fayyad',
    'https://ar.alfayadh.org/',
    6,
    'Arabic (ar.alfayadh.org) and Persian (fa.alfayadh.org), read through the WordPress REST API.'
  ),
  (
    'alrohani',
    'السيد محمد الروحاني',
    'Muhammad al-Rohani',
    'https://alrohani.org/',
    7,
    'Arabic only. Question URL is https://alrohani.org/index.php?act=qa&action=view&id={id}.'
  ),
  (
    'rohani',
    'السيد محمد صادق الروحاني',
    'Muhammad Sadiq al-Rohani',
    'https://www.rohani.ir/',
    8,
    'Arabic and Persian. Question URL is https://www.rohani.ir/{language}/idetail/{id}/x. Sharia and belief rulings are separate top-level topics.'
  ),
  (
    'mshirazi',
    'السيد محمد الشيرازي',
    'Muhammad al-Husayni al-Shirazi',
    'https://www.alshirazi.com/',
    9,
    'Arabic only. Static windows-1256 pages with no API. Question URL is the chapter page https://www.alshirazi.com/rflo/alestiftaatalmarjeyeh/{chapter}.htm. The book Muntakhab al-Masail is stored in book_edition.'
  )
ON CONFLICT (code) DO UPDATE SET
  name_ar = excluded.name_ar,
  name_en = excluded.name_en,
  base_url = excluded.base_url,
  sort_order = excluded.sort_order,
  note = excluded.note;

CREATE TABLE IF NOT EXISTS language (
  authority_code TEXT NOT NULL DEFAULT 'sistani' REFERENCES authority (code),
  code TEXT NOT NULL,
  native_name TEXT NOT NULL,
  hreflang TEXT NOT NULL DEFAULT '',
  direction TEXT NOT NULL CHECK (direction IN ('rtl', 'ltr')),
  declared_question_count INTEGER,
  indexed_at TEXT,
  PRIMARY KEY (authority_code, code)
) STRICT;

CREATE TABLE IF NOT EXISTS topic (
  authority_code TEXT NOT NULL DEFAULT 'sistani' REFERENCES authority (code),
  language_code TEXT NOT NULL,
  site_id TEXT NOT NULL,
  title TEXT NOT NULL,
  letter TEXT NOT NULL DEFAULT '',
  position INTEGER NOT NULL CHECK (position >= 1),
  declared_count INTEGER,
  url TEXT NOT NULL,
  parent_site_id TEXT,
  fetch_status TEXT NOT NULL DEFAULT 'error'
    CHECK (fetch_status IN ('ok', 'partial', 'error')),
  fetched_at TEXT,
  PRIMARY KEY (authority_code, language_code, site_id),
  FOREIGN KEY (authority_code, language_code)
    REFERENCES language (authority_code, code),
  FOREIGN KEY (authority_code, language_code, parent_site_id)
    REFERENCES topic (authority_code, language_code, site_id)
) STRICT;

CREATE INDEX IF NOT EXISTS topic_authority_position
  ON topic (authority_code, language_code, position);

CREATE TABLE IF NOT EXISTS question (
  authority_code TEXT NOT NULL DEFAULT 'sistani' REFERENCES authority (code),
  language_code TEXT NOT NULL,
  site_id TEXT NOT NULL,
  question_text TEXT NOT NULL,
  answer_text TEXT NOT NULL,
  question_html TEXT NOT NULL,
  answer_html TEXT NOT NULL,
  url TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  fetched_at TEXT NOT NULL,
  changed_at TEXT NOT NULL,
  PRIMARY KEY (authority_code, language_code, site_id),
  FOREIGN KEY (authority_code, language_code)
    REFERENCES language (authority_code, code)
) STRICT;

CREATE INDEX IF NOT EXISTS question_authority
  ON question (authority_code, language_code, site_id);

CREATE TABLE IF NOT EXISTS placement (
  authority_code TEXT NOT NULL DEFAULT 'sistani',
  language_code TEXT NOT NULL,
  topic_site_id TEXT NOT NULL,
  question_site_id TEXT NOT NULL,
  page_number INTEGER NOT NULL CHECK (page_number >= 1),
  page_url TEXT NOT NULL,
  anchor_url TEXT NOT NULL,
  number_label TEXT NOT NULL,
  number_value INTEGER NOT NULL CHECK (number_value >= 1),
  position INTEGER NOT NULL CHECK (position >= 1),
  PRIMARY KEY (authority_code, language_code, topic_site_id, page_number, position),
  UNIQUE (authority_code, language_code, topic_site_id, question_site_id, page_number),
  FOREIGN KEY (authority_code, language_code, topic_site_id)
    REFERENCES topic (authority_code, language_code, site_id) ON DELETE CASCADE,
  FOREIGN KEY (authority_code, language_code, question_site_id)
    REFERENCES question (authority_code, language_code, site_id) ON DELETE CASCADE
) STRICT;

CREATE INDEX IF NOT EXISTS placement_authority_question
  ON placement (authority_code, language_code, question_site_id);

CREATE INDEX IF NOT EXISTS placement_authority_topic
  ON placement (authority_code, language_code, topic_site_id, page_number, position);

CREATE TABLE IF NOT EXISTS fetch_error (
  url TEXT NOT NULL PRIMARY KEY,
  authority_code TEXT NOT NULL DEFAULT 'sistani',
  language_code TEXT NOT NULL DEFAULT '',
  kind TEXT NOT NULL,
  error TEXT NOT NULL,
  attempted_at TEXT NOT NULL
) STRICT;

CREATE INDEX IF NOT EXISTS fetch_error_authority
  ON fetch_error (authority_code, language_code);

CREATE TABLE IF NOT EXISTS crawl (
  id INTEGER PRIMARY KEY,
  started_at TEXT NOT NULL,
  finished_at TEXT,
  status TEXT NOT NULL CHECK (status IN ('running', 'ok', 'incomplete')),
  languages TEXT NOT NULL DEFAULT '',
  authorities TEXT NOT NULL DEFAULT '',
  note TEXT NOT NULL DEFAULT ''
) STRICT;

DROP VIEW IF EXISTS qa;
CREATE VIEW qa AS
SELECT
  a.code AS authority_code,
  a.name_ar AS authority_name_ar,
  a.name_en AS authority_name_en,
  a.sort_order AS authority_sort,
  q.language_code,
  l.native_name AS language_name,
  l.direction,
  t.site_id AS topic_id,
  t.title AS topic_title,
  t.parent_site_id AS topic_parent_id,
  t.letter AS topic_letter,
  t.position AS topic_position,
  p.page_number,
  p.page_url,
  p.number_value AS number,
  p.number_label,
  q.site_id AS question_id,
  q.url AS question_url,
  p.anchor_url AS page_anchor_url,
  q.question_text,
  q.answer_text,
  q.question_html,
  q.answer_html
FROM question AS q
JOIN authority AS a ON a.code = q.authority_code
JOIN language AS l
  ON l.authority_code = q.authority_code
 AND l.code = q.language_code
JOIN placement AS p
  ON p.authority_code = q.authority_code
 AND p.language_code = q.language_code
 AND p.question_site_id = q.site_id
JOIN topic AS t
  ON t.authority_code = p.authority_code
 AND t.language_code = p.language_code
 AND t.site_id = p.topic_site_id;

DROP VIEW IF EXISTS topic_count_gap;
CREATE VIEW topic_count_gap AS
SELECT
  t.authority_code,
  t.language_code,
  t.site_id,
  t.title,
  t.declared_count,
  COUNT(p.question_site_id) AS fetched_count,
  t.url
FROM topic AS t
LEFT JOIN placement AS p
  ON p.authority_code = t.authority_code
 AND p.language_code = t.language_code
 AND p.topic_site_id = t.site_id
GROUP BY t.authority_code, t.language_code, t.site_id
HAVING t.declared_count IS NOT NULL
   AND COUNT(p.question_site_id) != t.declared_count;

DROP TABLE IF EXISTS question_fts;
CREATE VIRTUAL TABLE question_fts USING fts5(
  authority_code UNINDEXED,
  language_code UNINDEXED,
  question_site_id UNINDEXED,
  topic_title,
  question_text,
  answer_text,
  tokenize = 'unicode61 remove_diacritics 2'
);
