#!/usr/bin/env python3
"""Sayyid Muhammad Sadiq al-Rohani Q&A from rohani.ir.

ASP.NET with URL rewriting; no API. Each language has two sections (sharia
rulings and belief rulings) with their own ids:

    /{lang}/Istefta/{section}/x            section page: category links
    /{lang}/ic/{category}/x                category page, 1st page
    /{lang}/ic/{category}/{page}/x         later pages, 20 items per page
    /{lang}/idetail/{id}/x                 one question and answer

Arabic sections are 18345 and 18346; Persian are 18322 and 18323. (Asking the
/fa/ site for 18345 just serves the Arabic section.) Category ids differ per
language. The slug after the id is ignored by the server.
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

SITE = "https://www.rohani.ir"
AUTHORITY = "rohani"
MAX_PAGES = 1000
LANGUAGES = {
    "ar": ("العربية", "ar", "rtl"),
    "fa": ("فارسی", "fa", "rtl"),
}
SECTIONS = {
    "ar": ("18345", "18346"),
    "fa": ("18322", "18323"),
}

SECTION_TITLE = re.compile(r"<h2>\s*<a [^>]*>(.*?)</a>", re.S)
LABEL = re.compile(r"^\s*(?:استفتاء|الاستفتاء|السؤال|سؤال|پرسش|جواب|الجواب|پاسخ)\s*[:：]\s*", re.S)
DETAIL = re.compile(
    r"""<div class=['"]IsteftaQuestion['"]>(.*?)</div>\s*<div class=['"]IsteftaAnswer['"]>(.*?)</div>\s*(?=<img|<div class=['"]clear)""",
    re.S,
)


def category_re(language: str):
    return re.compile(
        r"""<a [^>]*href=['"]/%s/ic/(\d+)/[^'"#]*#data['"][^>]*>(.*?)</a>""" % language, re.S
    )


def item_re(language: str):
    return re.compile(
        r"""IsteftaItem['"]\s+href=['"](?:https?://www\.rohani\.ir)?/%s/idetail/(\d+)/""" % language
    )


def section_url(language: str, section: str) -> str:
    return "%s/%s/Istefta/%s/x" % (SITE, language, section)


def category_url(language: str, category: str, page: int = 1) -> str:
    if page <= 1:
        return "%s/%s/ic/%s/x" % (SITE, language, category)
    return "%s/%s/ic/%s/%s/x" % (SITE, language, category, page)


def question_url(language: str, site_id: str) -> str:
    return "%s/%s/idetail/%s/x" % (SITE, language, site_id)


def parse_section(source: str, language: str) -> Tuple[str, List[Tuple[str, str]]]:
    title = SECTION_TITLE.search(source)
    categories = []
    seen = set()
    for site_id, name in category_re(language).findall(source):
        if site_id not in seen:
            seen.add(site_id)
            categories.append((site_id, html_to_text(name).strip() or site_id))
    return (html_to_text(title.group(1)).strip() if title else ""), categories


def parse_listing(source: str, language: str) -> List[str]:
    ids: List[str] = []
    for site_id in item_re(language).findall(source):
        if site_id not in ids:
            ids.append(site_id)
    return ids


def strip_labels(fragment: str) -> str:
    # Some answers repeat the label inside the body ("جواب: الجواب: ...").
    for _ in range(3):
        stripped = LABEL.sub("", fragment, count=1)
        if stripped == fragment:
            break
        fragment = stripped
    return fragment


def parse_question(source: str, language: str, site_id: str, page_url: str = "") -> Optional[dict]:
    match = DETAIL.search(source)
    if not match:
        return None
    question = strip_labels(match.group(1))
    answer = strip_labels(match.group(2))
    item = make_item(site_id, question, answer, question_url(language, site_id), 1, page_url)
    return item if item["question_text"] and item["answer_text"] else None


def crawl_category(client: Client, language: str, category: str) -> List[dict]:
    items: List[dict] = []
    seen = set()
    page = 1
    while page <= MAX_PAGES:
        url = category_url(language, category, page)
        ids = [site_id for site_id in parse_listing(client.get(url), language) if site_id not in seen]
        if not ids:
            break
        seen.update(ids)
        for site_id in ids:
            item = parse_question(client.get(question_url(language, site_id)), language, site_id, url)
            if item is not None:
                item["page"] = page
                items.append(item)
        page += 1
    return items


