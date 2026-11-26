"""Sistani istiftāʾāt. See references in the fatwa-corpus skill."""

from __future__ import annotations

import gzip
import hashlib
import http.client
import re
import sqlite3
import threading
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from typing import Iterator, List, Optional, Sequence, Tuple

from db import log, utc_now
from htmlutil import (
    absolutize,
    class_tokens,
    clean_html,
    html_to_text,
    parse_attrs,
    parse_localized_int,
    read_element,
    start_events,
    walk,
)

HOST = "www.sistani.org"
ORIGIN = "https://www.sistani.org"
AUTHORITY = "sistani"
UA = "Mozilla/5.0 (compatible; MuntathirSistaniMirror/1.0; +https://www.sistani.org/)"
TOPIC_HREF = re.compile(r"^/(?P<lang>[a-z]+)/qa/(?P<id>[0-9]+)/?$")
NEXT_WORDS = {
    "next", "suivant", "suivante", "sonraki", "sonrakı", "növbəti", "novbeti",
    "التالي", "التالی", "بعدی", "اگلا", "آگے", "»", "›", "››", ">>",
}
FALLBACK_LANGUAGES = (
    ("arabic", "العربية", "ar-sa", "rtl"),
    ("persian", "فارسی", "fa", "rtl"),
    ("urdu", "اردو", "ur", "rtl"),
    ("english", "English", "en-us", "ltr"),
    ("azari", "Azərbaycan", "az-az-cyrl", "ltr"),
    ("turkish", "Türkçe", "tr", "ltr"),
    ("french", "Français", "fr", "ltr"),
)


@dataclass
class ParsedTopic:
    site_id: str
    title: str
    letter: str
    position: int
    declared_count: Optional[int]
    url: str


@dataclass
class ParsedQuestion:
    site_id: str
    number_label: str
    number_value: int
    question_html: str
    answer_html: str
    question_text: str
    answer_text: str
    warnings: List[str] = field(default_factory=list)

    @property
    def content_hash(self) -> str:
        payload = (self.question_html + "\0" + self.answer_html).encode("utf-8")
        return hashlib.sha256(payload).hexdigest()


def parse_index(source: str, language: str) -> Tuple[List[ParsedTopic], Optional[int]]:
    tree_start = None
    for event in start_events(source):
        if event[1] == "div" and event[2].get("id") == "qa-tree":
            tree_start = event[4]
            break
    if tree_start is None:
        raise ValueError("QA index has no #qa-tree")
    _, _, inner, _ = read_element(source, tree_start)
    topics: List[ParsedTopic] = []
    letter = ""
    seen = set()
    index = 0
    while index < len(inner):
        left = inner.find("<", index)
        if left < 0:
            break
        event = next(walk(inner, left))
        if event[0] != "start":
            index = event[-1] if event[-1] > left else left + 1
            continue
        if event[1] == "div" and "letter" in class_tokens(event[2]):
            _, _, letter_html, end = read_element(inner, event[4])
            letter = html_to_text(letter_html)
            index = end
            continue
        if event[1] == "a":
            match = TOPIC_HREF.match(event[2].get("href", ""))
            if match and match.group("lang") == language:
                _, _, anchor_html, end = read_element(inner, event[4])
                site_id = match.group("id")
                if site_id not in seen:
                    seen.add(site_id)
                    topics.append(ParsedTopic(
                        site_id=site_id,
                        title=html_to_text(anchor_html),
                        letter=letter,
                        position=len(topics) + 1,
                        declared_count=parse_localized_int(event[2].get("title", "")),
                        url="%s/%s/qa/%s/" % (ORIGIN, language, site_id),
                    ))
                index = end
                continue
        index = event[-1]
    declared = None
    for event in start_events(source):
        if event[1] == "b" and "hbaz1" in class_tokens(event[2]):
            _, _, count_html, _ = read_element(source, event[4])
            declared = parse_localized_int(html_to_text(count_html))
            break
    return topics, declared


