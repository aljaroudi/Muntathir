#!/usr/bin/env python3
"""Shirazi istiftāʾāt from alshirazi.org into the shared fatwa database.

The catalog is not in the first HTML response. A session cookie plus
POST /estefta returns the category tree and every question id. POST
/esteftaResult returns that question's text. The public link is the
share URL the site prints on each answer.
"""

from __future__ import annotations

import gzip
import hashlib
import html
import http.client
import sqlite3
import threading
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Dict, List, Optional, Sequence, Tuple

from db import log, utc_now
from htmlutil import class_tokens, html_to_text, read_element, start_events, walk

HOST = "alshirazi.org"
ORIGIN = "https://" + HOST
AUTHORITY = "shirazi"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
LANGUAGES = {
    "AR": ("العربية", "ar", "rtl"),
    "EN": ("English", "en", "ltr"),
    "FA": ("فارسی", "fa", "rtl"),
}


def question_url(language: str, site_id: str) -> str:
    return "%s/estefta?ShareEstefta=%s&langs=%s" % (ORIGIN, site_id, language)


def catalog_url(language: str) -> str:
    return "%s/estefta?langs=%s" % (ORIGIN, language)


def before_script(source: str) -> str:
    cut = source.find("<script")
    return source[:cut] if cut > 0 else source


def parse_catalog(source: str) -> Tuple[List[dict], List[dict]]:
    """Return categories and questions from a dataType=estefta response."""
    source = before_script(source)
    categories: List[dict] = []
    questions: List[dict] = []
    stack: List[str] = []
    pending = None
    ul_owned: List[bool] = []
    index = 0
    while index < len(source):
        left = source.find("<", index)
        if left < 0:
            break
        event = next(walk(source, left))
        if event[0] == "end" and event[1] == "ul":
            if ul_owned and ul_owned.pop() and stack:
                stack.pop()
            index = event[3]
            continue
        if event[0] != "start":
            index = event[-1] if event[-1] > left else left + 1
            continue
        tokens = class_tokens(event[2])
        if event[1] == "span" and "estefta_main_cat" in tokens:
            _, _, inner, end = read_element(source, event[4])
            site_id = event[2].get("id") or event[2].get("rel") or ""
            if site_id:
                categories.append({
                    "site_id": site_id,
                    "title": html_to_text(inner),
                    "parent_site_id": stack[-1] if stack else None,
                })
                pending = site_id
            index = end
            continue
        if event[1] == "ul":
            if pending:
                stack.append(pending)
                ul_owned.append(True)
                pending = None
            else:
                ul_owned.append(False)
            index = event[5]
            continue
        if event[1] == "a" and "esteftaItem" in tokens:
            _, _, inner, end = read_element(source, event[4])
            site_id = event[2].get("rel") or ""
            title = html_to_text(inner).lstrip("-").strip()
            if site_id:
                questions.append({
                    "site_id": site_id,
                    "title": title,
                    "topic_site_id": stack[-1] if stack else None,
                })
            pending = None
            index = end
            continue
        index = event[-1]
    return categories, questions


def parse_items(source: str) -> List[dict]:
    source = before_script(source)
    items = []
    seen = set()
    index = 0
    while index < len(source):
        left = source.find("<", index)
        if left < 0:
            break
        event = next(walk(source, left))
        if event[0] == "start" and event[1] == "a" and "esteftaItem" in class_tokens(event[2]):
            _, _, inner, end = read_element(source, event[4])
            site_id = event[2].get("rel") or ""
            if site_id and site_id not in seen:
                seen.add(site_id)
                items.append({
                    "site_id": site_id,
                    "title": html_to_text(inner).lstrip("-").strip(),
                })
            index = end
            continue
        index = event[-1] if event[0] != "start" and event[-1] > left else (event[5] if event[0] == "start" else left + 1)
    return items


def input_value(source: str, element_id: str) -> str:
    for event in start_events(before_script(source)):
        if event[1] == "input" and event[2].get("id") == element_id:
            return html.unescape(event[2].get("value", "")).strip()
    return ""


