import Foundation

/// A deliberately simple estimate of the primary text, independent of enabled translations.
enum ReadingTime {
    static func words(arabic: String, english: String = "") -> Int {
        let source = arabic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? english : arabic
        let plain = (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)).characters).map(String.init) ?? source
        return plain.split(whereSeparator: \.isWhitespace).filter { $0.contains(where: \.isLetter) }.count
    }

    static func minutes(words: Int) -> Int {
        words > 0 ? max(1, (words + 199) / 200) : 0
    }

    static func duration(words: Int) -> Measurement<UnitDuration>? {
        let minutes = minutes(words: words)
        guard minutes > 0 else { return nil }
        return minutes < 60 ? Measurement(value: Double(minutes), unit: .minutes)
            : Measurement(value: Double((minutes + 59) / 60), unit: .hours)
    }
}
