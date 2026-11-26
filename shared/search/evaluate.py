"""Measure Quran search recall for typed standard spellings; run after changing quran_spelling.py.

Oracle: a Quran word counts as findable when some standard spelling the lexicon lists for it
(shared/lexicon `Index`) resolves to the word's index key. A second check types every lexicon
word the Quran index lacks and reports how often, and to what, it is rewritten.
"""
import argparse
from collections import Counter
from pathlib import Path
import sqlite3
import sys

HERE = Path(__file__).parent
sys.path[:0] = [str(HERE), str(HERE.parent / "lexicon")]
from analyze import Index  # noqa: E402
from normalize import normalize, spell  # noqa: E402
from quran_spelling import Vocabulary, fold, resolve  # noqa: E402

ROOT = HERE.parents[1]


def spellings(token):
    """Standard spellings of a Quran token (lexicon/qac.py): superscript alef as alef or as nothing, و+alef."""
    standard = token.replace("وٰا۟", "ا").replace("وٰ", "ا")
    return {spell(v) for v in (token, standard, token.replace("ىٰ", "ى").replace("ٰ", ""))} - {""}


def main(args):
    index = Index(args.lexicon)
    db = sqlite3.connect(args.quran.resolve().as_uri() + "?mode=ro", uri=True)
    vocabulary = Vocabulary(db.execute("select term, doc from quran_words_vocab"))
    total = findable = before = after = 0
    failures, rewrites = Counter(), Counter()
    for (text,) in db.execute("select text from quran"):
        for token in text.split():
            key = fold(token)
            if not key: continue
            typed = {fold(v) for v in spellings(token) if normalize(v) in index.forms}
            if not typed: continue
            total += 1
            was = key in typed
            now = was or any(resolve(t, vocabulary) == key for t in typed)
            before += was
            after += now
            if now and not was: rewrites[key] += 1
            if not now: failures[key, "/".join(sorted(typed))] += 1
    print(f"Quran words with a standard spelling in the lexicon: {total}")
    print(f"  found by typing it, current index key:  {100 * before / total:.1f}%")
    print(f"  found by typing it, with resolve():     {100 * after / total:.1f}%")
    print("  still missed:", [f"{k} <- {t}" for (k, t), _ in failures.most_common(12)])
    print("  newly found, most common:", [k for k, _ in rewrites.most_common(10)])

    # Rewrites of typed words the index does not hold: wrong only if the word is unrelated.
    absent = [w for w in {fold(f) for f in index.forms} if len(w) >= 3 and not vocabulary.weight(w)]
    changed = [(w, resolve(w, vocabulary)) for w in absent]
    changed = [(w, r) for w, r in changed if r != w]
    print(f"Lexicon words the index lacks: {len(absent)}; rewritten to an indexed spelling: {len(changed)} ({100 * len(changed) / len(absent):.1f}%)")
    import random
    random.seed(1)
    print("  sample:", [f"{w}->{r}" for w, r in random.sample(changed, min(25, len(changed)))])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lexicon", type=Path, default=ROOT / "lexicon.sqlite")
    parser.add_argument("--quran", type=Path, default=ROOT / "apple/Muntathir/Resources/Quran/quran.db")
    main(parser.parse_args())