def parse_result(source: str, site_id: str, language: str) -> Optional[dict]:
    question = input_value(source, "estefta_body_questionV")
    answer = input_value(source, "estefta_body_answerV")
    if not question and not answer:
        return None
    link = input_value(source, "esteftaLinkCur_%s" % site_id) or question_url(language, site_id)
    question_html = html.escape(question)
    answer_html = html.escape(answer)
    digest = hashlib.sha256((question_html + "\0" + answer_html).encode("utf-8")).hexdigest()
    return {
        "site_id": site_id,
        "question_text": question,
        "answer_text": answer,
        "question_html": question_html,
        "answer_html": answer_html,
        "url": link,
        "content_hash": digest,
    }


def daily_title(page: str, language: str) -> str:
    fallback = {"AR": "الاستفتاءات اليومية", "EN": "Daily Q&A", "FA": "استفتائات روزانه"}.get(language, "Daily")
    index = 0
    while index < len(page):
        left = page.find("<", index)
        if left < 0:
            break
        event = next(walk(page, left))
        if event[0] == "start" and event[1] == "button" and event[2].get("rel") == "esteftaVip":
            _, _, inner, _ = read_element(page, event[4])
            title = html_to_text(inner)
            return title or fallback
        index = event[-1] if event[-1] > left else left + 1
    return fallback


class Client:
    def __init__(self, delay: float):
        self.delay = delay
        self.cookies: Dict[str, str] = {}
        self.token = ""
        self._lock = threading.Lock()
        self._pace = threading.Lock()
        self._next = 0.0
        self._local = threading.local()

    def close(self) -> None:
        conn = getattr(self._local, "conn", None)
        if conn is not None:
            conn.close()
            self._local.conn = None

    def _connection(self) -> http.client.HTTPSConnection:
        conn = getattr(self._local, "conn", None)
        if conn is None:
            conn = http.client.HTTPSConnection(HOST, timeout=45)
            self._local.conn = conn
        return conn

    def _wait(self) -> None:
        with self._pace:
            now = time.monotonic()
            if self._next > now:
                time.sleep(self._next - now)
            self._next = time.monotonic() + self.delay

    def _store_cookies(self, response: http.client.HTTPResponse) -> None:
        updates = {}
        for key, value in response.getheaders():
            if key.lower() != "set-cookie":
                continue
            pair = value.split(";", 1)[0]
            name, sep, val = pair.partition("=")
            if sep:
                updates[name.strip()] = val.strip()
        if updates:
            with self._lock:
                self.cookies.update(updates)

    def _cookie_header(self) -> str:
        with self._lock:
            return "; ".join("%s=%s" % item for item in self.cookies.items())

    def request(self, method: str, path: str, body: Optional[bytes] = None, headers: Optional[dict] = None) -> Tuple[int, str]:
        current = path
        for _ in range(6):
            self._wait()
            conn = self._connection()
            sent = dict(headers or {})
            sent.setdefault("User-Agent", UA)
            sent.setdefault("Accept", "text/html, */*; q=0.01")
            sent.setdefault("Accept-Encoding", "gzip")
            cookie = self._cookie_header()
            if cookie:
                sent["Cookie"] = cookie
            try:
                conn.request(method, current, body=body, headers=sent)
                response = conn.getresponse()
                raw = response.read()
            except Exception:
                self.close()
                raise
            self._store_cookies(response)
            if (response.getheader("Connection") or "").lower() == "close":
                self.close()
            if (response.getheader("Content-Encoding") or "").lower() == "gzip":
                raw = gzip.decompress(raw)
            if response.status in (301, 302, 303, 307, 308) and method == "GET":
                location = response.getheader("Location")
                if not location:
                    break
                target = urllib.parse.urljoin(ORIGIN + current, location)
                parts = urllib.parse.urlparse(target)
                if parts.netloc not in (HOST, ""):
                    raise RuntimeError("redirect left the site: %s" % target)
                current = parts.path or "/"
                if parts.query:
                    current += "?" + parts.query
                method = "GET"
                body = None
                continue
            return response.status, raw.decode("utf-8", "replace")
        raise RuntimeError("too many redirects for %s" % path)

    def open_session(self, language: str) -> str:
        status, page = self.request("GET", "/estefta?langs=%s" % language)
        if status != 200:
            raise RuntimeError("session HTTP %s" % status)
        token = ""
        for event in start_events(page):
            if event[1] == "meta" and event[2].get("name") == "csrf-token":
                token = event[2].get("content", "")
                break
        if not token:
            raise RuntimeError("no csrf token")
        with self._lock:
            self.token = token
        return page

    def post(self, path: str, fields: dict, language: str) -> str:
        last = "unknown error"
        for attempt in range(4):
            with self._lock:
                token = self.token
            payload = dict(fields)
            payload["_token"] = token
            body = urllib.parse.urlencode(payload).encode("utf-8")
            try:
                status, text = self.request("POST", path, body, {
                    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                    "X-Requested-With": "XMLHttpRequest",
                    "X-CSRF-TOKEN": token,
                    "Referer": catalog_url(language),
                    "Origin": ORIGIN,
                    "Content-Length": str(len(body)),
                })
            except Exception as exc:
                last = str(exc)
                time.sleep(1.2 * (2 ** attempt))
                continue
            if status == 419 or "Page Expired" in text:
                last = "HTTP 419"
                self.open_session(language)
                continue
            if status in (429, 500, 502, 503, 504):
                last = "HTTP %s" % status
                time.sleep(1.2 * (2 ** attempt))
                continue
            if status != 200:
                raise RuntimeError("HTTP %s %s" % (status, path))
            return text
        raise RuntimeError("%s: %s" % (path, last))


