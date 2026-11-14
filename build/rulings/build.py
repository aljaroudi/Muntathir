#!/usr/bin/env python3
"""Build the read-only rulings database from the crawl mirror.

    python3 build.py

Reads data/fatwa.sqlite (site language codes, HTML, crawl bookkeeping).
Writes dist/rulings.db (one language code, text, links, search index).

The crawlers key URLs on the site's own codes (arabic, AR, fa). Those stay
in the mirror. This file is the one the app should open.
"""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "data" / "fatwa.sqlite"
OUTPUT = HERE / "dist" / "rulings.db"

# Site path/query code -> one code. hreflang is not copied; nothing reads it.
SITE_LANGUAGE = {
    ("sistani", "arabic"): "ar",
    ("sistani", "persian"): "fa",
    ("sistani", "urdu"): "ur",
    ("sistani", "english"): "en",
    ("sistani", "azari"): "az",
    ("sistani", "turkish"): "tr",
    ("sistani", "french"): "fr",
    ("shirazi", "AR"): "ar",
    ("shirazi", "EN"): "en",
    ("shirazi", "FA"): "fa",
    ("khorasani", "ar"): "ar",
    ("khorasani", "en"): "en",
    ("khorasani", "fa"): "fa",
}

LANGUAGES = {
    "ar": ("العربية", "rtl"),
    "fa": ("فارسی", "rtl"),
    "ur": ("اردو", "rtl"),
    "en": ("English", "ltr"),
    "az": ("Azərbaycan", "ltr"),
    "tr": ("Türkçe", "ltr"),
    "fr": ("Français", "ltr"),
}

SCHEMA = """
PRAGMA application_id = 1179809601;
PRAGMA user_version = 1;
PRAGMA page_size = 4096;

CREATE TABLE authority (
  code TEXT NOT NULL PRIMARY KEY,
  name_ar TEXT NOT NULL,
  name_en TEXT NOT NULL,
  sort_order INTEGER NOT NULL
) STRICT;

CREATE TABLE language (
  code TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  direction TEXT NOT NULL CHECK (direction IN ('rtl', 'ltr'))
) STRICT;

CREATE TABLE topic (
  id INTEGER PRIMARY KEY,
  authority_code TEXT NOT NULL REFERENCES authority (code),
  language_code TEXT NOT NULL REFERENCES language (code),
  site_id TEXT NOT NULL,
  title TEXT NOT NULL,
  letter TEXT NOT NULL DEFAULT '',
  position INTEGER NOT NULL,
  parent_id INTEGER REFERENCES topic (id),
  url TEXT NOT NULL,
  UNIQUE (authority_code, language_code, site_id)
) STRICT;

CREATE INDEX topic_browse ON topic (authority_code, language_code, position);

CREATE TABLE question (
  id INTEGER PRIMARY KEY,
  authority_code TEXT NOT NULL REFERENCES authority (code),
  language_code TEXT NOT NULL REFERENCES language (code),
  site_id TEXT NOT NULL,
  question TEXT NOT NULL,
  answer TEXT NOT NULL,
  url TEXT NOT NULL,
  UNIQUE (authority_code, language_code, site_id)
) STRICT;

CREATE TABLE placement (
  topic_id INTEGER NOT NULL REFERENCES topic (id),
  question_id INTEGER NOT NULL REFERENCES question (id),
  number INTEGER NOT NULL,
  position INTEGER NOT NULL,
  PRIMARY KEY (topic_id, position),
  UNIQUE (topic_id, question_id)
) STRICT;

CREATE INDEX placement_question ON placement (question_id);

CREATE VIEW qa AS
SELECT
  a.code AS authority_code,
  a.name_ar AS authority_name_ar,
  a.name_en AS authority_name_en,
  a.sort_order AS authority_sort,
  q.language_code,
  l.name AS language_name,
  l.direction,
  t.site_id AS topic_id,
  t.title AS topic_title,
  t.letter AS topic_letter,
  t.position AS topic_position,
  parent.site_id AS topic_parent_id,
  p.number,
  p.position,
  q.site_id AS question_id,
  q.question,
  q.answer,
  q.url
FROM placement AS p
JOIN question AS q ON q.id = p.question_id
JOIN topic AS t ON t.id = p.topic_id
JOIN authority AS a ON a.code = q.authority_code
JOIN language AS l ON l.code = q.language_code
LEFT JOIN topic AS parent ON parent.id = t.parent_id;

CREATE VIRTUAL TABLE question_fts USING fts5(
  question,
  answer,
  content = 'question',
  content_rowid = 'id',
  tokenize = 'unicode61 remove_diacritics 2'
);
"""


def language_code(authority: str, site_code: str) -> str:
    try:
        return SITE_LANGUAGE[(authority, site_code)]
    except KeyError as exc:
        raise SystemExit("no language mapping for %s/%s" % (authority, site_code)) from exc


