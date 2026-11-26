import Foundation
import os

/// Index terms with the number of verses holding each.
struct QuranVocabulary: Sendable {
    private let docs: [String: Int]
    private let sorted: [String]

    init(_ terms: [(term: String, docs: Int)]) {
        docs = Dictionary(terms.map { ($0.term, $0.docs) }, uniquingKeysWith: { first, _ in first })
        sorted = docs.keys.sorted()
    }

    /// Verses holding the term, or any term starting with it when `prefix`.
    func weight(_ spelling: String, prefix: Bool) -> Int {
        guard prefix else { return docs[spelling] ?? 0 }
        var low = 0, high = sorted.count
        while low < high {
            let middle = (low + high) / 2
            if sorted[middle] < spelling {
                low = middle + 1
            } else {
                high = middle
            }
        }
        var total = 0
        while low < sorted.count, sorted[low].hasPrefix(spelling) {
            total += docs[sorted[low]] ?? 0
            low += 1
        }
        return total
    }
}

/// Typed Arabic to the spelling the Quran word index holds.
///
/// The index folds the Uthmani text (`QuranSearchText.normalize`): the superscript alef, small ya and
/// other marks are deleted, so words that standard spelling writes with a long vowel lose it:
/// الصلاة is indexed as الصلوه, الكتاب as الكتب, النبيين as النبين, آمنوا as ءامنوا. Typing the standard
/// spelling finds nothing. `resolve` rewrites a typed key to a spelling the index really contains, so it
/// never invents a match. Port of shared/search/quran_spelling.py; shared/fixtures/quran-spelling.json
/// holds the cases both must agree on.
enum QuranSpelling {
    /// What one alef may stand for in Uthmani spelling: itself, nothing (superscript alef), و or وا
    /// (الصلوٰة, الربوٰا), ءا (ءامنوا). Fewest edits first.
    private static let alefs = ["ا", "", "و", "وا", "ءا"]
    private static let maxAlefs = 3
    private static let maxDeletions = 6
    private static let minLetters = 2
    private static let seats: [Character: [Character]] = ["و": ["ؤ"], "ي": ["ئ"], "ئ": ["ء"], "ؤ": ["ء"]]

    /// Spellings the index may hold for a typed key, with the edits each takes; includes the key itself.
    static func candidates(_ key: String) -> [String: Int] {
        var found = [key: 0]
        func add(_ spelling: String, _ edits: Int) {
            found[spelling] = min(edits, found[spelling] ?? edits)
        }
        guard key.unicodeScalars.contains(where: { (0x600 ... 0x6FF).contains($0.value) }) else { return found }
        let letters = Array(key)
        // A leading alef is a madda (آمنوا = ءامنوا) unless it is the article's.
        let article = key.hasPrefix("ال")
        let positions = letters.indices.filter { letters[$0] == "ا" && ($0 > 0 || !article) }
        let medial = positions.count - (letters.first == "ا" && !article ? 1 : 0)
        let options = medial <= maxAlefs ? alefs : medial <= maxDeletions ? Array(alefs.prefix(2)) : Array(alefs.prefix(1))
        var choice = [Int](repeating: 0, count: positions.count)
        while true {
            var spelling = "", edits = 0, last = 0, valid = true
            for (position, pick) in zip(positions, choice) {
                // Only a madda can open a word; the others need a letter before them.
                if position == 0, !["ا", "ءا"].contains(options[pick]) {
                    valid = false
                }
                spelling += String(letters[last ..< position]) + options[pick]
                if pick != 0 {
                    edits += 1
                }
                last = position + 1
            }
            spelling += String(letters[last...])
            if valid {
                add(spelling, edits)
            }
            var slot = positions.count - 1
            while slot >= 0 {
                choice[slot] += 1
                if choice[slot] < options.count {
                    break
                }
                choice[slot] = 0
                slot -= 1
            }
            if slot < 0 {
                break
            }
        }
        // A doubled ya is one ya plus the small ya the fold deletes (النبيين).
        for (spelling, edits) in found where spelling.contains("يي") {
            add(spelling.replacingOccurrences(of: "يي", with: "ي"), edits + 1)
        }
        // Typed without the hamza seat that Uthmani spelling keeps (المومنين, الملايكة), or with a seat
        // where the mushaf writes the hamza alone (إسرائيل = اسرءيل).
        for (spelling, edits) in found {
            let characters = Array(spelling)
            for (index, character) in characters.enumerated() {
                for seat in seats[character] ?? [] {
                    var changed = characters
                    changed[index] = seat
                    add(String(changed), edits + 1)
                }
            }
        }
        return found.filter { $0.key.count >= minLetters || $0.key == key }
    }

    /// The key if the index holds it, else the spelling it holds with the fewest edits, then the most
    /// typed letters kept (replacing an alef beats deleting it), then the most verses.
    static func resolve(_ key: String, in vocabulary: QuranVocabulary, prefix: Bool) -> String {
        if vocabulary.weight(key, prefix: prefix) > 0 {
            return key
        }
        var best: (Int, Int, Int, String)?
        for (spelling, edits) in candidates(key) {
            let weight = vocabulary.weight(spelling, prefix: prefix)
            guard weight > 0 else { continue }
            let candidate = (edits, -spelling.count, -weight, spelling)
            if best == nil || candidate < best! {
                best = candidate
            }
        }
        return best?.3 ?? key
    }

    /// Query terms in the spelling the Arabic index holds. The last term also matches as a prefix
    /// once it has three letters (`QuranSearchText.ftsQuery`), so it resolves as one.
    static func resolve(_ terms: [String], in vocabulary: QuranVocabulary) -> [String] {
        terms.enumerated().map { offset, term in
            resolve(term, in: vocabulary, prefix: offset == terms.count - 1 && term.count >= 3)
        }
    }

    private static let alternativeCache = OSAllocatedUnfairLock(initialState: [String: [String]]())
    private static let alternativeLimit = 40

    /// Other spellings of a typed term to look for in text, likeliest first, in the folded form
    /// `SearchMatch` compares: the same candidates `resolve` weighs, judged by the text being highlighted
    /// instead of the index. Only used when the typed term itself does not occur.
    static func alternatives(for term: String) -> [String] {
        let key = QuranSearchText.normalize(term)
        if let known = alternativeCache.withLock({ $0[key] }) {
            return known
        }
        let own = QuranSearchText.fold(key)
        var seen: Set<String> = [own]
        let ordered = candidates(key).filter { $0.value <= 2 }
            .sorted { ($0.value, -$0.key.count, $0.key) < ($1.value, -$1.key.count, $1.key) }
            .map { QuranSearchText.fold(QuranSearchText.normalize($0.key)) }
            .filter { seen.insert($0).inserted }
        let result = Array(ordered.prefix(alternativeLimit))
        alternativeCache.withLock { cache in
            if cache.count > 256 {
                cache.removeAll()
            }
            cache[key] = result
        }
        return result
    }
}
