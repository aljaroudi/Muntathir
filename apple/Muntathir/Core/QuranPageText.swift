import Foundation

/// Maps QPC display words to the unchanged Tanzil text used by saved highlights.
struct QuranPageText {
    struct Word {
        let display: NSRange
        let source: String
        let canonical: NSRange?
    }

    struct Line {
        let range: NSRange
        let kind: QuranPage.Line.Kind
        let centered: Bool
    }

    let text: String
    let words: [Word]
    let lines: [Line]
    let verses: [String: Ayah]

    init(page: QuranPage, surahs: [QuranSurah]) {
        var text = ""
        var words: [Word] = []
        var lines: [Line] = []
        let ranges = page.verses.mapValues { Self.canonicalWords($0) }
        for line in page.lines {
            if let previous = lines.last {
                text += previous.kind == .ayah && !previous.centered && line.kind == .ayah && !line.centered ? "\u{2028}" : "\n"
            }
            let start = text.utf16.count
            switch line.kind {
            case .surahName:
                text += "سُورَةُ " + (surahs.first { $0.id == line.surah }?.arabic ?? "")
            case .basmallah:
                text += "بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ"
            case .ayah:
                for (offset, word) in line.words.enumerated() {
                    if offset > 0 {
                        text += " "
                    }
                    let range = NSRange(location: text.utf16.count, length: word.text.utf16.count)
                    text += word.text
                    guard let verse = page.verses[word.index] else { continue }
                    let canonical = ranges[word.index] ?? []
                    words.append(Word(display: range, source: verse.id,
                                      canonical: canonical.indices.contains(word.word - 1) ? canonical[word.word - 1] : nil))
                }
            }
            lines.append(Line(range: NSRange(location: start, length: text.utf16.count - start), kind: line.kind, centered: line.centered))
        }
        self.text = text
        self.words = words
        self.lines = lines
        verses = Dictionary(uniqueKeysWithValues: page.verses.values.map { ($0.id, $0) })
    }

    static func canonicalWords(_ verse: Ayah) -> [NSRange] {
        var ranges = verse.text.ranges(of: /\S+/).filter { range in
            verse.text[range].unicodeScalars.contains { CharacterSet.letters.contains($0) && $0.value != 0x0640 }
        }.map { NSRange($0, in: verse.text) }
        // QPC joins إِل ياسين into one word; Tanzil keeps the two source words.
        if verse.id == "37:130", ranges.count == 4 {
            ranges[2] = NSUnionRange(ranges[2], ranges[3])
            ranges.removeLast()
        }
        return ranges
    }

    func sources(in selection: [NSRange]) -> [String] {
        var seen = Set<String>()
        return words.filter { word in selection.contains { NSIntersectionRange(word.display, $0).length > 0 } }
            .map(\.source).filter { seen.insert($0).inserted }
    }

    func highlights(in selection: [NSRange]) -> [ReadingHighlight] {
        sources(in: selection).compactMap { source in
            guard let verse = verses[source] else { return nil }
            let selected = words.filter { word in word.source == source && selection.contains { NSIntersectionRange(word.display, $0).length > 0 } }
            let mapped = selected.flatMap { word -> [NSRange] in
                guard let canonical = word.canonical else { return [] }
                return selection.compactMap { Self.map($0, from: word.display, in: text, to: canonical, in: verse.text) }
            }
            let ranges = Self.merged(mapped, bridging: Self.canonicalWords(verse)).compactMap { HighlightRange($0, in: verse.text) }
            guard !ranges.isEmpty else { return nil }
            return ReadingHighlight(source: source, isHadith: false, block: "arabic", ranges: ranges,
                                    excerpt: ranges.map(\.quote).joined(separator: " … "), reference: source)
        }
    }

    func displayRanges(for highlight: ReadingHighlight) -> [NSRange] {
        guard !highlight.isHadith, let verse = verses[highlight.source] else { return [] }
        let canonical = highlight.ranges(in: verse.text, block: "arabic")
        let matching = words.filter { $0.source == highlight.source }.flatMap { word -> [NSRange] in
            if highlight.block == nil {
                return [word.display]
            }
            guard let range = word.canonical else { return [] }
            return canonical.compactMap { Self.map($0, from: range, in: verse.text, to: word.display, in: text) }
        }
        return Self.merged(matching, bridging: words.filter { $0.source == highlight.source }.map(\.display))
    }

    private static func map(_ selection: NSRange, from source: NSRange, in sourceText: String, to target: NSRange, in targetText: String) -> NSRange? {
        let intersection = NSIntersectionRange(selection, source)
        guard intersection.length > 0 else { return nil }
        if intersection == source {
            return target
        }
        func letters(_ text: String, range: NSRange) -> [(key: String, range: NSRange)] {
            guard let indices = Range(range, in: text) else { return [] }
            return text[indices].indices.compactMap { index in
                let key = QuranSearchText.normalize(String(text[index])).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return nil }
                return (key, NSRange(index ..< text.index(after: index), in: text))
            }
        }
        let from = letters(sourceText, range: source)
        let to = letters(targetText, range: target)
        // shortcut: distinct spellings use the containing word until an edition-specific character alignment is available.
        guard !from.isEmpty, from.map(\.key) == to.map(\.key) else { return target }
        let selected = zip(from, to).filter { NSIntersectionRange($0.0.range, intersection).length > 0 }.map(\.1.range)
        guard let first = selected.first, let last = selected.last else { return target }
        return NSUnionRange(first, last)
    }

    /// Merge adjacent selected words, including their whitespace, without filling unselected words.
    private static func merged(_ ranges: [NSRange], bridging words: [NSRange]? = nil) -> [NSRange] {
        var result: [NSRange] = []
        for range in ranges.sorted(by: { $0.location < $1.location }) {
            if let last = result.last {
                let gap = NSRange(location: NSMaxRange(last), length: max(0, range.location - NSMaxRange(last)))
                let containsWord = words?.contains { NSIntersectionRange($0, gap).length > 0 } ?? false
                if !containsWord {
                    result[result.count - 1] = NSUnionRange(last, range)
                    continue
                }
            }
            result.append(range)
        }
        return result
    }
}
