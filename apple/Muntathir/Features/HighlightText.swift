import SwiftUI
import UIKit

extension EnvironmentValues {
    @Entry var searchMatchQuery = ""
    @Entry var focusedHighlight: ReadingHighlight? = nil
}

/// A stable, visible representation shared by range storage, validation, and text rendering.
enum HighlightTextContent {
    static let pearlAttribute = NSAttributedString.Key("MuntathirPearl")
    static func canonical(_ markdown: AttributedString) -> String {
        HadithText.paragraphs(markdown).map { paragraph in
            (paragraph.marker.map { $0 + " " } ?? "") + (paragraph.quoted ? "│ " : "") + String(paragraph.text.characters)
        }.joined(separator: "\n\n")
    }

    static func applying(_ highlights: [ReadingHighlight], to attributed: NSAttributedString, block: String, differentiate: Bool = false, mappedRanges: [String: [NSRange]]? = nil) -> NSMutableAttributedString {
        let rendered = NSMutableAttributedString(attributedString: attributed)
        // Apply oldest first; the newest color wins without removing any saved notes.
        for highlight in highlights.sorted(by: { $0.modifiedAt == $1.modifiedAt ? $0.id < $1.id : $0.modifiedAt < $1.modifiedAt }) {
            for range in mappedRanges?[highlight.id] ?? highlight.ranges(in: rendered.string, block: block) {
                rendered.addAttribute(.backgroundColor, value: highlight.color.textBackground, range: range)
                rendered.addAttribute(pearlAttribute, value: highlight.color == .cyan, range: range)
                if differentiate {
                    rendered.enumerateAttribute(.underlineStyle, in: range) { style, subrange, _ in
                        if style == nil {
                            rendered.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: subrange)
                        }
                    }
                }
            }
        }
        return rendered
    }

    static func attributed(text: String, markdown: AttributedString?, arabic: Bool, hadith: Bool = false, size: CGFloat, alignment: NSTextAlignment) -> NSMutableAttributedString {
        let font = arabic ? UIFont(name: hadith ? "Lateef-Light" : "KFGQPCHAFSUthmanicScript-Regula", size: size) ?? .systemFont(ofSize: size) : .systemFont(ofSize: size)
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.baseWritingDirection = arabic ? .rightToLeft : .natural
        style.lineSpacing = max(0, size * 1.75 - font.lineHeight)
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
                    if run.underlineStyle != nil {
                        result.addAttributes([.underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: UIColor(Color.accentColor)], range: NSRange(location: offset, length: length))
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
    @Environment(\.searchMatchQuery) private var searchQuery
    @AppStorage("showArabicDiacritics") private var showMarks = true
    @AppStorage("readingSizePercent") private var percent = 100
    @ScaledMetric(relativeTo: .body) private var bodySize = 17
    @ScaledMetric(relativeTo: .title2) private var arabicSize = 28
    @State private var editing: ReadingHighlight?
    @State private var tappedHighlights: [ReadingHighlight] = []
    @State private var choosingHighlight = false

    var body: some View {
        let size = (arabic ? arabicSize : bodySize) * CGFloat(min(160, max(80, percent))) / 100
        let highlights = store?.highlights(for: source, isHadith: isHadith) ?? []
        let passage = HighlightTextContent.attributed(text: text, markdown: markdown, arabic: arabic, hadith: isHadith,
                                                      size: size, alignment: centered ? .center : .natural)
        let display = ArabicDisplay(SearchMatch.applying(to: passage, query: searchQuery), showMarks: showMarks)
        SelectableHighlightText(
            attributed: display.attributed,
            highlights: highlights, block: block, focused: focused?.source == source && focused?.isHadith == isHadith && (focused?.block != nil || block == "arabic" || focusWholeItem) ? focused : nil,
            differentiate: differentiate, select: { ranges in
                let saved = ranges.compactMap { HighlightRange(display.sourceRange($0), in: text) }
                guard !saved.isEmpty, !source.isEmpty else { return }
                editing = ReadingHighlight(source: source, isHadith: isHadith, block: block, ranges: saved,
                                           excerpt: saved.map(\.quote).joined(separator: " … "), reference: reference.isEmpty ? source : reference)
            }, tap: { matches in
                if matches.count == 1 {
                    editing = matches.first
                } else {
                    tappedHighlights = matches
                    choosingHighlight = true
                }
            }, mappedRanges: showMarks ? nil : Dictionary(uniqueKeysWithValues: highlights.map {
                ($0.id, $0.ranges(in: text, block: block).map(display.displayRange))
            })
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
                Button(highlight.note.isEmpty ? String(highlight.excerpt.prefix(60)) : String(localized: "Highlight note") + ": " + String(highlight.note.prefix(60))) {
                    editing = highlight
                }
            }
        }
        .sheet(item: $editing) { value in
            HighlightEditor(highlight: value, existing: highlights.contains { $0.id == value.id })
        }
    }
}

