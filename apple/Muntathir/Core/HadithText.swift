import SwiftUI

/// Parses once in the reader actor; views receive prepared text rather than reparsing while scrolling.
enum HadithText {
    static let startMarker = "\u{E000}"
    static let endMarker = "\u{E001}"

    static func markdown(_ source: String) -> AttributedString {
        (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible))) ?? AttributedString(source)
    }

    static func paragraphs(_ text: AttributedString) -> [HadithParagraph] {
        text.runs[\.presentationIntent].enumerated().map { index, run in
            let (intent, range) = run
            return HadithParagraph(id: index, text: AttributedString(text[range]), intent: intent)
        }
    }

    static func flattened(_ text: AttributedString) -> AttributedString {
        var result = AttributedString()
        for paragraph in paragraphs(text) {
            if !result.characters.isEmpty {
                result.append(AttributedString("\n"))
            }
            var content = paragraph.text
            content.presentationIntent = nil
            result.append(content)
        }
        return result
    }

    static func highlighted(_ source: String, terms: [String] = [], marked: Bool = false) -> AttributedString {
        var text = markdown(source)
        if marked {
            while let start = text.range(of: startMarker), let end = text.range(of: endMarker), start.upperBound <= end.lowerBound {
                emphasize(&text, range: start.upperBound ..< end.lowerBound)
                text.removeSubrange(end)
                text.removeSubrange(start)
            }
        } else if !terms.isEmpty {
            let raw = String(text.characters)
            for range in SearchMatch.ranges(in: raw, terms: terms) {
                if let indices = Range(range, in: raw),
                   let start = AttributedString.Index(indices.lowerBound, within: text),
                   let end = AttributedString.Index(indices.upperBound, within: text)
                {
                    emphasize(&text, range: start ..< end)
                }
            }
        }
        return text
    }

    /// Slice FTS-marked source by unmarked scalar positions, keeping markers balanced across the narrator/body boundary.
    static func markedSlice(_ source: String, range: Range<Int>) -> String {
        var result = ""
        var position = 0
        var highlighted = false
        var opened = false
        for scalar in source.unicodeScalars {
            if scalar.value == 0xE000 {
                highlighted = true
            } else if scalar.value == 0xE001 {
                highlighted = false
            } else {
                if range.contains(position) {
                    if highlighted != opened {
                        result += highlighted ? startMarker : endMarker
                        opened = highlighted
                    }
                    result.unicodeScalars.append(scalar)
                }
                position += 1
            }
        }
        if opened {
            result += endMarker
        }
        return result
    }

    static func preview(_ source: String, terms: [String] = [], marked: Bool = false) -> AttributedString {
        let source = marked ? source : previewWindow(source, terms: terms)
        let text = flattened(highlighted(source, terms: terms, marked: marked))
        return SearchMatch.preview(text, compact: !terms.isEmpty || marked)
    }

    /// Long narrations are cut around the strongest match before parsing; previews show at most a few hundred characters.
    /// The margins exceed the preview budget, so trimming still adds the leading and trailing ellipses.
    static func previewWindow(_ source: String, terms: [String]) -> String {
        let text = source as NSString
        guard text.length > 1500 else { return source }
        let hit = SearchMatch.firstMatch(in: source, terms: terms) ?? 0
        var start = max(0, hit - 300)
        var end = min(text.length, hit + 900)
        let whitespace = CharacterSet.whitespacesAndNewlines
        if start > 0 {
            let found = text.rangeOfCharacter(from: whitespace, range: NSRange(location: start, length: hit - start))
            start = found.location == NSNotFound ? start : NSMaxRange(found)
        }
        if end < text.length {
            let found = text.rangeOfCharacter(from: whitespace, options: .backwards, range: NSRange(location: hit, length: end - hit))
            end = found.location == NSNotFound ? end : found.location
        }
        // Never split a surrogate pair or composed character at either edge.
        let range = text.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))
        return text.substring(with: range)
    }

    private static func emphasize(_ text: inout AttributedString, range: Range<AttributedString.Index>) {
        text[range].underlineStyle = Text.LineStyle(pattern: .solid, color: .accentColor)
        // Weight also distinguishes matches without relying only on color.
        for run in Array(text[range].runs) {
            var intent = run.inlinePresentationIntent ?? []
            intent.insert(.stronglyEmphasized)
            text[run.range].inlinePresentationIntent = intent
        }
    }
}

