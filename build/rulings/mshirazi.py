#!/usr/bin/env python3
"""Sayyid Muhammad al-Husayni al-Shirazi from alshirazi.com.

The site is hand-written static HTML (windows-1256) with no API, feed or
sitemap, so both parts are crawled from their index pages.

Q&A, الاستفتاءات المرجعية (rflo/alestiftaatalmarjeyeh/):

    fehres.htm       links 1.htm .. 5.htm (1.htm is a glossary, not Q&A)
    N.htm            size-6 heading = section, size-5 heading = question title,
                     paragraphs "س : ..." and "ج : ..." = question and answer

Book, منتخب المسائل الإسلامية (rflo/montakhab/):

    fehres.htm       group headings (العبادات, المعاملات) above links to chapter
                     pages; chapter pages are either leaves (مسألة N : ...) or
                     further indexes. Stored in book_edition like the Sistani
                     and Sadiq Shirazi books.

Questions have no anchors, so the URL is the chapter page.
"""

from __future__ import annotations

import json
import re
import sqlite3
import urllib.parse
from typing import Dict, List, Optional, Sequence, Tuple

from books import ensure_mirror, entries
from db import log
from htmlutil import clean_html, html_to_text
from mirror import Client, empty_report, failed_report, make_item, save

SITE = "https://www.alshirazi.com"
QA_ROOT = SITE + "/rflo/alestiftaatalmarjeyeh/"
BOOK_ROOT = SITE + "/rflo/montakhab/"
AUTHORITY = "mshirazi"
LANGUAGES = {"ar": ("العربية", "ar", "rtl")}
BOOK_ID = "montakhab"
BOOK_TITLE = "منتخب المسائل الإسلامية"

ANCHOR = re.compile(r"""<a\s[^>]*?href\s*=\s*["']([^"'#]+\.htm)["'][^>]*>(.*?)</a>""", re.S | re.I)
SEGMENT = re.compile(r"(?=<p\b)|(?=</td)|(?=</tr)", re.I)
MARKER = re.compile(r"^([سج])\s*[:：]\s*")
RULE_COLON = re.compile(r"(مسأل[ةه]\s*\d+)\s*[:：]\s*")
# The source has typos like "امسألة 1 :" or "ر مسألة 5 :"; a lone letter before a label.
STRAY = re.compile(r"(?m)^[\u0621-\u064A]\s*(?=مسأل[ةه]\s*\d+\s*[:：])")
TATWEEL = re.compile("ـ")


def body_of(source: str) -> str:
    start = source.lower().find("<body")
    return source[start:] if start >= 0 else source


def plain(fragment: str) -> str:
    return html_to_text(fragment).strip()


def unlink(fragment: str) -> str:
    """Keep anchor text; html_to_text would append the target URL."""
    return ANCHOR.sub(lambda m: m.group(2), fragment)


def links(source: str, base: str) -> List[Tuple[str, str]]:
    found: List[Tuple[str, str]] = []
    for href, inner in ANCHOR.findall(body_of(source)):
        url = urllib.parse.urljoin(base, href.strip())
        title = plain(inner)
        if url.startswith(SITE) and title:
            found.append((url, title))
    return found


# --- Q&A ---------------------------------------------------------------


def parse_chapter(source: str, chapter: str, url: str) -> Tuple[List[dict], Dict[str, List[dict]], List[str]]:
    """Return (section topics, {topic id: items}, warnings) for one chapter page."""
    sections: List[dict] = []
    listings: Dict[str, List[dict]] = {}
    warnings: List[str] = []
    state = {"topic": chapter, "q": [], "a": [], "ordinal": 0}

    def flush() -> None:
        question, answer = state["q"], state["a"]
        state["q"], state["a"] = [], []
        if not question and not answer:
            return
        state["ordinal"] += 1
        site_id = "%s-%d" % (chapter, state["ordinal"])
        if not question or not answer:
            warnings.append("%s: incomplete pair dropped" % site_id)
            return
        item = make_item(site_id, "<br>".join(question), "<br>".join(answer), url, 1, url)
        if item["question_text"] and item["answer_text"]:
            listings.setdefault(state["topic"], []).append(item)
        else:
            warnings.append("%s: empty pair dropped" % site_id)

    for segment in SEGMENT.split(body_of(source)):
        text = plain(unlink(segment))
        if not text:
            continue
        if 'size="6"' in segment.lower().replace("'", '"') and not MARKER.match(text):
            flush()
            site_id = "%s-s%d" % (chapter, len(sections) + 1)
            sections.append({"site_id": site_id, "title": text, "parent_site_id": chapter,
                             "url": url, "declared_count": 0})
            state["topic"] = site_id
            continue
        marker = MARKER.match(text)
        if marker is None and 'size="5"' in segment.lower().replace("'", '"') and len(text) < 120:
            flush()  # question title; the mirror has no title field
            continue
        fragment = re.sub(r"^\s*[سج]\s*[:：]\s*", "", clean_html(unlink(segment)))
        if marker and marker.group(1) == "س":
            if state["a"]:
                flush()
            state["q"].append(fragment)
        elif marker:
            if not state["q"]:
                warnings.append("%s: answer without question" % chapter)
            state["a"].append(fragment)
        elif state["a"]:
            state["a"].append(fragment)
        elif state["q"]:
            state["q"].append(fragment)
    flush()
    return sections, listings, warnings


