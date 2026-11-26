#!/usr/bin/env python3
"""Build the read-only rulings database from the crawl mirror.

    python3 build.py

Reads data/fatwa.sqlite (site language codes, HTML, crawl bookkeeping).
Writes dist/rulings.db (one language code, text, links, search index).

The crawlers key URLs on the site's own codes (arabic, AR, fa). Those stay
in the mirror. This file is the one the app should open.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import tempfile
import sqlite3
import sys
from pathlib import Path

from books import parse_page
from db import SCHEMA_PATH

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
    ("hakeem", "ar"): "ar",
    ("hakeem", "en"): "en",
    ("hakeem", "fa"): "fa",
    ("hakeem", "ur"): "ur",
    ("najafi", "ar"): "ar",
    ("fayadh", "ar"): "ar",
    ("fayadh", "fa"): "fa",
    ("alrohani", "ar"): "ar",
    ("rohani", "ar"): "ar",
    ("rohani", "fa"): "fa",
    ("mshirazi", "ar"): "ar",
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
PRAGMA user_version = 2;
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

CREATE TABLE entry (
  id INTEGER PRIMARY KEY,
  authority_code TEXT NOT NULL REFERENCES authority (code),
  language_code TEXT NOT NULL REFERENCES language (code),
  site_id TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'qa' CHECK(kind IN ('qa','rule','intro')),
  context TEXT NOT NULL DEFAULT '',
  prompt TEXT,
  body TEXT NOT NULL,
  label TEXT NOT NULL DEFAULT '',
  url TEXT NOT NULL,
  UNIQUE (authority_code, language_code, site_id)
) STRICT;

CREATE TABLE footnote (
  topic_id INTEGER NOT NULL REFERENCES topic(id),
  entry_id INTEGER REFERENCES entry(id),
  label TEXT NOT NULL,
  body TEXT NOT NULL
) STRICT;
CREATE INDEX footnote_lookup ON footnote(topic_id,entry_id);

CREATE VIEW question AS
SELECT id,authority_code,language_code,site_id,kind,context,
       CASE WHEN prompt IS NULL THEN label WHEN label='' THEN prompt ELSE label || ' · ' || prompt END AS question,
       body AS answer,url FROM entry;

CREATE TABLE placement (
  topic_id INTEGER NOT NULL REFERENCES topic (id),
  question_id INTEGER NOT NULL REFERENCES entry (id),
  number INTEGER NOT NULL,
  printed_label TEXT,
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
LEFT JOIN topic AS parent ON parent.id = t.parent_id
WHERE q.kind = 'qa';

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


def build(source: Path, output: Path, exclude: frozenset[str] = frozenset()) -> None:
    if not source.is_file():
        raise SystemExit("missing crawl database: %s" % source)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as staging:
        candidate = Path(staging) / "rulings.db"
        build_candidate(source, candidate, exclude)
        candidate.replace(output)


def build_candidate(source: Path, output: Path, exclude: frozenset[str] = frozenset()) -> None:
    src = sqlite3.connect(source)
    src.row_factory = sqlite3.Row
    # Refresh authority rows (names, sort_order) from schema.sql; the crawl DB only gets them when scraping.
    src.executescript(SCHEMA_PATH.read_text())
    # Excluded authorities are hidden behind temp views, so every read below skips them.
    # The iOS pack drops rohani (rohani.ir is under US sanctions); Android keeps it.
    unknown = exclude - {row[0] for row in src.execute("SELECT code FROM authority")}
    if unknown:
        raise SystemExit("unknown authority: %s" % " ".join(sorted(unknown)))
    if exclude:
        listed = ",".join("'%s'" % code.replace("'", "''") for code in sorted(exclude))
        for table, column in (("authority", "code"), ("language", "authority_code"), ("topic", "authority_code"),
                              ("question", "authority_code"), ("placement", "authority_code"),
                              ("book_edition", "authority")):
            if src.execute("SELECT 1 FROM sqlite_master WHERE name=?", (table,)).fetchone():
                src.execute("CREATE TEMP VIEW %s AS SELECT * FROM main.%s WHERE %s NOT IN (%s)"
                            % (table, table, column, listed))
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

        topics = {
            (row["authority_code"], row["language_code"], row["site_id"]): row
            for row in src.execute("SELECT * FROM topic ORDER BY authority_code, language_code, position, site_id")
        }
        root_ids = {}
        for key, row in topics.items():
            if not row["parent_site_id"]:
                root_ids[key] = len(root_ids) + 1

        def main_section(key: tuple[str, str, str]) -> int:
            visited = set()
            while key not in root_ids:
                if key in visited:
                    raise ValueError(f"Cycle in topic hierarchy: {key}")
                visited.add(key)
                key = (*key[:2], topics[key]["parent_site_id"])
            return root_ids[key]

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
            INSERT INTO entry (id, authority_code, language_code, site_id, prompt, body, url)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            question_rows,
        )

        placements = []
        seen = set()
        positions = {}
        for row in src.execute(
            """
            SELECT p.*
            FROM placement AS p LEFT JOIN topic AS t
              ON (p.authority_code, p.language_code, p.topic_site_id)
               = (t.authority_code, t.language_code, t.site_id)
            ORDER BY p.authority_code, p.language_code, t.position, t.site_id, p.position
            """
        ):
            authority, site_language = row["authority_code"], row["language_code"]
            section = main_section((authority, site_language, row["topic_site_id"]))
            question = question_id[(authority, language_code(authority, site_language), row["question_site_id"])]
            if (section, question) not in seen:
                seen.add((section, question))
                positions[section] = positions.get(section, 0) + 1
                placements.append((section, question, row["number_value"], positions[section]))

        sections = []
        for key, section in root_ids.items():
            if section in positions:
                authority, site_language, site_id = key
                row = topics[key]
                sections.append((section, authority, language_code(authority, site_language), site_id,
                                 row["title"], row["letter"], row["position"], row["url"]))
        out.executemany(
            """
            INSERT INTO topic (id, authority_code, language_code, site_id, title, letter, position, url)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            sections,
        )
        out.executemany(
            "INSERT INTO placement (topic_id, question_id, number, position) VALUES (?, ?, ?, ?)",
            placements,
        )
        check_legacy(src, out)
        add_books(src, out)
        check_books(out)
        if exclude:
            listed = ",".join("?" * len(exclude))
            for table in ("entry", "topic"):
                if out.execute("SELECT 1 FROM %s WHERE authority_code IN (%s) LIMIT 1" % (table, listed),
                               tuple(exclude)).fetchone():
                    raise ValueError("Excluded authority leaked into %s" % table)
        out.execute("INSERT INTO question_fts (rowid, question, answer) SELECT id, question, answer FROM question")
        out.execute("INSERT INTO question_fts (question_fts) VALUES ('optimize')")
        if not out.execute("SELECT 1 FROM question_fts WHERE question_fts MATCH 'الصلاة' LIMIT 1").fetchone():
            raise ValueError("Empty rulings search index")
        out.execute("PRAGMA optimize")
        out.commit()
        out.execute("VACUUM")
        if out.execute("PRAGMA foreign_key_check").fetchone() or out.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise ValueError("Invalid rulings pack")
    finally:
        src.close()
        out.close()


