"""Measure root lookup against verified roots; run after changing normalize.py or analyze.py.

Quran: every word's Quranic Arabic Corpus root, so it scores the analyzer alone (the shipped
pack also stores these roots directly). Hadith: hand-checked words in
`shared/fixtures/lexicon-gold.json` through the shipped lookup, a regression gate that must
stay at zero failures.
A result is wrong when it names no verified root, including any root for a rootless particle.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent))
from analyze import Analyzer, Index  # noqa: E402
from build import content_arguments, corpus_frequency, corpus_words, resolver  # noqa: E402
from normalize import spell  # noqa: E402
from qac import gold  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "shared/fixtures/lexicon-gold.json"


def same(index, root, expected):
    """A verified root, a lexicon spelling of it (سما for سمو), or its final و/ي counterpart,
    which the lexicographers themselves file either way (رضي، رضو)."""
    if root == expected or index.related(root, expected): return True
    return len(root) == len(expected) and root[:-1] == expected[:-1] and {root[-1], expected[-1]} <= set("وي")


def correct(index, found, expected):
    return any(same(index, root, gold_root) for root in found for gold_root in expected)


def quran(analyzer, index, verified, rootless, show):
    counts = Counter()
    wrong = Counter()
    for word, roots in verified.items():
        weight = sum(roots.values())
        found = analyzer.roots(word)
        counts["words"] += weight
        if not found: counts["missing"] += weight; continue
        if not correct(index, found[:1], roots):
            counts["wrong"] += weight
            if correct(index, found, roots): counts["lower"] += weight
            wrong[word, "/".join(found), "/".join(roots)] += weight
        counts["top3"] += weight * correct(index, found[:3], roots)
        if weight <= 2:
            counts["rare"] += weight
            counts["rare right"] += weight * correct(index, found[:1], roots)
            counts["rare top3"] += weight * correct(index, found[:3], roots)
    particles = sum(1 for word in rootless if analyzer.roots(word))
    answered = counts["words"] - counts["missing"]
    print(f"Quran: {counts['words']} words with a verified root; answered {100 * answered / counts['words']:.1f}%, "
          f"top-1 precision {100 * (answered - counts['wrong']) / answered:.2f}% "
          f"(right root ranked lower for {counts['lower']}); {particles}/{len(rootless)} rootless words given a root")
    print(f"  Right root in the top 3: {100 * counts['top3'] / answered:.2f}%")
    print(f"  Words seen at most twice (closest to hadith-only vocabulary): top-1 "
          f"{100 * counts['rare right'] / counts['rare']:.2f}%, top 3 {100 * counts['rare top3'] / counts['rare']:.2f}% of {counts['rare']}")
    for (word, found, expected), count in wrong.most_common(show):
        print(f"  {count:4} {word} -> {found}  expected {expected}")


def fixture(index, quran_path, counts):
    """The shipped lookup (verified Quran roots, then the analyzer) on hand-checked words."""
    resolve, _ = resolver(index, quran_path, counts)
    cases = json.loads(FIXTURE.read_text())
    failures = []
    for case in cases:
        found = resolve(spell(case["word"]))
        expected = case["roots"]
        # Optional cases are particles: no root is fine, a wrong root is not.
        if (found or not case.get("optional")) and not correct(index, found[:1], expected):
            failures.append((case["word"], found, expected))
    print(f"Fixture: {len(cases) - len(failures)}/{len(cases)} pass")
    for word, found, expected in failures: print(f"  {word} -> {found or '—'}  expected {expected or '—'}")
    return not failures


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--show", type=int, default=40, help="most frequent wrong results to list")
    args, corpora = content_arguments(parser)
    index = Index(args.source)
    verified, rootless = gold(index, args.quran)
    counts = corpus_words(corpora)
    print("Analyzer alone, without a frequency prior:")
    quran(Analyzer(index), index, verified, rootless, 0)
    # Out of sample: the prior comes from the other content only, and no corpus word is known.
    print("Analyzer alone, with the prior from hadith, rulings and sermons:")
    quran(Analyzer(index, corpus_frequency(index, counts)), index, verified, rootless, args.show)
    if not fixture(index, args.quran, counts): sys.exit(1)
