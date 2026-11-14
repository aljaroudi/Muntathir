#!/usr/bin/env python3
"""Wahid Khorasani Q&A from wahidkhorasani.com/qna.

The listing is a JSON API, not the Nuxt shell:

    GET https://api.wahidkhorasani.com/api/qna/questions?language=fa&page=1
    GET https://api.wahidkhorasani.com/api/qna/questions/{slug}
    GET https://api.wahidkhorasani.com/api/qna/categories?language=fa

Arabic and English locales exist, but the API currently returns no questions
for them. Persian is the published corpus.
"""

from __future__ import annotations

import hashlib
import html
import json
import re
import sqlite3
import threading
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Dict, List, Optional, Sequence

from db import log, utc_now
from htmlutil import clean_html, html_to_text

API = "https://api.wahidkhorasani.com"
SITE = "https://wahidkhorasani.com"
AUTHORITY = "khorasani"
UA = "Mozilla/5.0 (compatible; MuntathirFatwaMirror/1.0; +https://wahidkhorasani.com/qna)"
LANGUAGES = {
    "fa": ("فارسی", "fa", "rtl"),
    "ar": ("العربية", "ar", "rtl"),
    "en": ("English", "en", "ltr"),
}
LABEL = re.compile(
    r"^(?:سؤال|السؤال|پرسش|Question|جواب|الجواب|پاسخ|Answer)\s*[:：]\s*",
    re.I,
)


def question_url(slug: str) -> str:
    return "%s/qna/%s" % (SITE, urllib.parse.quote(slug, safe=""))


def category_url(slug: str) -> str:
    return "%s/qna/category/%s" % (SITE, urllib.parse.quote(slug, safe=""))


def strip_label(text: str) -> str:
    return LABEL.sub("", text).strip()


def answer_parts(answers: Sequence[dict]) -> tuple:
    texts = []
    html_parts = []
    for answer in answers:
        body = answer.get("body") or ""
        cleaned = clean_html(body)
        text = strip_label(html_to_text(cleaned or body))
        if text:
            texts.append(text)
        if cleaned:
            html_parts.append(cleaned)
    return "\n\n".join(texts), "<br><br>".join(html_parts)


class Client:
    def __init__(self, delay: float):
        self.delay = delay
        self._pace = threading.Lock()
        self._next = 0.0

    def get(self, path: str, params: Optional[dict] = None) -> dict:
        query = ("?" + urllib.parse.urlencode(params)) if params else ""
        url = API + path + query
        last = "unknown error"
        for attempt in range(4):
            with self._pace:
                now = time.monotonic()
                if self._next > now:
                    time.sleep(self._next - now)
                self._next = time.monotonic() + self.delay
            request = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
            try:
                with urllib.request.urlopen(request, timeout=45) as response:
                    payload = json.loads(response.read().decode("utf-8"))
            except Exception as exc:
                last = str(exc)
                time.sleep(1.2 * (2 ** attempt))
                continue
            if not payload.get("success", True):
                raise RuntimeError(payload.get("message") or "API error")
            return payload.get("data", payload)
        raise RuntimeError("%s: %s" % (url, last))


def list_questions(client: Client, language: str, limit: int) -> tuple:
    items = []
    page = 1
    meta = {"total": 0, "last_page": 1}
    while True:
        data = client.get("/api/qna/questions", {
            "language": language,
            "per_page": 100,
            "page": page,
        })
        meta = data.get("meta") or meta
        items.extend(data.get("items") or [])
        if limit and len(items) >= limit:
            return items[:limit], meta
        if page >= int(meta.get("last_page") or 1):
            break
        page += 1
    return items, meta


def parse_detail(data: dict) -> dict:
    question = strip_label(data.get("body") or data.get("title") or "")
    answer_text, answer_html = answer_parts(data.get("answers") or [])
    digest = hashlib.sha256((question + "\0" + answer_html).encode("utf-8")).hexdigest()
    category = data.get("category") or {}
    return {
        "site_id": str(data["id"]),
        "slug": data.get("slug") or "",
        "question_text": question,
        "answer_text": answer_text,
        "question_html": html.escape(question),
        "answer_html": answer_html,
        "url": question_url(data["slug"]),
        "content_hash": digest,
        "category_id": None if category.get("id") is None else str(category["id"]),
    }


