#!/usr/bin/env python3
"""Sheikh Bashir al-Najafi Q&A from alnajafy.com.

There is no API; pages are server-rendered under /list/:

    category   mainnews-1-677-{id}.html          (id 0 is the fatwa root)
    page N     mainnews-{N}-1-677-{id}-1.html    (N >= 2)

A category page lists either sub-categories
(<li id="gallery_image_li"><a href=...><div class="istefsub">title</div></a></li>)
or ten full Q&As per page
(<li id="gallery_image_li" title="{question id}"><div class="istefsub">
السؤال:...<br><br>الجواب:...</div></li>). A page past the last one is empty.
Questions have no page of their own, so the URL is the category page plus
#{question id}.

The site's language switch is ?la=1..7. Only la=1 (Arabic) is mirrored; it is
also what the site serves by default.
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

SITE = "https://www.alnajafy.com"
AUTHORITY = "najafi"
ROOT = "0"
MAX_PAGES = 1000
LANGUAGES = {"ar": ("العربية", "ar", "rtl")}  # site code ar == ?la=1

SUBCATEGORY = re.compile(
    r"""<a\s+href=["']mainnews-1-677-(\d+)\.html["']\s*>\s*<div class=["']istefsub["']>(.*?)</div>\s*</a>""",
    re.S,
)
ITEM = re.compile(
    r"""<li id=["']gallery_image_li["']\s+title=["'](\d+)["']>\s*<div class=["']istefsub["']>(.*?)</div>\s*</li>""",
    re.S,
)
QA = re.compile(
    r"^\s*السؤال\s*[:：]?\s*(.*?)\s*(?:<br\s*/?>\s*)*الجواب\s*[:：]\s*(.*?)\s*$",
    re.S,
)


def category_url(category: str, page: int = 1) -> str:
    if page <= 1:
        return "%s/list/mainnews-1-677-%s.html" % (SITE, category)
    return "%s/list/mainnews-%s-1-677-%s-1.html" % (SITE, page, category)


def parse_subcategories(source: str) -> List[Tuple[str, str]]:
    seen = set()
    found = []
    for site_id, title in SUBCATEGORY.findall(source):
        if site_id in seen:
            continue
        seen.add(site_id)
        found.append((site_id, html_to_text(title).strip() or site_id))
    return found


def parse_items(source: str, category: str, page: int) -> List[dict]:
    page_url = category_url(category, page)
    items = []
    for site_id, inner in ITEM.findall(source):
        match = QA.match(inner)
        if not match or not match.group(1).strip() or not match.group(2).strip():
            continue
        items.append(make_item(
            site_id, match.group(1), match.group(2),
            "%s#%s" % (page_url, site_id), page, page_url,
        ))
    return items


def crawl_category(client: Client, category: str, title: str) -> dict:
    first = client.get(category_url(category))
    subcategories = parse_subcategories(first)
    items: List[dict] = []
    seen = set()
    page = 1
    source = first
    while page <= MAX_PAGES:
        found = [item for item in parse_items(source, category, page) if item["site_id"] not in seen]
        if not found:
            break
        seen.update(item["site_id"] for item in found)
        items.extend(found)
        page += 1
        source = client.get(category_url(category, page))
    return {"id": category, "title": title, "subcategories": subcategories, "items": items}


def crawl_language(conn: sqlite3.Connection, client: Client, language: str, concurrency: int, limit: int) -> dict:
    client.get("%s/list/alnajafy.html?la=1" % SITE)  # pin the Arabic edition for this session
    frontier: List[Tuple[str, str, Optional[str]]] = [
        (site_id, title, None) for site_id, title in parse_subcategories(client.get(category_url(ROOT)))
    ]
    if not frontier:
        return empty_report(AUTHORITY, language, "no fatwa categories found")
    topics: List[dict] = []
    listings: Dict[str, List[dict]] = {}
    failed: List[str] = []
    visited = set()
    lock = threading.Lock()

    def work(entry: Tuple[str, str, Optional[str]]):
        try:
            return entry, crawl_category(client, entry[0], entry[1]), None
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
                    log("najafi topic %s: %s" % (site_id, error))
                    continue
                with lock:
                    listings[site_id] = result["items"]
                next_frontier.extend((sub_id, sub_title, site_id) for sub_id, sub_title in result["subcategories"])
            log("najafi %s: %s categories, %s questions" % (
                language, len(topics), sum(len(items) for items in listings.values())))
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
    client = Client(delay)
    reports = []
    for language in list(languages or LANGUAGES):
        try:
            reports.append(crawl_language(conn, client, language, concurrency, limit))
        except Exception as exc:
            reports.append(failed_report(AUTHORITY, language, str(exc)))
    return reports


def self_test() -> None:
    root = """
    <ul><li id="gallery_image_li" ><a href="mainnews-1-677-198.html"><div class="istefsub">العبادات</div></a></li>
    <li id="gallery_image_li" ><a href="mainnews-1-677-286.html">
      <div class="istefsub">المعاملات</div></a></li></ul>
    """
    assert parse_subcategories(root) == [("198", "العبادات"), ("286", "المعاملات")], parse_subcategories(root)
    leaf = """
    <li id="gallery_image_li" title="14833"><div class="istefsub">السؤال:هل يجوز التكفين بكفن قد كتب عليه القرآن الكريم؟<br><br>الجواب:بسمه سبحانه: يجوز. والله العالم. </div></li>
    <li id="gallery_image_li" title="12504"><div class="istefsub">السؤال:سؤالي حول الأموات:
    هل يجوز؟<br><br>الجواب:بسمه سبحانه
    نعم<br>والله العالم</div></li>
    <li id="gallery_image_li" title="1"><div class="istefsub">السؤال:بلا جواب</div></li>
    """
    assert parse_subcategories(leaf) == []
    items = parse_items(leaf, "2", 3)
    assert [item["site_id"] for item in items] == ["14833", "12504"], items
    assert items[0]["question_text"] == "هل يجوز التكفين بكفن قد كتب عليه القرآن الكريم؟", items[0]["question_text"]
    assert items[0]["answer_text"] == "بسمه سبحانه: يجوز. والله العالم.", items[0]["answer_text"]
    assert "السؤال" not in items[1]["question_text"] and "الجواب" not in items[1]["answer_text"]
    assert items[1]["answer_text"].endswith("والله العالم"), items[1]["answer_text"]
    assert items[0]["url"] == "https://www.alnajafy.com/list/mainnews-3-1-677-2-1.html#14833"
    assert category_url("2") == "https://www.alnajafy.com/list/mainnews-1-677-2.html"
    print("najafi self-test ok")


if __name__ == "__main__":
    self_test()
