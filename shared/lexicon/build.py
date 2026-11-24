"""Build the read-only dictionary pack from the supplied lexicon.sqlite."""
import argparse
import os
from pathlib import Path
import re
import sqlite3
import tempfile
import unicodedata

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / "apple/build/Lexicon/lexicon.db"
SOURCES = ("mo7eet", "faaq", "sa7a7", "nehay", "lesan", "tahzeeb")
FOLD = str.maketrans("أإآٱىؤئ", "اااايوي")
MARKS = re.compile(r"[\u0610-\u061a\u0640\u064b-\u065f\u0670\u06d6-\u06ed]")


def normalize(text):
    return MARKS.sub("", unicodedata.normalize("NFKC", text)).translate(FOLD)


def validate(path):
    with sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True) as db:
        assert db.execute("pragma quick_check").fetchall() == [("ok",)]
        assert db.execute("pragma user_version").fetchone() == (1,)
        assert db.execute("select 1 from forms where norm=? and root='كتب'", (normalize("كُتُب"),)).fetchone()
        assert db.execute("select 1 from passages where passages match ? limit 1", ('"كتاب"',)).fetchone()
        assert db.execute("select count(distinct source) from entries").fetchone() == (6,)


def build(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=target.parent) as stage:
        path = Path(stage) / target.name
        with sqlite3.connect(source.resolve().as_uri() + "?mode=ro", uri=True) as original, sqlite3.connect(path) as db:
            db.executescript("""
                pragma user_version=1;
                create table entries(root text not null, source integer not null, body text not null);
                create table forms(form text not null, norm text not null, root text not null);
                -- Tokenize marks with their word when SQLite excerpts the original entry.
                create virtual table passages using fts5(body, content='entries', content_rowid='rowid',
                    tokenize="unicode61 categories 'L* N* Co M*'");
            """)
            forms = original.execute("select form,root from word_forms")
            db.executemany("insert into forms values(?,?,?)", ((f, normalize(f), r) for f, r in forms))
            for root, *definitions in original.execute("select root," + ",".join(SOURCES) + " from dictionary order by root"):
                db.execute("insert into forms values(?,?,?)", (root, normalize(root), root))
                for source_id, body in enumerate(definitions):
                    if body and body.strip():
                        row = db.execute("insert into entries values(?,?,?)", (root, source_id, body))
                        db.execute("insert into passages(rowid,body) values(?,?)", (row.lastrowid, normalize(body)))
            db.executescript("""
                create index spelling on forms(form,root);
                create index normalized on forms(norm,root);
                create unique index definitions on entries(root,source);
                insert into passages(passages) values('optimize');
                analyze;
            """)
        validate(path)
        os.replace(path, target)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?", type=Path, default=ROOT / "lexicon.sqlite")
    parser.add_argument("--output", type=Path, default=PACK)
    args = parser.parse_args()
    build(args.source, args.output)
