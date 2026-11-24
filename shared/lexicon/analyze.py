"""Deterministic root lookup for words the lexicon's word list doesn't spell out.

`Index` is the lexicon's own word list (normalized form -> roots that have a dictionary entry).
`Analyzer.roots` collects candidates from the word itself, Uthmani spelling variants, and
clitic segmentations allowed by Arabic grammar, then ranks them. Every candidate is a stem
the word list already contains, so the analyzer never invents a root; it only finds which
listed word a spelling hides, and which reading is likeliest.
"""
from collections import defaultdict
import math
import sqlite3

from normalize import HAMZA, MARKS, normalize, spell

SOURCES = ("mo7eet", "faaq", "sa7a7", "nehay", "lesan", "tahzeeb")
HAMZA_AND_WEAK = str.maketrans("أإآؤئءى", "ااااااي")
WEAK = "وي"
# Headings no spelling rule relates: Tahdhib files the divine name apart from its root.
EXTRA_FAMILY = [("الله", "أله")]


def root_key(root):
    """Spelling-insensitive root identity: hamza seats and the final weak letter collapse."""
    root = root.translate(HAMZA_AND_WEAK)
    return root[:-1] + "ي" if root[-1:] in "اوي" else root


def realizations(root):
    """Radical spellings a lexicon heading stands for: alef as a hidden و/ي, and a biliteral
    heading as its doubled root (سما -> سمو, سمي; كان -> كون, كين; حق -> حقق)."""
    root = root.replace("ى", "ا")
    out = set()
    if len(root) == 2: out.add(root + root[-1])
    for i, letter in enumerate(root):
        if letter == "ا" and i > 0:
            out |= {root[:i] + weak + root[i + 1:] for weak in WEAK}
    return out - {root}


class Index:
    def __init__(self, source):
        with sqlite3.connect(source.resolve().as_uri() + "?mode=ro", uri=True) as db:
            rows = db.execute("select root," + ",".join(SOURCES) + " from dictionary").fetchall()
            forms = db.execute("select form, root, prefix from word_forms").fetchall()
        self.sources = {root: sum(1 for b in bodies if b and b.strip()) for root, *bodies in rows}
        self.entries = {root for root, count in self.sources.items() if count}
        self.by_key = defaultdict(set)
        for root in self.entries:
            self.by_key[root_key(root)].add(root)
        # Each heading's family: the heading plus the entries it stands for, so every source's
        # definition shows together however that source spells the root.
        self.family = {root: {root} for root in self.entries}
        links = [(root, member) for root in self.entries for member in realizations(root) & self.entries]
        for root, member in links + [link for link in EXTRA_FAMILY if set(link) <= self.entries]:
            self.family[root].add(member)
            self.family[member].add(root)
        # Listed words by exact spelling, and by spelling with hamza seats folded; `questions`
        # holds readings the word list only gets with a question alef (أفضل as أَفَضَلَّ).
        self.spelled = defaultdict(set)
        self.forms = defaultdict(set)
        self.questions = set()
        self.dropped = set()
        plain = set()
        for form, root, prefix in forms + [(root, root, "") for root in self.entries]:
            root = self.clean(root)
            if not root: continue
            self.spelled[spell(form)].add(root)
            self.forms[normalize(form)].add(root)
            (self.questions if str(prefix).startswith("أ") else plain).add((normalize(form), root))
        self.questions -= plain

    def clean(self, root):
        """The entry root a word-list root names, or None when no dictionary covers it."""
        root = MARKS.sub("", root).strip()
        if root in self.entries: return root
        candidates = self.by_key.get(root_key(root), ())
        if len(candidates) == 1: return next(iter(candidates))
        self.dropped.add(root)
        return None

    def related(self, a, b):
        return b in self.family.get(a, ())


