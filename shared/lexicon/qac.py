"""Verified Quran word roots from the vendored Quranic Arabic Corpus morphology."""
from collections import Counter, defaultdict
import gzip
from pathlib import Path
import sqlite3

from analyze import root_key
from normalize import normalize, spell

MORPHOLOGY = Path(__file__).parent / "vendor/quran-morphology.txt.gz"
# Corpus roots the lexicons file under a different spelling than the folds in `root_key` reach.
ALIASES = {
    "طمأن": "طمن", "صرصر": "صرر", "صفصف": "صفف", "دمدم": "دمم",
    "عدو": "عدا", "بلو": "بلا", "شكو": "شكا", "لؤلؤ": "لألأ",
}


def corpus_roots(index, path=MORPHOLOGY):
    """(sura, aya, word) -> (voweled corpus spelling, lexicon roots) for every Quran word."""
    words = defaultdict(set)
    spellings = defaultdict(str)
    unmapped = set()
    with gzip.open(path, "rt", encoding="utf-8") as file:
        for line in file:
            location, segment, _, features = line.rstrip("\n").split("\t")
            sura, aya, word, _ = map(int, location.split(":"))
            spellings[(sura, aya, word)] += segment
            for feature in features.split("|"):
                if not feature.startswith("ROOT:"): continue
                root = feature[5:].strip()
                root = ALIASES.get(root, root)
                if root not in index.entries:
                    matches = index.by_key.get(root_key(root), set())
                    root = next(iter(matches)) if len(matches) == 1 else None
                if root: words[(sura, aya, word)].add(root)
                else: unmapped.add(feature[5:])
    assert not unmapped, f"Quranic corpus roots with no lexicon entry: {sorted(unmapped)}"
    return {location: (spelling, words[location]) for location, spelling in spellings.items()}


def quran_words(quran):
    """((sura, aya, word), spellings) in reading order, skipping pause-mark tokens. Spellings
    are the word in `spell` form, then standard spellings of its superscript alefs
    (ذٰلك -> ذالك, ذلك; هٰذا -> هاذا, هذا; الصلوٰة -> الصلاه)."""
    with sqlite3.connect(quran.resolve().as_uri() + "?mode=ro", uri=True) as db:
        for sura, aya, text in db.execute("select sura, aya, text from quran order by sura, aya"):
            tokens = [token for token in text.split() if spell(token)]
            for position, token in enumerate(tokens, 1):
                spellings = [spell(token)]
                # Uthmani و with a superscript alef is a standard alef (الصلوٰة، الربوٰا).
                standard = token.replace("وٰا۟", "ا").replace("وٰ", "ا")
                for variant in (standard, token.replace("ىٰ", "ى").replace("ٰ", "")):
                    if spell(variant) and spell(variant) not in spellings: spellings.append(spell(variant))
                yield (sura, aya, position), spellings


def gold(index, quran):
    """Quran word (`spell` form) -> Counter of verified roots, plus the set of words with none."""
    corpus = corpus_roots(index)
    by_word = defaultdict(Counter)
    rootless = set()
    aligned = 0
    for location, spellings in quran_words(quran):
        voweled, roots = corpus.get(location, ("", set()))
        # The corpus keeps interrogative hamza (ءالله) the app text drops; anything else is a
        # tokenization shift, which is skipped rather than guessed.
        if normalize(voweled) not in (normalize(spellings[0]), "ء" + normalize(spellings[0])): continue
        aligned += 1
        # The app's lightly voweled text writes a final ya dotless (الَّتى); the corpus's full
        # vowels tell it apart from alef maqsura: kasra before it makes it ي (عَلَى keeps ى).
        if "ِى" in voweled:
            dotted = spell(voweled.replace("ِى", "ِي"))
            if dotted not in spellings: spellings = spellings + [dotted]
        for word in spellings:
            if roots: by_word[word].update(roots)
            else: rootless.add(word)
    assert aligned > 77_350, f"Only {aligned} Quran words align with the corpus"
    return by_word, rootless - set(by_word)
