#!/usr/bin/env python3
"""Sayyid Muhammad al-Rohani Q&A from alrohani.org.

Server-rendered PHP, windows-1256 encoded, no API and no pagination:

    index.php?act=qa&id=3                    fatwa root: one .cat_entry per category
    index.php?act=qa&id={category}           one .msg_row per question (question truncated)
    index.php?act=qa&action=view&id={id}     full question and answer

The server answers 406 unless the request carries an Accept header, which
mirror.Client always sends.
"""

from __future__ import annotations

import re
import sqlite3
import threading
from concurrent.futures import ThreadPoolExecutor
from typing import Dict, List, Optional, Sequence, Tuple

from db import log
from htmlutil import html_to_text
from mirror import Client, empty_report, failed_report, make_item, save

SITE = "https://alrohani.org"
AUTHORITY = "alrohani"
ROOT = "3"
LANGUAGES = {"ar": ("العربية", "ar", "rtl")}

CATEGORY = re.compile(
    r"""<div class=["']cat_entry["']>\s*<a href=["']index\.php\?act=qa&(?:amp;)?id=(\d+)["']>(.*?)</a>""",
    re.S,
)
ROW = re.compile(
    r"""<div class=["']msg_row["']>\s*<a href=["']index\.php\?act=qa&(?:amp;)?action=view&(?:amp;)?id=(\d+)["']""",
    re.S,
)
QUESTION = re.compile(r"""<div class=["']msg_qu_display["']>(.*?)</div>""", re.S)
ANSWER = re.compile(r"""<div class=["']msg_ans_display["']>(.*?)</div>\s*(?=<(?:/?div|a|!--|br)\b|$)""", re.S)


def category_url(category: str) -> str:
    return "%s/index.php?act=qa&id=%s" % (SITE, category)


def question_url(site_id: str) -> str:
    return "%s/index.php?act=qa&action=view&id=%s" % (SITE, site_id)


def parse_categories(source: str) -> List[Tuple[str, str]]:
    seen = set()
    found = []
    for site_id, title in CATEGORY.findall(source):
        if site_id in seen:
            continue
        seen.add(site_id)
        found.append((site_id, html_to_text(title).strip() or site_id))
    return found


def parse_row_ids(source: str) -> List[str]:
    ids: List[str] = []
    for site_id in ROW.findall(source):
        if site_id not in ids:
            ids.append(site_id)
    return ids


def parse_question(source: str, site_id: str) -> Optional[dict]:
    question = QUESTION.search(source)
    answer = ANSWER.search(source)
    if not question or not answer:
        return None
    item = make_item(site_id, question.group(1), answer.group(1), question_url(site_id))
    return item if item["question_text"] and item["answer_text"] else None


def crawl_category(client: Client, category: str, cache: Dict[str, Optional[dict]]) -> dict:
    source = client.get(category_url(category))
    items = []
    for site_id in parse_row_ids(source):
        if site_id not in cache:
            cache[site_id] = parse_question(client.get(question_url(site_id)), site_id)
        if cache[site_id] is not None:
            items.append(dict(cache[site_id], page_url=category_url(category)))
    return {"subcategories": parse_categories(source), "items": items}


def crawl_language(conn: sqlite3.Connection, client: Client, language: str, concurrency: int, limit: int) -> dict:
    frontier: List[Tuple[str, str, Optional[str]]] = [
        (site_id, title, None) for site_id, title in parse_categories(client.get(category_url(ROOT)))
    ]
    if not frontier:
        return empty_report(AUTHORITY, language, "no fatwa categories found")
    topics: List[dict] = []
    listings: Dict[str, List[dict]] = {}
    failed: List[str] = []
    visited = {ROOT}
    cache: Dict[str, Optional[dict]] = {}
    lock = threading.Lock()

    def work(entry):
        try:
            return entry, crawl_category(client, entry[0], cache), None
        except Exception as exc:
            return entry, None, exc

    with ThreadPoolExecutor(max_workers=max(1, concurrency)) as pool:
        while frontier:
            frontier = [entry for entry in frontier if entry[0] not in visited]
            if limit:
                frontier = frontier[: max(0, limit - len(topics))]
            visited.update(entry[0] for entry in frontier)
            next_frontier: List[Tuple[str, str, Optional[str]]] = []
            for entry, result, error in pool.map(work, frontier):
                site_id, title, parent = entry
                topics.append({
                    "site_id": site_id, "title": title, "parent_site_id": parent,
                    "url": category_url(site_id), "declared_count": 0,
                })
                if error is not None:
                    failed.append(site_id)
                    log("alrohani topic %s: %s" % (site_id, error))
                    continue
                with lock:
                    listings[site_id] = result["items"]
                next_frontier.extend((sub, name, site_id) for sub, name in result["subcategories"])
            log("alrohani %s: %s categories, %s questions" % (language, len(topics), len(cache)))
            frontier = next_frontier
            if limit and len(topics) >= limit:
                break
    if not any(listings.values()) and not failed:
        return empty_report(AUTHORITY, language, "no published questions")
    return save(conn, AUTHORITY, language, LANGUAGES[language], topics, listings, failed)


def crawl(
    conn: sqlite3.Connection,
    languages: Optional[Sequence[str]] = None,
    concurrency: int = 4,
    delay: float = 0.05,
    limit: int = 0,
) -> List[dict]:
    client = Client(delay, encoding="cp1256")
    reports = []
    for language in list(languages or LANGUAGES):
        try:
            reports.append(crawl_language(conn, client, language, concurrency, limit))
        except Exception as exc:
            reports.append(failed_report(AUTHORITY, language, str(exc)))
    return reports


def self_test() -> None:
    root = """
    <div class="cat_cont">
    <div class="cat_entry"><a href="index.php?act=qa&id=1">مسائل الصلاة</a></div>
    <div class="cat_entry"><a href="index.php?act=qa&id=2">مسائل الحج</a></div>
    </div>"""
    assert parse_categories(root) == [("1", "مسائل الصلاة"), ("2", "مسائل الحج")], parse_categories(root)
    listing = """
    <div class="msg_row">
    <a href="index.php?act=qa&action=view&id=10">حكم الصلاة</a>
    </div>
    <div class="msg_qustion"> ... <a href="index.php?act=qa&action=view&id=10"><img></a></div>
    <div class="msg_row">
    <a href="index.php?act=qa&action=view&id=9">حكم آخر</a>
    </div>"""
    assert parse_row_ids(listing) == ["10", "9"], parse_row_ids(listing)
    detail = """
    <div class="msg_qu_title">حكم الصلاة</div>
    <div class="msg_qu_display">الجلود المستوردة &#1740; ما حكم صلاته ؟<br />ثانياً</div>
    <div><img src="images/answer.gif" alt="الجواب" /></div>
    <div class="msg_ans_display"><p> يحكم بعدم التذكية.</p>
    </div>


    <a href="?act=ask"></a>"""
    item = parse_question(detail, "10")
    assert item["site_id"] == "10"
    assert item["question_text"].startswith("الجلود المستوردة ی"), item["question_text"]
    assert item["answer_text"] == "يحكم بعدم التذكية.", item["answer_text"]
    assert item["url"] == "https://alrohani.org/index.php?act=qa&action=view&id=10"
    assert parse_question("<div>nothing</div>", "1") is None
    print("alrohani self-test ok")


if __name__ == "__main__":
    self_test()