# Proclitic chains: optional question alef (only before a conjunction), optional conjunction,
# then at most one of preposition / future sin / article combinations.
CONJUNCTIONS = ("", "و", "ف", "او", "اف")
ATTACHED = ("", "ب", "ك", "ل", "س", "ال", "بال", "كال", "لل")
PRONOUNS = ("ه", "ها", "هما", "هم", "هن", "ك", "كما", "كم", "كن", "ي", "نا", "ني")
INFLECTIONS = ("ت", "تم", "تما", "تن", "نا", "وا", "ا", "ن", "ون", "ين", "ان", "ات", "ه")
MIN_STEM = 3
# Ranking costs: each stripped clitic or restored radical, a match that only holds once hamza
# seats are folded, and a word-list reading of a stem the Quranic corpus reads otherwise.
STRIP_COST = 1.0
FOLD_COST = 1.0
UNVERIFIED_COST = 1.0
# The frequency prior only orders readings within a cost step; it can't outweigh one.
PRIOR_WEIGHT = 0.9
# Readings scoring more than MARGIN below the best are dropped (keeps 97% of right roots at
# ~1.1 roots per word), as is any reading needing more than MAX_COST (25% precise beyond it).
MARGIN = 1.0
MAX_COST = 2.0


class Analyzer:
    def __init__(self, index, frequency=None, verified=None, rootless=()):
        """`frequency`: root -> occurrences in the app's text, the prior for ambiguous spellings.
        `verified`: word -> Counter of Quranic corpus roots, trusted over the word list for stems.
        `rootless`: words the corpus marks as particles or names, which get no root."""
        self.index = index
        self.frequency = frequency or {}
        self.verified = verified or {}
        self.rootless = set(rootless) - set(self.verified)
        self.scale = math.log1p(max(self.frequency.values(), default=0)) or 1

    def listed(self, stem):
        """(root, cost) for the listed words a stem spells, preferring hamza-exact matches."""
        if stem in self.rootless: return []
        exact = self.index.spelled.get(stem, set())
        folded = stem.translate(HAMZA)
        found = [(root, ((folded, root) in self.index.questions) * STRIP_COST) for root in exact]
        found += [(root, FOLD_COST + ((folded, root) in self.index.questions) * STRIP_COST) for root in self.index.forms.get(folded, set()) - exact]
        if stem in self.verified:
            known = self.verified[stem]
            return [(root, 0) for root in known] + [(root, cost + UNVERIFIED_COST) for root, cost in found if root not in known]
        return found

    def roots(self, word):
        """Ranked roots for one word in `spell` form; empty when no listed word explains it."""
        splits = [word] + [stem for _, stem in self.stems(word)]
        # The longest verified reading decides between a particle (كالذي = ك + الذي) and a word.
        known = next((stem for stem in splits if stem in self.rootless or stem in self.verified), None)
        if not word or known in self.rootless: return []
        cost = {}
        for root, strips in self.candidates(word):
            cost[root] = min(cost.get(root, math.inf), strips)
        # A verified reading of any split outranks the word list's readings of the others. Not
        # across the article: a bare Quran word can be indefinite (رَبًّا), which ال rules out.
        readings = [(prefix, stem) for prefix, stem in [("", word)] + self.stems(word) if not prefix.endswith("ال")]
        # Including a stem under its pronoun suffix (بسمه = بسم + ه).
        readings += [(prefix, stem[:-len(p)]) for prefix, stem in readings for p in PRONOUNS if stem.endswith(p) and len(stem) - len(p) >= MIN_STEM]
        verified = set().union(*(self.verified.get(stem, ()) for _, stem in readings))
        if verified:
            cost = {root: value + (0 if any(root == known or self.index.related(root, known) for known in verified) else UNVERIFIED_COST)
                    for root, value in cost.items()}
        return self.rank(cost)

    def prior(self, root):
        """0...1: how common the root's family is in the app's text, on a log scale."""
        seen = sum(self.frequency.get(member, 0) for member in self.index.family.get(root, {root}))
        return math.log1p(seen) / self.scale

    def rank(self, cost):
        scores = {root: cost[root] * STRIP_COST - PRIOR_WEIGHT * self.prior(root) for root in cost if cost[root] <= MAX_COST}
        if not scores: return []
        best = min(scores.values())
        out = []
        for root in sorted(scores, key=lambda root: (scores[root], root)):
            # Readings far less likely than the best are noise in a list of definitions, and a
            # later spelling of an already listed root adds nothing.
            if scores[root] - best > MARGIN: break
            if not any(self.index.related(kept, root) for kept in out): out.append(root)
        return out

    def candidates(self, word):
        """(root, clitics stripped) for every listed reading of the word."""
        for spelling in [word] + self.spellings(word):
            for root, cost in self.listed(spelling): yield root, cost
        for prefix, stem in self.stems(word):
            for spelling in [stem] + self.spellings(stem):
                for root, cost in self.listed(spelling): yield root, cost + 1
        for prefix, stem in self.stems(word) + [("", word)]:
            # Verb subject and noun plural endings the word list often leaves out (فتحت، فسقوا).
            for ending in INFLECTIONS:
                if not stem.endswith(ending) or len(stem) - len(ending) < MIN_STEM: continue
                base = stem[:-len(ending)]
                for spelling in self.attachments(base):
                    for root, cost in self.listed(spelling): yield root, cost + 1 + bool(prefix)
        for prefix, stem in self.stems(word, minimum=2):
            # A doubled root loses its last radical in writing: الحق = ال + حقّ (حقق).
            if len(stem) == 2 and stem + stem[-1] in self.index.entries: yield stem + stem[-1], 1
        for root in self.weak_roots(word): yield root, 1
        for prefix, stem in self.stems(word) + [("", word)]:
            if prefix.endswith("ال") or stem.startswith("ال"): continue    # The article never takes a pronoun suffix.
            for pronoun in PRONOUNS:
                if not stem.endswith(pronoun): continue
                for base in self.attachments(stem[:-len(pronoun)]):
                    if len(base) < MIN_STEM: continue
                    for root, cost in self.listed(base): yield root, cost + 1 + bool(prefix)

    def weak_roots(self, word):
        """Roots whose weak radical a short verb form drops in writing: كنت, يكن (كون),
        يجب, تجد (وجب, وجد), قل (قول). Only two-letter cores, and only roots with an entry."""
        for prefix, stem in self.stems(word, minimum=2) + [("", word)]:
            for ending in ("",) + INFLECTIONS:
                core = stem[:len(stem) - len(ending)] if ending and stem.endswith(ending) else stem if not ending else None
                if not core: continue
                imperfect = core[:1] in ("ي", "ت", "ن", "ا") and len(core) == 3
                if imperfect: core = core[1:]
                if len(core) != 2: continue
                roots = {core[0] + weak + core[1] for weak in WEAK}
                if imperfect: roots.add("و" + core)
                yield from roots & self.index.entries

    @staticmethod
    def spellings(word):
        """Uthmani spellings a reader's selection can carry, mapped to standard spelling."""
        out = []
        if word.startswith("يا") and len(word) > 4: out.append(word[2:])          # ياقوم -> قوم
        if word.startswith("ويا") and len(word) > 5: out.append(word[3:])
        if word.startswith("ها") and len(word) > 3: out.append("ه" + word[2:])    # هاذا -> هذا
        if "ء" in word[1:-1]:
            # Uthmani writes a medial hamza on the line where standard spelling seats it.
            out += [word[0] + word[1:-1].replace("ء", seat) + word[-1] for seat in "أئؤ"]
        return out

    @staticmethod
    def stems(word, minimum=MIN_STEM):
        """(prefix, stem) splits allowed by the proclitic grammar."""
        splits = set()
        for conjunction in CONJUNCTIONS:
            if not word.startswith(conjunction): continue
            rest = word[len(conjunction):]
            for attached in ATTACHED:
                prefix = conjunction + attached
                if not prefix or not rest.startswith(attached): continue
                stem = rest[len(attached):]
                if attached == "لل":
                    # ل before the article drops its alef: للذين = ل + الذين, لله = ل + الله.
                    splits |= {(prefix, "ال" + stem), (prefix, "الل" + stem)}
                    continue
                if attached == "س" and not stem.startswith(("ي", "ت", "ن", "ا")): continue
                if attached.endswith("ال") and stem.startswith("ال"): continue
                splits.add((prefix, stem))
        return sorted((s for s in splits if len(s[1]) >= minimum), key=lambda s: (-len(s[1]), s))

    @staticmethod
    def attachments(base):
        """How a word's ending is spelled before a pronoun, mapped back to its bare spelling."""
        out = [base]
        if base.endswith("ت"): out.append(base[:-1] + "ه")      # نعمتك -> نعمه (نعمة)
        if base.endswith("ا"): out.append(base[:-1] + "ى")      # هداهم -> هدى
        if base.endswith("و"): out.append(base + "ا")           # قاتلوهم -> قاتلوا
        if base.endswith("تمو"): out.append(base[:-1])          # اتيتموه -> اتيتم
        return out
