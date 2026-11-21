"""Shared HTTP client and SQLite writer for the newer authority scrapers.

najafi.py, fayadh.py, alrohani.py and rohani.py each walk a site into

    topics    [{"site_id", "title", "parent_site_id", "url", "declared_count"}]
    listings  {topic_site_id: [item, ...]}
    item      {"site_id", "question_text", "answer_text", "question_html",
               "answer_html", "url", "content_hash", "page", "page_url"}

and hand them to save(), which upserts language/topic/question/placement the
same way hakeem.py does. hakeem.py keeps its own copy; it predates this file.
"""

from __future__ import annotations

import hashlib
import re
import sqlite3
import threading
import time
import urllib.request
from typing import Dict, List, Optional, Sequence, Tuple

from db import utc_now
from htmlutil import clean_html, html_to_text

BROWSER_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)


class Client:
    """GET with a global request pace, retries and a configurable charset."""

    def __init__(self, delay: float, encoding: str = "utf-8", headers: Optional[dict] = None):
        self.delay = delay
        self.encoding = encoding
        self.headers = {"User-Agent": BROWSER_UA, "Accept": "text/html,application/xhtml+xml"}
        self.headers.update(headers or {})
        self._pace = threading.Lock()
        self._next = 0.0

    def fetch(self, url: str) -> Tuple[str, dict]:
        last = "unknown error"
        for attempt in range(4):
            with self._pace:
                now = time.monotonic()
                if self._next > now:
                    time.sleep(self._next - now)
                self._next = time.monotonic() + self.delay
            request = urllib.request.Request(url, headers=self.headers)
            try:
                with urllib.request.urlopen(request, timeout=45) as response:
                    body = response.read().decode(self.encoding, "replace")
                    return body, {key.lower(): value for key, value in response.headers.items()}
            except Exception as exc:
                last = str(exc)
                time.sleep(1.2 * (2 ** attempt))
        raise RuntimeError("%s: %s" % (url, last))

    def get(self, url: str) -> str:
        return self.fetch(url)[0]


LABEL = re.compile(
    r"^(\s*(?:<(?:p|span|strong|b|div)\b[^>]*>\s*)*)"
    r"(?:السؤال|سؤال|الجواب|جواب|استفتاء|پرسش|پاسخ|س|ج)(?:\s|&nbsp;|&#160;)*[:：](?:\s|&nbsp;|&#160;)*"
)


def strip_label(fragment: str) -> str:
    """Drop a leading "السؤال :" / "جواب :" style label, keeping any opening tags."""
    for _ in range(3):  # some bodies repeat it ("جواب: الجواب: ...")
        stripped = LABEL.sub(r"\1", fragment, count=1)
        if stripped == fragment:
            break
        fragment = stripped
    return fragment


def make_item(site_id: str, question_html: str, answer_html: str, url: str, page: int = 1, page_url: str = "") -> dict:
    q_html = clean_html(strip_label(question_html))
    a_html = clean_html(strip_label(answer_html))
    return {
        "site_id": str(site_id),
        "question_text": html_to_text(q_html).strip(),
        "answer_text": html_to_text(a_html).strip(),
        "question_html": q_html,
        "answer_html": a_html,
        "url": url,
        "page": page,
        "page_url": page_url or url,
        "content_hash": hashlib.sha256((q_html + "\0" + a_html).encode("utf-8")).hexdigest(),
    }


def empty_report(authority: str, language: str, warning: str) -> dict:
    return {
        "authority": authority, "language": language, "ok": True, "topics": 0,
        "declared": 0, "questions": 0, "inserted": 0, "updated": 0, "deleted": 0,
        "errors": 0, "partials": 0, "warnings": [warning], "warning_count": 1,
    }


def failed_report(authority: str, language: str, error: str) -> dict:
    return {
        "authority": authority, "language": language, "ok": False, "topics": 0,
        "declared": 0, "questions": 0, "inserted": 0, "updated": 0, "deleted": 0,
        "errors": 1, "partials": 0, "warnings": [], "warning_count": 0, "error": error,
    }