def save(
    conn: sqlite3.Connection,
    language: str,
    categories: Sequence[dict],
    bodies: Dict[str, dict],
    failed: Sequence[str],
) -> dict:
    now = utc_now()
    meta = LANGUAGES[language]
    by_topic: Dict[str, List[str]] = {}
    for body in bodies.values():
        topic_id = body.get("category_id") or "uncategorized"
        by_topic.setdefault(topic_id, []).append(body["site_id"])
    known_ids = {str(category["id"]) for category in categories}
    topic_rows = []
    for position, category in enumerate(sorted(categories, key=lambda item: (item.get("sort_order") or 0, item["id"])), start=1):
        site_id = str(category["id"])
        parent = category.get("parent_id")
        topic_rows.append({
            "site_id": site_id,
            "title": category.get("name") or site_id,
            "parent_site_id": str(parent) if parent and str(parent) in known_ids else None,
            "position": position,
            "declared_count": len(by_topic.get(site_id, [])),
            "url": category_url(category.get("slug") or site_id),
        })
    if by_topic.get("uncategorized"):
        topic_rows.append({
            "site_id": "uncategorized",
            "title": "بدون دسته‌بندی",
            "parent_site_id": None,
            "position": len(topic_rows) + 1,
            "declared_count": len(by_topic["uncategorized"]),
            "url": "%s/qna" % SITE,
        })
    inserted = 0
    updated = 0
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
            (AUTHORITY, language, meta[0], meta[1], meta[2], len(bodies) + len(failed), now),
        )
        for topic in topic_rows:
            conn.execute(
                """
                INSERT INTO topic (
                  authority_code, language_code, site_id, title, letter, position,
                  declared_count, url, parent_site_id, fetch_status, fetched_at
                ) VALUES (?, ?, ?, ?, '', ?, ?, ?, ?, 'ok', ?)
                ON CONFLICT (authority_code, language_code, site_id) DO UPDATE SET
                  title = excluded.title,
                  position = excluded.position,
                  declared_count = excluded.declared_count,
                  url = excluded.url,
                  parent_site_id = excluded.parent_site_id,
                  fetch_status = 'ok',
                  fetched_at = excluded.fetched_at
                """,
                (
                    AUTHORITY, language, topic["site_id"], topic["title"], topic["position"],
                    topic["declared_count"], topic["url"], topic["parent_site_id"], now,
                ),
            )
        for site_id, body in bodies.items():
            existing = conn.execute(
                """
                SELECT content_hash FROM question
                WHERE authority_code = ? AND language_code = ? AND site_id = ?
                """,
                (AUTHORITY, language, site_id),
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
                    AUTHORITY, language, site_id, body["question_text"], body["answer_text"],
                    body["question_html"], body["answer_html"], body["url"], body["content_hash"],
                    now, now,
                ),
            )
            conn.execute(
                """
                DELETE FROM placement
                WHERE authority_code = ? AND language_code = ? AND question_site_id = ?
                """,
                (AUTHORITY, language, site_id),
            )
        for topic_id, ids in by_topic.items():
            for position, site_id in enumerate(ids, start=1):
                conn.execute(
                    """
                    INSERT INTO placement (
                      authority_code, language_code, topic_site_id, question_site_id,
                      page_number, page_url, anchor_url, number_label, number_value, position
                    ) VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?)
                    """,
                    (
                        AUTHORITY, language, topic_id, site_id,
                        next(topic["url"] for topic in topic_rows if topic["site_id"] == topic_id),
                        bodies[site_id]["url"], str(position), position, position,
                    ),
                )
        keep = set(bodies) | set(failed)
        conn.execute("CREATE TEMP TABLE IF NOT EXISTS khorasani_keep (site_id TEXT PRIMARY KEY)")
        conn.execute("DELETE FROM khorasani_keep")
        if keep:
            conn.executemany("INSERT INTO khorasani_keep (site_id) VALUES (?)", [(site_id,) for site_id in keep])
        conn.execute(
            """
            DELETE FROM placement
            WHERE authority_code = ? AND language_code = ?
              AND question_site_id NOT IN (SELECT site_id FROM khorasani_keep)
            """,
            (AUTHORITY, language),
        )
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
            (AUTHORITY, language),
        ).rowcount
    row = conn.execute(
        "SELECT COUNT(*) AS n FROM question WHERE authority_code = ? AND language_code = ?",
        (AUTHORITY, language),
    ).fetchone()
    return {
        "authority": AUTHORITY,
        "language": language,
        "ok": not failed,
        "topics": len(topic_rows),
        "declared": len(bodies) + len(failed),
        "questions": int(row["n"]),
        "inserted": inserted,
        "updated": updated,
        "deleted": deleted,
        "errors": len(failed),
        "partials": 0,
        "warnings": [],
        "warning_count": 0,
    }