def parse_questions(source: str) -> List[ParsedQuestion]:
    questions = []
    seen = set()
    for event in start_events(source):
        if event[1] != "div" or "one-qa" not in class_tokens(event[2]):
            continue
        _, _, inner, _ = read_element(source, event[4])
        parsed = parse_one_qa(inner)
        if parsed is None or parsed.site_id in seen:
            if parsed is not None:
                parsed.warnings.append("duplicate question %s on page" % parsed.site_id)
            continue
        seen.add(parsed.site_id)
        questions.append(parsed)
    return questions


def parse_one_qa(inner: str) -> Optional[ParsedQuestion]:
    href = ""
    name = ""
    number_label = ""
    span_inner = None
    span_id = ""
    warnings: List[str] = []
    index = 0
    while index < len(inner):
        left = inner.find("<", index)
        if left < 0:
            break
        event = next(walk(inner, left))
        if event[0] != "start":
            index = event[-1] if event[-1] > left else left + 1
            continue
        if event[1] == "a" and "qa-num" in class_tokens(event[2]):
            href = event[2].get("href", "")
            name = event[2].get("name", "")
            _, _, anchor_html, end = read_element(inner, event[4])
            number_label = html_to_text(anchor_html)
            index = end
            continue
        if event[1] == "span" and event[2].get("id", "").startswith("q"):
            span_id = event[2]["id"][1:]
            _, _, span_inner, end = read_element(inner, event[4])
            index = end
            break
        index = event[-1]
    match = TOPIC_HREF.match(href)
    site_id = match.group("id") if match else (name or span_id)
    if not site_id:
        return None
    ids = [item for item in (match.group("id") if match else "", name, span_id) if item]
    if len(set(ids)) > 1:
        warnings.append("id mismatch href=%s name=%s span=%s" % (href, name, span_id))
    question_html = span_inner or ""
    answer_html = ""
    if span_inner is not None:
        answer_at = _answer_div_start(span_inner)
        if answer_at is None:
            question_html = span_inner
            warnings.append("question %s has no answer block" % site_id)
        else:
            question_html = span_inner[:answer_at]
            _, _, answer_html, _ = read_element(span_inner, answer_at)
    question_html = clean_html(question_html)
    answer_html = clean_html(answer_html)
    number_value = parse_localized_int(number_label) or 0
    return ParsedQuestion(
        site_id=site_id,
        number_label=number_label,
        number_value=number_value,
        question_html=question_html,
        answer_html=answer_html,
        question_text=html_to_text(question_html),
        answer_text=html_to_text(answer_html),
        warnings=warnings,
    )


def _answer_div_start(source: str) -> Optional[int]:
    for event in start_events(source):
        if event[1] == "div" and "b" in class_tokens(event[2]):
            return event[4]
    return None


def pagination_urls(source: str, language: str, topic_id: str) -> List[str]:
    scope = source
    for event in start_events(source):
        if event[1] == "div" and event[2].get("id") == "main-qa-content":
            _, _, scope, _ = read_element(source, event[4])
            break
    found = []
    index = 0
    base = "%s/%s/qa/%s/" % (ORIGIN, language, topic_id)
    while index < len(scope):
        left = scope.find("<", index)
        if left < 0:
            break
        event = next(walk(scope, left))
        if event[0] != "start":
            index = event[-1] if event[-1] > left else left + 1
            continue
        if event[1] != "a" or "qa-num" in class_tokens(event[2]):
            index = event[-1]
            continue
        href = absolutize(event[2].get("href", ""), base)
        _, _, anchor_html, end = read_element(scope, event[4])
        text = html_to_text(anchor_html).strip().lower()
        index = end
        if not _same_topic(href, language, topic_id):
            continue
        path = urllib.parse.urlparse(href)
        canonical = base.rstrip("/")
        if path.path.rstrip("/") == urllib.parse.urlparse(base).path.rstrip("/") and not path.query:
            continue
        if (
            re.search(r"(?:[?&](?:page|p|start)=\d+|/page/\d+/?$)", href)
            or "next" in event[2].get("rel", "")
            or text in NEXT_WORDS
            or re.fullmatch(r"\d+", text)
        ):
            if href not in found and href.rstrip("/") != canonical:
                found.append(href)
    return found