def check_legacy(src: sqlite3.Connection, out: sqlite3.Connection) -> None:
    source_questions = src.execute("SELECT COUNT(*) FROM question").fetchone()[0]
    built_questions = out.execute("SELECT COUNT(*) FROM question").fetchone()[0]
    if built_questions != source_questions:
        raise SystemExit(f"Question count mismatch: {built_questions}/{source_questions}")
    expected_placed = {
        (authority, language_code(authority, language), site_id)
        for authority, language, site_id in src.execute(
            "SELECT DISTINCT authority_code, language_code, question_site_id FROM placement"
        )
    }
    actual_placed = set(out.execute("SELECT DISTINCT authority_code, language_code, question_id FROM qa"))
    if actual_placed != expected_placed:
        raise SystemExit("Flattening changed which questions have a section")
    if out.execute("""
        SELECT 1 FROM topic AS t
        WHERE parent_id IS NOT NULL OR NOT EXISTS (SELECT 1 FROM placement WHERE topic_id = t.id)
        LIMIT 1
    """).fetchone():
        raise SystemExit("Built sections must be flat and nonempty")
    built_placements = out.execute("SELECT COUNT(*) FROM placement").fetchone()[0]
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


QUESTION_TITLES = dict(ar="أسئلة", en="Questions", fa="پرسش‌ها", ur="سوالات",
                       az="Suallar", tr="Sorular", fr="Questions")


def check_books(out) -> None:
    """Report final entry totals; check_legacy runs before the books are added."""
    for kind, count, books in out.execute(
        "SELECT kind, COUNT(*), SUM(site_id LIKE 'book:%') FROM entry GROUP BY kind ORDER BY kind"
    ):
        print("entries %s %s (books %s)" % (kind, count, books))
    if out.execute("SELECT 1 FROM entry WHERE site_id LIKE 'book:%' AND label = '' AND TRIM(body) = '' LIMIT 1").fetchone():
        raise SystemExit("Book entry has neither label nor body")
    # A source can print a ruling number with no text; keep the label and flag it.
    empty = out.execute("SELECT COUNT(*) FROM entry WHERE site_id LIKE 'book:%' AND TRIM(body) = ''").fetchone()[0]
    if empty:
        print("warning: %s book entries have an empty body" % empty)