def crawl_language(conn: sqlite3.Connection, client: Client, language: str, concurrency: int, limit: int) -> dict:
    listed, meta = list_questions(client, language, limit)
    total = int(meta.get("total") or 0)
    if total == 0 or not listed:
        log("khorasani %s: 0 questions" % language)
        return {
            "authority": AUTHORITY,
            "language": language,
            "ok": True,
            "topics": 0,
            "declared": 0,
            "questions": 0,
            "inserted": 0,
            "updated": 0,
            "deleted": 0,
            "errors": 0,
            "partials": 0,
            "warnings": ["%s has no published questions" % language],
            "warning_count": 1,
        }
    categories = client.get("/api/qna/categories", {"language": language})
    if not isinstance(categories, list):
        categories = []
    log("khorasani %s: %s questions, %s categories" % (language, len(listed), len(categories)))
    bodies: Dict[str, dict] = {}
    failed: List[str] = []
    done = 0

    def fetch(item: dict) -> tuple:
        detail = client.get("/api/qna/questions/" + urllib.parse.quote(item["slug"], safe=""))
        return str(item["id"]), parse_detail(detail)

    with ThreadPoolExecutor(max_workers=max(1, concurrency)) as pool:
        futures = {pool.submit(fetch, item): item for item in listed}
        for future in as_completed(futures):
            item = futures[future]
            done += 1
            try:
                site_id, parsed = future.result()
                bodies[site_id] = parsed
            except Exception as exc:
                failed.append(str(item["id"]))
                log("khorasani %s %s: %s" % (language, item.get("slug"), exc))
            if done % 25 == 0 or done == len(listed):
                log("khorasani %s %s/%s" % (language, done, len(listed)))
    return save(conn, language, categories, bodies, failed)


def crawl(
    conn: sqlite3.Connection,
    languages: Optional[Sequence[str]] = None,
    concurrency: int = 4,
    delay: float = 0.05,
    limit: int = 0,
) -> List[dict]:
    client = Client(delay)
    reports = []
    for language in list(languages or ("fa", "ar", "en")):
        reports.append(crawl_language(conn, client, language, concurrency, limit))
    return reports


def self_test() -> None:
    parsed = parse_detail({
        "id": 232,
        "slug": "sndok-ha-khang",
        "title": "صندوق هاى خانگى",
        "body": "سؤال: حكم صندوق هاى قرعه‌كشى خانگى چيست؟",
        "category": {"id": 25, "slug": "معاملات"},
        "answers": [{
            "body": "<p>جواب: <span style=\"font-size: 15pt;\">جايز نيست.</span></p>",
            "image_url": None,
        }],
    })
    assert parsed["site_id"] == "232"
    assert parsed["question_text"] == "حكم صندوق هاى قرعه‌كشى خانگى چيست؟"
    assert parsed["answer_text"] == "جايز نيست."
    assert parsed["url"] == "https://wahidkhorasani.com/qna/sndok-ha-khang"
    assert "font-size" not in parsed["answer_html"]
    print("khorasani self-test ok")


if __name__ == "__main__":
    self_test()
