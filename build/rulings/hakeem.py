#!/usr/bin/env python3
"""Sayyid Muhammad Saeed al-Hakeem Q&A from alhakeem.com.

There is no JSON API; pages are server-rendered:

    GET https://www.alhakeem.com/{lang}/questions/{category}/{page}

Each page holds up to 20 full Q&A items, the bootpag page count, and the
whole category tree (nested <ul> with question counts in .badge).

Arabic and English have their own trees (different id ranges). The Persian
tree is a stub with zero counts, but Persian Q&A is served under the Arabic
category ids, so Persian walks the Arabic tree. Urdu has no Q&A today.
"""

from __future__ import annotations

import hashlib
import re
import sqlite3
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Dict, List, Optional, Sequence, Tuple

from db import log, utc_now
from htmlutil import clean_html, html_to_text

SITE = "https://www.alhakeem.com"
AUTHORITY = "hakeem"
UA = "Mozilla/5.0 (compatible; MuntathirFatwaMirror/1.0; +https://www.alhakeem.com/)"
LANGUAGES = {
    "ar": ("العربية", "ar", "rtl"),
    "en": ("English", "en", "ltr"),
    "fa": ("فارسی", "fa", "rtl"),
    "ur": ("اردو", "ur", "rtl"),
}
LABEL = re.compile(
    r"^\s*(?:<span>\s*)?(?:السؤال|السوال|سؤال|سوال|پرسش|الجواب|جواب|پاسخ|Question|Answer|Q|A)\s*[:：]\s*(?:</span>\s*)?",
    re.I,
)
TREE_TOKEN = re.compile(
    r"<ul\b|</ul>|<a href=['\"]%s/[a-z]+/questions/(\d+)['\"][^>]*>(.*?)</a>\s*</span>\s*<span class=['\"]badge['\"]>(\d*)</span>"
    % re.escape(SITE),
    re.S,
)
TOTAL = re.compile(r"total:\s*'(\d+)'")
ITEM = re.compile(
    r'<div class="box_header[^"]*">(.*?)</div>\s*'
    r'<div class="question_content">(.*?)</div>\s*'
    r'<div class="question_answer">(.*?)</div>'
    r'.*?question/print/(\d+)',
    re.S,
)


def question_url(language: str, site_id: str) -> str:
    return "%s/%s/question/%s" % (SITE, language, site_id)


def category_url(language: str, site_id: str, page: int = 1) -> str:
    base = "%s/%s/questions/%s" % (SITE, language, site_id)
    return base if page == 1 else "%s/%s" % (base, page)


def strip_label(fragment: str) -> str:
    return LABEL.sub("", fragment.strip(), count=1)


class Client:
    def __init__(self, delay: float):
        self.delay = delay
        self._pace = threading.Lock()
        self._next = 0.0

    def get(self, url: str) -> str:
        last = "unknown error"
        for attempt in range(4):
            with self._pace:
                now = time.monotonic()
                if self._next > now:
                    time.sleep(self._next - now)
                self._next = time.monotonic() + self.delay
            request = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "text/html"})
            try:
                with urllib.request.urlopen(request, timeout=45) as response:
                    return response.read().decode("utf-8", "replace")
            except Exception as exc:
                last = str(exc)
                time.sleep(1.2 * (2 ** attempt))
        raise RuntimeError("%s: %s" % (url, last))


def parse_tree(source: str) -> List[dict]:
    start = source.find('class="easy-tree"')
    if start < 0:
        return []
    stack: List[Optional[str]] = []
    last: Optional[str] = None
    nodes: List[dict] = []
    seen = set()
    for match in TREE_TOKEN.finditer(source, start):
        token = match.group(0)
        if token.startswith("<ul"):
            stack.append(last)
            continue
        if token == "</ul>":
            if not stack:
                break
            stack.pop()
            if not stack:
                break
            continue
        site_id = match.group(1)
        last = site_id
        if site_id in seen:
            continue
        seen.add(site_id)
        nodes.append({
            "site_id": site_id,
            "title": html_to_text(match.group(2)).strip() or site_id,
            "parent_site_id": stack[-1] if stack else None,
            "position": len(nodes) + 1,
            "declared_count": int(match.group(3) or 0),
        })
    return nodes