struct HadithParagraph: Identifiable {
    let id: Int
    let text: AttributedString
    let intent: PresentationIntent?

    var heading: Int? {
        for component in intent?.components ?? [] {
            if case let .header(level) = component.kind {
                return level
            }
        }
        return nil
    }

    var marker: String? {
        var ordinal: Int?
        var ordered = false
        for component in intent?.components ?? [] {
            switch component.kind {
            case let .listItem(value): ordinal = value
            case .orderedList: ordered = true
            default: break
            }
        }
        return ordinal.map { ordered ? "\($0)." : "•" }
    }

    var quoted: Bool {
        intent?.components.contains { $0.kind == .blockQuote } ?? false
    }
}

/// Temporary search styling. Source text and saved highlights stay unchanged.
enum SearchMatch {
    static func ranges(in raw: String, terms: [String]) -> [NSRange] {
        guard !terms.isEmpty else { return [] }
        var normalized = ""
        var originalRanges: [NSRange] = []
        // Folding is per character, so repeated characters reuse one result instead of refolding.
        var keys: [Character: String] = [:]
        var offset16 = 0
        for character in raw {
            let length = character.utf16.count
            let key: String
            if let known = keys[character] {
                key = known
            } else {
                key = character.isASCII ? String(character).lowercased() : QuranSearchText.fold(QuranSearchText.normalize(String(character)))
                keys[character] = key
            }
            normalized += key
            originalRanges.append(contentsOf: repeatElement(NSRange(location: offset16, length: length), count: key.utf16.count))
            offset16 += length
        }
        let searchable = normalized as NSString
        var ranges: [NSRange] = []
        func occurrences(of key: String) -> [NSRange] {
            var found: [NSRange] = []
            var offset = 0
            while offset < searchable.length {
                let match = searchable.range(of: key, range: NSRange(location: offset, length: searchable.length - offset))
                guard match.location != NSNotFound, match.length > 0 else { break }
                found.append(NSUnionRange(originalRanges[match.location], originalRanges[NSMaxRange(match) - 1]))
                offset = NSMaxRange(match)
            }
            return found
        }
        for term in terms {
            let key = QuranSearchText.fold(QuranSearchText.normalize(term))
            guard !key.isEmpty else { continue }
            var found = occurrences(of: key)
            if found.isEmpty {
                // Typed in standard spelling where the mushaf spells it otherwise (الصلاة, الصلوٰة).
                for spelling in QuranSpelling.alternatives(for: term) {
                    found = occurrences(of: spelling)
                    if !found.isEmpty {
                        break
                    }
                }
            }
            ranges.append(contentsOf: found)
        }
        return ranges
    }

    /// Prefer a sequence of distinct nearby matches over an isolated common word.
    static func bestMatch(in text: NSString, hits: [NSRange]) -> Int? {
        var start = 0, end = 0, score = 0, bestScore = 0
        var best: Int?
        var seen = Set<String>()
        for hit in hits.sorted(by: { $0.location < $1.location }) {
            let word = QuranSearchText.fold(QuranSearchText.normalize(text.substring(with: hit)))
            if hit.location < end {
                continue
            }
            if hit.location - end > 3 || seen.contains(word) || seen.isEmpty {
                start = hit.location
                score = 0
                seen.removeAll(keepingCapacity: true)
            }
            seen.insert(word)
            score += word.utf16.count + 1
            if score > bestScore {
                best = start; bestScore = score
            }
            end = NSMaxRange(hit)
        }
        return best
    }

    static func firstMatch(in raw: String, terms: [String]) -> Int? {
        bestMatch(in: raw as NSString, hits: ranges(in: raw, terms: terms))
    }

    static func visibleBlocks(_ texts: [AttributedString], preferred: Int) -> [Int] {
        let matching = texts.indices.filter { index in texts[index].runs.contains { $0.underlineStyle != nil } }
        if !matching.isEmpty {
            return matching
        }
        if texts.indices.contains(preferred), !texts[preferred].characters.isEmpty {
            return [preferred]
        }
        return texts.indices.first { !texts[$0].characters.isEmpty }.map { [$0] } ?? []
    }