def save_language(
    conn: sqlite3.Connection,
    language: str,
    native_name: str,
    hreflang: str,
    direction: str,
    categories: Sequence[dict],
    questions: Sequence[dict],
    daily: Sequence[dict],
    daily_name: str,
    bodies: Dict[str, dict],
    failed: Sequence[str],
) -> dict:
    now = utc_now()
    page = catalog_url(language)
    by_topic: Dict[str, List[dict]] = {}
    for position, question in enumerate(questions, start=1):
        topic_id = question["topic_site_id"] or "root"
        question = dict(question)
        question["position"] = position
        by_topic.setdefault(topic_id, []).append(question)
    daily_ids = [item["site_id"] for item in daily]
    topic_rows = [{
        "site_id": "daily",
        "title": daily_name,
        "parent_site_id": None,
        "position": 1,
        "declared_count": len(daily_ids),
    }]
    for position, category in enumerate(categories, start=2):
        direct = by_topic.get(category["site_id"], [])
        topic_rows.append({
            "site_id": category["site_id"],
            "title": category["title"],
            "parent_site_id": category["parent_site_id"],
            "position": position,
            "declared_count": len(direct),
        })
    if by_topic.get("root"):
        topic_rows.append({
            "site_id": "root",
            "title": native_name,
            "parent_site_id": None,
            "position": len(topic_rows) + 1,
            "declared_count": len(by_topic["root"]),
        })
    catalog_ids = {question["site_id"] for question in questions} | set(daily_ids)
    inserted = 0
    updated = 0
    conn.execute("PRAGMA foreign_keys = ON")
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
            (AUTHORITY, language, native_name, hreflang, direction, len(catalog_ids), now),
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
                    topic["declared_count"], page, topic["parent_site_id"], now,
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
        grouped: Dict[str, List[str]] = {}
        for question in questions:
            if question["site_id"] in bodies:
                grouped.setdefault(question["topic_site_id"] or "root", []).append(question["site_id"])
        for topic_id, ids in grouped.items():
            for position, site_id in enumerate(ids, start=1):
                conn.execute(
                    """
                    INSERT INTO placement (
                      authority_code, language_code, topic_site_id, question_site_id,
                      page_number, page_url, anchor_url, number_label, number_value, position
                    ) VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?)
                    """,
                    (
                        AUTHORITY, language, topic_id, site_id, page,
                        bodies[site_id]["url"], str(position), position, position,
                    ),
                )
        daily_position = 0
        for site_id in daily_ids:
            if site_id not in bodies:
                continue
            daily_position += 1
            conn.execute(
                """
                INSERT INTO placement (
                  authority_code, language_code, topic_site_id, question_site_id,
                  page_number, page_url, anchor_url, number_label, number_value, position
                ) VALUES (?, ?, 'daily', ?, 1, ?, ?, ?, ?, ?)
                """,
                (
                    AUTHORITY, language, site_id, page, bodies[site_id]["url"],
                    str(daily_position), daily_position, daily_position,
                ),
            )
        keep = set(bodies) | set(failed)
        conn.execute("CREATE TEMP TABLE IF NOT EXISTS shirazi_keep (site_id TEXT PRIMARY KEY)")
        conn.execute("DELETE FROM shirazi_keep")
        conn.executemany("INSERT INTO shirazi_keep (site_id) VALUES (?)", [(site_id,) for site_id in keep])
        conn.execute(
            """
            DELETE FROM placement
            WHERE authority_code = ? AND language_code = ?
              AND question_site_id NOT IN (SELECT site_id FROM shirazi_keep)
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
        conn.execute("CREATE TEMP TABLE IF NOT EXISTS shirazi_topic (site_id TEXT PRIMARY KEY)")
        conn.execute("DELETE FROM shirazi_topic")
        conn.executemany(
            "INSERT INTO shirazi_topic (site_id) VALUES (?)",
            [(topic["site_id"],) for topic in topic_rows],
        )
        conn.execute(
            """
            DELETE FROM topic
            WHERE authority_code = ? AND language_code = ?
              AND site_id NOT IN (SELECT site_id FROM shirazi_topic)
              AND NOT EXISTS (
                SELECT 1 FROM placement AS p
                WHERE p.authority_code = topic.authority_code
                  AND p.language_code = topic.language_code
                  AND p.topic_site_id = topic.site_id
              )
            """,
            (AUTHORITY, language),
        )
    row = conn.execute(
        "SELECT COUNT(*) AS n FROM question WHERE authority_code = ? AND language_code = ?",
        (AUTHORITY, language),
    ).fetchone()
    return {
        "authority": AUTHORITY,
        "language": language,
        "ok": not failed,
        "topics": len(topic_rows),
        "declared": len(catalog_ids),
        "questions": int(row["n"]),
        "inserted": inserted,
        "updated": updated,
        "deleted": deleted,
        "errors": len(failed),
        "partials": 0,
        "warnings": [],
        "warning_count": 0,
    }


def fetch_one(client: Client, language: str, site_id: str) -> Optional[dict]:
    text = client.post("/esteftaResult", {
        "esteftaItemId": site_id,
        "ShareEsteftaItemCurRoot": "0",
        "_Type": "v",
        "langs": language,
    }, language)
    return parse_result(text, site_id, language)


def crawl_language(conn: sqlite3.Connection, client: Client, language: str, concurrency: int, limit: int) -> dict:
    meta = LANGUAGES.get(language, (language, "", "ltr"))
    page = client.open_session(language)
    catalog = client.post("/estefta", {
        "dataType": "estefta",
        "ShareEstefra": "",
        "search": "",
        "ShareTreatise": "",
        "langs": language,
    }, language)
    daily_html = client.post("/estefta", {
        "dataType": "esteftaVip",
        "ShareEstefra": "",
        "search": "",
        "ShareTreatise": "",
        "langs": language,
    }, language)
    categories, questions = parse_catalog(catalog)
    daily = parse_items(daily_html)
    if not questions:
        raise RuntimeError("%s catalog parsed 0 questions" % language)
    wanted = []
    seen = set()
    for question in questions:
        if question["site_id"] not in seen:
            seen.add(question["site_id"])
            wanted.append(question["site_id"])
    for item in daily:
        if item["site_id"] not in seen:
            seen.add(item["site_id"])
            wanted.append(item["site_id"])
    if limit:
        wanted = wanted[:limit]
    log("shirazi %s: %s categories, %s questions" % (language, len(categories), len(wanted)))
    bodies: Dict[str, dict] = {}
    failed: List[str] = []
    done = 0
    workers = max(1, min(concurrency, 4))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(fetch_one, client, language, site_id): site_id for site_id in wanted}
        for future in as_completed(futures):
            site_id = futures[future]
            done += 1
            try:
                parsed = future.result()
            except Exception as exc:
                parsed = None
                log("shirazi %s %s: %s" % (language, site_id, exc))
            if parsed is None:
                failed.append(site_id)
                conn.execute(
                    """
                    INSERT INTO fetch_error (url, authority_code, language_code, kind, error, attempted_at)
                    VALUES (?, ?, ?, 'question', ?, ?)
                    ON CONFLICT (url) DO UPDATE SET
                      error = excluded.error,
                      attempted_at = excluded.attempted_at
                    """,
                    (question_url(language, site_id), AUTHORITY, language, "empty or failed", utc_now()),
                )
                conn.commit()
            else:
                bodies[site_id] = parsed
                conn.execute("DELETE FROM fetch_error WHERE url = ?", (question_url(language, site_id),))
            if done % 25 == 0 or done == len(wanted):
                log("shirazi %s %s/%s" % (language, done, len(wanted)))
    if limit:
        questions = [question for question in questions if question["site_id"] in set(wanted)]
        daily = [item for item in daily if item["site_id"] in set(wanted)]
    return save_language(
        conn, language, meta[0], meta[1], meta[2],
        categories, questions, daily, daily_title(page, language), bodies, failed,
    )


def crawl(
    conn: sqlite3.Connection,
    languages: Optional[Sequence[str]] = None,
    concurrency: int = 4,
    delay: float = 0.05,
    limit: int = 0,
) -> List[dict]:
    client = Client(delay)
    chosen = list(languages or LANGUAGES)
    reports = []
    try:
        for language in chosen:
            reports.append(crawl_language(conn, client, language, concurrency, limit))
    finally:
        client.close()
    return reports


def self_test() -> None:
    catalog = """
    <ul class="my-nav">
      <li>
        <a rel="416"><span id="416" class="estefta_main_cat">العبادات</span></a>
        <ul>
          <li>
            <a rel="564"><span id="564" class="estefta_main_cat">الربا</span></a>
            <ul>
              <a href="#" rel="24663" class="esteftaItem"><b>-</b>معاملة واقعها الربا</a>
            </ul>
          </li>
        </ul>
      </li>
    </ul>
    """
    categories, questions = parse_catalog(catalog)
    assert [item["site_id"] for item in categories] == ["416", "564"], categories
    assert categories[1]["parent_site_id"] == "416"
    assert questions[0]["site_id"] == "24663"
    assert questions[0]["topic_site_id"] == "564"
    assert questions[0]["title"] == "معاملة واقعها الربا"
    result = """
    <input id="estefta_body_questionV" value="هل يجوز؟">
    <input id="estefta_body_answerV" value="لا يجوز.">
    <input id="esteftaLinkCur_24663" value="https://alshirazi.org/estefta?ShareEstefta=24663&amp;langs=AR">
    """
    parsed = parse_result(result, "24663", "AR")
    assert parsed is not None
    assert parsed["question_text"] == "هل يجوز؟"
    assert parsed["answer_text"] == "لا يجوز."
    assert "langs=AR" in parsed["url"] and "&amp;" not in parsed["url"]
    print("shirazi self-test ok")


if __name__ == "__main__":
    self_test()
