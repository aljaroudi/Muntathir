import SwiftUI
import UIKit

extension EnvironmentValues {
    @Entry var focusedHighlight: ReadingHighlight? = nil
}

/// A stable, visible representation shared by range storage, validation, and text rendering.
enum HighlightTextContent {
    static func canonical(_ markdown: AttributedString) -> String {
        HadithText.paragraphs(markdown).map { paragraph in
            (paragraph.marker.map { $0 + " " } ?? "") + (paragraph.quoted ? "│ " : "") + String(paragraph.text.characters)
        }.joined(separator: "\n\n")
    }

    static func applying(_ highlights: [ReadingHighlight], to attributed: NSAttributedString, block: String, differentiate: Bool = false) -> NSMutableAttributedString {
        let rendered = NSMutableAttributedString(attributedString: attributed)
        // Apply oldest first; the newest color wins without removing any saved notes.
        for highlight in highlights.sorted(by: { $0.modifiedAt == $1.modifiedAt ? $0.id < $1.id : $0.modifiedAt < $1.modifiedAt }) {
            for range in highlight.ranges(in: rendered.string, block: block) {
                rendered.addAttribute(.backgroundColor, value: UIColor(highlight.color.color).withAlphaComponent(0.3), range: range)
                if differentiate {
                    rendered.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                }
            }
        }
        return rendered
    }

    static func attributed(text: String, markdown: AttributedString?, arabic: Bool, size: CGFloat, alignment: NSTextAlignment) -> NSMutableAttributedString {
        let font = arabic ? UIFont(name: "KFGQPCHAFSUthmanicScript-Regula", size: size) ?? .systemFont(ofSize: size) : .systemFont(ofSize: size)
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.baseWritingDirection = arabic ? .rightToLeft : .natural
        style.lineSpacing = max(0, size * 1.5 - font.lineHeight)
        let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: style])
        if let markdown {
            var offset = 0
            for paragraph in HadithText.paragraphs(markdown) {
                let prefix = (paragraph.marker.map { $0 + " " } ?? "") + (paragraph.quoted ? "│ " : "")
                offset += prefix.utf16.count
                for run in paragraph.text.runs {
                    let length = String(paragraph.text[run.range].characters).utf16.count
                    var traits: UIFontDescriptor.SymbolicTraits = []
                    if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true || paragraph.heading != nil {
                        traits.insert(.traitBold)
                    }
                    if run.inlinePresentationIntent?.contains(.emphasized) == true {
                        traits.insert(.traitItalic)
                    }
                    let runSize = paragraph.heading.map { size * ($0 <= 2 ? 1.3 : 1.1) } ?? size
                    let descriptor = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
                    result.addAttribute(.font, value: UIFont(descriptor: descriptor, size: runSize), range: NSRange(location: offset, length: length))
                    if run.inlinePresentationIntent?.contains(.strikethrough) == true {
                        result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: offset, length: length))
                    }
                    if let background = run.backgroundColor {
                        result.addAttribute(.backgroundColor, value: UIColor(background), range: NSRange(location: offset, length: length))
                    }
                    if let link = run.link {
                        result.addAttribute(.link, value: link, range: NSRange(location: offset, length: length))
                    }
                    offset += length
                }
                offset += 2
            }
        }
        return result
    }
}

struct HighlightText: View {
    let text: String
    let source: String
    let block: String
    var isHadith = false
    var reference: String = ""
    var arabic = false
    var centered = false
    var markdown: AttributedString?
    var focusWholeItem = false
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    @Environment(\.quranUserStore) private var store
    @Environment(\.focusedHighlight) private var focused
    @AppStorage("readingSizePercent") private var percent = 100
    @ScaledMetric(relativeTo: .body) private var bodySize = 17
    @ScaledMetric(relativeTo: .title2) private var arabicSize = 28
    @State private var editing: ReadingHighlight?
    @State private var tappedHighlights: [ReadingHighlight] = []
    @State private var choosingHighlight = false

    var body: some View {
        let size = (arabic ? arabicSize : bodySize) * CGFloat(min(160, max(80, percent))) / 100
        let highlights = store?.highlights(for: source, isHadith: isHadith) ?? []
        SelectableHighlightText(
            attributed: HighlightTextContent.attributed(text: text, markdown: markdown, arabic: arabic, size: size, alignment: centered ? .center : .natural),
            highlights: highlights, block: block, focused: focused?.source == source && focused?.isHadith == isHadith && (focused?.block != nil || block == "arabic" || focusWholeItem) ? focused : nil,
            differentiate: differentiate, select: { ranges in
                let saved = ranges.compactMap { HighlightRange($0, in: text) }
                guard !saved.isEmpty, !source.isEmpty else { return }
                editing = ReadingHighlight(source: source, isHadith: isHadith, block: block, ranges: saved,
                                           excerpt: saved.map(\.quote).joined(separator: " … "), reference: reference.isEmpty ? source : reference)
            }, edit: { editing = $0 }, tap: { matches in
                if matches.count == 1 {
                    editing = matches.first
                } else {
                    tappedHighlights = matches
                    choosingHighlight = true
                }
            }
        )
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Highlights", isPresented: $choosingHighlight, titleVisibility: .visible) {
            ForEach(tappedHighlights) { highlight in
                Button(highlight.note.isEmpty ? String(highlight.excerpt.prefix(60)) : String(highlight.note.prefix(60))) {
                    editing = highlight
                }
            }
        }
        .accessibilityActions {
            ForEach(highlights.filter { !$0.ranges(in: text, block: block).isEmpty }) { highlight in
                Button(highlight.note.isEmpty ? String(localized: "Edit highlight") + ": " + String(highlight.excerpt.prefix(60)) : String(localized: "Highlight note") + ": " + String(highlight.note.prefix(60))) {
                    editing = highlight
                }
            }
        }
        .sheet(item: $editing) { value in
            HighlightEditor(highlight: value, existing: highlights.contains { $0.id == value.id })
        }
    }
}