def add_books(src, out):
    def topic(authority, lang, key, title, url, position, parent=None):
        return out.execute("""INSERT INTO topic(authority_code,language_code,site_id,title,url,position,parent_id)
                              VALUES (?,?,?,?,?,?,?)""",
                           (authority, lang, key, title, url, position, parent)).lastrowid

    for authority, lang in out.execute("SELECT DISTINCT authority_code,language_code FROM topic").fetchall():
        out.execute("""UPDATE entry SET context=? || COALESCE((SELECT ' · ' || t.title
                       FROM placement p JOIN topic t ON p.topic_id=t.id WHERE p.question_id=entry.id
                       ORDER BY t.position,t.id LIMIT 1),'') WHERE authority_code=? AND language_code=?""",
                    (QUESTION_TITLES[lang], authority, lang))
        root = topic(authority, lang, "collection:questions", QUESTION_TITLES[lang], "", 0)
        out.execute("UPDATE topic SET parent_id=? WHERE authority_code=? AND language_code=? AND id!=?",
                    (root, authority, lang, root))
    if not src.execute("SELECT 1 FROM sqlite_master WHERE name='book_edition'").fetchone():
        raise ValueError("Missing book mirror. Run build/rulings/books.py and build/rulings/treatise.py first.")
    for edition in src.execute("SELECT * FROM book_edition ORDER BY authority,language,position,site_id"):
        authority = edition["authority"]
        lang = language_code(authority, edition["language"])
        out.execute("INSERT OR IGNORE INTO language VALUES (?,?,?)", (lang, *LANGUAGES[lang]))
        prefix = "book:" + edition["site_id"]
        root = topic(authority, lang, prefix, edition["title"], edition["url"], edition["position"])
        parents = {}
        paths = {}
        entries_by_source = {}
        chapter_parent = root
        for position, chapter in enumerate(json.loads(edition["chapters"]), 1):
            key = prefix + ":" + chapter["id"]
            title = chapter["title"]
            if not title and not chapter["entries"]:
                continue
            parent = parents[chapter["parent"]] if chapter.get("parent") else root
            if authority == "sistani":
                # A flat HTML contents list can still publish a breadcrumb in the heading.
                parts = re.split(r"\s*»\s*", title)
                if parts[0].upper().startswith("CHAPTER "):
                    chapter_parent = root
                elif len(parts) > 1:
                    for depth in range(1, len(parts)):
                        path = tuple(parts[:depth])
                        if path not in paths:
                            paths[path] = topic(authority, lang, prefix + ":heading:" + " » ".join(path),
                                                path[-1], chapter["url"], position, parent)
                        parent = paths[path]
                else:
                    parent = chapter_parent
            section = topic(authority, lang, key, title, chapter["url"], position, parent)
            if authority == "sistani":
                paths[tuple(parts)] = section
                if title.upper().startswith("CHAPTER "):
                    chapter_parent = section
            parents[chapter["id"]] = section
            rows = chapter["entries"]
            notes = []
            if chapter.get("notes_parsed"):
                notes = [(note["label"], note["body"], [] if note["chapter"] else [i])
                         for i, row in enumerate(rows) for note in row.get("footnotes", [])]
            elif authority == "sistani" and "book-footnote" in chapter["raw"]:
                rows, notes = parse_page(chapter["raw"], title, edition["site_id"], separate_notes=True)
                if len(rows) != len(chapter["entries"]):
                    raise ValueError("Entry boundaries changed: " + chapter["url"])
            used = {}
            entry_ids = []
            for index, entry in enumerate(rows, 1):
                number = entry["number"]
                label = entry["label"]
                if label:
                    identity = "".join(label.split())
                elif entry["kind"] == "intro":
                    identity = "intro"
                else:
                    original = chapter["entries"][index - 1]
                    identity = original.get("identity_digest") or hashlib.sha256((original["prompt"] or original["body"]).encode()).hexdigest()[:20]
                used[identity] = used.get(identity, 0) + 1
                if used[identity] > 1:
                    identity += "." + str(used[identity])
                url = chapter["url"]
                share = re.search(r"[?&]ShareTreatise=(\d+)", url)
                source_key = prefix + ":share:" + share[1] if share else key
                site_id = source_key + ":" + identity
                qid = entries_by_source.get(site_id)
                if qid is None:
                    context = edition["title"] + " · " + title
                    qid = out.execute("""
                        INSERT INTO entry(authority_code,language_code,site_id,kind,context,label,prompt,body,url)
                        VALUES (?,?,?,?,?,?,?,?,?)
                    """, (authority, lang, site_id, entry["kind"], context, label or str(number),
                          entry["prompt"] or None, entry["body"], url)).lastrowid
                    entries_by_source[site_id] = qid
                entry_ids.append(qid)
                out.execute("INSERT INTO placement(topic_id,question_id,number,printed_label,position) VALUES (?,?,?,?,?)",
                            (section,qid,number,entry["label"] or None,index))
            for label, body, owners in notes:
                out.executemany("INSERT INTO footnote VALUES (?,?,?,?)",
                                [(section, entry_id, label, body) for entry_id in
                                 ([entry_ids[i] for i in owners] if owners else [None])])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--exclude", action="append", default=[], metavar="AUTHORITY",
                        help="leave an authority out (repeatable); the iOS pack uses --exclude rohani")
    args = parser.parse_args()
    build(SOURCE, args.output, frozenset(args.exclude))
    print("db: %s" % args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
