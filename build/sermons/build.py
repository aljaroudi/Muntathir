"""Compile the bundled sermon database from local publication sources."""
import argparse
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile

from fadak.publication import load_sermon

OUTPUT = Path(__file__).resolve().parents[2] / "shared/sermons/sermons.db"


def build(target):
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=target.parent) as staging:
        file = Path(staging) / target.name
        with closing(sqlite3.connect(file)) as db, db:
            db.executescript("""
                PRAGMA foreign_keys = ON;
                CREATE TABLE sermon(id TEXT PRIMARY KEY, title TEXT NOT NULL, speaker_id TEXT NOT NULL, source TEXT NOT NULL);
                CREATE TABLE segment(sermon TEXT REFERENCES sermon, id TEXT, position INTEGER NOT NULL,
                    section TEXT NOT NULL, kind TEXT NOT NULL, text TEXT NOT NULL, PRIMARY KEY(sermon, id));
                CREATE TABLE edition(sermon TEXT REFERENCES sermon, id TEXT, position INTEGER NOT NULL,
                    language TEXT NOT NULL, kind TEXT NOT NULL, credit TEXT, PRIMARY KEY(sermon, id));
                CREATE TABLE translation(sermon TEXT, edition TEXT, segment TEXT, text TEXT NOT NULL,
                    PRIMARY KEY(sermon, edition, segment), FOREIGN KEY(sermon, edition) REFERENCES edition,
                    FOREIGN KEY(sermon, segment) REFERENCES segment);
            """)
            sermon = load_sermon()
            key = sermon["id"]
            db.execute("INSERT INTO sermon VALUES (:id,:title,:speaker_id,:source)", sermon)
            for position, segment in enumerate(sermon["segments"]):
                db.execute("INSERT INTO segment VALUES (?,?,?,?,?,?)",
                           (key, segment["id"], position, segment["section"], segment["kind"], segment["text"]))
            for position, edition in enumerate(sermon["editions"]):
                db.execute("INSERT INTO edition VALUES (?,?,?,?,?,?)",
                           (key, edition["id"], position, edition["language"], edition["kind"], edition.get("credit")))
                db.executemany("INSERT INTO translation VALUES (?,?,?,?)",
                               ((key, edition["id"], segment, text) for segment, text in edition["aligned"].items()))
        file.replace(target)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    build(parser.parse_args().output)