def build(source: Path, output: Path) -> None:
    if not source.is_file():
        raise SystemExit("missing crawl database: %s" % source)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.unlink(missing_ok=True)
    for suffix in ("-wal", "-shm"):
        sidecar = Path(str(output) + suffix)
        if sidecar.exists():
            sidecar.unlink()

    src = sqlite3.connect(source)
    src.row_factory = sqlite3.Row
    out = sqlite3.connect(output)
    try:
        out.executescript(SCHEMA)
        authorities = list(src.execute("SELECT code, name_ar, name_en, sort_order FROM authority ORDER BY sort_order"))
        out.executemany(
            "INSERT INTO authority (code, name_ar, name_en, sort_order) VALUES (?, ?, ?, ?)",
            [(row["code"], row["name_ar"], row["name_en"], row["sort_order"]) for row in authorities],
        )

        used = {
            language_code(row["authority_code"], row["code"])
            for row in src.execute("SELECT authority_code, code FROM language")
        }
        out.executemany(
            "INSERT INTO language (code, name, direction) VALUES (?, ?, ?)",
            [(code, LANGUAGES[code][0], LANGUAGES[code][1]) for code in sorted(used)],
        )

        topic_id = {}
        next_topic = 1
        topic_rows = []
        for row in src.execute(
            """
            SELECT authority_code, language_code, site_id, title, letter, position, parent_site_id, url
            FROM topic
            ORDER BY authority_code, language_code, position, site_id
            """
        ):
            code = language_code(row["authority_code"], row["language_code"])
            topic_id[(row["authority_code"], code, row["site_id"])] = next_topic
            topic_rows.append((
                next_topic,
                row["authority_code"],
                code,
                row["site_id"],
                row["title"],
                row["letter"],
                row["position"],
                row["parent_site_id"],
                row["url"],
            ))
            next_topic += 1
        out.executemany(
            """
            INSERT INTO topic (id, authority_code, language_code, site_id, title, letter, position, url)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [(row[0], row[1], row[2], row[3], row[4], row[5], row[6], row[8]) for row in topic_rows],
        )
        out.executemany(
            "UPDATE topic SET parent_id = ? WHERE id = ?",
            [
                (topic_id[(row[1], row[2], row[7])], row[0])
                for row in topic_rows
                if row[7]
            ],
        )

        question_id = {}
        next_question = 1
        question_rows = []
        for row in src.execute(
            """
            SELECT authority_code, language_code, site_id, question_text, answer_text, url
            FROM question
            ORDER BY authority_code, language_code, site_id
            """
        ):
            code = language_code(row["authority_code"], row["language_code"])
            question_id[(row["authority_code"], code, row["site_id"])] = next_question
            question_rows.append((
                next_question,
                row["authority_code"],
                code,
                row["site_id"],
                row["question_text"],
                row["answer_text"],
                row["url"],
            ))
            next_question += 1
        out.executemany(
            """
            INSERT INTO question (id, authority_code, language_code, site_id, question, answer, url)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            question_rows,
        )

        placements = []
        for row in src.execute(
            """
            SELECT authority_code, language_code, topic_site_id, question_site_id, number_value, position
            FROM placement
            ORDER BY authority_code, language_code, topic_site_id, position
            """
        ):
            code = language_code(row["authority_code"], row["language_code"])
            placements.append((
                topic_id[(row["authority_code"], code, row["topic_site_id"])],
                question_id[(row["authority_code"], code, row["question_site_id"])],
                row["number_value"],
                row["position"],
            ))
        out.executemany(
            "INSERT INTO placement (topic_id, question_id, number, position) VALUES (?, ?, ?, ?)",
            placements,
        )
        out.execute("INSERT INTO question_fts (rowid, question, answer) SELECT id, question, answer FROM question")
        out.execute("INSERT INTO question_fts (question_fts) VALUES ('optimize')")
        out.execute("PRAGMA optimize")
        out.commit()
        out.execute("VACUUM")
        check(src, out)
    finally:
        src.close()
        out.close()


def check(src: sqlite3.Connection, out: sqlite3.Connection) -> None:
    source_questions = src.execute("SELECT COUNT(*) FROM question").fetchone()[0]
    source_placements = src.execute("SELECT COUNT(*) FROM placement").fetchone()[0]
    built_questions = out.execute("SELECT COUNT(*) FROM question").fetchone()[0]
    built_placements = out.execute("SELECT COUNT(*) FROM placement").fetchone()[0]
    if built_questions != source_questions or built_placements != source_placements:
        raise SystemExit("count mismatch questions %s/%s placements %s/%s" % (
            built_questions, source_questions, built_placements, source_placements,
        ))
    orphans = out.execute(
        """
        SELECT COUNT(*) FROM topic AS child
        LEFT JOIN topic AS parent ON parent.id = child.parent_id
        WHERE child.parent_id IS NOT NULL AND parent.id IS NULL
        """
    ).fetchone()[0]
    if orphans:
        raise SystemExit("%s topics point at a missing parent" % orphans)
    sample = out.execute(
        "SELECT language_code, url FROM question WHERE authority_code = 'sistani' AND site_id = '6357'"
    ).fetchone()
    if sample is None or sample[0] != "ar" or "6357" not in sample[1]:
        raise SystemExit("sistani 6357 did not map to ar")
    hit = out.execute(
        "SELECT count(*) FROM question_fts WHERE question_fts MATCH 'الصلاة'"
    ).fetchone()[0]
    if hit < 1:
        raise SystemExit("search index returned nothing for الصلاة")
    codes = [row[0] for row in out.execute("SELECT code FROM language ORDER BY code")]
    print("languages: %s" % " ".join(codes))
    for row in out.execute(
        """
        SELECT authority_code, language_code, COUNT(*)
        FROM question
        GROUP BY 1, 2
        ORDER BY 1, 2
        """
    ):
        print("%s %s %s" % row)
    print("questions %s  placements %s" % (built_questions, built_placements))


def main() -> int:
    build(SOURCE, OUTPUT)
    print("db: %s" % OUTPUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