def crawl_language(conn: sqlite3.Connection, client: Client, language: str, concurrency: int, limit: int) -> dict:
    topics: List[dict] = []
    categories: List[Tuple[str, str, str]] = []  # (category, title, section topic id)
    seen = set()
    for section in SECTIONS[language]:
        title, found = parse_section(client.get(section_url(language, section)), language)
        topic_id = "s%s" % section
        topics.append({
            "site_id": topic_id, "title": title or topic_id, "parent_site_id": None,
            "url": section_url(language, section), "declared_count": 0,
        })
        for site_id, name in found:
            if site_id not in seen:
                seen.add(site_id)
                categories.append((site_id, name, topic_id))
    if not categories:
        return empty_report(AUTHORITY, language, "%s has no question categories" % language)
    if limit:
        categories = categories[:limit]
    log("rohani %s: %s categories" % (language, len(categories)))
    listings: Dict[str, List[dict]] = {}
    failed: List[str] = []
    lock = threading.Lock()
    done = 0

    def work(entry):
        try:
            return entry, crawl_category(client, language, entry[0]), None
        except Exception as exc:
            return entry, None, exc

    with ThreadPoolExecutor(max_workers=max(1, concurrency)) as pool:
        for entry, items, error in pool.map(work, categories):
            site_id, name, parent = entry
            topics.append({
                "site_id": site_id, "title": name, "parent_site_id": parent,
                "url": category_url(language, site_id), "declared_count": 0,
            })
            done += 1
            if error is not None:
                failed.append(site_id)
                log("rohani %s topic %s: %s" % (language, site_id, error))
            else:
                with lock:
                    listings[site_id] = items
            if done % 10 == 0 or done == len(categories):
                log("rohani %s %s/%s" % (language, done, len(categories)))
    if not any(listings.values()) and not failed:
        return empty_report(AUTHORITY, language, "%s has no published questions" % language)
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
    section = """
    <h2> <a href='/ar/Istefta/18345/x'>الإستفتاءات الشرعیة</a> </h2>
    <div id="pnlCat" class="IsteftaCat">
    <a id="a1" class="Fade" href="/ar/ic/48/%d8%a7#data">الاجتهاد و التقليد</a>
    <a id="a2" class="Fade" href="/ar/ic/64/x#data">الطهارة (الوضــــوء)</a>
    <a class="Fade" href="/fa/ic/99/x#data">other language</a>
    </div>"""
    title, categories = parse_section(section, "ar")
    assert title == "الإستفتاءات الشرعیة", title
    assert categories == [("48", "الاجتهاد و التقليد"), ("64", "الطهارة (الوضــــوء)")], categories
    listing = """
    <a class="Fade IsteftaItem" href='/ar/idetail/9312/x'> عن تقليد؟ <span>(جدید)</span></a>
    <a class="Fade IsteftaItem" href='/ar/idetail/7782/y'> عن التقليد؟ </a>
    <a class="Fade IsteftaItem" href='http://www.rohani.ir/ar/idetail/7782/z'> مكرر </a>"""
    assert parse_listing(listing, "ar") == ["9312", "7782"], parse_listing(listing, "ar")
    detail = """<div class="FontBody"><div class='IsteftaQuestion'>استفتاء: <p style="text-align: justify;">هل يجوز؟&nbsp;</p></div><div class='IsteftaAnswer'>جواب: <p><span>باسمه جلت اسماؤه<br /> يجب تقليد الاعلم.</span></p></div><img style='float:left;' src='/images/mohr.jpg' /><div class='clear'></div></div>"""
    item = parse_question(detail, "ar", "7782")
    assert item["question_text"] == "هل يجوز؟", item["question_text"]
    assert item["answer_text"].startswith("باسمه جلت اسماؤه") and "جواب" not in item["answer_text"][:5], item["answer_text"]
    assert item["url"] == "https://www.rohani.ir/ar/idetail/7782/x"
    doubled = detail.replace("جواب: <p>", "جواب: الجواب: <p>")
    assert parse_question(doubled, "ar", "1")["answer_text"].startswith("باسمه"), doubled
    assert category_url("fa", "5", 3) == "https://www.rohani.ir/fa/ic/5/3/x"
    assert parse_question("<div></div>", "ar", "1") is None
    print("rohani self-test ok")


if __name__ == "__main__":
    self_test()
