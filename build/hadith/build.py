#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# ///
"""Build read-only hadith SQLite databases from the local source folders.

Outputs:
  build/hadith/dist/hadith.db
  Sources live in build/hadith/data; schema is schema.sql.

Usage:
  uv run build/hadith/build.py
  uv run build/hadith/build.py --sittah   # Kutub al-Sittah + Shia only
  uv run build/hadith/build.py --sittah --four  # Six Books + Four Books + Nahj al-Balagha
"""

from __future__ import annotations

import argparse
import csv
import unicodedata
import json
import re
import sqlite3
import sys
import zlib
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
DATA = HERE / "data"
DIST = HERE / "dist"
DATA_PATH = ROOT / "temp/hadith-data"
ADDITIONAL_PATH = ROOT / "temp/additional-books"

# The Six Books (الكتب الستة). Used only when --sittah is passed.
SITTAH_BOOKS = frozenset(
    {"bukhari", "muslim", "abudawud", "tirmidhi", "nasai", "ibnmajah"}
)

# Canonical source names, with volume suffixes removed.
FOUR_BOOKS = frozenset({
    "Al-Kafi-Kulayni",
    "Man-La-Yahduruh-al-Faqih-Saduq",
    "Tahdhib-al-Ahkam-Tusi",
    "Al-Istibsar-Tusi",
})
FOUR_BASE_BOOKS = frozenset(f"alkafi-{v}" for v in range(1, 9))
FOUR_ADDITIONAL_BOOKS = FOUR_BOOKS | {"Nahj-al-Balagha-Radi"}


WENSINCK_BOOKS = {
    "bukhari": "خ",
    "muslim": "م",
    "abudawud": "د",
    "tirmidhi": "ت",
    "nasai": "ن",
    "ibnmajah": "جه",
    "ahmed": "حم",
    "malik": "ط",
    "darimi": "دي",
}
EXTRA_BOOK_ABBR = {
    "aladab_almufrad": "أدب",
    "bulugh_almaram": "بلغ",
    "mishkat_almasabih": "مشك",
    "musannaf_ibnabi_shaybah": "مصن",
    "nawawi40": "نو٤٠",
    "qudsi40": "قد٤٠",
    "riyad_assalihin": "رياض",
    "shahwaliullah40": "شاه",
    "shamail_muhammadiyah": "شمائل",
}
ALL_BOOK_ABBR = {**WENSINCK_BOOKS, **EXTRA_BOOK_ABBR}
SIGLUM_TO_BOOK = {v: k for k, v in ALL_BOOK_ABBR.items()}

# Diacritics / tatweel ranges matching build/quran/build.sh `norm`.
_STRIP_RANGES = (
    range(0x610, 0x61B),
    (0x640,),
    range(0x64B, 0x660),
    (0x670,),
    range(0x6D6, 0x6EE),
)
_STRIP = {chr(c) for r in _STRIP_RANGES for c in r}
_ALEF_MAP = str.maketrans(
    {
        "\u0622": "ا",  # آ
        "\u0623": "ا",  # أ
        "\u0625": "ا",  # إ
        "\u0671": "ا",  # ٱ
        "ى": "ي",
        "ة": "ه",
    }
)
_TOKEN_SPLIT = re.compile(r"[\s\u060c\u061b\u061f\u066a-\u066d\u06d4,.;:!?\"'()\[\]{}<>/\\|_+=*&^%$#@~`]+")


def norm(text: str) -> str:
    if not text:
        return ""
    out = "".join(ch for ch in text if ch not in _STRIP)
    return out.translate(_ALEF_MAP)


class HadithDirectory:
    def __init__(self, path: Path) -> None:
        self.path = path

    def read_json(self, rel: str):
        return json.loads((self.path / rel).read_bytes())

    def exists(self, rel: str) -> bool:
        return (self.path / rel).is_file()

    def list_prefix(self, rel_dir: str) -> list[str]:
        return sorted(str(p.relative_to(self.path)) for p in (self.path / rel_dir).rglob("*") if p.is_file())


class RefResolver:
    """Map hadith references onto surrogate hadith.id values."""

    def __init__(self, loaded_books: set[str] | None = None) -> None:
        # (book, chapter_idx, id_in_book) -> hadith_id
        self.exact: dict[tuple[str, int, int], int] = {}
        # (book, id_in_book) -> first hadith_id by chapter order
        self.by_iib: dict[tuple[str, int], int] = {}
        self.loaded_books = loaded_books  # None = all books in scope
        self.stats: Counter[str] = Counter()

    def _in_scope(self, book: str) -> bool:
        return self.loaded_books is None or book in self.loaded_books

    def register(self, hadith_id: int, book_id: str, chapter_idx: int, id_in_book: int) -> None:
        self.exact[(book_id, chapter_idx, id_in_book)] = hadith_id
        key = (book_id, id_in_book)
        if key not in self.by_iib:
            self.by_iib[key] = hadith_id

    def resolve(self, ref: str, source: str) -> int | None:
        ref = (ref or "").strip()
        if not ref:
            self.stats[f"{source}:empty"] += 1
            return None
        parts = ref.split(":")
        try:
            if len(parts) == 3:
                book, ch, iib = parts[0], int(parts[1]), int(parts[2])
                hid = self.exact.get((book, ch, iib))
            elif len(parts) == 2:
                book, iib = parts[0], int(parts[1])
                hid = self.by_iib.get((book, iib))
            else:
                self.stats[f"{source}:bad_shape"] += 1
                return None
        except ValueError:
            self.stats[f"{source}:bad_int"] += 1
            return None
        if not self._in_scope(book):
            self.stats[f"{source}:skip"] += 1
            return None
        if hid is None:
            self.stats[f"{source}:miss"] += 1
            return None
        self.stats[f"{source}:ok"] += 1
        return hid

    def resolve_wensinck(self, siglum: str, ref: str, source: str = "wensinck") -> int | None:
        book = SIGLUM_TO_BOOK.get(siglum)
        if not book:
            self.stats[f"{source}:bad_siglum"] += 1
            return None
        if not self._in_scope(book):
            self.stats[f"{source}:skip"] += 1
            return None
        parts = ref.split(":")
        if len(parts) != 2:
            self.stats[f"{source}:bad_shape"] += 1
            return None
        try:
            ch, iib = int(parts[0]), int(parts[1])
        except ValueError:
            self.stats[f"{source}:bad_int"] += 1
            return None
        hid = self.exact.get((book, ch, iib))
        if hid is None:
            self.stats[f"{source}:miss"] += 1
            return None
        self.stats[f"{source}:ok"] += 1
        return hid

    def assert_ok(self, source: str, min_rate: float = 0.99) -> None:
        related = {k: v for k, v in self.stats.items() if k.startswith(f"{source}:")}
        ok = related.get(f"{source}:ok", 0)
        skip = related.get(f"{source}:skip", 0)
        # Skips (out-of-scope books under --sittah) do not count against the rate.
        scored = sum(v for k, v in related.items() if not k.endswith(":skip"))
        if scored == 0:
            print(f"  ref {source}: no in-scope attempts (skipped={skip})")
            return
        rate = ok / scored
        print(f"  ref {source}: {ok}/{scored} ({rate:.2%}) skipped={skip} {dict(related)}")
        if rate < min_rate:
            raise SystemExit(f"Reference resolution for {source} below {min_rate:.0%}: {rate:.2%}")


