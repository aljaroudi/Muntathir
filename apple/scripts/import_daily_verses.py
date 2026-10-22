#!/usr/bin/env python3
"""Validate a complete Hijri schedule against the bundled Quran database and export IDs only."""

import argparse
import csv
from contextlib import closing
import json
from pathlib import Path
import sqlite3
import tempfile


def compile_schedule(path, database):
    entries = []
    seen = set()
    with closing(sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True)) as connection:
        english = database.resolve().with_name("en.qarai.db").as_uri() + "?mode=ro"
        connection.execute("ATTACH ? AS en", (english,))
        with path.open(encoding="utf-8-sig", newline="") as stream:
            rows = csv.DictReader(stream)
            if rows.fieldnames != ["hijriMonth", "hijriDay", "verseID"]:
                raise ValueError("Expected CSV header: hijriMonth,hijriDay,verseID")
            for row_number, row in enumerate(rows, 2):
                try:
                    month, day, verse_id = (int(row[key]) for key in rows.fieldnames)
                except (ValueError, TypeError):
                    raise ValueError(f"Row {row_number}: fill all three integer fields") from None
                if None in row or not 1 <= month <= 12 or not 1 <= day <= 30:
                    raise ValueError(f"Row {row_number}: invalid date or extra columns")
                if (month, day) in seen:
                    raise ValueError(f"Row {row_number}: duplicate Hijri date {month}/{day}")
                verse = connection.execute('SELECT q.text, e.text FROM main.quran q JOIN en.quran e USING ("index") WHERE "index" = ?', (verse_id,)).fetchone()
                if verse_id <= 0 or verse is None or not all(text and text.strip() for text in verse):
                    raise ValueError(f"Row {row_number}: verse ID {verse_id} needs Arabic in quran.db and English in en.qarai.db")
                seen.add((month, day))
                entries.append(dict(hijriMonth=month, hijriDay=day, verseID=verse_id))
    if len(seen) != 360:
        raise ValueError(f"Schedule has {len(seen)}/360 dates; include days 1–30 for every month")
    return {"entries": sorted(entries, key=lambda entry: (entry["hijriMonth"], entry["hijriDay"]))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schedule", type=Path, required=True)
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = compile_schedule(args.schedule, args.database)
    except (ValueError, OSError, sqlite3.Error) as error:
        parser.exit(1, f"{error}\n")
    # Validate everything before replacing a previously working resource.
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=args.output.parent, delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(result, stream, indent=2)
        stream.write("\n")
    try:
        temporary.replace(args.output)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Wrote {len(result['entries'])} dated verse IDs to {args.output}")


if __name__ == "__main__":
    main()
