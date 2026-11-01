#!/usr/bin/env python3
"""Align QAC roots with the normalized Arabic text: fills quran_search.root and quran_roots_raw."""

import sqlite3
import sys
from collections import defaultdict

morphology, database = sys.argv[1:3]

forms = defaultdict(lambda: defaultdict(str))  # (sura, aya) -> {word: form}
roots = defaultdict(dict)  # (sura, aya) -> {word: root}
for line in open(morphology, encoding="utf-8"):
    location, form, _, features = line.rstrip("\n").split("\t")
    sura, aya, word, _ = map(int, location.split(":"))
    forms[sura, aya][word] += form
    for feature in features.split("|"):
        if feature.startswith("ROOT:"):
            roots[sura, aya][word] = feature[5:]

db = sqlite3.connect(database)
verses, pairs, mismatches = [], set(), []
for index, sura, aya, text in db.execute('SELECT "index", sura, aya, text FROM quran_search'):
    tokens = text.split()
    numbers = sorted(forms[sura, aya])
    # QAC writes "بعدما" where the text has "بعد ما" in these three verses.
    joined = {(2, 181, 3), (8, 6, 4), (13, 37, 8)}
    spans = [2 if (sura, aya, n) in joined else len(forms[sura, aya][n].split()) for n in numbers]
    # Tanzil prefixes verse 1 of every surah except 1 and 9 with the 4-word basmala; QAC does not.
    skip = 4 if aya == 1 and sura not in (1, 9) else 0
    if len(tokens) != skip + sum(spans):
        mismatches.append(f"{sura}:{aya} text={len(tokens)} qac={skip + sum(spans)}")
        continue
    position, verse = skip, []
    for n, span in zip(numbers, spans):
        if root := roots[sura, aya].get(n):
            verse.append(root)
            pairs.update((token, root) for token in tokens[position:position + span])
        position += span
    verses.append((" ".join(verse), index))

if mismatches:
    sys.exit("Word counts differ:\n" + "\n".join(mismatches))

with db:
    db.executemany('UPDATE quran_search SET root = ? WHERE "index" = ?', verses)
    db.executemany("INSERT INTO quran_roots_raw VALUES (?, ?)", sorted(pairs))
