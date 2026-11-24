"""Typed Arabic -> the spelling the Quran word index holds.

The index folds the Uthmani text (`fold`): superscript alef, small ya and the other marks are
deleted, so words standard spelling writes with a long vowel the mushaf marks differently lose it:
الصلاة is indexed as الصلوه, الكتاب as الكتب, النبيين as النبين, آمنوا as ءامنوا. Typing the
standard spelling finds nothing. `resolve` rewrites a typed key to the spelling the index has, but
only to a spelling the index really contains, so it never invents a match. Swift and Kotlin port
`candidates` and `resolve`; `shared/fixtures/quran-spelling.json` holds the cases all three share.
"""
from bisect import bisect_left
from itertools import product

# The index key (QuranSearchText.normalize in the apps, `norm` in build/quran/build.sh).
FOLD = {0x622: "ا", 0x623: "ا", 0x625: "ا", 0x671: "ا", 0x649: "ي", 0x629: "ه"}
STRIPPED = [(0x610, 0x61A), (0x640, 0x640), (0x64B, 0x65F), (0x670, 0x670), (0x6D6, 0x6ED)]

# What one alef may stand for in Uthmani spelling: itself, nothing (superscript alef), و or وا
# (الصلوٰة, الربوٰا), ءا (ءامنوا). Listed fewest edits first.
ALEF = ("ا", "", "و", "وا", "ءا")
MAX_ALEFS = 3          # beyond this only deletion is tried, which covers most superscript alefs
MAX_DELETIONS = 6
MIN_LETTERS = 2


def fold(text):
    out = []
    for char in text:
        code = ord(char)
        if any(low <= code <= high for low, high in STRIPPED): continue
        out.append(FOLD.get(code, char))
    return "".join(out)


def candidates(key):
    """{spelling: edits} the index may hold for a typed key, including the key itself."""
    found = {key: 0}

    def add(spelling, edits):
        found[spelling] = min(edits, found.get(spelling, edits))

    if not any("؀" <= char <= "ۿ" for char in key): return found
    # A leading alef is a madda (آمنوا = ءامنوا) unless it is the article's.
    alefs = [i for i, char in enumerate(key) if char == "ا" and (i > 0 or not key.startswith("ال"))]
    medial = len(alefs) - (key[:1] == "ا" and not key.startswith("ال"))
    if medial <= MAX_ALEFS: options = ALEF
    elif medial <= MAX_DELETIONS: options = ALEF[:2]
    else: options = ALEF[:1]
    for choice in product(range(len(options)), repeat=len(alefs)):
        spelling, edits, last, valid = [], 0, 0, True
        for position, pick in zip(alefs, choice):
            # Only a madda can open a word; the others need a letter before them.
            if position == 0 and options[pick] not in ("ا", "ءا"): valid = False
            spelling += [key[last:position], options[pick]]
            edits += pick != 0
            last = position + 1
        spelling.append(key[last:])
        if valid: add("".join(spelling), edits)
    # A doubled ya is one ya plus the small ya the fold deletes (النبيين).
    for spelling, edits in list(found.items()):
        if "يي" in spelling: add(spelling.replace("يي", "ي"), edits + 1)
    # Typed without the hamza seat that Uthmani spelling keeps (المومنين, الملايكة).
    for spelling, edits in list(found.items()):
        for i, char in enumerate(spelling):
            # Or typed with a seat where the mushaf writes the hamza alone (إسرائيل = اسرءيل).
            for seat in {"و": "ؤ", "ي": "ئ", "ئ": "ء", "ؤ": "ء"}.get(char, ""):
                add(spelling[:i] + seat + spelling[i + 1:], edits + 1)
    return {spelling: edits for spelling, edits in found.items() if len(spelling) >= MIN_LETTERS or spelling == key}


class Vocabulary:
    """Index terms with the number of verses holding them."""

    def __init__(self, terms):
        self.docs = dict(terms)
        self.sorted = sorted(self.docs)

    def weight(self, spelling, prefix=False):
        if not prefix: return self.docs.get(spelling, 0)
        total, i = 0, bisect_left(self.sorted, spelling)
        while i < len(self.sorted) and self.sorted[i].startswith(spelling):
            total += self.docs[self.sorted[i]]
            i += 1
        return total


def resolve(key, vocabulary, prefix=False):
    """The key if the index holds it, else the spelling it holds with the fewest edits, then the most
    typed letters kept (replacing an alef beats deleting it), then the most verses."""
    if vocabulary.weight(key, prefix): return key
    present = {}
    for spelling, edits in candidates(key).items():
        weight = vocabulary.weight(spelling, prefix)
        if weight: present[spelling] = (edits, -len(spelling), -weight, spelling)
    return min(present.values())[3] if present else key
