"""Edition-specific, reading boundaries for the large OpenITI collections."""
from __future__ import annotations

import bisect
import html
import re

PAGE = re.compile(r"PageV([0-9]+|0M)P([0-9]+)")


def clean(text: str) -> str:
    text = re.sub(r"(?m)^~~", "", text)
    text = re.sub(r"<[^>]*>", "", text, flags=re.S)
    text = html.unescape(text)
    text = PAGE.sub("", text)
    text = re.sub(r"NoteV\w+P\d+N\d+|\bms\d+\b", "", text)
    text = re.sub(r"(?m)^#{1,5}\s*\|*\s*", "", text)
    return re.sub(r"[ \t]+", " ", text).strip()


def parse(text: str, edition: str) -> list[dict]:
    if edition not in {"wasail", "bihar"}:
        raise ValueError(f"Unsupported narration parser: {edition}")
    body = text.split("#META#Header#End#", 1)[1].split("#####ENDNOTES#", 1)[0]
    body = body.replace("~~", "  ")
    body = re.sub(r"\bms\d+\b", lambda m: " " * len(m[0]), body)
    pages = list(PAGE.finditer(body))
    if not pages:
        raise ValueError("This edition requires printed page markers")
    ends = [m.start() for m in pages]

    def location(offset: int) -> tuple[int, str]:
        # OpenITI page markers terminate the printed page, rather than starting it.
        marker = pages[min(bisect.bisect_left(ends, offset), len(pages) - 1)]
        return int(marker[1]) if marker[1].isdigit() else 1, marker[0]

    # Delimiters are discovered in the original text, retaining offsets for provenance.
    events: list[tuple[int, int, str, str, int | None]] = []
    if edition == "wasail":
        heading = re.compile(r"(?m)^#\s*(?:(?:أبواب|كتاب)\s+[^\n]*?\s+)?(\d+\s*-\s*باب\s+)")
        for m in heading.finditer(body):
            events.append((m.start(), m.end(), "heading", m[0], None))
        # Global edition numbers occur as Note tags, brackets or parentheses; local
        # chapter numbers follow them. Preserve the printed global number verbatim.
        numbered = re.compile(r"(?:NoteV\w+P\d+N(?P<note>\d+)|\[(?P<bracket>\d+)(?:\s*و\s*\d+)*\]|\((?P<paren>\d{3,})(?:\s*و\s*\d+)*\))\s*(?:~~\s*)?(?:\d+(?:\s*و\s*\d+)*\s*)?[-–]")
        for m in numbered.finditer(body):
            number = int(m['note'] or m['bracket'] or m['paren'])
            events.append((m.start(), m.end(), "entry", "", number))
    else:
        for m in re.finditer(r"(?m)^###\s*\|+\s*", body):
            events.append((m.start(), m.end(), "heading", "", None))
        for m in re.finditer(r"(?m)^#\s*(\d+)\s*[-–]\s*", body):
            events.append((m.start(), m.end(), "entry", "", int(m[1])))

    # Split at the start of each printed volume, including volumes of indexes.
    previous = None
    for index, marker in enumerate(pages):
        volume = marker[1]
        if previous is not None and volume != previous and volume != "0M":
            offset = pages[index - 1].end()
            events.append((offset, offset, "volume", "", None))
        previous = volume
    events.sort()
    records: list[dict] = []
    chapter = 0
    title = "المقدمة"
    pending = ""
    active = None
    seen: set[int] = set()
    started = False

    def emit():
        nonlocal active
        if active and active['text'].strip():
            active['text'] = clean(active['text'])
            if active['text']:
                records.append(active)
        active = None

    def append_text(text: str):
        nonlocal active, pending
        if active:
            active['text'] += text
        else:
            pending += text

    # Keep the author/editor's opening material, without assigning a narration number.
    pending = body[:events[0][0]] if events else body
    pending_offset = 0
    for i, (start, end, kind, prefix, number) in enumerate(events):
        next_start = events[i + 1][0] if i + 1 < len(events) else len(body)
        fragment = body[end:next_start]
        volume, page = location(end)
        if kind == "volume":
            emit()
            if clean(pending):
                old_volume, old_page = location(pending_offset)
                records.append(dict(volume=old_volume, chapter=chapter, title=title,
                                    number=0, text=clean(pending), page=old_page))
            pending = fragment
            pending_offset = end
            chapter += 1
            seen = set()
        elif kind == "heading":
            # Keep organizational headings with no body as context for the next
            # section, rather than silently discarding their text.
            parent_title = title + "\n" if chapter and not active and not clean(pending) else ""
            emit()
            if clean(pending):
                old_volume, old_page = location(pending_offset)
                records.append(dict(volume=old_volume, chapter=chapter, title=title,
                                    number=0, text=clean(pending), page=old_page))
            pending = ""
            chapter += 1
            seen = set()
            started = True
            # A heading occupies its logical line and ~~ continuations, ending at
            # the next paragraph. Some Bihar headings include an inline Quran preface.
            split = re.search(r"\n#\s|\nPageV", fragment)
            heading_end = split.start() if split else len(fragment)
            embedded = re.search(r"\s+(?:\(\d{3,}\)\s*)?\d+\s*[-–]\s+", fragment[:heading_end])
            if embedded:
                heading_end = embedded.start()
            raw_title = clean(prefix + fragment[:heading_end])
            # Bihar embeds prose immediately after a parenthesized chapter title.
            close = re.search(r"\)\s*\*+\s+", raw_title)
            if edition == "bihar" and close:
                pending = raw_title[close.end():] + "\n"
                raw_title = raw_title[:close.end()]

            inline = re.search(r"\s+(?:الآيات|الايات)[،,:\s]", raw_title)
            if inline:
                pending += raw_title[inline.start():] + "\n"
                raw_title = raw_title[:inline.start()]
            if raw_title.startswith("بسم الله الرحمن الرحيم"):
                pending = raw_title + "\n" + pending
                raw_title = "المقدمة"
            title = raw_title.strip(" *()[]|.\n") or "مقدمة"
            pending = parent_title + pending + fragment[heading_end:]
            pending_offset = end + heading_end
        elif not started or number in seen:
            # Numbered lists in introductions or repeated numbers in commentary
            # remain text; never manufacture another narration identity for them.
            append_text(body[start:next_start])
        else:
            emit()
            seen.add(number)
            active = dict(volume=volume, chapter=chapter, title=title, number=number,
                          text=pending + body[start:end] + fragment, page=page)
            pending = ""
    emit()
    if clean(pending):
        volume, page = location(pending_offset)
        records.append(dict(volume=volume, chapter=chapter, title=title, number=0,
                            text=clean(pending), page=page))
    return records