def crawl_qa(conn: sqlite3.Connection, client: Client, language: str, limit: int) -> dict:
    chapters = [(url, title) for url, title in links(client.get(QA_ROOT + "fehres.htm"), QA_ROOT)
                if re.fullmatch(r"\d+\.htm", url[len(QA_ROOT):])]
    if not chapters:
        return empty_report(AUTHORITY, language, "no chapters found")
    topics: List[dict] = []
    listings: Dict[str, List[dict]] = {}
    failed: List[str] = []
    for url, title in chapters[: limit or None]:
        chapter = url[len(QA_ROOT):-4]
        topics.append({"site_id": chapter, "title": title, "parent_site_id": None, "url": url, "declared_count": 0})
        try:
            sections, found, warnings = parse_chapter(client.get(url), chapter, url)
        except Exception as exc:
            failed.append(chapter)
            log("mshirazi chapter %s: %s" % (chapter, exc))
            continue
        for warning in warnings:
            log("mshirazi " + warning)
        topics.extend(sections)
        listings.update(found)
        log("mshirazi %s: %s sections, %s questions" % (chapter, len(sections), sum(len(v) for v in found.values())))
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
            reports.append(crawl_qa(conn, client, language, limit))
        except Exception as exc:
            reports.append(failed_report(AUTHORITY, language, str(exc)))
    return reports


# --- Book --------------------------------------------------------------


def parse_index(source: str, base: str) -> List[Tuple[Optional[str], str, str]]:
    """Return (group title, url, link title) from the Montakhab front page."""
    found = []
    group: Optional[str] = None
    tables_left = 0
    token = re.compile(
        r"""bgcolor=["']#800000["'][^>]*>(?P<head>.*?)</td>|</table>|"""
        r"""<a\s[^>]*?href\s*=\s*["'](?P<href>[^"'#]+\.htm)["'][^>]*>(?P<text>.*?)</a>""",
        re.S | re.I,
    )
    for match in token.finditer(body_of(source)):
        if match.group("head") is not None:
            group = TATWEEL.sub("", plain(match.group("head")))
            tables_left = 2  # the heading's own table, then the link table
        elif match.group("href"):
            url = urllib.parse.urljoin(base, match.group("href").strip())
            title = plain(match.group("text"))
            if title and url.startswith(BOOK_ROOT):
                found.append((group, url, title))
        elif tables_left:
            tables_left -= 1
            if not tables_left:
                group = None
    return found


def leaf_entries(source: str, title: str, base: str = BOOK_ROOT) -> Tuple[Optional[str], List[dict], List[Tuple[str, str]]]:
    """Return (page heading, entries, child links) for one chapter page."""
    body = body_of(source)
    cut = body.lower().rfind("</map>")
    if cut >= 0:
        body = body[cut:]
    children = links(body, base)
    heading = None
    lines: List[str] = []
    for segment in SEGMENT.split(body):
        text = plain(unlink(segment))
        if not text:
            continue
        tag = segment.lower().replace("'", '"')
        if heading is None and not lines and ('size="6"' in tag or 'size="5"' in tag) and len(text) < 120:
            heading = text
            continue
        lines.append(text)
    text = RULE_COLON.sub(r"\1: ", STRAY.sub("", "\n".join(lines)))
    labelled = re.search(r"مسأل[ةه]\s*\d+", text)
    if not labelled and children:
        return heading, [], children  # a pure index
    rows = entries(text, title) if text.strip() else []
    if rows and not any(row["label"] for row in rows):  # prose chapter: one unnumbered text
        for row in rows:
            row.update(kind="intro", number=0)
    return heading, rows, children


def crawl_book(db: sqlite3.Connection, delay: float = 0.05) -> List[str]:
    """Mirror the Montakhab into book_edition. Returns failures; nothing is written if any."""
    client = Client(delay, encoding="cp1256")
    ensure_mirror(db)
    front = client.get(BOOK_ROOT + "fehres.htm")
    chapters: List[dict] = []
    group_ids: Dict[str, str] = {}
    queue: List[Tuple[str, str, Optional[str], bool]] = []  # url, title, parent id, title from link only
    seen = {BOOK_ROOT + "fehres.htm"}
    for group, url, title in parse_index(front, BOOK_ROOT + "fehres.htm"):
        parent = None
        if group:
            if group not in group_ids:
                group_ids[group] = "group:%d" % (len(group_ids) + 1)
                chapters.append(dict(id=group_ids[group], title=group, parent=None, url=BOOK_ROOT + "fehres.htm",
                                     raw="", entries=[]))
            parent = group_ids[group]
        queue.append((url, title, parent, False))
    failures: List[str] = []
    index = 0
    while index < len(queue):
        url, title, parent, prefer_heading = queue[index]
        index += 1
        if url in seen:
            continue
        seen.add(url)
        chapter_id = urllib.parse.unquote(url[len(BOOK_ROOT):-4])
        try:
            raw = client.get(url)
            heading, rows, children = leaf_entries(raw, title, url)
        except Exception as exc:
            failures.append("%s: %s" % (url, exc))
            continue
        if prefer_heading and heading:
            title = heading
        chapters.append(dict(id=chapter_id, title=title, parent=parent, url=url, raw=raw, entries=rows))
        for child_url, child_title in children:
            if child_url.startswith(BOOK_ROOT) and child_url not in seen:
                queue.append((child_url, child_title, chapter_id, bool(rows)))
    if not failures and not any(chapter["entries"] for chapter in chapters):
        failures.append("montakhab: no entries parsed")
    if failures:
        for failure in failures:
            log("mshirazi book " + failure)
        return failures
    with db:
        db.execute(
            "INSERT OR REPLACE INTO book_edition(authority,language,site_id,title,url,chapters) VALUES (?,?,?,?,?,?)",
            (AUTHORITY, "ar", BOOK_ID, BOOK_TITLE, BOOK_ROOT + "fehres.htm", json.dumps(chapters, ensure_ascii=False)),
        )
    log("mshirazi book: %s chapters, %s entries" % (len(chapters), sum(len(c["entries"]) for c in chapters)))
    return []


