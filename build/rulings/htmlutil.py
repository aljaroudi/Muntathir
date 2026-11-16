"""Shared HTML walking for the fatwa scrapers."""

from __future__ import annotations

import html
import re
import urllib.parse
from typing import Iterator, Optional, Tuple

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}
DIGIT_MAP = str.maketrans("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹", "01234567890123456789")
DEFAULT_BASE = "https://www.sistani.org/"
HOST = "www.sistani.org"
ORIGIN = "https://www.sistani.org"
Event = Tuple


def parse_attrs(raw: str) -> dict:
    attrs = {}
    for match in re.finditer(
        r"""([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?""",
        raw,
    ):
        key = match.group(1).lower()
        value = next((group for group in match.groups()[1:] if group is not None), "")
        attrs[key] = (attrs.get(key, "") + " " + value).strip() if key in attrs else value
    return attrs


def class_tokens(attrs: dict) -> set:
    return set(attrs.get("class", "").split())


def walk(source: str, start: int = 0) -> Iterator[Event]:
    index = start
    length = len(source)
    while index < length:
        left = source.find("<", index)
        if left < 0:
            if index < length:
                yield ("text", source[index:], index, length)
            return
        if left > index:
            yield ("text", source[index:left], index, left)
        if source.startswith("<!--", left):
            end = source.find("-->", left + 4)
            if end < 0:
                yield ("text", source[left:], left, length)
                return
            end += 3
            yield ("comment", source[left:end], left, end)
            index = end
            continue
        right = source.find(">", left + 1)
        if right < 0:
            yield ("text", source[left:], left, length)
            return
        raw = source[left + 1:right]
        end = right + 1
        if raw.startswith("/"):
            name = raw[1:].strip().split(None, 1)[0].lower()
            yield ("end", name, left, end)
        elif raw.startswith("!") or raw.startswith("?"):
            yield ("comment", source[left:end], left, end)
        else:
            self_closing = raw.endswith("/")
            body = raw[:-1].rstrip() if self_closing else raw
            bits = body.split(None, 1)
            name = bits[0].lower()
            attr_raw = bits[1] if len(bits) > 1 else ""
            if name in VOID:
                self_closing = True
            yield ("start", name, parse_attrs(attr_raw), self_closing, left, end)
        index = end


def read_element(source: str, start: int) -> Tuple[str, dict, str, int]:
    event = next(walk(source, start))
    if event[0] != "start":
        raise ValueError("expected a start tag")
    name, attrs, self_closing = event[1], event[2], event[3]
    open_end = event[5]
    if self_closing:
        return name, attrs, "", open_end
    depth = 1
    for event in walk(source, open_end):
        if event[0] == "start" and event[1] == name and not event[3]:
            depth += 1
        elif event[0] == "end" and event[1] == name:
            depth -= 1
            if depth == 0:
                return name, attrs, source[open_end:event[2]], event[3]
    raise ValueError("unclosed <%s>" % name)


def parse_localized_int(value: Optional[str]) -> Optional[int]:
    if not value:
        return None
    numbers = re.findall(r"\d+", value.translate(DIGIT_MAP))
    if not numbers:
        return None
    return int(numbers[-1])


def absolutize(href: str, base: str = DEFAULT_BASE) -> str:
    if not href or href.startswith(("javascript:", "mailto:", "#")):
        return ""
    absolute = urllib.parse.urljoin(base, href)
    parsed = urllib.parse.urlparse(absolute)
    if parsed.netloc in ("", HOST, "sistani.org"):
        path = parsed.path or "/"
        if parsed.query:
            path += "?" + parsed.query
        return ORIGIN + path
    return absolute


def strip_colon(value: str) -> str:
    return re.sub(r"^[\s:：]+", "", value)


def html_to_text(fragment: str) -> str:
    tokens: List[str] = []
    skip = 0
    anchor_href = None
    anchor_text: List[str] = []

    def emit(text: str) -> None:
        collapsed = " ".join(text.replace("\xa0", " ").split())
        if collapsed:
            tokens.append(collapsed)

    for event in walk(fragment):
        kind = event[0]
        if kind == "start" and event[1] in ("script", "style"):
            skip += 1
            continue
        if kind == "end" and event[1] in ("script", "style") and skip:
            skip -= 1
            continue
        if skip:
            continue
        if kind == "start" and event[1] == "a":
            anchor_href = absolutize(event[2].get("href", ""))
            anchor_text = []
            continue
        if kind == "end" and event[1] == "a" and anchor_href is not None:
            text = " ".join(anchor_text).strip()
            if anchor_href and anchor_href not in text:
                text = "%s (%s)" % (text, anchor_href) if text else anchor_href
            if text:
                tokens.append(text)
            anchor_href = None
            continue
        if kind == "text":
            collapsed = " ".join(html.unescape(event[1]).replace("\xa0", " ").split())
            if not collapsed:
                continue
            if anchor_href is not None:
                anchor_text.append(collapsed)
            else:
                tokens.append(collapsed)
            continue
        if kind == "start" and event[1] == "br":
            tokens.append("\n")
            continue
        if kind == "start" and event[1] in ("p", "div", "li", "tr", "h1", "h2", "h3"):
            tokens.append("\n")
    parts: List[str] = []
    for token in tokens:
        if token == "\n":
            parts.append("\n")
        elif parts and parts[-1] != "\n":
            parts.append(" ")
            parts.append(token)
        else:
            parts.append(token)
    text = "".join(parts)
    text = re.sub(r" *\n *", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return strip_colon(text).strip()


def clean_html(fragment: str) -> str:
    pieces: List[str] = []
    skip_stack: List[str] = []

    def drop_span(attrs: dict) -> bool:
        tokens = class_tokens(attrs)
        return "nvy" in tokens or "disn" in tokens

    for event in walk(fragment):
        kind = event[0]
        if skip_stack:
            if kind == "start" and event[1] == skip_stack[-1]:
                skip_stack.append(event[1])
            elif kind == "end" and event[1] == skip_stack[-1]:
                skip_stack.pop()
            continue
        if kind == "start" and event[1] in ("script", "style"):
            skip_stack.append(event[1])
            continue
        if kind == "start" and event[1] == "span" and drop_span(event[2]):
            skip_stack.append("span")
            continue
        if kind == "start" and event[1] == "br":
            pieces.append("<br>")
            continue
        if kind == "start" and event[1] == "a":
            href = absolutize(event[2].get("href", ""))
            if href:
                pieces.append('<a href="%s">' % html.escape(href, quote=True))
            continue
        if kind == "end" and event[1] == "a":
            if pieces and pieces[-1].startswith("<a "):
                pieces.pop()
            else:
                pieces.append("</a>")
            continue
        if kind == "text":
            text = html.unescape(event[1]).replace("\xa0", " ")
            if text.strip():
                pieces.append(html.escape(" ".join(text.split())))
            elif pieces and not pieces[-1].endswith((">", "\n")):
                pieces.append(" ")
    rendered = "".join(pieces)
    rendered = re.sub(r"(?:<br>)+$", "", rendered)
    rendered = re.sub(r"^(?:<br>|\s)+", "", rendered)
    rendered = strip_colon(re.sub(r"^[\s:：]+", "", rendered))
    return rendered.strip()


def start_events(source: str) -> Iterator[Event]:
    index = 0
    while index < len(source):
        left = source.find("<", index)
        if left < 0:
            return
        event = next(walk(source, left))
        if event[0] == "start":
            yield event
            index = event[5]
        else:
            index = event[-1] if event[-1] > left else left + 1

