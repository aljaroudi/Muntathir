import Foundation

/// Boundaries use UTF-16, matching native text selection and saved highlights.
struct ArabicDisplay {
    private static let marks = CharacterSet(charactersIn: Unicode.Scalar(0x064B)! ... Unicode.Scalar(0x0652)!)
        .union(CharacterSet(charactersIn: "\u{0656}\u{0657}\u{0670}\u{06E1}\u{08F0}\u{08F1}\u{08F2}"))
    static func plain(_ text: String) -> String {
        String(text.unicodeScalars.filter { !marks.contains($0) })
    }

    let attributed: NSMutableAttributedString
    private var displayed: [Int] = []
    private var original: [Int] = []

    init(_ source: NSMutableAttributedString, showMarks: Bool) {
        guard !showMarks, source.string.rangeOfCharacter(from: Self.marks) != nil else {
            attributed = source
            return
        }
        attributed = NSMutableAttributedString(string: "")
        let utf16 = source.string as NSString
        original = [0]
        displayed = [0]
        for (index, unit) in source.string.utf16.enumerated() {
            if let scalar = Unicode.Scalar(unit), Self.marks.contains(scalar) {
                original[original.count - 1] = index + 1
            } else {
                original.append(index + 1)
            }
            displayed.append(original.count - 1)
        }
        let result = attributed
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attributes, range, _ in
            let text = Self.plain(utf16.substring(with: range))
            result.append(NSAttributedString(string: text, attributes: attributes))
        }
    }

    func displayRange(_ range: NSRange) -> NSRange {
        map(range, using: displayed)
    }

    func sourceRange(_ range: NSRange) -> NSRange {
        map(range, using: original)
    }

    private func map(_ range: NSRange, using offsets: [Int]) -> NSRange {
        guard !offsets.isEmpty else { return range }
        return NSRange(location: offsets[range.location], length: offsets[NSMaxRange(range)] - offsets[range.location])
    }
}
