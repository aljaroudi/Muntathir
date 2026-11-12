import SwiftUI
import UIKit

struct QuranPageReader: View {
    let page: QuranPage
    let surahs: [QuranSurah]
    let highlight: ReadingHighlight?
    let select: (Ayah) -> Void
    @Environment(\.quranUserStore) private var store
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    @Environment(\.locale) private var locale
    @State private var editing: ReadingHighlight?
    @State private var additionalHighlights: [ReadingHighlight] = []
    @State private var actionVerse: Ayah?
    @State private var tappedHighlights: [ReadingHighlight] = []
    @State private var choosingHighlight = false
    @State private var actions = VerseActionState()

    var body: some View {
        let content = QuranPageText(page: page, surahs: surahs)
        let highlights = (store?.highlights ?? []).filter { !$0.isHadith && content.verses[$0.source] != nil }
        let missingFocus = highlight.flatMap { value in highlights.contains { $0.id == value.id } ? nil : value }
        let mappedHighlights = highlights + [missingFocus].compactMap(\.self)
        let ranges = Dictionary(uniqueKeysWithValues: mappedHighlights.map { ($0.id, content.displayRanges(for: $0)) })
        GeometryReader { geometry in
            let lineHeight = max(1, geometry.size.height / 15)
            SelectableHighlightText(
                attributed: Self.attributed(content, width: geometry.size.width, lineHeight: lineHeight),
                highlights: highlights, block: "arabic", focused: highlight,
                differentiate: differentiate,
                select: { selection in
                    let drafts = content.highlights(in: selection)
                    additionalHighlights = Array(drafts.dropFirst())
                    editing = drafts.first
                }, edit: { value in
                    additionalHighlights = []
                    editing = value
                }, tap: { matches in
                    additionalHighlights = []
                    if matches.count == 1 {
                        editing = matches.first
                    } else {
                        tappedHighlights = matches; choosingHighlight = true
                    }
                }, mappedRanges: ranges,
                additionalActions: { selection in
                    content.sources(in: selection).compactMap { source in
                        guard let ayah = content.verses[source] else { return nil }
                        return UIAction(title: String(localized: "Actions for verse \(QuranReference.display(source, locale: locale))"), image: UIImage(systemName: "ellipsis.circle")) { _ in
                            select(ayah)
                            actionVerse = ayah
                        }
                    }
                }, selectionChanged: { range in
                    if let source = content.sources(in: [range]).first, let ayah = content.verses[source] {
                        select(ayah)
                    }
                }, canHighlight: content.canHighlight
            )
            .frame(width: geometry.size.width, height: lineHeight * CGFloat(content.lines.count))
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("quran-page-text-\(page.number)")
        }
        .sheet(item: $editing) { value in
            HighlightEditor(highlight: value, existing: highlights.contains { $0.id == value.id }, additionalHighlights: additionalHighlights)
        }
        .confirmationDialog("Highlights", isPresented: $choosingHighlight, titleVisibility: .visible) {
            ForEach(tappedHighlights) { value in
                Button(value.note.isEmpty ? String(value.excerpt.prefix(60)) : value.note) { editing = value }
            }
        }
        .confirmationDialog("Verse actions", isPresented: Binding(get: { actionVerse != nil }, set: {
            if !$0 {
                actionVerse = nil
            }
        }), titleVisibility: .visible) {
            if let ayah = actionVerse {
                VerseActionMenu(ayah: ayah, translation: nil, actions: actions)
            }
        }
        .modifier(VerseActionPresentation(actions: actions))
    }

    static func attributed(_ content: QuranPageText, width: CGFloat, lineHeight: CGFloat) -> NSMutableAttributedString {
        let reference = UIFont(name: "KFGQPCHAFSUthmanicScript-Regula", size: 100) ?? .systemFont(ofSize: 100)
        let text = content.text as NSString
        let widest = content.lines.map { text.substring(with: $0.range).size(withAttributes: [.font: reference]).width }.max() ?? 1
        let size = min(100 * max(1, width - 2) / max(1, widest), lineHeight * 0.6)
        let font = reference.withSize(size)
        let result = NSMutableAttributedString(string: content.text, attributes: [.font: font, .foregroundColor: UIColor.label])
        for line in content.lines {
            let style = NSMutableParagraphStyle()
            style.baseWritingDirection = .rightToLeft
            style.alignment = line.kind != .ayah || line.centered ? .center : .justified
            style.minimumLineHeight = lineHeight
            style.maximumLineHeight = lineHeight
            let paragraphRange = NSRange(location: line.range.location, length: min(line.range.length + 1, result.length - line.range.location))
            result.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
            if line.kind == .ayah, !line.centered, let indices = Range(line.range, in: content.text) {
                let spaces = content.text[indices].indices.filter { content.text[$0] == " " }
                let measured = text.substring(with: line.range).size(withAttributes: [.font: font]).width
                let expansion = max(0, width - 2 - measured) / CGFloat(max(1, spaces.count))
                // UIKit leaves forced lines ragged; spacing real spaces keeps selection and backgrounds continuous.
                for index in spaces {
                    result.addAttribute(.kern, value: expansion, range: NSRange(index ... index, in: content.text))
                }
            }
        }
        return result
    }
}
