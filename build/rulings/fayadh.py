#!/usr/bin/env python3
"""Sheikh Ishaq al-Fayyad Q&A from ar.alfayadh.org and fa.alfayadh.org.

Both sites are WordPress and expose the standard REST API, so no HTML is
parsed:

    GET {site}/wp-json/wp/v2/questions_category?per_page=100
    GET {site}/wp-json/wp/v2/question?per_page=100&page=N

A `question` post has the question as its title, the answer as its content
and one or more `questions_category` ids (the category tree is given by each
category's `parent`). Totals come from the X-WP-Total / X-WP-TotalPages
headers. Each language is its own site with its own ids.
"""

from __future__ import annotations

import json
import re
import sqlite3
from typing import Dict, List, Optional, Sequence

from db import log
from mirror import Client, empty_report, failed_report, make_item, save
from htmlutil import html_to_text

AUTHORITY = "fayadh"
PER_PAGE = 100
LANGUAGES = {
    "ar": ("العربية", "ar", "rtl"),
    "fa": ("فارسی", "fa", "rtl"),
}
UNCATEGORIZED = {"ar": "غير مصنف", "fa": "بدون دسته‌بندی"}
ZERO_WIDTH = re.compile("[​‌‍‎‏⁠﻿]+")


def site(language: str) -> str:
    return "https://%s.alfayadh.org" % language


def api(language: str, route: str, **params) -> str:
    query = "&".join("%s=%s" % (key, value) for key, value in params.items())
    return "%s/wp-json/wp/v2/%s?%s" % (site(language), route, query)


def get_pages(client: Client, language: str, route: str, limit_pages: int = 0, **params) -> List[dict]:
    rows: List[dict] = []
    page = 1
    while True:
        body, headers = client.fetch(api(language, route, per_page=PER_PAGE, page=page, **params))
        rows.extend(json.loads(body))
        total = int(headers.get("x-wp-totalpages", "1") or 1)
        if page >= total or (limit_pages and page >= limit_pages):
            return rows
        page += 1


def clean_title(raw: str) -> str:
    return ZERO_WIDTH.sub("", html_to_text(raw)).strip()


def parse_topics(language: str, categories: Sequence[dict]) -> List[dict]:
    ids = {str(category["id"]) for category in categories}
    topics = []
    for category in categories:
        parent = str(category.get("parent") or 0)
        topics.append({
            "site_id": str(category["id"]),
            "title": clean_title(category.get("name", "")) or str(category["id"]),
            "parent_site_id": parent if parent in ids else None,
            "url": category.get("link") or site(language),
            "declared_count": int(category.get("count") or 0),
        })
    # Parents first, then by name, so positions are stable between crawls.
    order = {topic["site_id"]: topic for topic in topics}

    def depth(topic: dict) -> int:
        level = 0
        while topic["parent_site_id"] and level < 50:
            topic = order[topic["parent_site_id"]]
            level += 1
        return level

    topics.sort(key=lambda topic: (depth(topic), topic["title"], int(topic["site_id"])))
    return topics


def parse_question(post: dict, topic_id: str) -> Optional[dict]:
    question = post.get("title", {}).get("rendered", "")
    answer = post.get("content", {}).get("rendered", "")
    if not html_to_text(question).strip() or not html_to_text(answer).strip():
        return None
    link = post.get("link") or ""
    return make_item(str(post["id"]), question, answer, link, 1, link)


def crawl_language(conn: sqlite3.Connection, client: Client, language: str, limit: int) -> dict:
    categories = get_pages(client, language, "questions_category", _fields="id,name,parent,count,link")
    topics = parse_topics(language, categories)
    posts = get_pages(
        client, language, "question",
        limit_pages=1 if limit else 0, _fields="id,link,title,content,questions_category",
    )
    log("fayadh %s: %s categories, %s questions" % (language, len(topics), len(posts)))
    if not posts:
        return empty_report(AUTHORITY, language, "%s has no published questions" % language)
    known = {topic["site_id"] for topic in topics}
    listings: Dict[str, List[dict]] = {}
    for post in posts:
        ids = [str(value) for value in post.get("questions_category") or [] if str(value) in known]
        topic_id = ids[0] if ids else "0"
        item = parse_question(post, topic_id)
        if item is None:
            continue
        for owner in ids or ["0"]:  # save() keeps it in the deepest listed topic
            listings.setdefault(owner, []).append(item)
    if "0" in listings:
        topics.append({
            "site_id": "0", "title": UNCATEGORIZED[language], "parent_site_id": None,
            "url": site(language) + "/qa/", "declared_count": 0,
        })
    return save(conn, AUTHORITY, language, LANGUAGES[language], topics, listings)


def crawl(
    conn: sqlite3.Connection,
    languages: Optional[Sequence[str]] = None,
    concurrency: int = 4,
    delay: float = 0.05,
    limit: int = 0,
) -> List[dict]:
    client = Client(delay, headers={"Accept": "application/json"})
    reports = []
    for language in list(languages or LANGUAGES):
        try:
            reports.append(crawl_language(conn, client, language, limit))
        except Exception as exc:
            reports.append(failed_report(AUTHORITY, language, str(exc)))
    return reports


def self_test() -> None:
    categories = [
        {"id": 7, "name": "​مسائل في الغسل", "parent": 6, "count": 1, "link": "https://ar.alfayadh.org/c/7/"},
        {"id": 6, "name": "الطهارة", "parent": 0, "count": 0, "link": "https://ar.alfayadh.org/c/6/"},
    ]
    topics = parse_topics("ar", categories)
    assert [(t["site_id"], t["parent_site_id"], t["title"]) for t in topics] == [
        ("6", None, "الطهارة"), ("7", "6", "مسائل في الغسل"),
    ], topics
    post = {
        "id": 3637, "link": "https://ar.alfayadh.org/question/x/",
        "title": {"rendered": "هل يجوز &#8220;الغسل&#8221;؟"},
        "content": {"rendered": "<p>يجوز.</p>\n<p>والله العالم.</p>\n"},
        "questions_category": [7],
    }
    item = parse_question(post, "7")
    assert item["site_id"] == "3637"
    assert item["question_text"] == "هل يجوز “الغسل”؟", item["question_text"]
    assert item["answer_text"].startswith("يجوز."), item["answer_text"]
    assert item["url"] == "https://ar.alfayadh.org/question/x/"
    assert parse_question({**post, "content": {"rendered": " "}}, "7") is None
    assert api("fa", "question", per_page=100, page=2) == \
        "https://fa.alfayadh.org/wp-json/wp/v2/question?per_page=100&page=2"
    print("fayadh self-test ok")


if __name__ == "__main__":
    self_test()