def connect(path: Path) -> sqlite3.Connection:
    if path.exists():
        path.unlink()
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    db.execute("PRAGMA foreign_keys = ON")
    db.execute("PRAGMA journal_mode = DELETE")
    db.execute("PRAGMA synchronous = OFF")
    db.execute("PRAGMA temp_store = MEMORY")
    db.execute("PRAGMA cache_size = -200000")
    return db


def apply_schema(db: sqlite3.Connection, sql_path: Path) -> None:
    db.executescript(sql_path.read_text(encoding="utf-8"))


def english_parts(english) -> tuple[str, str]:
    if isinstance(english, dict):
        return str(english.get("narrator") or ""), str(english.get("text") or "")
    if isinstance(english, str):
        return "", english
    return "", ""


# Allowed graders only; English/Arabic names are the canonical display labels.
GRADERS = {
    'behbudi': ('البهبودي', 'Shaykh Baqir al-Behbudi'),
    'mohseni': ('المحسني', 'Shaykh Asif al-Mohseni'),
    'ghaffari': ('الغفاري', 'Ali Akbar al-Ghaffari'),
}
GRADER_ALIASES = {name.casefold(): key for key, names in GRADERS.items() for name in (key, *names) if name}
GRADER_ALIASES['behdudi'] = 'behbudi'
def grade_key(text: str) -> str:
    text = unicodedata.normalize('NFKD', text)
    text = ''.join(c for c in text if not unicodedata.combining(c))
    return ' '.join(text.casefold().translate(str.maketrans({"’": "'", "`": "'", "ی": "ي"})).split())


def load_grade_labels(path: Path) -> dict[str, tuple[str, str]]:
    groups: dict[str, set[tuple[str, str]]] = defaultdict(set)
    with path.open(encoding='utf-8', newline='') as handle:
        for row in csv.DictReader(handle):
            labels = ((row.get('label_en') or '').strip(), (row.get('label_ar') or '').strip())
            if not any(labels):
                continue
            for raw in (row.get('grade') or '', *labels):
                key = grade_key(raw)
                if key:
                    groups[key].add(labels)
    return {key: next(iter(labels)) for key, labels in groups.items() if len(labels) == 1}


GRADE_LABELS = load_grade_labels(DATA / 'grade-labels.csv')


def clean_grading(value: str) -> str:
    return ' '.join(unicodedata.normalize('NFC', value).split())


def grading_language(value: str) -> str:
    return 'ar' if re.search(r'[\u0600-\u06ff]', value) else 'en'


