"""Build the Fadak reader from aligned editions, including partial source texts."""
import json
import re
from pathlib import Path

FADAK = Path(__file__).resolve().parent


def reader_text(text):
    text = re.sub(r"(?m)^\s*---\s*$", "", text)
    text = re.sub(r"(?m)^\s*(?:#{1,6} |>[ ]?)", "", text).replace("**", "").strip()
    text = re.sub(r"\b(I|me|my|he|him|his|she|her|they|them|their|we|our|us|you|your)-(?:azwj|saww|asws)\b",
                  r"\1", text, flags=re.I)
    text = re.sub(r"\b(Messenger|Prophet) \([as]\)", r"\1 ﷺ", text)
    text = re.sub(r"\b(Fatima|al-Zahra) \(a\)", r"\1 عليها السلام", text)
    for suffix, blessing in (("azwj", "ﷻ"), ("saww", "ﷺ")):
        text = re.sub(rf"-{suffix}\b", " " + blessing, text, flags=re.I)
    for names, blessing in (("Fatima|Fatimah|Zahra|Khadija|Zaynab", "عليها السلام"),
                            ("Ali|Hasan|Hassan|Husayn|Hussain", "عليه السلام"),
                            ("forefathers|Imams|Ahlulbayt", "عليهم السلام")):
        text = re.sub(rf"\b({names})-asws\b", r"\1 " + blessing, text, flags=re.I)
    if re.search(r"\b(?:azwj|saww|asws)\b", text, re.I):
        raise ValueError("Honorific needs a referent review")
    return text


# Final Arabic clause of each reading paragraph in the speech and closing elegy.
PARAGRAPH_ENDS = {6, 7, 8, 14, 23, 33, 44, 57, 69, 80, 92, 106, 114, 128,
                  143, 154, 166, 174, 176, 182, 183, 184, 188, 192, *range(193, 201)}
END_IDS = {f"s{i:03}" for i in PARAGRAPH_ENDS}


def align(rows, segments, required=(), *, basmala=None):
    """Display a range translation once, after its final Arabic segment."""
    order = {s["id"]: i for i, s in enumerate(segments)}
    covered = set()
    aligned = {}
    previous = -1
    for row in rows:
        start = order.get(row["segmentId"], -1)
        end_id = row.get("endSegmentId", row["segmentId"])
        end = order.get(end_id, -1)
        text = reader_text(row["text"])
        if start <= previous or end < start or not text:
            raise ValueError(f"Invalid translation range {row['segmentId']}–{end_id}")
        if any(s["id"] in END_IDS for s in segments[start:end]):
            raise ValueError(f"Translation crosses a paragraph boundary: {row['segmentId']}–{end_id}")
        covered.update(s["id"] for s in segments[start:end + 1])
        aligned[end_id] = text
        previous = end
    if not covered:
        raise ValueError("Translation contains no aligned passages")
    if missing := set(required) - covered:
        raise ValueError(f"Missing speech passages: {', '.join(sorted(missing))}")
    if basmala:
        # Speech coverage excludes the narrator's three intervening stage directions.
        spoken = {s["id"] for s in segments if "wikishiaIndex" in s} - {"s037", "s057", "s115"}
        if spoken - covered == {"s008"}:
            aligned["s008"] = reader_text(basmala)
    return aligned


def wikishia(segments, speech):
    wiki, = (FADAK / "data/translations").glob("en*/3.*.md")
    body = wiki.read_text().split("## ثانياً", 1)[0]
    pairs = re.findall(r"### \[(\d+)\].*?English \(WikiShia Translation\):\*\*\n> ([^\n]+)", body, re.S)
    mapping = {s["wikishiaIndex"]: s["id"] for s in segments if "wikishiaIndex" in s}
    if [int(i) for i, _ in pairs] != list(mapping) or len(mapping) != 175:
        raise ValueError("WikiShia alignment differs from the canonical speech")
    translations = {mapping[int(i)]: text for i, text in pairs}
    # The source export includes webpage prose before two quotations and two detached footnote numbers.
    translations["s144"] = "He said: O daughter" + translations["s144"].split("He said: O daughter", 1)[1]
    translations["s167"] = 'She said: "Glory be' + translations["s167"].split('and said: "Glory be', 1)[1]
    translations["s046"] = translations["s046"].replace("sustenance10", "sustenance")
    translations["s102"] = translations["s102"].replace("thing29", "thing")
    translations["s142"] = translations["s142"].removesuffix(" and knowing the betrayal which your hearts sensed.")
    # The acquisition of the mounts precedes their use. The second English sentence spans s160–s161.
    translations["s159"], translations["s160"] = translations["s160"], translations["s159"]
    translations["s160"] += " " + translations.pop("s161")
    rows = [dict(segmentId=k, text=v) for k, v in translations.items()]
    for row in rows:
        if row["segmentId"] == "s160":
            row["endSegmentId"] = "s161"
    return dict(id="en-3", language="en", kind="human", credit="Ahl al-Bayt World Assembly", aligned=align(rows, segments, speech))


def load_sermon():
    source = json.loads((FADAK / "data/segments.json").read_text())
    ids = [s["id"] for s in source]
    if len(ids) != len(set(ids)) or any(not s["arabic"].strip() for s in source):
        raise ValueError("Empty or duplicate Arabic segment")
    # s007 labels the start of the speech in the manuscript.
    # The reader ends before the later dialogue with Amir al-Mu’minin.
    segments = [s for s in source[ids.index("s006"):]
                if s["id"] != "s007" and s["sectionId"] != "05-ali-dialogue"]
    visible_ids = {s["id"] for s in segments}
    speech = {s["id"] for s in segments if "wikishiaIndex" in s}
    editions = [wikishia(segments, speech)]
    for file in sorted((FADAK / "human").glob("*.json")):
        edition = json.loads(file.read_text())
        editions.append(dict(id=edition["id"], language=edition["language"], kind="human",
                             credit=edition["credit"], aligned=align(edition["passages"], segments, basmala=edition.get("basmala"))))
    for file in sorted((FADAK / "editions").glob("*.json")):
        rows = json.loads(file.read_text())
        if any(r["source"] != "ai" or r["register"] not in ("literal", "simplified") for r in rows):
            raise ValueError(f"Unexpected machine edition in {file.name}")
        for register in ("literal", "simplified"):
            visible = [r for r in rows if r["register"] == register and r["segmentId"] in visible_ids]
            if not visible:
                continue
            editions.append(dict(id=f"{file.stem}-{register}", language=file.stem, kind=register,
                                 aligned=align(visible, segments)))
    paragraphs = []
    clauses = []
    for segment in segments:
        clauses.append(segment)
        if segment["id"] not in END_IDS:
            continue
        first = clauses[0]
        separator = "\n" if "s185" <= first["id"] <= "s192" else " "
        paragraphs.append(dict(id=first["id"], section=first["sectionId"], kind=first["kind"],
                               text=separator.join(reader_text(c["arabic"]) for c in clauses)))
        for edition in editions:
            aligned = edition["aligned"]
            pieces = [aligned.pop(c["id"]) for c in clauses if c["id"] in aligned]
            if pieces:
                aligned[first["id"]] = separator.join(pieces)
        clauses = []
    if clauses:
        raise ValueError("Unpublished Arabic clauses at end of sermon")
    return dict(id="fadak", title="خطبة الزهراء", speaker_id="fatima-al-zahra",
                source=reader_text(source[ids.index("s004")]["arabic"]),
                segments=paragraphs, editions=editions)
