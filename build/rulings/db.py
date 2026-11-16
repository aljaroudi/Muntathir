"""SQLite setup for the fatwa corpus."""

from __future__ import annotations

import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SCHEMA_PATH = ROOT / "schema.sql"
DEFAULT_DB = ROOT / "data" / "fatwa.sqlite"


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def table_exists(conn: sqlite3.Connection, name: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
        (name,),
    ).fetchone()
    return row is not None


def has_column(conn: sqlite3.Connection, table: str, column: str) -> bool:
    rows = conn.execute("PRAGMA table_info(%s)" % table).fetchall()
    return any(row[1] == column for row in rows)


def migrate_v1_to_v2(conn: sqlite3.Connection) -> None:
    """Add authority as the leading key. Existing rows are Sistani."""
    if table_exists(conn, "question") and has_column(conn, "question", "authority_code"):
        return
    if not table_exists(conn, "question") and not table_exists(conn, "question_v1"):
        return
    conn.execute("PRAGMA foreign_keys = OFF")
    conn.execute("DROP VIEW IF EXISTS qa")
    conn.execute("DROP VIEW IF EXISTS topic_count_gap")
    if table_exists(conn, "fetch_error") and not has_column(conn, "fetch_error", "authority_code"):
        conn.execute(
            "ALTER TABLE fetch_error ADD COLUMN authority_code TEXT NOT NULL DEFAULT 'sistani'"
        )
    if table_exists(conn, "crawl") and not has_column(conn, "crawl", "authorities"):
        conn.execute("ALTER TABLE crawl ADD COLUMN authorities TEXT NOT NULL DEFAULT ''")
    for name in ("language", "topic", "question", "placement"):
        if table_exists(conn, name) and not table_exists(conn, name + "_v1"):
            conn.execute("ALTER TABLE %s RENAME TO %s_v1" % (name, name))
    conn.commit()


def copy_v1_rows(conn: sqlite3.Connection) -> None:
    if not table_exists(conn, "question_v1"):
        return
    conn.execute("PRAGMA foreign_keys = OFF")
    with conn:
        conn.execute(
            """
            INSERT INTO language (
              authority_code, code, native_name, hreflang, direction,
              declared_question_count, indexed_at
            )
            SELECT 'sistani', code, native_name, hreflang, direction,
                   declared_question_count, indexed_at
            FROM language_v1
            """
        )
        conn.execute(
            """
            INSERT INTO topic (
              authority_code, language_code, site_id, title, letter, position,
              declared_count, url, parent_site_id, fetch_status, fetched_at
            )
            SELECT 'sistani', language_code, site_id, title, letter, position,
                   declared_count, url, NULL, fetch_status, fetched_at
            FROM topic_v1
            """
        )
        conn.execute(
            """
            INSERT INTO question (
              authority_code, language_code, site_id, question_text, answer_text,
              question_html, answer_html, url, content_hash, fetched_at, changed_at
            )
            SELECT 'sistani', language_code, site_id, question_text, answer_text,
                   question_html, answer_html, url, content_hash, fetched_at, changed_at
            FROM question_v1
            """
        )
        conn.execute(
            """
            INSERT INTO placement (
              authority_code, language_code, topic_site_id, question_site_id,
              page_number, page_url, anchor_url, number_label, number_value, position
            )
            SELECT 'sistani', language_code, topic_site_id, question_site_id,
                   page_number, page_url, page_url || '#' || question_site_id,
                   number_label, number_value, position
            FROM placement_v1
            """
        )
        for name in ("placement_v1", "question_v1", "topic_v1", "language_v1"):
            conn.execute("DROP TABLE %s" % name)
        conn.execute("DROP TABLE IF EXISTS source")
    conn.execute("PRAGMA foreign_keys = ON")
    log("migrated Sistani rows onto authority_code")


def init_db(path: Path, reset: bool) -> sqlite3.Connection:
    if reset and path.exists():
        path.unlink()
        for suffix in ("-wal", "-shm"):
            sidecar = Path(str(path) + suffix)
            if sidecar.exists():
                sidecar.unlink()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    conn.execute("PRAGMA synchronous = NORMAL")
    conn.execute("PRAGMA busy_timeout = 5000")
    migrate_v1_to_v2(conn)
    conn.executescript(SCHEMA_PATH.read_text())
    copy_v1_rows(conn)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.commit()
    return conn



def rebuild_fts(conn: sqlite3.Connection) -> None:
    conn.execute("DELETE FROM question_fts")
    conn.execute(
        """
        INSERT INTO question_fts (
          authority_code, language_code, question_site_id, topic_title, question_text, answer_text
        )
        SELECT
          q.authority_code,
          q.language_code,
          q.site_id,
          ifnull(group_concat(t.title, ' '), ''),
          q.question_text,
          q.answer_text
        FROM question AS q
        LEFT JOIN placement AS p
          ON p.authority_code = q.authority_code
         AND p.language_code = q.language_code
         AND p.question_site_id = q.site_id
        LEFT JOIN topic AS t
          ON t.authority_code = p.authority_code
         AND t.language_code = p.language_code
         AND t.site_id = p.topic_site_id
        GROUP BY q.authority_code, q.language_code, q.site_id
        """
    )
    conn.commit()