struct SelectableHighlightText: UIViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let attributed: NSMutableAttributedString
    let highlights: [ReadingHighlight]
    let block: String
    let focused: ReadingHighlight?
    let differentiate: Bool
    let select: ([NSRange]) -> Void
    let tap: ([ReadingHighlight]) -> Void
    var mappedRanges: [String: [NSRange]]?
    var additionalActions: ([NSRange]) -> [UIMenuElement] = { _ in [] }
    var selectionChanged: (NSRange) -> Void = { _ in }
    var canHighlight: ([NSRange]) -> Bool = { _ in true }

    func ranges(for highlight: ReadingHighlight) -> [NSRange] {
        mappedRanges?[highlight.id] ?? highlight.ranges(in: attributed.string, block: block)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> HighlightUITextView {
        let storage = NSTextStorage()
        let layout = ReaderUnderlineLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer()
        layout.addTextContainer(container)
        let view = HighlightUITextView(frame: .zero, textContainer: container)
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
        let rendered = HighlightTextContent.applying(highlights, to: attributed, block: block, differentiate: differentiate, mappedRanges: mappedRanges)
        view.sheenEnabled = !reduceMotion && scenePhase == .active
        view.setRenderedText(rendered)
        if let focused, let range = ranges(for: focused).first {
            view.focusID = focused.id
            view.focusRange = range
            view.setNeedsLayout()
        } else {
            view.focusRange = nil
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: HighlightUITextView, context _: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitted.height)
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
                    parent.ranges(for: highlight).contains { NSLocationInRange(offset, $0) }
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
                view.selectedTextRange = nil
                view.resignFirstResponder()
                parent.tap(matches)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            if textView.selectedRange.length > 0 {
                parent.selectionChanged(textView.selectedRange)
            }
        }

        func textView(_ textView: UITextView, editMenuForTextInRanges ranges: [NSValue], suggestedActions: [UIMenuElement]) -> UIMenu? {
            let selected = ranges.map(\.rangeValue).filter { $0.length > 0 }
            var actions: [UIMenuElement] = []
            if !selected.isEmpty, parent.canHighlight(selected) {
                actions.append(UIAction(title: String(localized: "Highlight"), image: UIImage(systemName: "highlighter")) { [weak self, weak textView] _ in
                    textView?.selectedTextRange = nil
                    textView?.resignFirstResponder()
                    self?.parent.select(selected)
                })
            }
            return UIMenu(children: actions + suggestedActions + parent.additionalActions(selected))
        }
    }
}