def _same_topic(url: str, language: str, topic_id: str) -> bool:
    parts = [part for part in urllib.parse.urlparse(url).path.split("/") if part]
    return len(parts) >= 3 and parts[0] == language and parts[1] == "qa" and parts[2] == topic_id


class Fetch:
    def __init__(self, status: int, url: str, text: str):
        self.status = status
        self.url = url
        self.text = text


class SiteClient:
    def __init__(self, delay: float):
        self.delay = delay
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

    def get(self, url: str) -> Fetch:
        parsed = urllib.parse.urlparse(url)
        if parsed.netloc not in ("", HOST, "sistani.org"):
            raise RuntimeError("refusing off-site URL %s" % url)
        path = parsed.path or "/"
        if parsed.query:
            path += "?" + parsed.query
        current = path
        book_request = "/book/" in parsed.path
        for _ in range(6):
            if book_request and current != path:
                raise ValueError(f"unexpected book redirect from {path} to {current}")
            self._wait()
            conn = self._connection()
            try:
                conn.request("GET", current, headers={
                    "User-Agent": UA,
                    "Accept": "text/html",
                    "Accept-Encoding": "gzip",
                    "Connection": "keep-alive",
                })
                response = conn.getresponse()
                if book_request and response.status == 200 and response.headers.get_content_type() not in ("text/html", "application/xhtml+xml"):
                    raise ValueError(f"non-HTML book response for {current}")
                body = response.read()
            except Exception:
                self.close()
                raise
            if (response.getheader("Connection") or "").lower() == "close":
                self.close()
            encoding = (response.getheader("Content-Encoding") or "").lower()
            if encoding == "gzip":
                body = gzip.decompress(body)
            if response.status in (301, 302, 303, 307, 308):
                location = response.getheader("Location")
                if not location:
                    break
                target = urllib.parse.urljoin(ORIGIN + current.split("#", 1)[0], location)
                target_parts = urllib.parse.urlparse(target)
                if target_parts.netloc not in (HOST, "sistani.org", ""):
                    raise RuntimeError("redirect left the site: %s" % target)
                current = target_parts.path or "/"
                if target_parts.query:
                    current += "?" + target_parts.query
                continue
            text = body.decode("utf-8")
            final = ORIGIN + current.split("#", 1)[0]
            return Fetch(response.status, final, text)
        raise RuntimeError("too many redirects for %s" % url)


def fetch_retry(client: SiteClient, url: str, attempts: int = 4) -> Fetch:
    last = "unknown error"
    for attempt in range(attempts):
        try:
            result = client.get(url)
        except Exception as exc:
            last = str(exc)
            client.close()
            time.sleep(1.2 * (2 ** attempt))
            continue
        if result.status in (429, 500, 502, 503, 504):
            last = "HTTP %s" % result.status
            time.sleep(1.2 * (2 ** attempt))
            continue
        if result.status == 200 and not result.text:
            last = "empty body"
            time.sleep(1.2 * (2 ** attempt))
            continue
        return result
    raise RuntimeError("%s: %s" % (url, last))


def discover_languages(client: SiteClient) -> List[Tuple[str, str, str, str]]:
    try:
        home = fetch_retry(client, ORIGIN + "/")
    except Exception as exc:
        log("homepage fetch failed (%s); using the known language list" % exc)
        return list(FALLBACK_LANGUAGES)
    if home.status != 200:
        log("homepage HTTP %s; using the known language list" % home.status)
        return list(FALLBACK_LANGUAGES)
    names = {}
    directions = {}
    for event in start_events(home.text):
        if event[1] != "a":
            continue
        href = event[2].get("href", "")
        match = re.fullmatch(r"/([a-z]+)/", href)
        if not match:
            continue
        tokens = class_tokens(event[2])
        if "rtl" not in tokens and "ltr" not in tokens:
            continue
        _, _, inner, _ = read_element(home.text, event[4])
        code = match.group(1)
        names[code] = html_to_text(inner) or code
        directions[code] = "rtl" if "rtl" in tokens else "ltr"
    hreflangs = {}
    for event in start_events(home.text):
        if event[1] != "link" or event[2].get("rel") != "alternate":
            continue
        href = event[2].get("href", "")
        match = re.fullmatch(r"/([a-z]+)/", href)
        if match:
            hreflangs[match.group(1)] = event[2].get("hreflang", "")
    if not names:
        return list(FALLBACK_LANGUAGES)
    return [
        (code, names[code], hreflangs.get(code, ""), directions[code])
        for code in names
    ]