def self_test() -> None:
    qa = """<body><table><tr><td><p align="center"><a href="x.htm">المؤلفات</a></td></tr></table>
    <table><tr><td><p align="center"><b><font color="#800000" size="6">الطهارة</font></b>
    </td></tr><tr><td><b><font FACE="Arial"><p align="center"><font size="5" color="#000080">الوضوء بالثلج</font></p></font>
    </b></td></tr><tr><td><b>
    <p align="justify"><font face="Arial"><font color="#FF0000">س :</font> هل يجوز الوضوء
    بالثلج؟</font></p>
    <p align="justify"><font>علماً بأنه قليل</font></p>
    <p align="justify"><font face="Arial"><font color="#800080">ج :</font> إن كان الماء ينتقل صح.</font></p>
    </b></td></tr><tr><td><p align="center"><font size="5">غسل الجمعة</font></p>
    <p><font color="#FF0000">س :</font> هل يجزي؟</p><p><font>ج :</font> مشكل.</p></td></tr></table></body>"""
    sections, listings, warnings = parse_chapter(qa, "3", "https://x/3.htm")
    assert [s["title"] for s in sections] == ["الطهارة"], sections
    assert sections[0]["parent_site_id"] == "3" and not warnings, warnings
    items = listings["3-s1"]
    assert [i["site_id"] for i in items] == ["3-1", "3-2"], items
    assert items[0]["question_text"] == "هل يجوز الوضوء بالثلج؟\nعلماً بأنه قليل", items[0]["question_text"]
    assert items[0]["answer_text"] == "إن كان الماء ينتقل صح.", items[0]["answer_text"]
    assert items[1]["answer_text"] == "مشكل."
    leaf = """<body><map name="m"><area href="../fehres.htm"></map><img src="a.jpg"></td></tr></table>
    <table><tr><td align="right"><p align="center" dir="rtl"><b><font color="#400080" size="6"><font face="Arial">&nbsp;</font><font size="5">الجماع</font></font></b></p>
    </td></tr><tr><td><p align="justify"><font><b><font color="#FF0000">مسألة
    10 : </font><font>الجماع يبطل الصوم.</font></b></font></p>
    <p><font color="#FF0000">مسألة 11 : </font><font>إذا شك صح صومه.</font></p></td></tr></table></body>"""
    heading, rows, children = leaf_entries(leaf, "الجماع")
    assert heading == "الجماع", heading
    assert [(r["number"], r["kind"]) for r in rows] == [(10, "rule"), (11, "rule")], rows
    assert rows[0]["body"] == "الجماع يبطل الصوم.", rows[0]["body"]
    assert children == []
    _, prose, _ = leaf_entries("<body><p>نص بلا ترقيم</p><p>تتمة</p></body>", "التوحيد")
    assert [(r["kind"], r["number"]) for r in prose] == [("intro", 0)], prose
    _, typo, _ = leaf_entries("<body><p>مسألة 1 : أ</p><p>ر مسألة 2 : ب</p><p>ممسألة 3 : ج</p></body>", "t")
    assert [r["number"] for r in typo] == [1, 2, 3], typo
    index = """<body><table><tr><td bgcolor="#800000"><p><font>&nbsp;الـعبــادات</font></td></tr></table>
    <table><tr><td><p><a href="ahkamsoum/indsoum.htm">احكام الصوم</a></td></tr></table>
    <table><tr><td><p><a href="haditha/haditha.htm">مسائل حديثة</a></td></tr></table></body>"""
    found = parse_index(index, BOOK_ROOT + "fehres.htm")
    assert found == [
        ("العبادات", BOOK_ROOT + "ahkamsoum/indsoum.htm", "احكام الصوم"),
        (None, BOOK_ROOT + "haditha/haditha.htm", "مسائل حديثة"),
    ], found
    print("mshirazi self-test ok")


if __name__ == "__main__":
    self_test()