private final class ReaderUnderlineLayoutManager: NSLayoutManager {
    override func drawUnderline(forGlyphRange glyphRange: NSRange, underlineType: NSUnderlineStyle,
                                baselineOffset: CGFloat, lineFragmentRect lineRect: CGRect,
                                lineFragmentGlyphRange lineGlyphRange: NSRange, containerOrigin: CGPoint)
    {
        guard underlineType == .thick, let container = textContainers.first,
              let context = UIGraphicsGetCurrentContext(), let storage = textStorage
        else {
            super.drawUnderline(forGlyphRange: glyphRange, underlineType: underlineType,
                                baselineOffset: baselineOffset, lineFragmentRect: lineRect,
                                lineFragmentGlyphRange: lineGlyphRange, containerOrigin: containerOrigin)
            return
        }

        let index = characterIndexForGlyph(at: glyphRange.location)
        let font = storage.attribute(.font, at: index, effectiveRange: nil) as? UIFont
        let color = storage.attribute(.underlineColor, at: index, effectiveRange: nil) as? UIColor
        let thickness = max(2, (font?.lineHeight ?? 0) * 0.055)
        let baseline = lineRect.minY + location(forGlyphAt: glyphRange.location).y
        let bottom = baseline - (font?.descender ?? -thickness)
        context.saveGState()
        context.setFillColor((color ?? UIColor(Color.accentColor)).cgColor)
        enumerateEnclosingRects(forGlyphRange: glyphRange,
                                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                in: container)
        { rect, _ in
            context.fill(CGRect(x: rect.minX + containerOrigin.x, y: bottom - thickness + containerOrigin.y,
                                width: rect.width, height: thickness))
        }
        context.restoreGState()
    }
}

final class HighlightUITextView: UITextView {
    private var renderedText: NSAttributedString?
    private let sheen = CAGradientLayer()
    private var needsSheen = true
    var sheenEnabled = true {
        didSet {
            if !sheenEnabled {
                sheen.removeAllAnimations(); sheen.removeFromSuperlayer()
            }
            if sheenEnabled != oldValue {
                setNeedsLayout()
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            sheen.removeAllAnimations()
            sheen.removeFromSuperlayer()
            needsSheen = true
        } else {
            setNeedsLayout()
        }
    }

    private func playPearlSheen() {
        guard needsSheen, sheenEnabled, window != nil, bounds.width > 0,
              let renderedText, renderedText.length > 0 else { return }
        let path = UIBezierPath()
        renderedText.enumerateAttribute(HighlightTextContent.pearlAttribute,
                                        in: NSRange(location: 0, length: renderedText.length))
        { value, range, _ in
            guard value as? Bool == true,
                  let start = position(from: beginningOfDocument, offset: range.location),
                  let end = position(from: start, offset: range.length),
                  let textRange = textRange(from: start, to: end) else { return }
            for selection in selectionRects(for: textRange) where !selection.rect.isEmpty {
                path.append(UIBezierPath(rect: selection.rect))
            }
        }
        guard !path.isEmpty else { return }
        needsSheen = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sheen.frame = bounds
        sheen.colors = [UIColor.clear.cgColor, UIColor.white.withAlphaComponent(0.18).cgColor, UIColor.clear.cgColor]
        sheen.startPoint = CGPoint(x: 0, y: 0.5)
        sheen.endPoint = CGPoint(x: 1, y: 0.5)
        sheen.locations = [1, 1.1, 1.2]
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        sheen.mask = mask
        layer.addSublayer(sheen)
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-0.2, -0.1, 0]
        animation.toValue = [1, 1.1, 1.2]
        animation.duration = 1.5
        sheen.add(animation, forKey: "pearlSheen")
    }

    func setRenderedText(_ rendered: NSAttributedString) {
        // UIKit normalizes paragraph attributes; comparing its text storage resets selection on SwiftUI updates.
        guard renderedText != rendered else { return }
        let selection = selectedRange
        let sameText = text == rendered.string
        needsSheen = true
        sheen.removeAllAnimations()
        sheen.removeFromSuperlayer()
        renderedText = NSAttributedString(attributedString: rendered)
        attributedText = rendered
        if sameText {
            selectedRange = selection
        }
    }

    var focusID: String?
    var focusRange: NSRange?
    private var scrolledID: String?

    override func layoutSubviews() {
        super.layoutSubviews()
        playPearlSheen()
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

extension SearchMatch {
    static func applying(to text: NSMutableAttributedString, query: String) -> NSMutableAttributedString {
        for range in ranges(in: text.string, terms: QuranSearchText.terms(query)) {
            text.addAttributes([.underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: UIColor(Color.accentColor)], range: range)
        }
        return text
    }
}
