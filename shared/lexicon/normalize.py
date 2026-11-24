"""Arabic spelling folds shared by the lexicon build and the app readers.

The Swift and Kotlin readers port `normalize` exactly; `shared/fixtures/lexicon-normalize.json`
holds the cases all three must agree on.
"""
import re
import unicodedata

# Quranic annotation signs, harakat, superscript alef (handled before this runs), and tatweel.
MARKS = re.compile(r"[ؐ-ؚـً-ٰٟۖ-ۭ]")
# Persian ی and ک appear in some ruling texts; they fold to their Arabic letters.
NON_LETTERS = re.compile(r"[^ء-غف-يٱکی]")
SPELLING = str.maketrans("ٱةکی", "اهكي")
# Hamza seats and alef maqsura, which typed and Uthmani text spell inconsistently.
HAMZA = str.maketrans("أإآىؤئ", "ااايوي")


def normalize(text):
    """Fold one word to the spelling the pack's `words.norm` column is keyed by."""
    return spell(text).translate(HAMZA)


def spell(text):
    """`normalize` without folding hamza seats, so مؤت (giver) and موت (death) stay apart."""
    return NON_LETTERS.sub("", letters(text)).translate(SPELLING)


def letters(text):
    text = unicodedata.normalize("NFKC", text)
    # Uthmani: alef maqsura carrying a superscript alef is just the maqsura; any other
    # superscript alef is a written alef in standard spelling (السمٰوٰت -> السماوات).
    text = text.replace("ىٰ", "ى").replace("ٰ", "ا")
    text = MARKS.sub("", text)
    # Uthmani writes hamza before alef where standard spelling has آ (ءامن، لءايات، قرءان).
    return re.sub("ءا(?=\\w)", "آ", text)