class GradingImporter:
    def __init__(self, db: sqlite3.Connection):
        self.db = db
        self.unparsed: Counter[str] = Counter()
        self.input_count = 0
        self.output_count = 0

    def grader(self, name_en: str = '', name_ar: str = '') -> str | None:
        """Return canonical grader id, or None if unnamed/unknown (unknown is ignored)."""
        name_en, name_ar = clean_grading(name_en), clean_grading(name_ar)
        if not (name_en or name_ar):
            return None
        key = GRADER_ALIASES.get(name_en.casefold()) or GRADER_ALIASES.get(name_ar.casefold())
        if not key:
            return None
        name_ar, name_en = GRADERS[key]
        self.db.execute('INSERT INTO grader VALUES (?, ?, ?) ON CONFLICT(id) DO NOTHING',
                        (key, name_ar, name_en))
        return key

    def parse(self, value: str | dict, grader: str = '') -> dict | None:
        if not value:
            return None
        if grader:
            grader_id = self.grader(grader)
            if grader_id is None:
                return None  # named but not in the allowlist
        else:
            grader_id = None
        result = dict(grader_id=grader_id, grade_ar='', grade_en='',
                      reference_ar='', reference_en='', status='judgment')
        original = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, sort_keys=True)
        result['originals'] = [original]
        if isinstance(value, dict):
            author = value.get('author') or {}
            if author:
                name_en, name_ar = author.get('name_en') or '', author.get('name_ar') or ''
                if name_en or name_ar:
                    result['grader_id'] = self.grader(name_en, name_ar)
                    if result['grader_id'] is None:
                        return None
            for field in ('grade_ar', 'grade_en', 'reference_ar', 'reference_en'):
                result[field] = clean_grading(value.get(field) or '')
            if not (result['grade_ar'] or result['grade_en']):
                text = value.get('grade') or value.get('grade_app') or ''
                result['grade_' + grading_language(text)] = clean_grading(text)
            if value.get('source') and not (result['reference_ar'] or result['reference_en']):
                result['reference_' + grading_language(value['source'])] = clean_grading(value['source'])
        else:
            text = value.strip()
            attribution, separator, rest = text.partition(':')
            if separator and attribution.casefold() in GRADER_ALIASES:
                result['grader_id'] = self.grader(attribution)
                text = rest.strip()
            elif separator and attribution.strip():
                return None  # named attribution outside the allowlist
            parts = re.split(r'\n\s*[-–—]\s*', text, maxsplit=1)
            text = clean_grading(parts[0])
            if len(parts) == 2:
                reference = clean_grading(parts[1])
                result['reference_' + grading_language(reference)] = reference
            result['grade_' + grading_language(text)] = text
        self.input_count += 1
        found = None
        for field, index in (('grade_en', 0), ('grade_ar', 1)):
            labels = GRADE_LABELS.get(grade_key(result[field]))
            if not labels:
                continue
            result[field] = labels[index]
            found = labels
        if found:
            if not result['grade_en']:
                result['grade_en'] = found[0]
            if not result['grade_ar']:
                result['grade_ar'] = found[1]
        judgments = [result[k] for k in ('grade_ar', 'grade_en') if result[k]]
        if judgments and all(v.casefold() in ('not included', 'لم يخرجه') for v in judgments):
            result.update(status='not_included', grade_ar='', grade_en='')
        elif not judgments or any(v.isdecimal() for v in judgments):
            result['status'] = 'unparsed'
        if result['status'] == 'unparsed':
            result.update(grade_ar='', grade_en='')
            self.unparsed[original] += 1
        return result

    @staticmethod
    def same_assessment(left: dict, right: dict) -> bool:
        if left['status'] != right['status']:
            return False
        # An unattributed summary can duplicate a richer assessment, never overwrite one.
        if left['grader_id'] and right['grader_id'] and left['grader_id'] != right['grader_id']:
            return False
        fields = ('grade_ar', 'grade_en', 'reference_ar', 'reference_en')
        if any(left[k] and right[k] and left[k] != right[k] for k in fields):
            return False
        return left['status'] == 'not_included' or any(
            left[k] and left[k] == right[k] for k in ('grade_ar', 'grade_en'))

    def add(self, hadith_id: int, row: dict, external: list[tuple[str, str | dict]] | None = None) -> None:
        candidates = []
        for value in row.get('gradingsFull') or []:
            candidates.append((value, ''))
        for grader, field in (('behbudi', 'behbudiGrading'), ('behbudi', 'behdudiGrading'),
                              ('mohseni', 'mohseniGrading')):
            if row.get(field):
                candidates.append((row[field], grader))
        candidates.extend((value, grader) for grader, value in (external or []))
        if row.get('grade'):
            candidates.append((row['grade'], ''))
        records = []
        for value, grader in candidates:
            record = self.parse(value, grader)
            if record is None:
                continue
            identity = ('grader_id', 'grade_ar', 'grade_en', 'reference_ar', 'reference_en', 'status')
            exact = [r for r in records if all(r[k] == record[k] for k in identity)
                     and (record['status'] != 'unparsed' or r['originals'] == record['originals'])]
            matches = exact or [r for r in records if self.same_assessment(r, record)]
            if len(matches) == 1:
                match = matches[0]
                for key in ('grader_id', 'grade_ar', 'grade_en', 'reference_ar', 'reference_en'):
                    match[key] = match[key] or record[key]
                match['originals'] = list(dict.fromkeys(match['originals'] + record['originals']))
            else:
                records.append(record)
        for record in records:
            self.db.execute('''INSERT INTO hadith_grading
                (hadith_id, grader_id, grade_ar, grade_en, reference_ar, reference_en, status, original_text)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
                (hadith_id, *(record[k] for k in ('grader_id', 'grade_ar', 'grade_en', 'reference_ar', 'reference_en', 'status')),
                 '\n\n'.join(record['originals'])))
        self.output_count += len(records)

    def report(self) -> None:
        print(f'  gradings: {self.input_count} inputs -> {self.output_count} records; '
              f'{sum(self.unparsed.values())} unparsed inputs retained')
        for text, count in self.unparsed.most_common(5):
            print(f'    unparsed ({count}): {text[:180]!r}')


def load_books_chapters_hadiths(
    z: HadithDirectory,
    db: sqlite3.Connection,
    resolver: RefResolver,
    *,
    sittah: bool = False,
    four: bool = False,
) -> tuple[int, int]:
    books = z.read_json("books.json")
    book_rows: list[tuple] = []
    sort_order = 0
    collections: dict[str, tuple] = {}

    def add_book(meta: dict, sect: str, group: str) -> None:
        nonlocal sort_order
        collection_id = meta["id"]
        name_ar, name_en = meta.get("name_ar") or "", meta.get("name_en") or ""
        if collection_id.startswith("alkafi-"):
            collection_id, name_ar, name_en = "alkafi", "الكافي", "Al-Kafi"
        elif collection_id.startswith("uyun-rida-"):
            collection_id, name_ar, name_en = "uyun-rida", "عيون أخبار الرضا", "Uyun Akhbar al-Rida"
        collections.setdefault(collection_id, (collection_id, name_ar, name_en, sort_order))
        book_rows.append(
            (
                meta["id"],
                sect,
                group,
                meta.get("name_ar") or "",
                meta.get("name_en") or "",
                meta.get("author"),
                meta.get("died"),
                1 if meta.get("graded") else 0,
                meta.get("volume"),
                ALL_BOOK_ABBR.get(meta["id"]),
                sort_order,
                collection_id,
            )
        )
        sort_order += 1

    for group in ("the_9_books", "forties", "other_books"):
        for meta in books["sunni"][group]:
            if sittah and meta["id"] not in SITTAH_BOOKS:
                continue
            add_book(meta, "sunni", group)
    for meta in books["shia"]:
        if four and meta["id"] not in FOUR_BASE_BOOKS:
            continue
        add_book(meta, "shia", "shia")
    if sittah:
        print(f"  --sittah: sunni limited to {sorted(SITTAH_BOOKS)}")

    db.executemany("INSERT INTO collection VALUES (?, ?, ?, ?)", collections.values())
    db.executemany(
        """
        INSERT INTO book (
          id, sect, book_group, name_ar, name_en, author, died, graded, volume, siglum, sort_order, collection_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        book_rows,
    )

    chapter_id = 0
    hadith_id = 0
    chapter_rows: list[tuple] = []
    hadith_rows: list[tuple] = []
    grading_importer = GradingImporter(db)
    grading_rows: list[tuple[int, dict, list]] = []
    sunni_count = 0
    shia_count = 0

    for book_id, sect, *_rest in ((r[0], r[1]) for r in book_rows):
        rel_index = f"{sect}/{book_id}/index.json"
        if not z.exists(rel_index):
            print(f"  missing index: {rel_index}")
            continue
        chapters = z.read_json(rel_index)
        # Retain each source assessment and its identifiable attribution.
        grade_map: dict[str, list] = defaultdict(list)
        rel_g = f"{sect}/{book_id}/grades.json"
        if z.exists(rel_g):
            raw = z.read_json(rel_g)
            if isinstance(raw, dict):
                for key, value in raw.items():
                    grade_map[str(key)].append(('', value))

        for ch_idx, ch in enumerate(chapters):
            file_name = ch.get("file") or f"{ch_idx + 1}.json"
            chapter_id += 1
            chapter_rows.append(
                (
                    chapter_id,
                    book_id,
                    ch_idx,
                    file_name,
                    ch.get("name_ar") or "",
                    ch.get("name_en") or "",
                    int(ch.get("count") or 0),
                )
            )
            rel = f"{sect}/{book_id}/{file_name}"
            if not z.exists(rel):
                print(f"  missing chapter: {rel}")
                continue
            hadiths = z.read_json(rel)
            for h in hadiths:
                iib = h.get("idInBook")
                if iib is None:
                    iib = h.get("hadithNumber")
                if iib is None:
                    iib = h.get("id")
                if iib is None:
                    continue
                iib = int(iib)
                source_id = h.get("id")
                if source_id is None:
                    source_id = h.get("hadithNumber")
                narrator, text = english_parts(h.get("english"))
                arabic = h.get("arabic") or ""
                hadith_id += 1
                hadith_rows.append(
                    (
                        hadith_id,
                        book_id,
                        chapter_id,
                        ch_idx,
                        iib,
                        int(source_id) if source_id is not None else None,
                        arabic,
                        narrator,
                        text,
                        h.get("url") or "",
                    )
                )
                resolver.register(hadith_id, book_id, ch_idx, iib)
                if sect == "sunni":
                    sunni_count += 1
                else:
                    shia_count += 1
                grading_rows.append((hadith_id, h, grade_map.get(str(iib), [])))

    if chapter_rows:
        db.executemany(
            """
            INSERT INTO chapter (
              id, book_id, chapter_idx, file_name, name_ar, name_en, hadith_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            chapter_rows,
        )
    if hadith_rows:
        db.executemany(
            """
            INSERT INTO hadith (
              id, book_id, chapter_id, chapter_idx, id_in_book, source_id,
              arabic, english_narrator, english_text, url
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            hadith_rows,
        )
    for hid, row, external in grading_rows:
        grading_importer.add(hid, row, external)
    grading_importer.report()
    print(f"  books={len(book_rows)} chapters={chapter_id} hadiths sunni={sunni_count} shia={shia_count}")
    return sunni_count, shia_count


def ensure_root(db: sqlite3.Connection, root: str, **fields) -> None:
    if not root:
        return
    db.execute(
        """
        INSERT INTO root (
          root, buckwalter, definition_en, summary_en, quran_freq,
          mufradat, lanes, quran_meaning, wensinck9
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(root) DO UPDATE SET
          buckwalter = CASE WHEN excluded.buckwalter != '' THEN excluded.buckwalter ELSE root.buckwalter END,
          definition_en = CASE WHEN excluded.definition_en != '' THEN excluded.definition_en ELSE root.definition_en END,
          summary_en = CASE WHEN excluded.summary_en != '' THEN excluded.summary_en ELSE root.summary_en END,
          quran_freq = MAX(root.quran_freq, excluded.quran_freq),
          mufradat = CASE WHEN excluded.mufradat != '' THEN excluded.mufradat ELSE root.mufradat END,
          lanes = CASE WHEN excluded.lanes != '' THEN excluded.lanes ELSE root.lanes END,
          quran_meaning = CASE WHEN excluded.quran_meaning != '' THEN excluded.quran_meaning ELSE root.quran_meaning END,
          wensinck9 = MAX(root.wensinck9, excluded.wensinck9)
        """,
        (
            root,
            fields.get("buckwalter") or "",
            fields.get("definition_en") or "",
            fields.get("summary_en") or "",
            int(fields.get("quran_freq") or 0),
            fields.get("mufradat") or "",
            fields.get("lanes") or "",
            fields.get("quran_meaning") or "",
            1 if fields.get("wensinck9") else 0,
        ),
    )


# Source identities are explicit: numbering and URLs differ between editions.
EXISTING_ADDITIONAL_BOOKS = {
    **{f"Al-Kafi-Volume-{v}-Kulayni": f"alkafi-{v}" for v in range(1, 9)},
    **{f"Uyun-akhbar-al-Rida-Volume-{v}-Saduq": f"uyun-rida-{v}" for v in (1, 2)},
    "Al-Amali-Mufid": "al-amali-mufid",
    "Al-Amali-Saduq": "al-amali-saduq",
    "Al-Khisal-Saduq": "al-khisal",
    "Al-Tawhid-Saduq": "al-tawhid",
    "Maani-al-Akhbar-Saduq": "maani-al-akhbar",
    "Kamil-al-Ziyarat-Qummi": "kamil-al-ziyarat",
    "Kitab-al-Ghayba-Numani": "kitab-al-ghayba-numani",
    "Kitab-al-Ghayba-Tusi": "kitab-al-ghayba-tusi",
}

ADDITIONAL_ARABIC_TITLES = {
    "Mujam-al-Ahadith-al-Mutabara-Muhsini": "معجم الأحاديث المعتبرة",
    "Kitab-al-Duafa-Ghadairi": "كتاب الضعفاء",
    "Thawab-al-Amal-wa-iqab-al-Amal-Saduq": "ثواب الأعمال وعقاب الأعمال",
    "Fadail-al-Shia-Saduq": "فضائل الشيعة",
    "Sifat-al-Shia-Saduq": "صفات الشيعة",
    "Kitab-al-Mumin-Ahwazi": "كتاب المؤمن",
    "Kitab-al-Zuhd-Ahwazi": "كتاب الزهد",
    "Nahj-al-Balagha-Radi": "نهج البلاغة",
    "Risalat-al-Huquq-Abidin": "رسالة الحقوق",
    "Man-La-Yahduruh-al-Faqih-Saduq": "من لا يحضره الفقيه",
    "Kamal-al-Din-wa-Tamam-al-Nima-Saduq": "كمال الدين وتمام النعمة",
    "Fadail-al-Ashhur-al-Thalatha-Saduq": "فضائل الأشهر الثلاثة",
    "Tahdhib-al-Ahkam-Tusi": "تهذيب الأحكام",
    "Al-Istibsar-Tusi": "الاستبصار",
    "Al-Imama-wa’l-Tabsira-min-al-Hayra-Babawayh": "الإمامة والتبصرة من الحيرة",
}


def load_additional_books(folder: Path, db: sqlite3.Connection, *, four: bool = False) -> int:
    """Numbered exports supersede allBooks.json; existing corpus editions remain authoritative."""
    metadata = {m["bookId"]: m for m in json.loads((folder / "BookNames.json").read_bytes())}
    files = sorted((p for p in folder.glob("*.json") if p.stem.isdecimal()), key=lambda p: int(p.stem))
    if not files:
        raise ValueError(f"No numbered book exports in {folder}")
    hid = db.execute("SELECT coalesce(max(id), 0) FROM hadith").fetchone()[0]
    cid = db.execute("SELECT coalesce(max(id), 0) FROM chapter").fetchone()[0]
    order = db.execute("SELECT coalesce(max(sort_order), -1) + 1 FROM book").fetchone()[0]
    imported = skipped = 0
    grading_importer = GradingImporter(db)
    seen_books: set[str] = set()
    for path in files:
        rows = json.loads(path.read_bytes())
        if not rows:
            raise ValueError(f"Empty book export: {path}")
        source_book = rows[0]["bookId"]
        if source_book in seen_books or any(r["bookId"] != source_book for r in rows):
            raise ValueError(f"Duplicate or mixed book export: {path}")
        seen_books.add(source_book)
        group = re.sub(r"-Volume-\d+", "", source_book)
        if four and group not in FOUR_ADDITIONAL_BOOKS:
            continue
        meta = metadata[source_book]
        existing = EXISTING_ADDITIONAL_BOOKS.get(source_book)
        if existing and db.execute("SELECT 1 FROM book WHERE id = ?", (existing,)).fetchone():
            skipped += 1
            continue
        book_id = "additional-" + source_book
        group = re.sub(r"-Volume-\d+", "", source_book)
        collection_id = "additional-" + group
        name_en = meta["BookName"]
        name_ar = ADDITIONAL_ARABIC_TITLES.get(group, name_en)
        volume = meta.get("volume")
        multi_volume = "-Volume-" in source_book
        db.execute("INSERT OR IGNORE INTO collection VALUES (?, ?, ?, ?)",
                   (collection_id, name_ar, name_en, order))
        db.execute("""INSERT INTO book
            (id, collection_id, sect, book_group, name_ar, name_en, author, volume, sort_order)
            VALUES (?, ?, 'shia', 'shia', ?, ?, ?, ?, ?)""",
            (book_id, collection_id, f"{name_ar} — {volume}" if multi_volume else name_ar,
             f"{name_en} — {volume}" if multi_volume else name_en, meta.get("author"), volume, order))
        order += 1
        chapters: dict[tuple, tuple[int, int]] = {}
        source_ids: set[int] = set()
        for row in rows:
            number = row["id"]
            if not isinstance(number, int) or number <= 0 or number in source_ids:
                raise ValueError(f"Invalid or duplicate source number in {path}: {number}")
            source_ids.add(number)
            key = (row.get("categoryId"), row.get("chapterInCategoryId"), row.get("chapter", ""))
            if key not in chapters:
                cid += 1
                chapter_idx = len(chapters)
                chapters[key] = cid, chapter_idx
                title = " · ".join(dict.fromkeys(x for x in (row.get("category"), row.get("chapter")) if x))
                db.execute("INSERT INTO chapter (id, book_id, chapter_idx, file_name, name_en) VALUES (?, ?, ?, ?, ?)",
                           (cid, book_id, chapter_idx, path.name, title))
            chapter_id, chapter_idx = chapters[key]
            hid += 1
            db.execute("""INSERT INTO hadith
                (id, book_id, chapter_id, chapter_idx, id_in_book, source_id, arabic, english_text, url)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (hid, book_id, chapter_id, chapter_idx, number, number,
                 row.get("arabicText") or "", row.get("englishText") or "", row.get("URL") or ""))
            grading_importer.add(hid, row)
            imported += 1
        db.execute("UPDATE chapter SET hadith_count = (SELECT count(*) FROM hadith WHERE chapter_id = chapter.id) WHERE book_id = ?", (book_id,))
    missing = set(metadata) - seen_books
    if missing:
        raise ValueError(f"Missing numbered exports for: {sorted(missing)}")
    grading_importer.report()
    print(f"  additional: imported={imported}, kept existing editions={skipped}, numbered exports={len(files)}")
    return imported


def localize_books(db: sqlite3.Connection) -> None:
    books = json.loads((DATA / "books-and-authors.json").read_text())["books"]
    for row in books:
        # Per-book edits take precedence; blank translations retain the source names.
        db.execute("""UPDATE book SET name_ar = coalesce(nullif(?, ''), name_ar),
            name_en = coalesce(nullif(?, ''), name_en),
            author_ar = coalesce(nullif(?, ''), author_ar),
            author = coalesce(nullif(?, ''), author) WHERE id = ?""",
            (row.get("name_ar") or "", row.get("name_en") or "", row.get("author_ar") or "",
             row.get("author_en") or "", row["id"]))
    # Collection titles omit the individual volume suffix.
    for collection_id, in db.execute("SELECT id FROM collection").fetchall():
        if collection_id in {"alkafi", "uyun-rida"}:
            continue
        book = db.execute("SELECT name_ar FROM book WHERE collection_id = ? ORDER BY sort_order LIMIT 1",
                          (collection_id,)).fetchone()
        if book:
            db.execute("UPDATE collection SET name_ar = ? WHERE id = ?",
                       (re.sub(r"\s*[—–]\s*\d+$", "", book[0]), collection_id))


def load_morphology(z: HadithDirectory, db: sqlite3.Connection) -> None:
    lexicon = z.read_json("roots_lexicon.json")
    for root_ar, entry in lexicon.items():
        ensure_root(
            db,
            root_ar,
            buckwalter=entry.get("buckwalter") or "",
            definition_en=entry.get("definition_en") or "",
            summary_en=entry.get("summary_en") or "",
            quran_freq=entry.get("quran_freq") or 0,
        )
    print(f"  roots_lexicon={len(lexicon)}")

    word_rows: list[tuple] = []
    defs = z.read_json("word_defs_v2.json")
    for form, entry in defs.items():
        nform = norm(form)
        if nform != form:
            # Prefer storing the already-normalized key; keep as-is if source differs.
            pass
        root = entry.get("r") or None
        if root:
            ensure_root(db, root, summary_en=(entry.get("g") or "")[:500])
        number = entry.get("form")
        if number not in (None, "s", "p", "d"):
            number = None
        voice = entry.get("voice")
        if voice not in (None, "active", "passive"):
            voice = None
        aspect = entry.get("asp")
        if aspect not in (None, "perfect", "imperfect", "command"):
            aspect = None
        word_rows.append(
            (
                form,
                root,
                entry.get("lem"),
                entry.get("pos"),
                number,
                voice,
                aspect,
                entry.get("g") or "",
                int(entry.get("n") or 0),
                "camel",
            )
        )
    db.executemany(
        """
        INSERT INTO word_form (
          form, root, lemma, pos, number, voice, aspect, gloss, corpus_count, source
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(form) DO UPDATE SET
          root = COALESCE(excluded.root, word_form.root),
          lemma = COALESCE(excluded.lemma, word_form.lemma),
          pos = COALESCE(excluded.pos, word_form.pos),
          number = COALESCE(excluded.number, word_form.number),
          voice = COALESCE(excluded.voice, word_form.voice),
          aspect = COALESCE(excluded.aspect, word_form.aspect),
          gloss = CASE WHEN excluded.gloss != '' THEN excluded.gloss ELSE word_form.gloss END,
          corpus_count = MAX(word_form.corpus_count, excluded.corpus_count),
          source = 'camel'
        """,
        word_rows,
    )
    print(f"  word_defs_v2={len(defs)}")

    # Fallback forms from older defs
    if z.exists("word_defs.json"):
        v1 = z.read_json("word_defs.json")
        rows = []
        for form, entry in v1.items():
            root = entry.get("r")
            if root:
                ensure_root(db, root, summary_en=(entry.get("g") or "")[:500])
            rows.append(
                (
                    form,
                    root,
                    None,
                    None,
                    None,
                    None,
                    None,
                    entry.get("g") or "",
                    int(entry.get("n") or 0),
                    "defs_v1",
                )
            )
        db.executemany(
            """
            INSERT OR IGNORE INTO word_form (
              form, root, lemma, pos, number, voice, aspect, gloss, corpus_count, source
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            rows,
        )
        print(f"  word_defs_v1_extra={len(v1)}")


def load_bridge_and_families(z: HadithDirectory, db: sqlite3.Connection, resolver: RefResolver) -> None:
    bridge = z.read_json("quran_hadith_bridge.json")
    ayah_rows: list[tuple] = []
    hadith_root_rows: list[tuple] = []
    form_rows: list[tuple] = []

    for root_ar, entry in bridge.items():
        defs = entry.get("definitions") or {}
        ensure_root(
            db,
            root_ar,
            quran_freq=entry.get("frequency_quran") or entry.get("ayah_count") or 0,
            mufradat=defs.get("mufradat") or "",
            lanes=defs.get("lanes") or "",
            quran_meaning=defs.get("quran_meaning") or "",
        )
        for ayah in entry.get("ayahs") or []:
            try:
                sura_s, aya_s = str(ayah).split(":", 1)
                ayah_rows.append((root_ar, int(sura_s), int(aya_s)))
            except ValueError:
                continue
        for href in entry.get("hadith_ids") or []:
            hid = resolver.resolve(href, "bridge")
            if hid is not None:
                hadith_root_rows.append((hid, root_ar))
        for word in entry.get("words_in_hadith") or []:
            form_rows.append((word, root_ar, "bridge"))

    # Cross-check / extend from bridge_ids shards
    for rel in z.list_prefix("bridge_ids"):
        if not rel.endswith(".json"):
            continue
        root_ar = Path(rel).stem
        ensure_root(db, root_ar)
        data = z.read_json(rel)
        for book_id, chapters in data.items():
            if not isinstance(chapters, dict):
                continue
            if not resolver._in_scope(book_id):
                n = sum(len(ids) for ids in chapters.values() if isinstance(ids, list))
                resolver.stats["bridge_ids:skip"] += n
                continue
            for ch_s, ids in chapters.items():
                try:
                    ch_idx = int(ch_s)
                except ValueError:
                    continue
                for iib in ids:
                    hid = resolver.exact.get((book_id, ch_idx, int(iib)))
                    if hid is not None:
                        hadith_root_rows.append((hid, root_ar))
                        resolver.stats["bridge_ids:ok"] += 1
                    else:
                        resolver.stats["bridge_ids:miss"] += 1

    db.executemany("INSERT OR IGNORE INTO root_ayah (root, sura, aya) VALUES (?, ?, ?)", ayah_rows)
    db.executemany("INSERT OR IGNORE INTO hadith_root (hadith_id, root) VALUES (?, ?)", hadith_root_rows)
    db.executemany(
        """
        INSERT INTO word_form (form, root, lemma, pos, number, voice, aspect, gloss, corpus_count, source)
        VALUES (?, ?, NULL, NULL, NULL, NULL, NULL, '', 0, ?)
        ON CONFLICT(form) DO UPDATE SET
          root = COALESCE(word_form.root, excluded.root)
        """,
        form_rows,
    )
    print(f"  bridge roots={len(bridge)} ayah_links={len(ayah_rows)} hadith_root={len(hadith_root_rows)}")

    families = z.read_json("family_corpus.json")
    fam_rows = []
    fam_root_rows = []
    fam_book_rows = []
    for key, entry in families.items():
        fam_rows.append(
            (
                key,
                entry.get("name_ar") or "",
                entry.get("meaning") or "",
                int(entry.get("root_count") or len(entry.get("roots") or [])),
                int(entry.get("ayah_count") or 0),
                int(entry.get("hadith_count") or 0),
            )
        )
        stats_by_root = {s["root"]: s for s in (entry.get("root_stats") or []) if "root" in s}
        for root_ar in entry.get("roots") or []:
            ensure_root(db, root_ar)
            st = stats_by_root.get(root_ar, {})
            fam_root_rows.append(
                (
                    key,
                    root_ar,
                    int(st.get("ayah_count") or 0),
                    int(st.get("hadith_count") or 0),
                    int(st.get("frequency_quran") or 0),
                )
            )
        for book_id, count in (entry.get("book_breakdown") or {}).items():
            fam_book_rows.append((key, book_id, int(count)))

    db.executemany(
        """
        INSERT INTO family (key, name_ar, meaning, root_count, ayah_count, hadith_count)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        fam_rows,
    )
    db.executemany(
        """
        INSERT OR IGNORE INTO family_root (
          family_key, root, ayah_count, hadith_count, frequency_quran
        ) VALUES (?, ?, ?, ?, ?)
        """,
        fam_root_rows,
    )
    # Only insert family_book_count for known books
    known_books = {r[0] for r in db.execute("SELECT id FROM book")}
    db.executemany(
        """
        INSERT OR IGNORE INTO family_book_count (family_key, book_id, hadith_count)
        VALUES (?, ?, ?)
        """,
        [r for r in fam_book_rows if r[1] in known_books],
    )
    print(f"  families={len(families)}")


def load_concordances(z: HadithDirectory, db: sqlite3.Connection, resolver: RefResolver) -> None:
    concordance = z.read_json("concordance.json")
    rows: list[tuple] = []
    for form, refs in concordance.items():
        for ref in refs:
            hid = resolver.resolve(ref, "concordance")
            if hid is not None:
                rows.append((form, hid))
        if len(rows) >= 50_000:
            db.executemany("INSERT OR IGNORE INTO concordance (form, hadith_id) VALUES (?, ?)", rows)
            rows.clear()
    if rows:
        db.executemany("INSERT OR IGNORE INTO concordance (form, hadith_id) VALUES (?, ?)", rows)
    print(f"  concordance words={len(concordance)}")

    wensinck = z.read_json("wensinck.json")
    w_rows: list[tuple] = []
    form_rows: list[tuple] = []
    for root_ar, entry in wensinck.items():
        ensure_root(
            db,
            root_ar,
            buckwalter=entry.get("buckwalter") or "",
            summary_en=entry.get("gloss") or "",
            wensinck9=bool(entry.get("wensinck9")),
        )
        for form in entry.get("forms") or []:
            form_rows.append((form, root_ar))
        books = entry.get("books") or {}
        for siglum, refs in books.items():
            for ref in refs:
                hid = resolver.resolve_wensinck(siglum, ref)
                if hid is not None:
                    w_rows.append((root_ar, hid))
        if len(w_rows) >= 50_000:
            db.executemany("INSERT OR IGNORE INTO wensinck_ref (root, hadith_id) VALUES (?, ?)", w_rows)
            w_rows.clear()
    if w_rows:
        db.executemany("INSERT OR IGNORE INTO wensinck_ref (root, hadith_id) VALUES (?, ?)", w_rows)
    db.executemany(
        """
        INSERT INTO word_form (form, root, lemma, pos, number, voice, aspect, gloss, corpus_count, source)
        VALUES (?, ?, NULL, NULL, NULL, NULL, NULL, '', 0, 'wensinck')
        ON CONFLICT(form) DO UPDATE SET
          root = COALESCE(word_form.root, excluded.root)
        """,
        form_rows,
    )
    print(f"  wensinck roots={len(wensinck)} forms={len(form_rows)}")


def load_relations_freq_chord(z: HadithDirectory, db: sqlite3.Connection, resolver: RefResolver) -> None:
    connections = z.read_json("hadith_connections.json")
    rows = []
    for src_ref, items in connections.items():
        src = resolver.resolve(src_ref, "connections")
        if src is None:
            continue
        for item in items:
            if isinstance(item, str):
                dst_ref, t1, t2, t3, score = item, [], [], [], 0
            else:
                dst_ref = item.get("id")
                t1 = item.get("t1") or []
                t2 = item.get("t2") or []
                t3 = item.get("t3") or []
                score = int(item.get("score") or 0)
            dst = resolver.resolve(dst_ref, "connections")
            if dst is None or dst == src:
                continue
            rows.append(
                (
                    src,
                    dst,
                    score,
                    json.dumps(t1, ensure_ascii=False),
                    json.dumps(t2, ensure_ascii=False),
                    json.dumps(t3, ensure_ascii=False),
                )
            )
    db.executemany(
        """
        INSERT OR IGNORE INTO hadith_relation (
          src_id, dst_id, score, shared_words, shared_rulings, shared_topics
        ) VALUES (?, ?, ?, ?, ?, ?)
        """,
        rows,
    )
    print(f"  relations={len(rows)} from {len(connections)} sources")

    word_freq = z.read_json("word_freq.json")
    known_books = {r[0] for r in db.execute("SELECT id FROM book")}
    freq_rows = []
    for book_id, words in word_freq.items():
        if book_id not in known_books:
            continue
        for item in words:
            form = item.get("norm") or item.get("word") or ""
            if not form:
                continue
            freq_rows.append((book_id, form, int(item.get("count") or 0)))
    db.executemany(
        "INSERT OR IGNORE INTO word_freq (book_id, form, count) VALUES (?, ?, ?)",
        freq_rows,
    )
    print(f"  word_freq rows={len(freq_rows)}")

    chord = z.read_json("chord_matrices.json")
    book_keys = chord.get("book_keys") or []
    family_keys = chord.get("family_keys") or []
    matrix = chord.get("book_family_matrix") or []
    bf_rows = []
    for bi, book_id in enumerate(book_keys):
        if book_id not in known_books or bi >= len(matrix):
            continue
        row = matrix[bi]
        for fi, family_key in enumerate(family_keys):
            if fi >= len(row):
                break
            bf_rows.append((book_id, family_key, int(row[fi])))
    db.executemany(
        "INSERT OR IGNORE INTO book_family_count (book_id, family_key, count) VALUES (?, ?, ?)",
        bf_rows,
    )

    fam_matrix = chord.get("family_matrix") or []
    # Prefer top-15 labels if matrix is that size; else full family_keys.
    fam_labels = chord.get("family_keys_top15") or family_keys
    if fam_matrix and len(fam_matrix) != len(fam_labels) and len(fam_matrix) == len(family_keys):
        fam_labels = family_keys
    overlap_rows = []
    for i, a in enumerate(fam_labels):
        if i >= len(fam_matrix):
            break
        for j, b in enumerate(fam_labels):
            if j > i or j >= len(fam_matrix[i]):
                continue
            aa, bb = (a, b) if a <= b else (b, a)
            overlap_rows.append((aa, bb, int(fam_matrix[i][j])))
    db.executemany(
        "INSERT OR IGNORE INTO family_overlap (family_a, family_b, count) VALUES (?, ?, ?)",
        overlap_rows,
    )
    print(f"  chord book_family={len(bf_rows)} overlaps={len(overlap_rows)}")


def tokenize_arabic(text: str) -> list[str]:
    return [tok for tok in _TOKEN_SPLIT.split(norm(text)) if tok]


def build_fts(db: sqlite3.Connection, *, experimental_morphology: bool = False) -> None:
    # Preload form -> (root, lemma)
    form_map = {
        form: (root or "", lemma or "")
        for form, root, lemma in (db.execute("SELECT form, root, lemma FROM word_form") if experimental_morphology else [])
    }
    # Preload hadith -> roots
    roots_by_hadith: dict[int, set[str]] = defaultdict(set)
    for hid, root in (db.execute("SELECT hadith_id, root FROM hadith_root") if experimental_morphology else []):
        roots_by_hadith[hid].add(root)

    word_rows = []
    fts_rows = []
    en_rows = []
    for hid, arabic, en_narr, en_text in db.execute(
        "SELECT id, arabic, english_narrator, english_text FROM hadith"
    ):
        ntext = norm(arabic)
        tokens = tokenize_arabic(arabic)
        roots = set(roots_by_hadith.get(hid, ()))
        lemmas: set[str] = set()
        for tok in tokens:
            root, lemma = form_map.get(tok, ("", ""))
            if root:
                roots.add(root)
            if lemma:
                lemmas.add(norm(lemma))
        word_rows.append((hid, ntext, " ".join(sorted(roots)), " ".join(sorted(lemmas))) if experimental_morphology else (hid, ntext))
        fts_rows.append((hid, ntext))
        en = " ".join(x for x in (en_narr, en_text) if x).strip()
        if en:
            en_rows.append((hid, en))
        if len(word_rows) >= 5000:
            db.executemany(
                ("INSERT INTO hadith_words (rowid, text, root, lemma) VALUES (?, ?, ?, ?)" if experimental_morphology else "INSERT INTO hadith_words (rowid, text) VALUES (?, ?)"),
                word_rows,
            )
            db.executemany("INSERT INTO hadith_fts (rowid, text) VALUES (?, ?)", fts_rows)
            db.executemany("INSERT INTO hadith_en (rowid, text) VALUES (?, ?)", en_rows)
            word_rows.clear()
            fts_rows.clear()
            en_rows.clear()

    if word_rows:
        db.executemany(
            ("INSERT INTO hadith_words (rowid, text, root, lemma) VALUES (?, ?, ?, ?)" if experimental_morphology else "INSERT INTO hadith_words (rowid, text) VALUES (?, ?)"),
            word_rows,
        )
        db.executemany("INSERT INTO hadith_fts (rowid, text) VALUES (?, ?)", fts_rows)
        db.executemany("INSERT INTO hadith_en (rowid, text) VALUES (?, ?)", en_rows)

    for table in ("hadith_words", "hadith_fts", "hadith_en"):
        db.execute(f"INSERT INTO {table} ({table}) VALUES ('optimize')")
    print("  FTS indexes built")


def finalize(db: sqlite3.Connection, label: str) -> None:
    db.execute("ANALYZE")
    db.execute("PRAGMA optimize")
    db.commit()
    db.execute("VACUUM")
    integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
    if integrity != "ok":
        raise SystemExit(f"{label} integrity_check failed: {integrity}")
    fk = db.execute("PRAGMA foreign_key_check").fetchall()
    if fk:
        raise SystemExit(f"{label} foreign_key_check failed: {fk[:10]}")
    print(f"  {label} integrity ok")


def verify_hadith(
    db: sqlite3.Connection, sunni_count: int, shia_count: int, *, sittah: bool, four: bool = False, experimental_morphology: bool = False
) -> None:
    hadiths = db.execute("SELECT count(*) FROM hadith").fetchone()[0]
    by_sect = dict(db.execute(
        """
        SELECT b.sect, count(*)
        FROM hadith h JOIN book b ON b.id = h.book_id
        GROUP BY b.sect
        """
    ))
    print(
        f"  counts hadiths={hadiths} (sunni={by_sect.get('sunni', 0)} "
        f"shia={by_sect.get('shia', 0)})"
    )
    if sunni_count + shia_count != hadiths:
        raise SystemExit(
            f"Sect counts disagree with total: total={hadiths} "
            f"sunni={sunni_count} shia={shia_count}"
        )
    if sittah:
        if sunni_count < 30_000 or sunni_count > 40_000:
            raise SystemExit(f"Expected ~33k Sittah hadiths, got sunni={sunni_count}")
        if shia_count < 15_000:
            raise SystemExit(f"Expected ~21k Shia hadiths, got shia={shia_count}")
        sunni_books = {r[0] for r in db.execute("SELECT id FROM book WHERE sect = 'sunni'")}
        if sunni_books != set(SITTAH_BOOKS):
            raise SystemExit(f"Sittah book set mismatch: {sorted(sunni_books)}")
    elif not four and hadiths < 120_000:
        raise SystemExit(
            f"Expected ~127k+ combined hadiths, got total={hadiths} "
            f"sunni={sunni_count} shia={shia_count}"
        )
    # Group volumes for navigation without changing any source book or narration identity.
    grouped = dict(db.execute("SELECT collection_id, count(*) FROM book GROUP BY collection_id"))
    if grouped.get("alkafi") != 8 or (not four and grouped.get("uyun-rida") != 2):
        raise SystemExit(f"Unexpected volume grouping: {grouped}")
    if db.execute("SELECT count(*) FROM collection").fetchone()[0] != len(grouped):
        raise SystemExit("Collection catalog contains unused entries")

    # Search sanity
    q = norm("إنما الأعمال بالنيات")
    # Use prefix tokens from the famous matn
    n = db.execute(
        "SELECT count(*) FROM hadith_words WHERE hadith_words MATCH ?",
        ('text : "انما" AND text : "الاعمال"',),
    ).fetchone()[0]
    if n < 1:
        raise SystemExit("FTS text search for انما/الاعمال returned 0")

    # Bukhari 1 should match intentions
    row = db.execute(
        """
        SELECT h.id FROM hadith h
        WHERE h.book_id = 'bukhari' AND h.chapter_idx = 0 AND h.id_in_book = 1
        """
    ).fetchone()
    if not row:
        raise SystemExit("bukhari 1:1 missing")
    bukhari1 = row[0]
    hit = db.execute(
        "SELECT rowid FROM hadith_en WHERE hadith_en MATCH ? AND rowid = ?",
        ('"intentions"', bukhari1),
    ).fetchone()
    if not hit:
        # Soft check: any intentions hit
        any_hit = db.execute(
            "SELECT count(*) FROM hadith_en WHERE hadith_en MATCH ?",
            ('"intentions"',),
        ).fetchone()[0]
        if any_hit < 1:
            raise SystemExit("English FTS 'intentions' returned 0")
        print("  note: bukhari1 not in english intentions hits (empty translation?), general hit ok")

    if experimental_morphology:
        root_hits = db.execute(
            "SELECT count(*) FROM hadith_words WHERE hadith_words MATCH ?",
            ('root : "صوم"',),
        ).fetchone()[0]
        if root_hits < 1:
            raise SystemExit("Root FTS صوم returned 0")

    prefix_hits = db.execute(
        "SELECT count(*) FROM hadith_words WHERE hadith_words MATCH ?",
        ('text : "صل"*',),
    ).fetchone()[0]
    if prefix_hits < 1:
        raise SystemExit("Prefix FTS صل* returned 0")

    tri = db.execute(
        "SELECT count(*) FROM hadith_fts WHERE hadith_fts MATCH ?",
        ('"صوم"',),
    ).fetchone()[0]
    if tri < 1:
        raise SystemExit("Trigram FTS صوم returned 0")
    print("  search sanity ok")


def summarize(path: Path, db: sqlite3.Connection) -> None:
    tables = db.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '%_data' AND name NOT LIKE '%_idx' AND name NOT LIKE '%_docsize' AND name NOT LIKE '%_config' ORDER BY name"
    ).fetchall()
    print(f"== {path.name} ({path.stat().st_size / (1024 * 1024):.1f} MiB) ==")
    for (name,) in tables:
        try:
            n = db.execute(f'SELECT count(*) FROM "{name}"').fetchone()[0]
        except sqlite3.Error:
            n = "?"
        print(f"  {name}: {n}")

    compressor = zlib.compressobj(6)
    size = 0
    with path.open('rb') as source:
        while chunk := source.read(1024 * 1024):
            size += len(compressor.compress(chunk))
    size += len(compressor.flush())
    print(f"  Deflate estimate: {size / 1048576:.2f} MiB (not Apple download size)")
    for name, size in db.execute("SELECT name, sum(pgsize) FROM dbstat GROUP BY name ORDER BY sum(pgsize) DESC"):
        print(f"  storage {name}: {size / 1048576:.2f} MiB")


def assert_norm_consistency(z: HadithDirectory) -> None:
    defs = z.read_json("word_defs_v2.json")
    bad = [k for k in list(defs)[:5000] if norm(k) != k]
    # Allow a small number of imperfect keys; fail if systematic.
    if len(bad) > 50:
        raise SystemExit(f"word_defs_v2 keys not normalized, sample={bad[:10]}")
    print(f"  norm check: {len(bad)} / 5000 sampled keys differ after norm()")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        "--sittah",
        action="store_true",
        help=(
            "Limit Sunni books to the Kutub al-Sittah "
            "(bukhari, muslim, abudawud, tirmidhi, nasai, ibnmajah). "
            "Combine with --four to limit Shia books. Default: all Sunni books."
        ),
    )
    p.add_argument(
        "--four",
        action="store_true",
        help="Limit Shia books to the Four Books plus Nahj al-Balagha; combine with --sittah.",
    )
    p.add_argument("--experimental-morphology", action="store_true", help="Include unverified root/lemma mappings and indexes (off by default).")
    p.add_argument("--output", type=Path, default=DIST / "hadith.db", help="Destination database.")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    for source in (DATA_PATH, ADDITIONAL_PATH):
        if not source.is_dir():
            print(f"Missing source folder: {source}", file=sys.stderr)
            return 1
    print(f"Python {sys.version.split()[0]} SQLite {sqlite3.sqlite_version}")
    print(f"Reading {DATA_PATH} and {ADDITIONAL_PATH}")
    if args.sittah:
        print("Mode: --sittah (Six Books + Shia)")

    if args.four:
        metadata = json.loads((ADDITIONAL_PATH / "BookNames.json").read_bytes())
        available = {re.sub(r"-Volume-\d+", "", m["bookId"]) for m in metadata}
        missing = FOUR_BOOKS - available
        if missing:
            print(f"Warning: requested books missing from source exports: {sorted(missing)}", file=sys.stderr)

    DIST.mkdir(parents=True, exist_ok=True)
    z = HadithDirectory(DATA_PATH)
    if args.experimental_morphology:
        assert_norm_consistency(z)

    hadith_path = args.output
    print("Building hadith.db…")
    hdb = connect(hadith_path)
    apply_schema(hdb, HERE / "schema.sql")
    if args.experimental_morphology:
        apply_schema(hdb, HERE / "experimental-morphology.sql")
        hdb.executescript("""DROP TABLE hadith_words_vocab; DROP TABLE hadith_words;
            CREATE VIRTUAL TABLE hadith_words USING fts5(text, root, lemma, content='',
                tokenize='unicode61 remove_diacritics 2', prefix='2 3');
            CREATE VIRTUAL TABLE hadith_words_vocab USING fts5vocab(hadith_words, col);""")
    loaded_books: set[str] | None = set(SITTAH_BOOKS) if args.sittah else None
    # Shia book ids are discovered while loading; seed resolver after load.
    resolver = RefResolver(loaded_books=None)  # temporarily allow all during load
    hdb.execute("BEGIN")
    sunni_count, shia_count = load_books_chapters_hadiths(
        z, hdb, resolver, sittah=args.sittah, four=args.four
    )
    loaded_books = {r[0] for r in hdb.execute("SELECT id FROM book")}
    resolver.loaded_books = loaded_books
    if args.experimental_morphology:
        load_morphology(z, hdb)
        load_bridge_and_families(z, hdb, resolver)
        load_concordances(z, hdb, resolver)
        load_relations_freq_chord(z, hdb, resolver)
    shia_count += load_additional_books(ADDITIONAL_PATH, hdb, four=args.four)
    localize_books(hdb)
    hdb.commit()

    print("Building FTS…")
    hdb.execute("BEGIN")
    build_fts(hdb, experimental_morphology=args.experimental_morphology)
    hdb.commit()

    if args.experimental_morphology:
        for source in ("bridge", "bridge_ids", "concordance", "wensinck", "connections"):
            resolver.assert_ok(source, min_rate=0.90 if source == "connections" else 0.99)
        # These tables support source import, not reading or experimental word lookup.
        hdb.execute("PRAGMA foreign_keys = OFF")
        for table in ("root_ayah", "hadith_root", "family_root", "family_book_count", "concordance",
                      "wensinck_ref", "hadith_relation", "word_freq", "book_family_count", "family_overlap", "family"):
            hdb.execute(f'DROP TABLE "{table}"')
        hdb.commit()
        hdb.execute("PRAGMA foreign_keys = ON")

    finalize(hdb, "hadith.db")
    verify_hadith(hdb, sunni_count, shia_count, sittah=args.sittah, four=args.four, experimental_morphology=args.experimental_morphology)
    summarize(hadith_path, hdb)
    hdb.close()

    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
