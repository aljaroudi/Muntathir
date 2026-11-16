#!/usr/bin/env python3
"""Rebuild only basic offline search indexes without reimporting reader content.

Writes a separate schema-8 database. Never replace a published pack until its
compatible app build is available; schema-7 readers cannot open this output.
"""
import argparse
import sqlite3
from pathlib import Path
from build import build_fts, finalize


def compact(source: Path, destination: Path):
    if destination.exists() or source.resolve() == destination.resolve():
        raise ValueError('Destination must be new and different from source')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(source.resolve().as_uri() + '?mode=ro', uri=True) as original:
        with sqlite3.connect(destination) as db:
            original.backup(db)
            for name in ('hadith_words_vocab', 'hadith_partial', 'hadith_fts', 'hadith_words', 'hadith_en'):
                db.execute(f'DROP TABLE IF EXISTS {name}')
            db.executescript("""
                CREATE VIRTUAL TABLE hadith_words USING fts5(text,content='',tokenize='unicode61 remove_diacritics 2');
                CREATE VIRTUAL TABLE hadith_words_vocab USING fts5vocab(hadith_words,col);
                CREATE VIRTUAL TABLE hadith_en USING fts5(text,content='hadith_english_content',content_rowid='id',tokenize='unicode61 remove_diacritics 2');
                PRAGMA user_version=8;
            """)
            build_fts(db)
            finalize(db, destination.name)
            # The backup and index-only changes preserve every reader row and stable reference.
            assert db.execute('SELECT count(*) FROM hadith').fetchone() == original.execute('SELECT count(*) FROM hadith').fetchone()
    print(f'{source.stat().st_size} -> {destination.stat().st_size} bytes')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    compact(args.source, args.destination)
