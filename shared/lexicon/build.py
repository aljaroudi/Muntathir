"""Build the read-only dictionary pack from the supplied lexicon.sqlite.

Besides the six dictionaries, the pack holds a ranked root lookup for every word the
lexicon lists and every word in the app's Arabic content, so a selection resolves with one
indexed query. Quran words take their verified Quranic Arabic Corpus roots; everything
else goes through `analyze.py`. Run `evaluate.py` to measure changes to either.
"""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).parent))
from analyze import SOURCES, Analyzer, Index  # noqa: E402
from normalize import normalize, spell  # noqa: E402
from qac import gold  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / "apple/build/Lexicon/lexicon.db"
QURAN = ROOT / "apple/Muntathir/Resources/Quran/quran.db"
OVERRIDES = Path(__file__).parent / "overrides.json"
# Arabic text the app shows, so every word a reader can select has a precomputed lookup.
CORPORA = {
    "hadith": (ROOT / "build/hadith/dist/hadith.db", "select arabic from hadith"),
    "supplications": (ROOT / "build/hadith/dist/supplications.db", "select arabic from hadith"),
    "rulings": (ROOT / "build/rulings/dist/rulings.db",
                "select coalesce(label,'') || ' ' || coalesce(prompt,'') || ' ' || body from entry where language_code='ar'"),
    "sermons": (ROOT / "shared/sermons/sermons.db", "select text from segment"),
}
# Roots kept per word; later ones are rarer readings of the same spelling.
MAX_ROOTS = 4


def content_arguments(parser):
    """Shared CLI for the lexicon source and the app content the lookup is computed over."""
    parser.add_argument("source", nargs="?", type=Path, default=ROOT / "lexicon.sqlite")
    parser.add_argument("--quran", type=Path, default=QURAN)
    for name, (path, _) in CORPORA.items():
        parser.add_argument(f"--{name}", type=Path, default=path)
    args = parser.parse_args()
    return args, {name: (getattr(args, name), query) for name, (_, query) in CORPORA.items()}


def validate(path):
    with sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True) as db:
        assert db.execute("pragma quick_check").fetchall() == [("ok",)]
        assert db.execute("pragma user_version").fetchone() == (1,)
        lookup = lambda word: [r for (r,) in db.execute("select root from words where spelling=? order by rank", (spell(word),))]
        for word, root in (("كُتُب", "كتب"), ("والكتاب", "كتب"), ("الصلاة", "صلا"), ("السَّمَٰوَٰتِ", "سما"),
                           ("فَسَيَكْفِيكَهُمُ", "كفي"), ("الحق", "حقق"), ("كنت", "كون"), ("بالمؤمنين", "أمن")):
            found = lookup(word)
            assert found and (found[0] == root or db.execute("select 1 from family where root=? and member=?", (found[0], root)).fetchone()), (word, found)
        assert not db.execute("select 1 from words w where not exists (select 1 from entries e where e.root=w.root) limit 1").fetchone()
        assert db.execute("select 1 from family where root='سما' and member='سمو'").fetchone()
        assert db.execute("select 1 from rootless where spelling='الذين'").fetchone() and not lookup("الذين")
        assert db.execute("select count(distinct source) from entries").fetchone() == (6,)


def corpus_words(corpora):
    counts = Counter()
    for name, (path, query) in corpora.items():
        assert path.is_file(), f"Missing {name} content at {path}; build it first or pass --{name}"
        with sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True) as db:
            for (text,) in db.execute(query):
                counts.update(word for word in (spell(token) for token in text.split()) if len(word) > 1)
    return counts


def corpus_frequency(index, counts):
    """Root occurrences in the app's text, counting only words the word list reads one way."""
    frequency = Counter()
    for word, count in counts.items():
        roots = index.spelled.get(word, ())
        if len(roots) == 1: frequency[next(iter(roots))] += count
    return frequency


def resolver(index, quran, counts):
    """The pack's word -> ranked roots function, and the verified Quran words it draws on.
    `counts`: word -> occurrences across the app's Arabic text (`corpus_words`)."""
    verified, rootless = gold(index, quran)
    overrides = {spell(word): roots for word, roots in json.loads(OVERRIDES.read_text()).items() if not word.startswith("_")}
    for word, roots in overrides.items():
        assert set(roots) <= index.entries, (word, roots)
        verified[word] = Counter({root: len(roots) - rank for rank, root in enumerate(roots)})
    frequency = corpus_frequency(index, counts)
    for roots in verified.values(): frequency.update(roots)
    analyzer = Analyzer(index, frequency, verified, rootless)

    def resolve(word):
        """A word the Quran corpus verifies gets only its verified roots, most frequent reading first;
        a reading other texts give the same spelling is added through overrides.json, since the
        analyzer alone proposes noise (مالك: ملك, then أول). Other words get the analyzer's roots."""
        known = verified.get(word)
        if known: return [root for root, _ in known.most_common()][:MAX_ROOTS]
        return analyzer.roots(word)[:MAX_ROOTS]
    return resolve, verified


def build(source, target, quran=QURAN, corpora=CORPORA):
    index = Index(source)
    counts = corpus_words(corpora)
    resolve, verified = resolver(index, quran, counts)

    with sqlite3.connect(source.resolve().as_uri() + "?mode=ro", uri=True) as original:
        listed = {spell(form) for (form,) in original.execute("select form from word_forms")}
        dictionary = original.execute("select root," + ",".join(SOURCES) + " from dictionary order by root").fetchall()
    words = listed | {spell(root) for root in index.entries} | set(verified) | set(counts)

    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=target.parent) as stage:
        path = Path(stage) / target.name
        with sqlite3.connect(path) as db:
            db.executescript("""
                pragma user_version=1;
                create table entries(root text not null, source integer not null, body text not null);
                -- Ranked roots per word: `spelling` keeps hamza seats, `norm` folds them (normalize.py).
                create table words(spelling text not null, norm text not null, root text not null, rank integer not null,
                    primary key(spelling, rank)) without rowid;
                -- Words checked here and found to have no root (particles, names), which readers
                -- shouldn't retry without clitics.
                create table rootless(spelling text primary key) without rowid;
                -- Other headings the dictionaries file the same root under (سما: سمو, سمي).
                create table family(root text not null, member text not null, primary key(root, member)) without rowid;
            """)
            for root, *definitions in dictionary:
                for source_id, body in enumerate(definitions):
                    if body and body.strip():
                        db.execute("insert into entries values(?,?,?)", (root, source_id, body))
            db.executemany("insert into family values(?,?)",
                           ((root, member) for root, members in index.family.items() for member in members if member != root))
            resolved = {word: resolve(word) for word in sorted(words)}
            db.executemany("insert into words values(?,?,?,?)",
                           ((word, normalize(word), root, rank) for word, roots in resolved.items() for rank, root in enumerate(roots)))
            db.executemany("insert into rootless values(?)", ((word,) for word, roots in resolved.items() if not roots))
            db.executescript("""
                create index normalized on words(norm, rank);
                create unique index definitions on entries(root,source);
                analyze;
            """)
        validate(path)
        os.replace(path, target)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=PACK)
    args, corpora = content_arguments(parser)
    build(args.source, args.output, args.quran, corpora)