def parse_page(source: str, language: str) -> Tuple[int, List[dict]]:
    total = TOTAL.search(source)
    items = []
    for match in ITEM.finditer(source):
        title, raw_q, raw_a, site_id = match.groups()
        q_html = clean_html(strip_label(raw_q))
        a_html = clean_html(strip_label(raw_a))
        question = html_to_text(q_html).strip()
        answer = html_to_text(a_html).strip()
        items.append({
            "site_id": site_id,
            "title": html_to_text(title).strip(),
            "question_text": question,
            "answer_text": answer,
            "question_html": q_html,
            "answer_html": a_html,
            "url": question_url(language, site_id),
            "content_hash": hashlib.sha256((q_html + "\0" + a_html).encode("utf-8")).hexdigest(),
        })
    return (int(total.group(1)) if total else 1) or (1 if items else 0), items


def empty_report(language: str, warning: str) -> dict:
    return {
        "authority": AUTHORITY, "language": language, "ok": True, "topics": 0,
        "declared": 0, "questions": 0, "inserted": 0, "updated": 0, "deleted": 0,
        "errors": 0, "partials": 0, "warnings": [warning], "warning_count": 1,
    }


def save(
    conn: sqlite3.Connection,
    language: str,
    topics: Sequence[dict],
    listings: Dict[str, List[dict]],
    failed: Sequence[str],
) -> dict:
    now = utc_now()
    meta = LANGUAGES[language]
    by_id = {topic["site_id"]: topic for topic in topics}

    def depth(topic_id: str) -> int:
        level = 0
        node = by_id.get(topic_id)
        while node and node["parent_site_id"] and level < 50:
            level += 1
            node = by_id.get(node["parent_site_id"])
        return level

    # Parent pages also list every child's questions; keep each question only
    # in the deepest category that lists it.
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
    kept_topics = [topic for topic in topics if listings.get(topic["site_id"]) or topic["site_id"] in failed]
    # Keep ancestors of non-empty topics so the tree stays connected.
    keep_ids = set()
    for topic in kept_topics:
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
            (AUTHORITY, language, meta[0], meta[1], meta[2], len(bodies), now),
        )
        conn.execute(
            "DELETE FROM placement WHERE authority_code = ? AND language_code = ?",
            (AUTHORITY, language),
        )
        if not failed:
            conn.execute(
                "DELETE FROM topic WHERE authority_code = ? AND language_code = ?",
                (AUTHORITY, language),
            )
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
                    AUTHORITY, language, topic["site_id"], topic["title"], position,
                    len(listings.get(topic["site_id"], [])),
                    category_url(language, topic["site_id"]),
                    parent if parent in keep_ids else None,
                    "error" if topic["site_id"] in failed else "ok", now,
                ),
            )
        for site_id, body in bodies.items():
            existing = conn.execute(
                "SELECT content_hash FROM question WHERE authority_code = ? AND language_code = ? AND site_id = ?",
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
        for topic_id, items in listings.items():
            if topic_id not in keep_ids:
                continue
            seen = set()
            position = 0
            for index, item in enumerate(items):
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
                        AUTHORITY, language, topic_id, item["site_id"], item["page"],
                        category_url(language, topic_id, item["page"]), item["url"],
                        str(position), position, position,
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
                (AUTHORITY, language),
            ).rowcount
    row = conn.execute(
        "SELECT COUNT(*) AS n FROM question WHERE authority_code = ? AND language_code = ?",
        (AUTHORITY, language),
    ).fetchone()
    return {
        "authority": AUTHORITY, "language": language, "ok": not failed,
        "topics": len(topic_rows), "declared": sum(t["declared_count"] for t in topics),
        "questions": int(row["n"]), "inserted": inserted, "updated": updated,
        "deleted": deleted, "errors": len(failed), "partials": 0,
        "warnings": [], "warning_count": 0,
    }