def save(
    conn: sqlite3.Connection,
    authority: str,
    language: str,
    meta: Sequence[str],
    topics: Sequence[dict],
    listings: Dict[str, List[dict]],
    failed: Sequence[str] = (),
) -> dict:
    """Upsert one language. meta is (native_name, hreflang, direction)."""
    now = utc_now()
    by_id = {topic["site_id"]: topic for topic in topics}

    def depth(topic_id: str) -> int:
        level = 0
        node = by_id.get(topic_id)
        while node and node["parent_site_id"] and level < 50:
            level += 1
            node = by_id.get(node["parent_site_id"])
        return level

    # A question listed by several topics (or by a parent and its children)
    # is kept once, in the deepest topic that lists it.
    owner: Dict[str, str] = {}
    bodies: Dict[str, dict] = {}
    for topic_id, items in listings.items():
        for item in items:
            bodies.setdefault(item["site_id"], item)
            current = owner.get(item["site_id"])
            if current is None or depth(topic_id) > depth(current):
                owner[item["site_id"]] = topic_id
    listings = {
        topic_id: [item for item in items if owner[item["site_id"]] == topic_id]
        for topic_id, items in listings.items()
    }
    kept = [topic for topic in topics if listings.get(topic["site_id"]) or topic["site_id"] in failed]
    keep_ids = set()
    for topic in kept:  # keep ancestors so the tree stays connected
        node = topic
        while node and node["site_id"] not in keep_ids:
            keep_ids.add(node["site_id"])
            node = by_id.get(node["parent_site_id"] or "")
    topic_rows = [topic for topic in topics if topic["site_id"] in keep_ids]
    inserted = updated = 0
    with conn:
        conn.execute("PRAGMA defer_foreign_keys = ON")
        conn.execute(
            """
            INSERT INTO language (
              authority_code, code, native_name, hreflang, direction,
              declared_question_count, indexed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (authority_code, code) DO UPDATE SET
              native_name = excluded.native_name,
              hreflang = excluded.hreflang,
              direction = excluded.direction,
              declared_question_count = excluded.declared_question_count,
              indexed_at = excluded.indexed_at
            """,
            (authority, language, meta[0], meta[1], meta[2], len(bodies), now),
        )
        conn.execute("DELETE FROM placement WHERE authority_code = ? AND language_code = ?", (authority, language))
        if not failed:
            conn.execute("DELETE FROM topic WHERE authority_code = ? AND language_code = ?", (authority, language))
        for position, topic in enumerate(topic_rows, start=1):
            parent = topic["parent_site_id"]
            conn.execute(
                """
                INSERT INTO topic (
                  authority_code, language_code, site_id, title, letter, position,
                  declared_count, url, parent_site_id, fetch_status, fetched_at
                ) VALUES (?, ?, ?, ?, '', ?, ?, ?, ?, ?, ?)
                ON CONFLICT (authority_code, language_code, site_id) DO UPDATE SET
                  title = excluded.title,
                  position = excluded.position,
                  declared_count = excluded.declared_count,
                  url = excluded.url,
                  parent_site_id = excluded.parent_site_id,
                  fetch_status = excluded.fetch_status,
                  fetched_at = excluded.fetched_at
                """,
                (
                    authority, language, topic["site_id"], topic["title"], position,
                    len(listings.get(topic["site_id"], [])), topic["url"],
                    parent if parent in keep_ids else None,
                    "error" if topic["site_id"] in failed else "ok", now,
                ),
            )
        for site_id, body in bodies.items():
            existing = conn.execute(
                "SELECT content_hash FROM question WHERE authority_code = ? AND language_code = ? AND site_id = ?",
                (authority, language, site_id),
            ).fetchone()
            if existing is None:
                inserted += 1
            elif existing["content_hash"] != body["content_hash"]:
                updated += 1
            conn.execute(
                """
                INSERT INTO question (
                  authority_code, language_code, site_id, question_text, answer_text,
                  question_html, answer_html, url, content_hash, fetched_at, changed_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (authority_code, language_code, site_id) DO UPDATE SET
                  question_text = excluded.question_text,
                  answer_text = excluded.answer_text,
                  question_html = excluded.question_html,
                  answer_html = excluded.answer_html,
                  url = excluded.url,
                  content_hash = excluded.content_hash,
                  fetched_at = excluded.fetched_at,
                  changed_at = CASE
                    WHEN question.content_hash = excluded.content_hash THEN question.changed_at
                    ELSE excluded.changed_at
                  END
                """,
                (
                    authority, language, site_id, body["question_text"], body["answer_text"],
                    body["question_html"], body["answer_html"], body["url"], body["content_hash"],
                    now, now,
                ),
            )
        for topic_id, items in listings.items():
            if topic_id not in keep_ids:
                continue
            seen = set()
            position = 0
            for item in items:
                if item["site_id"] in seen:
                    continue
                seen.add(item["site_id"])
                position += 1
                conn.execute(
                    """
                    INSERT INTO placement (
                      authority_code, language_code, topic_site_id, question_site_id,
                      page_number, page_url, anchor_url, number_label, number_value, position
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        authority, language, topic_id, item["site_id"], item["page"],
                        item["page_url"], item["url"], str(position), position, position,
                    ),
                )
        deleted = 0
        if not failed:
            deleted = conn.execute(
                """
                DELETE FROM question
                WHERE authority_code = ? AND language_code = ?
                  AND NOT EXISTS (
                    SELECT 1 FROM placement AS p
                    WHERE p.authority_code = question.authority_code
                      AND p.language_code = question.language_code
                      AND p.question_site_id = question.site_id
                  )
                """,
                (authority, language),
            ).rowcount
    row = conn.execute(
        "SELECT COUNT(*) AS n FROM question WHERE authority_code = ? AND language_code = ?",
        (authority, language),
    ).fetchone()
    return {
        "authority": authority, "language": language, "ok": not failed,
        "topics": len(topic_rows), "declared": sum(t.get("declared_count", 0) for t in topics),
        "questions": int(row["n"]), "inserted": inserted, "updated": updated,
        "deleted": deleted, "errors": len(failed), "partials": 0,
        "warnings": [], "warning_count": 0,
    }
