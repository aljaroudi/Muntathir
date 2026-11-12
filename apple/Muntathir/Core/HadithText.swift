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
        let text = flattened(highlighted(source, terms: terms, marked: marked))
        return SearchMatch.preview(text)
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
        for index in raw.indices {
            let end = raw.index(after: index)
            let key = QuranSearchText.normalize(String(raw[index ..< end])).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            normalized += key
            originalRanges.append(contentsOf: repeatElement(NSRange(index ..< end, in: raw), count: key.utf16.count))
        }
        let searchable = normalized as NSString
        var ranges: [NSRange] = []
        for term in terms {
            let key = QuranSearchText.normalize(term).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
            guard !key.isEmpty else { continue }
            var offset = 0
            while offset < searchable.length {
                let found = searchable.range(of: key, range: NSRange(location: offset, length: searchable.length - offset))
                guard found.location != NSNotFound, found.length > 0 else { break }
                ranges.append(NSUnionRange(originalRanges[found.location], originalRanges[NSMaxRange(found) - 1]))
                offset = NSMaxRange(found)
            }
        }
        return ranges
    }

    static func preview(_ text: AttributedString) -> AttributedString {
        let firstHit = text.runs.first { $0.underlineStyle != nil }?.range.lowerBound ?? text.startIndex
        let distance = text.characters.distance(from: text.startIndex, to: firstHit)
        let start = text.characters.index(text.startIndex, offsetBy: max(0, distance - 45))
        let end = text.characters.index(start, offsetBy: 260, limitedBy: text.endIndex) ?? text.endIndex
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
        for range in ranges(in: raw, terms: QuranSearchText.terms(query)) {
            guard let indices = Range(range, in: raw),
                  let start = AttributedString.Index(indices.lowerBound, within: text),
                  let end = AttributedString.Index(indices.upperBound, within: text) else { continue }
            text[start ..< end].underlineStyle = Text.LineStyle(pattern: .solid, color: .accentColor)
        }
        return text
    }
}
