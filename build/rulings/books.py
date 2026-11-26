"""Mirror Sistani's HTML fatwa books. Run python3 build/rulings/books.py before build.py."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import html
import json
import re
import sqlite3
import sys

from db import DEFAULT_DB
from htmlutil import html_to_text, read_element, walk
from sistani import ORIGIN, SiteClient, fetch_retry

LANGS = ("english", "arabic", "persian", "urdu", "azari", "turkish", "french")
MIRROR = DEFAULT_DB
NUMBER = r"\d+(?:\s*[–‑-]\s*\d+)?[a-z]?"
RULE = re.compile(r"^(?P<label>(?:\[\s*\d+\s*\]\s*)?[(\[]?(?:ruling|issue|rule|(?:ال)?مسـ*[أئ]ل[هةہ](?:\s+نمبر)?|مساله|م\s*ـ+|hüküm|məsələ|mesele|article)\s*[:(（]?\s*(?P<num>" + NUMBER + r")[)）.:۔*ـ-]*)\s*", re.I)
REVERSED_RULE = re.compile(r"^(?P<label>(?P<num>\d+)\.\s*Mesele\s*:)[ \t]*", re.I)
QUESTION = re.compile(r"^(?:question|(?:ال)?سؤال|(?:ال)?سوال|پرسش|sual|soru)\s*(?P<num>\d+)?\s*\.?[:：]\s*", re.I)
ANSWER = re.compile(r"^(?:answer|(?:ال)?جواب|(?:ال)?إجابة|پاسخ|cavab|cevap|réponse)\s*[:：]\s*", re.I)
INTRO = re.compile(r"introduct|foreword|preface|مقد[ّ]?م|پیش[‌]*گفتار|تمهيد|تمہید|préface|giriş", re.I)


def links(source, path):
    found = {}
    for event in walk(source):
        if event[:2] == ("start", "a") and re.fullmatch(path, event[2].get("href", "")):
            href = event[2]["href"]
            title = html_to_text(read_element(source, event[4])[2])
            if title:
                found.setdefault(href, title)
    return found


def entries(text, title):
    result = []
    current = None
    if not text.strip() and title.strip():
        return [dict(kind="intro", number=0, label="", prompt="", body=title)]
    for line in text.strip().splitlines():
        line = line.strip()
        line = line.lstrip("\u200c\u200d\u200e\u200f")
        rule = RULE.match(line) or REVERSED_RULE.match(line)
        question = QUESTION.match(line[rule.end():] if rule else line)
        answer = ANSWER.match(line)
        if not answer and current and current["kind"] == "rule" and current["label"]:
            if any("؟" in paragraph for paragraph in current["body"]):
                answer = re.match(r"^ج\s*[ـ/]+\s*", line)
        if answer:
            if current is None:
                raise ValueError("unpaired answer marker")
            if current["kind"] == "rule" and current["label"]:
                current["kind"] = "qa"
                current["prompt"], current["body"] = current["body"], []
            if current["kind"] != "qa":
                raise ValueError("unpaired answer marker")
            if not current["answered"]:
                current["answered"] = True
                line = line[answer.end():]
            # Later answer markers belong to lettered subquestions of this same ruling.
        elif rule or question or line.startswith("Case:") or current is None:
            if rule:
                line = line[rule.end():]
            number = int(re.match(r"\d+", rule["num"])[0]) if rule else None
            label = rule["label"] if rule else ""
            if question and question["num"]:
                number = int(question["num"])
                label = question["num"]
            current = dict(kind="qa" if question else "rule", number=number, label=label,
                           prompt=[], body=[], answered=False)
            result.append(current)
            if question:
                line = line[question.end():]
        target = current["prompt"] if current["kind"] == "qa" and not current["answered"] else current["body"]
        target.append(line)
    if result and not result[0]["label"] and result[0]["kind"] == "rule" and (INTRO.search(title) or (len(result) > 1 and not text.lstrip().startswith("Case:"))):
        result[0].update(kind="intro", number=0)
    for position, entry in enumerate(result, 0 if result and result[0]["kind"] == "intro" else 1):
        if entry["number"] is None:
            entry["number"] = position
        entry.pop("answered")
        for field in ("prompt", "body"):
            entry[field] = "\n".join(entry[field]).strip()
        if entry["kind"] == "qa" and not (entry["prompt"] and entry["body"]):
            raise ValueError("incomplete " + entry["kind"])
    return result


def mark_dialogue(text, edition):
    # These editions print speaker names or a star and dash in place of Q&A labels.
    if edition in {"49", "19"}:
        speaker = re.compile(r"^\*\s*")
        respondent = re.compile(r"^[-ـ]+\s*")
    elif edition in {"26927", "25936", "25583", "25685"}:
        speaker = re.compile(r"^(?:Faṭimah|فاطمه|Fatıma|Fatimə)\s*:")
        respondent = re.compile(r"^(?:Mother|مادر|Anne|Ana)\s*:")
    else:
        return text
    lines = text.splitlines()
    pending = None
    for index, line in enumerate(lines):
        if speaker.match(line):
            pending = index
        elif pending is not None and respondent.match(line):
            lines[pending] = "Question: " + lines[pending]
            lines[index] = "Answer: " + line
            pending = None
    return "\n".join(lines)


NOTE_MARKER = re.compile(r"\[\s*(\d+)\s*\]|\(\s*(\d+)\s*\)")


def numbered_notes(text, rows):
    references = {}
    for index, row in enumerate(rows):
        for marker in NOTE_MARKER.finditer(row["prompt"] + "\n" + row["body"]):
            key = (marker.lastindex, int(marker[marker.lastindex]))
            references.setdefault(key, set()).add(index)
    definition = re.compile(r"(?m)^[ \t]*(?P<label>\[\s*\d+\s*\]|\(\s*\d+\s*\)|\d+(?:[ \t]*[.])?(?=[ \t]))")
    starts = list(definition.finditer(text))
    result = []
    preface = text[:starts[0].start()].strip() if starts else text.strip()
    if preface:
        result.append(("", preface, ()))
    for i, start in enumerate(starts):
        label = start["label"]
        number = int(re.search(r"\d+", label)[0])
        marker = NOTE_MARKER.fullmatch(label)
        owners = references.get((marker.lastindex, number), set()) if marker else set()
        if not owners:
            owners = references.get((1, number), set()) | references.get((2, number), set())
        end = starts[i + 1].start() if i + 1 < len(starts) else len(text)
        result.append((label, text[start.end():end].strip(), sorted(owners)))
    return result


def parse_page(source, title, edition=None, *, separate_notes=False):
    body = None
    footnotes = ""
    for event in walk(source):
        if event[0] != "start":
            continue
        classes = event[2].get("class", "").split()
        if "book-text" in classes:
            fragment = read_element(source, event[4])[2]
            # Several introductions are facsimiles with an official text alternative.
            for tag in reversed(list(walk(fragment))):
                if tag[:2] == ("start", "img"):
                    fragment = fragment[:tag[4]] + html.escape(html.unescape(tag[2].get("alt", ""))) + fragment[tag[5]:]
            body = html_to_text(fragment)
        elif "book-footnote" in classes:
            footnotes = html_to_text(read_element(source, event[4])[2])
    if body is None:
        raise ValueError("missing book-text")
    rows = entries(mark_dialogue(body, edition), title)
    if separate_notes:
        return rows, numbered_notes(footnotes, rows)
    if footnotes and rows:
        # Earlier packs hashed the rendered body, including appended notes, for unnumbered rules.
        legacy_bodies = [row["body"] for row in rows]
        for note in filter(str.strip, re.split(r"(?m)(?=^\[\d+\])", footnotes)):
            ref = re.match(r"\[\d+\]", note)
            owners = [i for i, row in enumerate(rows) if ref and ref[0] in row["prompt"] + legacy_bodies[i]]
            for i in owners or [len(rows) - 1]:
                legacy_bodies[i] += "\n\n" + note.strip()
        for row, legacy in zip(rows, legacy_bodies):
            if not row["label"] and row["kind"] == "rule" and legacy != row["body"]:
                row["identity_digest"] = hashlib.sha256(legacy.encode()).hexdigest()[:20]
        for label, body, owners in numbered_notes(footnotes, rows):
            for i in owners or [0]:
                rows[i].setdefault("footnotes", []).append(dict(label=label, body=body, chapter=not owners))
    return rows


def ensure_mirror(db):
    db.execute("""CREATE TABLE IF NOT EXISTS book_edition
        (authority TEXT, language TEXT, site_id TEXT, title TEXT, url TEXT, chapters TEXT,
         position INTEGER NOT NULL DEFAULT 1, PRIMARY KEY(authority,language,site_id))""")


def crawl(db, langs, book):
    client = SiteClient(0.15)

    def get(path):
        url = ORIGIN + path
        response = fetch_retry(client, url)
        if response.status != 200 or response.url != url:
            raise ValueError("unexpected response for " + url)
        return response.text

    ensure_mirror(db)
    failures = []
    with ThreadPoolExecutor(max_workers=4) as pool:
        for lang in langs:
            catalog = links(get(f"/{lang}/book/fatwa/"), rf"/{lang}/book/\d+/")
            if not catalog:
                failures.append(f"{lang}: no HTML book catalog")
            for position, (path, title) in enumerate(catalog.items(), 1):
                key = path.split("/")[-2]
                if book and key != book:
                    continue
                try:
                    toc = links(get(path), path + r"\d+/")
                    if not toc:
                        raise ValueError("no HTML chapters")
                    def chapter(item):
                        href, heading = item
                        try:
                            raw = get(href)
                            rows = parse_page(raw, heading, key)
                            return dict(id=href.split("/")[-2], title=heading, url=ORIGIN+href, raw=raw, entries=rows, notes_parsed=True)
                        except Exception as exc:
                            raise ValueError(f"{href}: {exc}") from exc
                    chapters = list(pool.map(chapter, toc.items()))
                    with db:
                        db.execute("INSERT OR REPLACE INTO book_edition(authority,language,site_id,title,url,chapters,position) VALUES (?,?,?,?,?,?,?)",
                                   ("sistani", lang, key, title, ORIGIN+path, json.dumps(chapters, ensure_ascii=False),position))
                    print(path, len(chapters), flush=True)
                except Exception as exc:
                    failures.append(f"{path}: {exc}")
                    print(failures[-1], file=sys.stderr, flush=True)
    return failures


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--language", action="append", choices=LANGS)
    cli.add_argument("--book")
    args = cli.parse_args()
    with sqlite3.connect(MIRROR) as database:
        sys.exit(bool(crawl(database, args.language or LANGS, args.book)))