def replace_placements(
    conn: sqlite3.Connection,
    language: str,
    topic: ParsedTopic,
    pages: Sequence[Tuple[int, str, Sequence[ParsedQuestion]]],
    status: str,
    now: str,
) -> Tuple[int, int]:
    inserted = 0
    updated = 0
    with conn:
        conn.execute(
            """
            INSERT INTO topic (
              authority_code, language_code, site_id, title, letter, position, declared_count,
              url, fetch_status, fetched_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (authority_code, language_code, site_id) DO UPDATE SET
              title = excluded.title,
              letter = excluded.letter,
              position = excluded.position,
              declared_count = excluded.declared_count,
              url = excluded.url,
              fetch_status = excluded.fetch_status,
              fetched_at = excluded.fetched_at
            """,
            (
                AUTHORITY, language, topic.site_id, topic.title, topic.letter, topic.position,
                topic.declared_count, topic.url, status, now,
            ),
        )
        conn.execute(
            """
            DELETE FROM placement
            WHERE authority_code = ? AND language_code = ? AND topic_site_id = ?
            """,
            (AUTHORITY, language, topic.site_id),
        )
        for page_number, page_url, questions in pages:
            for position, question in enumerate(questions, start=1):
                number = question.number_value or position
                existing = conn.execute(
                    "SELECT content_hash FROM question WHERE authority_code = ? AND language_code = ? AND site_id = ?",
                    (AUTHORITY, language, question.site_id),
                ).fetchone()
                if existing is None:
                    inserted += 1
                elif existing["content_hash"] != question.content_hash:
                    updated += 1
                conn.execute(
                    """
                    INSERT INTO question (
                      authority_code, language_code, site_id, question_text, answer_text,
                      question_html, answer_html, url, content_hash,
                      fetched_at, changed_at
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
                        WHEN question.content_hash = excluded.content_hash
                        THEN question.changed_at
                        ELSE excluded.changed_at
                      END
                    """,
                    (
                        AUTHORITY,
                        language,
                        question.site_id,
                        question.question_text,
                        question.answer_text,
                        question.question_html,
                        question.answer_html,
                        "%s/%s/qa/%s/" % (ORIGIN, language, question.site_id),
                        question.content_hash,
                        now,
                        now,
                    ),
                )
                conn.execute(
                    """
                    INSERT INTO placement (
                      authority_code, language_code, topic_site_id, question_site_id, page_number,
                      page_url, anchor_url, number_label, number_value, position
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        AUTHORITY, language, topic.site_id, question.site_id, page_number,
                        page_url, page_url + "#" + question.site_id,
                        question.number_label, number, position,
                    ),
                )
    return inserted, updated


def placement_count(conn: sqlite3.Connection, language: str, topic_id: str) -> int:
    row = conn.execute(
        """
        SELECT COUNT(*) AS n FROM placement
        WHERE authority_code = ? AND language_code = ? AND topic_site_id = ?
        """,
        (AUTHORITY, language, topic_id),
    ).fetchone()
    return int(row["n"])


def record_error(conn: sqlite3.Connection, url: str, language: str, kind: str, error: str) -> None:
    conn.execute(
        """
        INSERT INTO fetch_error (url, authority_code, language_code, kind, error, attempted_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT (url) DO UPDATE SET
          error = excluded.error,
          attempted_at = excluded.attempted_at
        """,
        (url, AUTHORITY, language, kind, error, utc_now()),
    )
    conn.commit()


def clear_error(conn: sqlite3.Connection, url: str) -> None:
    conn.execute("DELETE FROM fetch_error WHERE url = ?", (url,))


@dataclass
class TopicFetch:
    topic: ParsedTopic
    pages: List[Tuple[int, str, List[ParsedQuestion]]] = field(default_factory=list)
    status: str = "ok"
    error: str = ""
    warnings: List[str] = field(default_factory=list)


def fetch_topic(client: SiteClient, language: str, topic: ParsedTopic) -> TopicFetch:
    result = TopicFetch(topic=topic)
    try:
        first = fetch_retry(client, topic.url)
    except Exception as exc:
        result.status = "error"
        result.error = str(exc)
        return result
    if first.status != 200:
        result.status = "error"
        result.error = "HTTP %s" % first.status
        return result
    try:
        questions = parse_questions(first.text)
    except Exception as exc:
        result.status = "error"
        result.error = "parse error: %s" % exc
        return result
    seen = {question.site_id for question in questions}
    result.pages.append((1, topic.url, questions))
    for question in questions:
        result.warnings.extend(question.warnings)

    candidates = pagination_urls(first.text, language, topic.site_id)
    page_number = 1
    visited = {topic.url.rstrip("/")}
    while candidates and page_number < 30:
        url = candidates.pop(0)
        if url.rstrip("/") in visited:
            continue
        visited.add(url.rstrip("/"))
        try:
            fetched = fetch_retry(client, url)
        except Exception as exc:
            result.warnings.append("page %s: %s" % (url, exc))
            continue
        if fetched.status != 200 or not _same_topic(fetched.url, language, topic.site_id):
            continue
        extra = parse_questions(fetched.text)
        fresh = [question for question in extra if question.site_id not in seen]
        if not fresh:
            continue
        page_number += 1
        seen.update(question.site_id for question in fresh)
        result.pages.append((page_number, url, fresh))
        candidates.extend(pagination_urls(fetched.text, language, topic.site_id))

    got = len(seen)
    declared = topic.declared_count
    if declared is not None and got < declared:
        probe_page = 2
        while got < declared and probe_page <= 30:
            accepted = False
            for url in (
                "%s?page=%s" % (topic.url, probe_page),
                "%spage/%s/" % (topic.url, probe_page),
            ):
                if url.rstrip("/") in visited:
                    continue
                visited.add(url.rstrip("/"))
                try:
                    fetched = fetch_retry(client, url)
                except Exception:
                    continue
                if fetched.status != 200:
                    continue
                extra = parse_questions(fetched.text)
                fresh = [question for question in extra if question.site_id not in seen]
                if not fresh:
                    continue
                page_number += 1
                seen.update(question.site_id for question in fresh)
                result.pages.append((page_number, url, fresh))
                got = len(seen)
                accepted = True
                break
            if not accepted:
                break
            probe_page += 1
    got = sum(len(page[2]) for page in result.pages)
    truncated = "</html>" not in first.text.lower()
    if truncated:
        result.status = "partial"
        result.warnings.append("topic %s response was truncated" % topic.site_id)
    elif not questions and declared:
        result.status = "error"
        result.error = "no questions parsed; index says %s" % declared
    elif declared is not None and got != declared:
        # The index count is often stale. Extra-page probes already ran and
        # added nothing, so the section page is the complete published list.
        result.warnings.append(
            "topic %s %s: page has %s, index says %s" % (topic.site_id, topic.title, got, declared)
        )
    return result


def upsert_language(conn: sqlite3.Connection, language: Tuple[str, str, str, str], declared, now: str) -> None:
    code, name, hreflang, direction = language
    conn.execute(
        """
        INSERT INTO language (
          authority_code, code, native_name, hreflang, direction,
          declared_question_count, indexed_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (authority_code, code) DO UPDATE SET
          native_name = excluded.native_name,
          hreflang = excluded.hreflang,
          direction = excluded.direction,
          declared_question_count = excluded.declared_question_count,
          indexed_at = excluded.indexed_at
        """,
        (AUTHORITY, code, name, hreflang, direction, declared, now),
    )


def crawl_language(
    conn: sqlite3.Connection,
    client: SiteClient,
    language: Tuple[str, str, str, str],
    concurrency: int,
    limit: int,
) -> dict:
    code = language[0]
    index_url = "%s/%s/qa/" % (ORIGIN, code)
    now = utc_now()
    try:
        index = fetch_retry(client, index_url)
    except Exception as exc:
        record_error(conn, index_url, code, "index", str(exc))
        return {"language": code, "ok": False, "error": str(exc)}
    if index.status != 200 or 'id="qa-tree"' not in index.text:
        error = "HTTP %s, not a QA index" % index.status
        record_error(conn, index_url, code, "index", error)
        return {"language": code, "ok": False, "error": error}
    clear_error(conn, index_url)
    topics, declared = parse_index(index.text, code)
    if limit:
        topics = topics[:limit]
    upsert_language(conn, language, declared, now)
    conn.commit()
    if not limit:
        conn.execute("CREATE TEMP TABLE IF NOT EXISTS seen_topic (site_id TEXT PRIMARY KEY)")
        conn.execute("DELETE FROM seen_topic")
        conn.executemany("INSERT INTO seen_topic (site_id) VALUES (?)", [(topic.site_id,) for topic in topics])
        conn.execute(
            """
            DELETE FROM topic
            WHERE authority_code = ?
              AND language_code = ?
              AND site_id NOT IN (SELECT site_id FROM seen_topic)
            """,
            (AUTHORITY, code),
        )
        conn.commit()

    inserted = 0
    updated = 0
    errors = 0
    partials = 0
    warnings: List[str] = []
    done = 0
    log("%s: %s topics, index declares %s questions" % (code, len(topics), declared))

    with ThreadPoolExecutor(max_workers=concurrency) as pool:
        futures = {
            pool.submit(fetch_topic, client, code, topic): topic
            for topic in topics
        }
        for future in as_completed(futures):
            topic = futures[future]
            done += 1
            try:
                fetched = future.result()
            except Exception as exc:
                fetched = TopicFetch(topic=topic, status="error", error=str(exc))
            warnings.extend(fetched.warnings)
            if fetched.status == "error":
                errors += 1
                record_error(conn, topic.url, code, "topic", fetched.error)
                conn.execute(
                    """
                    INSERT INTO topic (
                      authority_code, language_code, site_id, title, letter, position, declared_count,
                      url, fetch_status
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'error')
                    ON CONFLICT (authority_code, language_code, site_id) DO UPDATE SET
                      title = excluded.title,
                      letter = excluded.letter,
                      position = excluded.position,
                      declared_count = excluded.declared_count,
                      url = excluded.url,
                      fetch_status = CASE
                        WHEN (
                          SELECT COUNT(*) FROM placement
                          WHERE authority_code = topic.authority_code
                            AND language_code = topic.language_code
                            AND topic_site_id = topic.site_id
                        ) > 0 THEN topic.fetch_status
                        ELSE 'error'
                      END
                    """,
                    (
                        AUTHORITY, code, topic.site_id, topic.title, topic.letter, topic.position,
                        topic.declared_count, topic.url,
                    ),
                )
                conn.commit()
            else:
                got = sum(len(page[2]) for page in fetched.pages)
                previous = placement_count(conn, code, topic.site_id)
                if fetched.status == "partial" and previous > got:
                    partials += 1
                    record_error(
                        conn, topic.url, code, "topic",
                        "kept %s previous rows; new fetch had %s" % (previous, got),
                    )
                else:
                    if fetched.status == "partial":
                        partials += 1
                        record_error(conn, topic.url, code, "topic", fetched.warnings[-1] if fetched.warnings else "partial")
                    else:
                        clear_error(conn, topic.url)
                    added, changed = replace_placements(
                        conn, code, topic, fetched.pages, fetched.status, utc_now()
                    )
                    inserted += added
                    updated += changed
            if done % 25 == 0 or done == len(topics):
                log("%s %s/%s topics" % (code, done, len(topics)))

    if not limit:
        deleted = conn.execute(
            """
            DELETE FROM question
            WHERE authority_code = ?
              AND language_code = ?
              AND NOT EXISTS (
                SELECT 1 FROM placement AS p
                WHERE p.authority_code = question.authority_code
                  AND p.language_code = question.language_code
                  AND p.question_site_id = question.site_id
              )
            """,
            (AUTHORITY, code),
        ).rowcount
        conn.commit()
    else:
        deleted = 0
    row = conn.execute(
        "SELECT COUNT(*) AS n FROM question WHERE authority_code = ? AND language_code = ?",
        (AUTHORITY, code),
    ).fetchone()
    return {
        "language": code,
        "ok": errors == 0 and partials == 0,
        "topics": len(topics),
        "declared": declared,
        "questions": int(row["n"]),
        "inserted": inserted,
        "updated": updated,
        "deleted": deleted,
        "errors": errors,
        "partials": partials,
        "warnings": warnings[:8],
        "warning_count": len(warnings),
    }

def crawl(conn, languages=None, concurrency=4, delay=0.05, limit=0):
    client = SiteClient(delay)
    reports = []
    try:
        available = discover_languages(client)
        if languages:
            wanted = set(languages)
            available = [item for item in available if item[0] in wanted]
        for language in available:
            reports.append(crawl_language(conn, client, language, concurrency, limit))
    finally:
        client.close()
    return reports


def self_test() -> None:
    index = """
    <b class="hbaz1 nvy">٦٠٤٩</b>
    <div id="qa-tree">
      <div class="letter r5 c">أ</div>
      <div class="qa-tree">
        <a href="/arabic/qa/02003/" title="عدد الأسئلة: ٢">آداب الولادة والمولود</a>
        <a href="/arabic/qa/0252/" title="عدد الأسئلة: ١٧">الأذان والإقامة</a>
      </div>
      <div class="letter r5 c">ب</div>
      <div class="qa-tree">
        <a href="/arabic/qa/0356/" title="Number of questions: 64">Buying &amp; Selling</a>
      </div>
    </div>
    """
    topics, declared = parse_index(index, "arabic")
    assert declared == 6049, declared
    assert [topic.site_id for topic in topics] == ["02003", "0252", "0356"]
    assert topics[0].declared_count == 2
    assert topics[1].letter == "أ" and topics[2].letter == "ب"
    assert topics[2].title == "Buying & Selling"
    assert topics[0].url.endswith("/arabic/qa/02003/")

    page = """
    <div id="main-qa-content">
      <div class="one-qa">
        <a href="/arabic/qa/6357/" name="6357" class="fl qa-num">٢</a>
        <span id="q6357">
          <span class="nvy b">السؤال</span>: هل يجوز اقامة صلاة العيد ؟<br />
          <div class="b">
            <span class="nvy">الجواب</span>: نعم اذا ثبت الهلال.
          </div>
          <span class=disn>sistani.org/6357</span>
        </span>
      </div>
      <div class="one-qa">
        <a href="/english/qa/15612/" name="15612" class="fr qa-num">1</a>
        <span id="q15612">
          <span class="nvy b">Question</span>: What about alcohol?
          <div class="b"><span class="nvy">Answer</span>: It is forbidden.<br>See <a href="/english/qa/">the index</a>.</div>
        </span>
      </div>
      <a href="/arabic/qa/0591/?page=2">2</a>
      <a href="/arabic/qa/0591/" rel="next">التالي</a>
    </div>
    """
    questions = parse_questions(page)
    assert len(questions) == 2, questions
    assert questions[0].site_id == "6357"
    assert questions[0].number_value == 2
    assert questions[0].question_text == "هل يجوز اقامة صلاة العيد ؟"
    assert questions[0].answer_text == "نعم اذا ثبت الهلال."
    assert "السؤال" not in questions[0].question_text
    assert "sistani.org" not in questions[0].answer_text
    assert questions[1].answer_text.startswith("It is forbidden.")
    assert "https://www.sistani.org/english/qa/" in questions[1].answer_text
    assert "<br>" in questions[1].answer_html
    pages = pagination_urls(page, "arabic", "0591")
    assert pages == ["https://www.sistani.org/arabic/qa/0591/?page=2"], pages
    assert parse_localized_int("تعداد سوالات: ۸") == 8
    assert parse_localized_int("Sualların sayı: 12") == 12
    assert parse_attrs('dir="rtl" itemscope itemtype="http://schema.org/Answer"')["itemscope"] == ""
    assert parse_attrs("class=disn")["class"] == "disn"
    print("sistani self-test ok")