private struct SelectableHighlightText: UIViewRepresentable {
    let attributed: NSMutableAttributedString
    let highlights: [ReadingHighlight]
    let block: String
    let focused: ReadingHighlight?
    let differentiate: Bool
    let select: ([NSRange]) -> Void
    let edit: (ReadingHighlight) -> Void
    let tap: ([ReadingHighlight]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> HighlightUITextView {
        let view = HighlightUITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tappedHighlight(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: HighlightUITextView, context: Context) {
        context.coordinator.parent = self
        let rendered = HighlightTextContent.applying(highlights, to: attributed, block: block, differentiate: differentiate)
        if view.attributedText != rendered {
            view.attributedText = rendered
        }
        if let focused, let range = focused.ranges(in: rendered.string, block: block).first {
            view.focusID = focused.id
            view.focusRange = range
            view.setNeedsLayout()
        } else {
            view.focusRange = nil
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: HighlightUITextView, context _: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: SelectableHighlightText
        init(_ parent: SelectableHighlightText) {
            self.parent = parent
        }

        private func highlights(at point: CGPoint, in view: UITextView) -> [ReadingHighlight] {
            guard let position = view.closestPosition(to: point) else { return [] }
            let nearest = view.offset(from: view.beginningOfDocument, to: position)
            for offset in [nearest, nearest - 1] where offset >= 0 && offset < parent.attributed.length {
                guard let start = view.position(from: view.beginningOfDocument, offset: offset),
                      let end = view.position(from: start, offset: 1),
                      let character = view.textRange(from: start, to: end),
                      view.firstRect(for: character).insetBy(dx: -2, dy: -2).contains(point) else { continue }
                return parent.highlights.filter { highlight in
                    highlight.ranges(in: parent.attributed.string, block: parent.block).contains { NSLocationInRange(offset, $0) }
                }
            }
            return []
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let view = gesture.view as? UITextView else { return false }
            return !highlights(at: gesture.location(in: view), in: view).isEmpty
        }

        func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func tappedHighlight(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view as? UITextView else { return }
            let matches = highlights(at: gesture.location(in: view), in: view)
            if !matches.isEmpty {
                parent.tap(matches)
            }
        }

        func textView(_: UITextView, editMenuForTextInRanges ranges: [NSValue], suggestedActions: [UIMenuElement]) -> UIMenu? {
            let selected = ranges.map(\.rangeValue).filter { $0.length > 0 }
            var actions: [UIMenuElement] = []
            if !selected.isEmpty {
                actions.append(UIAction(title: String(localized: "Highlight"), image: UIImage(systemName: "highlighter")) { [weak self] _ in self?.parent.select(selected) })
            }
            for highlight in parent.highlights where highlight.ranges(in: parent.attributed.string, block: parent.block).contains(where: { existing in
                selected.contains { NSIntersectionRange(existing, $0).length > 0 }
            }) {
                actions.append(UIAction(title: String(localized: "Edit highlight") + " · " + highlight.color.title + " · " + String(highlight.excerpt.prefix(35))) { [weak self] _ in self?.parent.edit(highlight) })
            }
            return UIMenu(children: actions + suggestedActions)
        }
    }
}

private final class HighlightUITextView: UITextView {
    var focusID: String?
    var focusRange: NSRange?
    private var scrolledID: String?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard window != nil, bounds.width > 0, let focusRange, let focusID, scrolledID != focusID,
              let start = position(from: beginningOfDocument, offset: focusRange.location),
              let end = position(from: start, offset: min(focusRange.length, 1)),
              let range = textRange(from: start, to: end) else { return }
        let rect = firstRect(for: range)
        guard !rect.isNull, !rect.isInfinite else { return }
        var ancestor = superview
        while let current = ancestor {
            if let scroll = current as? UIScrollView {
                scrolledID = focusID
                let target = convert(rect.insetBy(dx: 0, dy: -30), to: scroll)
                Task { @MainActor [weak scroll] in
                    await Task.yield()
                    scroll?.scrollRectToVisible(target, animated: false)
                }
                break
            }
            ancestor = current.superview
        }
    }
}
