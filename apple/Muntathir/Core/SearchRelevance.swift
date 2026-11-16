import Foundation

/// Comparable relevance within explicit match tiers. Source text stays untouched.
struct SearchRelevance: Comparable, Sendable {
    let tier: Int
    let missing: Int
    let fragments: Int
    let distance: Int
    let length: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.tier, lhs.missing, lhs.fragments, lhs.distance, lhs.length)
            < (rhs.tier, rhs.missing, rhs.fragments, rhs.distance, rhs.length)
    }

    static func score(_ text: String, terms: [String]) -> Self? {
        guard !text.isEmpty, !terms.isEmpty else { return nil }
        let query = terms.map(fold)
        let asciiQuery = query.allSatisfy { $0.utf8.allSatisfy { $0 < 128 } }
        if asciiQuery, query.contains(where: { $0.contains(where: \.isLetter) }),
           !text.unicodeScalars.contains(where: { $0.value < 128 && CharacterSet.letters.contains($0) })
        {
            return nil
        }
        let normalized = fold(QuranSearchText.normalize(text))
        let absent = query.filter { !normalized.contains($0) }
        if absent.count > 1 {
            return nil
        }
        if !absent.isEmpty, query.contains(where: { $0.count < 3 }) {
            return nil
        }
        let words = QuranSearchText.terms(text).map(fold)
        guard !query.isEmpty, !words.isEmpty else { return nil }
        var positions: [[Int]] = []
        var fragments = 0
        var corrections = 0
        for term in query {
            let exact = words.indices.filter { words[$0] == term }
            if !exact.isEmpty {
                positions.append(exact); continue
            }
            let partial = words.indices.filter { words[$0].contains(term) }
            if !partial.isEmpty {
                positions.append(partial); fragments += 1; continue
            }
            let corrected = words.indices.filter { close(words[$0], term) }
            if !corrected.isEmpty {
                positions.append(corrected); corrections += 1; continue
            }
            positions.append([])
        }
        let missing = positions.filter(\.isEmpty).count
        let literal = QuranSearchText.literalRank(text, terms: terms)
        let tier = literal < 2 ? literal : 2
        if tier == 2 {
            guard query.allSatisfy({ $0.count >= 3 }),
                  missing + corrections <= 1,
                  missing == 0 || query.count >= 3 else { return nil }
        }
        // Sliding window finds the tightest span covering every matched query term.
        let events = positions.enumerated().flatMap { term, offsets in offsets.map { ($0, term) } }
            .sorted { $0.0 < $1.0 }
        let required = positions.count - missing
        var counts: [Int: Int] = [:]
        var left = 0
        var distance = Int.max
        for right in events.indices {
            counts[events[right].1, default: 0] += 1
            while counts.count == required, left <= right {
                distance = min(distance, events[right].0 - events[left].0)
                let key = events[left].1
                counts[key, default: 0] -= 1
                if counts[key] == 0 {
                    counts.removeValue(forKey: key)
                }
                left += 1
            }
        }
        return Self(tier: tier, missing: missing + corrections, fragments: fragments,
                    distance: distance, length: words.count)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
    }

    /// One edit or adjacent transposition, restricted to words with enough evidence.
    private static func close(_ word: String, _ query: String) -> Bool {
        guard query.count >= 5, abs(word.count - query.count) <= 1 else { return false }
        let a = Array(word), b = Array(query)
        if a.count == b.count {
            let differences = a.indices.filter { a[$0] != b[$0] }
            if differences.count == 1 {
                return true
            }
            if differences.count == 2 {
                let first = differences[0], second = differences[1]
                return second == first + 1 && a[first] == b[second] && a[second] == b[first]
            }
            return false
        }
        let longer = a.count > b.count ? a : b
        let shorter = a.count > b.count ? b : a
        var offset = 0
        for index in shorter.indices {
            if longer[index + offset] != shorter[index] {
                guard offset == 0 else { return false }
                offset = 1
                if longer[index + offset] != shorter[index] {
                    return false
                }
            }
        }
        return true
    }
}