    static func preview(_ text: AttributedString, compact: Bool = false) -> AttributedString {
        let raw = String(text.characters)
        let hits = text.runs.compactMap { run -> NSRange? in
            guard run.underlineStyle != nil, let range = Range(run.range, in: raw) else { return nil }
            return NSRange(range, in: raw)
        }
        let offset = bestMatch(in: raw as NSString, hits: hits) ?? 0
        let position = String.Index(utf16Offset: offset, in: raw)
        let firstHit = AttributedString.Index(position, within: text) ?? text.startIndex
        let distance = text.characters.distance(from: text.startIndex, to: firstHit)
        var start = text.characters.index(text.startIndex, offsetBy: max(0, distance - (compact ? 12 : 45)))
        if compact {
            var wordStart = firstHit
            while wordStart > text.startIndex, !text.characters[text.characters.index(before: wordStart)].isWhitespace {
                wordStart = text.characters.index(before: wordStart)
            }
            let contextDistance = text.characters.distance(from: text.startIndex, to: wordStart)
            start = text.characters.index(text.startIndex, offsetBy: max(0, contextDistance - 12))
            while start > text.startIndex, start < wordStart, !text.characters[text.characters.index(before: start)].isWhitespace {
                start = text.characters.index(after: start)
            }
            if text.characters.distance(from: start, to: firstHit) > 100 {
                start = text.characters.index(text.startIndex, offsetBy: max(0, distance - 12))
            }
            if let newline = text.characters[start ..< firstHit].lastIndex(where: \.isNewline) {
                start = text.characters.index(after: newline)
            }
        }
        var end = text.characters.index(start, offsetBy: compact ? 160 : 260, limitedBy: text.endIndex) ?? text.endIndex
        if compact, end < text.endIndex {
            // Prefer whole words, but keep unbroken source text within the existing preview budget.
            let limit = text.characters.index(start, offsetBy: 260, limitedBy: text.endIndex) ?? text.endIndex
            var boundary = end
            while boundary < limit, !text.characters[boundary].isWhitespace {
                boundary = text.characters.index(after: boundary)
            }
            if boundary == text.endIndex || (boundary < limit && text.characters[boundary].isWhitespace) {
                end = boundary
            }
        }
        var result = AttributedString(text[start ..< end])
        if start > text.startIndex {
            result = AttributedString("… ") + result
        }
        if end < text.endIndex {
            result.append(AttributedString(" …"))
        }
        return result
    }

    static func text(_ raw: String, query: String) -> AttributedString {
        var text = AttributedString(raw)
        for range in ranges(in: raw, terms: QuranSearchText.queryTerms(query)) {
            guard let indices = Range(range, in: raw),
                  let start = AttributedString.Index(indices.lowerBound, within: text),
                  let end = AttributedString.Index(indices.upperBound, within: text) else { continue }
            text[start ..< end].underlineStyle = Text.LineStyle(pattern: .solid, color: .accentColor)
        }
        return text
    }
}

/// Use the prepared match ranges; scrolling never normalizes or searches the source again.
struct SearchMatchText: View {
    @AppStorage("showArabicDiacritics") private var showMarks = true
    let text: AttributedString

    init(_ text: AttributedString) {
        self.text = text
    }

    var body: some View {
        rendered.textRenderer(MatchRenderer())
    }

    private var rendered: Text {
        text.runs.reduce(Text("")) { result, run in
            var segment = AttributedString(text[run.range])
            let matched = segment.underlineStyle != nil
            segment.underlineStyle = nil
            if !showMarks {
                segment = AttributedString(ArabicDisplay.plain(String(segment.characters)), attributes: run.attributes)
                segment.underlineStyle = nil
            }
            let part = Text(segment)
            if matched {
                return Text("\(result)\(part.customAttribute(MatchUnderline()))")
            }
            return Text("\(result)\(part)")
        }
    }

    private struct MatchUnderline: TextAttribute {}

    private struct MatchRenderer: TextRenderer {
        func draw(layout: Text.Layout, in context: inout GraphicsContext) {
            for line in layout {
                context.draw(line)
                for run in line where run[MatchUnderline.self] != nil {
                    let rect = run.typographicBounds.rect
                    let thickness = max(2, rect.height * 0.055)
                    context.fill(Path(CGRect(x: rect.minX, y: rect.maxY - thickness,
                                             width: rect.width, height: thickness)), with: .color(.accentColor))
                }
            }
        }
    }
}