def load_tree(client: Client, language: str) -> List[dict]:
    topics = parse_tree(client.get(category_url(language, "1")))
    if language != "ar" and not any(topic["declared_count"] for topic in topics):
        # Persian tree is a zero-count stub; its Q&A lives under Arabic ids.
        topics = parse_tree(client.get(category_url("ar", "1")))
    return topics


def crawl_language(conn: sqlite3.Connection, client: Client, language: str, concurrency: int, limit: int) -> dict:
    topics = load_tree(client, language)
    if not topics:
        log("hakeem %s: no category tree" % language)
        return empty_report(language, "%s has no question categories" % language)
    if limit:
        topics = topics[:limit]
    log("hakeem %s: %s categories" % (language, len(topics)))
    listings: Dict[str, List[dict]] = {}
    failed: List[str] = []
    lock = threading.Lock()

    def fetch(topic_id: str) -> List[dict]:
        items: List[dict] = []
        page = 1
        while True:
            total, found = parse_page(client.get(category_url(language, topic_id, page)), language)
            for item in found:
                item["page"] = page
            items.extend(found)
            if page >= total or not found:
                return items
            page += 1

    done = 0
    with ThreadPoolExecutor(max_workers=max(1, concurrency)) as pool:
        futures = {pool.submit(fetch, topic["site_id"]): topic["site_id"] for topic in topics}
        for future in as_completed(futures):
            topic_id = futures[future]
            done += 1
            try:
                items = future.result()
                with lock:
                    listings[topic_id] = items
            except Exception as exc:
                failed.append(topic_id)
                log("hakeem %s topic %s: %s" % (language, topic_id, exc))
            if done % 25 == 0 or done == len(topics):
                log("hakeem %s %s/%s" % (language, done, len(topics)))
    if not any(listings.values()) and not failed:
        return empty_report(language, "%s has no published questions" % language)
    return save(conn, language, topics, listings, failed)


def crawl(
    conn: sqlite3.Connection,
    languages: Optional[Sequence[str]] = None,
    concurrency: int = 4,
    delay: float = 0.05,
    limit: int = 0,
) -> List[dict]:
    client = Client(delay)
    return [crawl_language(conn, client, language, concurrency, limit) for language in list(languages or LANGUAGES)]


def self_test() -> None:
    page = """
    <div class="easy-tree"><ul>
      <li class="active"><span><a href="https://www.alhakeem.com/ar/questions/1" role="button">التقليد</a></span> <span class="badge">70</span><ul>
        <li class=''><span><a href='https://www.alhakeem.com/ar/questions/2'>تقليد الأعلم</a></span> <span class='badge'>8</span></li>
      </ul></li>
      <li class=''><span><a href='https://www.alhakeem.com/ar/questions/5'>الطهارة</a></span> <span class='badge'>3</span></li>
    </ul></div>
    <div class="box-rounded box-shadow">
      <div class="box_header text-center">التقليد في أصول الدين</div>
      <div class="question_content">
        <span>السؤال : </span>هل يجوز التقليد في أُصول الدين ؟
      </div>
      <div class="question_answer">
        <span>الجواب : </span>لا يجوز.<br />
<br />
والتفصيل في محله.
      </div>
      <a onClick="openprintwin('https://www.alhakeem.com/ar/question/print/59')"></a>
    </div>
    <script>$('#page-selection').bootpag({ total: '4', page: '1' })</script>
    """
    tree = parse_tree(page)
    assert [(t["site_id"], t["parent_site_id"], t["declared_count"]) for t in tree] == [
        ("1", None, 70), ("2", "1", 8), ("5", None, 3)
    ], tree
    total, items = parse_page(page, "ar")
    assert total == 4
    assert len(items) == 1
    item = items[0]
    assert item["site_id"] == "59"
    assert item["question_text"] == "هل يجوز التقليد في أُصول الدين ؟", item["question_text"]
    assert item["answer_text"].startswith("لا يجوز."), item["answer_text"]
    assert "الجواب" not in item["answer_text"]
    assert item["url"] == "https://www.alhakeem.com/ar/question/59"
    print("hakeem self-test ok")


if __name__ == "__main__":
    self_test()
