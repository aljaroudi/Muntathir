import SwiftUI

extension EnvironmentValues {
    @Entry var searchMatchQuery = ""
    @Entry var focusedHighlight: ReadingHighlight? = nil
}

/// A stable, visible representation shared by range storage, validation, and text rendering.
enum HighlightTextContent {
    static let pearlAttribute = NSAttributedString.Key("MuntathirPearl")
    /// Marks which highlight owns each visible run, so touching highlights of the same color still get their own rounded ends.
    static let highlightAttribute = NSAttributedString.Key("MuntathirHighlight")
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
                rendered.addAttribute(highlightAttribute, value: highlight.id, range: range)
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

    static func attributed(text: String, markdown: AttributedString?, arabic: Bool, hadith: Bool = false, heading: Int? = nil, size: CGFloat, alignment: NSTextAlignment) -> NSMutableAttributedString {
        var font = arabic ? PlatformFont(name: hadith ? "Lateef-Light" : "KFGQPCHAFSUthmanicScript-Regula", size: size) ?? .systemFont(ofSize: size) : .systemFont(ofSize: size)
        if let heading {
            // Matches the markdown heading scale below for plain-text headings.
            font = font.with(bold: true, size: size * (heading <= 2 ? 1.3 : 1.1))
        }
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.baseWritingDirection = arabic ? .rightToLeft : .natural
        style.lineSpacing = max(0, size * 1.75 - font.lineHeight)
        let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: PlatformColor.label, .paragraphStyle: style])
        if let markdown {
            var offset = 0
            for paragraph in HadithText.paragraphs(markdown) {
                let prefix = (paragraph.marker.map { $0 + " " } ?? "") + (paragraph.quoted ? "│ " : "")
                offset += prefix.utf16.count
                for run in paragraph.text.runs {
                    let length = String(paragraph.text[run.range].characters).utf16.count
                    let bold = run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true || paragraph.heading != nil
                    let italic = run.inlinePresentationIntent?.contains(.emphasized) == true
                    let runSize = paragraph.heading.map { size * ($0 <= 2 ? 1.3 : 1.1) } ?? size
                    result.addAttribute(.font, value: font.with(bold: bold, italic: italic, size: runSize), range: NSRange(location: offset, length: length))
                    if run.inlinePresentationIntent?.contains(.strikethrough) == true {
                        result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: offset, length: length))
                    }
                    if run.underlineStyle != nil {
                        result.addAttributes([.underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: PlatformColor(Color.accentColor)], range: NSRange(location: offset, length: length))
                    }
                    if let background = run.backgroundColor {
                        result.addAttribute(.backgroundColor, value: PlatformColor(background), range: NSRange(location: offset, length: length))
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

/// A slice of a long highlightable block. Saved ranges stay relative to the whole block, so splitting
/// long passages into lazily rendered views never changes what a highlight points to.
struct HighlightSegment: Identifiable, Sendable {
    let id: Int
    let text: String
    var markdown: AttributedString?
    /// UTF-16 offset of `text` within the block's full text.
    let offset: Int

    /// Roughly how much text one view lays out; long readers otherwise lay out and diff the entire passage on every update.
    static let length = 2000

    static func split(_ text: String) -> [Self] {
        var result: [Self] = []
        var start: String.Index?
        var end = text.startIndex
        func close() {
            guard let first = start else { return }
            result.append(Self(id: result.count, text: String(text[first ..< end]), offset: text.utf16.distance(from: text.startIndex, to: first)))
            start = nil
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if start == nil {
                start = line.startIndex
            }
            end = line.endIndex
            if text.utf16.distance(from: start ?? end, to: end) >= length {
                close()
            }
        }
        close()
        return result
    }

    static func split(markdown: AttributedString) -> [Self] {
        var result: [Self] = []
        var start: AttributedString.Index?
        var end = markdown.startIndex
        var characters = 0
        var offset = 0
        func close() {
            guard let first = start else { return }
            let chunk = AttributedString(markdown[first ..< end])
            let text = HighlightTextContent.canonical(chunk)
            result.append(Self(id: result.count, text: text, markdown: chunk, offset: offset))
            // `canonical` joins paragraphs with a blank line.
            offset += text.utf16.count + 2
            start = nil
            characters = 0
        }
        for (_, range) in markdown.runs[\.presentationIntent] {
            if start == nil {
                start = range.lowerBound
            }
            end = range.upperBound
            characters += markdown.characters.distance(from: range.lowerBound, to: range.upperBound)
            if characters >= length {
                close()
            }
        }
        close()
        return result
    }
}

/// A whole highlightable passage and the segments it is displayed in.
struct HighlightBlock: Identifiable, Sendable {
    let id: String
    let text: String
    let segments: [HighlightSegment]

    init(id: String, markdown: AttributedString) {
        self.id = id
        text = HighlightTextContent.canonical(markdown)
        segments = HighlightSegment.split(markdown: markdown)
    }

    init(id: String, plain: String) {
        self.id = id
        text = plain
        segments = HighlightSegment.split(plain)
    }

    /// The segment a saved highlight starts in, so readers can scroll a lazy stack to it.
    func segment(for highlight: ReadingHighlight?) -> HighlightSegment? {
        guard let highlight, highlight.block == id, let location = highlight.ranges(in: text, block: id).first?.location else { return nil }
        return segments.last { $0.offset <= location }
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
    var ruling: Rulings.ID?
    var heading: Int?
    /// When `text` is a segment, the whole block it belongs to and where it starts.
    var blockText: String?
    var offset = 0
    var emphasizedMatch: NSRange?
    var textColor: Color?
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
        let highlights = store?.highlights(for: source, isHadith: isHadith, ruling: ruling) ?? []
        let passage = HighlightTextContent.attributed(text: text, markdown: markdown, arabic: arabic, hadith: isHadith || ruling != nil,
                                                      heading: heading, size: size, alignment: centered ? .center : .natural)
        let display = displayText(passage)
        let ranges = Dictionary(uniqueKeysWithValues: highlights.map { ($0.id, displayRanges(of: $0, display: display)) })
        SelectableHighlightText(
            attributed: display.attributed,
            highlights: highlights, block: block, focused: focused?.source == source && focused?.isHadith == isHadith && focused?.ruling == ruling && (focused?.block != nil || block == "arabic" || focusWholeItem) ? focused : nil,
            differentiate: differentiate, select: { ranges in
                let saved = ranges.compactMap {
                    let range = display.sourceRange($0)
                    return HighlightRange(NSRange(location: range.location + offset, length: range.length), in: blockText ?? text)
                }
                guard !saved.isEmpty, !source.isEmpty else { return }
                editing = ReadingHighlight(source: source, isHadith: isHadith, ruling: ruling, block: block, ranges: saved,
                                           excerpt: saved.map(\.quote).joined(separator: " … "), reference: reference.isEmpty ? source : reference)
            }, tap: { matches in
                if matches.count == 1 {
                    editing = matches.first
                } else {
                    tappedHighlights = matches
                    choosingHighlight = true
                }
            }, mappedRanges: ranges, canHighlight: { _ in !source.isEmpty }
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
            ForEach(highlights.filter { ranges[$0.id]?.isEmpty == false }) { highlight in
                let preview = String((highlight.note.isEmpty ? highlight.excerpt : highlight.note).prefix(60))
                let label = highlight.note.isEmpty ? preview : String(localized: "Highlight note") + ": " + preview
                Button(label) {
                    editing = highlight
                }
            }
        }
        .sheet(item: $editing) { value in
            HighlightEditor(highlight: value, existing: highlights.contains { $0.id == value.id })
        }
    }

    /// Validates against the whole block, then keeps the part inside this segment in display coordinates.
    private func displayText(_ passage: NSMutableAttributedString) -> ArabicDisplay {
        if let textColor {
            passage.addAttribute(.foregroundColor, value: PlatformColor(textColor), range: NSRange(location: 0, length: passage.length))
        }
        let matched = NSMutableAttributedString(attributedString: SearchMatch.applying(to: passage, query: searchQuery))
        if let emphasizedMatch, NSMaxRange(emphasizedMatch) <= matched.length {
            matched.addAttribute(.underlineStyle, value: NSUnderlineStyle.double.rawValue, range: emphasizedMatch)
        }
        return ArabicDisplay(matched, showMarks: showMarks)
    }

    private func displayRanges(of highlight: ReadingHighlight, display: ArabicDisplay) -> [NSRange] {
        let length = text.utf16.count
        return highlight.ranges(in: blockText ?? text, block: block).compactMap { range in
            let start = max(range.location - offset, 0), end = min(NSMaxRange(range) - offset, length)
            guard start < end else { return nil }
            let local = NSRange(location: start, length: end - start)
            return showMarks ? local : display.displayRange(local)
        }
    }
}

/// A command offered alongside "Highlight" when text is selected (edit menu on iOS, context menu on macOS).
struct HighlightTextAction {
    let title: String
    let systemImage: String
    let perform: () -> Void
}

#if os(iOS)
    struct SelectableHighlightText: UIViewRepresentable {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.scenePhase) private var scenePhase
        @Environment(\.lookupSelection) private var lookupSelection
        let attributed: NSMutableAttributedString
        let highlights: [ReadingHighlight]
        let block: String
        let focused: ReadingHighlight?
        let differentiate: Bool
        let select: ([NSRange]) -> Void
        let tap: ([ReadingHighlight]) -> Void
        var mappedRanges: [String: [NSRange]]?
        var additionalActions: ([NSRange]) -> [HighlightTextAction] = { _ in [] }
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
            let layout = ReaderTextLayoutManager()
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
                if !selected.isEmpty {
                    let value = selected.map { (textView.text as NSString).substring(with: $0) }.joined(separator: " ")
                    actions.append(UIAction(title: String(localized: "Dictionary"), image: UIImage(systemName: "character.book.closed")) { [weak self] _ in
                        self?.parent.lookupSelection(value)
                    })
                }
                let additional = parent.additionalActions(selected).map { action in
                    UIAction(title: action.title, image: UIImage(systemName: action.systemImage)) { _ in action.perform() }
                }
                return UIMenu(children: actions + suggestedActions + additional)
            }
        }
    }

    private final class ReaderTextLayoutManager: NSLayoutManager {
        // Background extent relative to point size. The Uthmani script's marks reach ~0.92 above and ~0.48 below the baseline,
        // while reader lines are ~1.75 tall, so these caps trim the empty line spacing without clipping diacritics.
        private static let ascentLimit: CGFloat = 1.0
        private static let descentLimit: CGFloat = 0.55
        private static let padding: CGFloat = 0.04
        private static let cornerRadius: CGFloat = 6
        private var drawingOrigin = CGPoint.zero

        override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
            drawingOrigin = origin
            super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        }

        override func fillBackgroundRectArray(_ rectArray: UnsafePointer<CGRect>, count rectCount: Int,
                                              forCharacterRange charRange: NSRange, color: UIColor)
        {
            guard let storage = textStorage, let container = textContainers.first, charRange.length > 0,
                  NSMaxRange(charRange) <= storage.length, let context = UIGraphicsGetCurrentContext()
            else {
                super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
                return
            }
            context.saveGState()
            defer { context.restoreGState() }
            color.setFill()

            // Backgrounds that aren't saved highlights (e.g. markdown) only get the slimmer height.
            guard storage.attribute(HighlightTextContent.highlightAttribute, at: charRange.location, effectiveRange: nil) != nil else {
                for index in 0 ..< rectCount {
                    UIRectFill(slimmed(rectArray[index], in: container))
                }
                return
            }

            storage.enumerateAttribute(HighlightTextContent.highlightAttribute, in: charRange) { id, range, _ in
                guard id != nil else { return }
                var whole = NSRange(location: NSNotFound, length: 0)
                storage.attribute(HighlightTextContent.highlightAttribute, at: range.location,
                                  longestEffectiveRange: &whole, in: NSRange(location: 0, length: storage.length))
                let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                guard glyphs.length > 0 else { return }
                var rects: [CGRect] = []
                enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                        in: container)
                { rect, _ in
                    rects.append(rect.offsetBy(dx: self.drawingOrigin.x, dy: self.drawingOrigin.y))
                }
                guard let top = rects.map(\.minY).min(), let bottom = rects.map(\.minY).max() else { return }
                let rightToLeft = Self.isRightToLeft(storage.string as NSString, range: range)
                    ?? ((storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?
                        .baseWritingDirection == .rightToLeft)
                let left: UIRectCorner = [.topLeft, .bottomLeft], right: UIRectCorner = [.topRight, .bottomRight]
                // Only the highlight's true start and end are rounded; line breaks in between stay square.
                // The start is the leading edge of the first line, the end the trailing edge of the last line.
                var corners = [UIRectCorner](repeating: [], count: rects.count)
                func outermost(onLineAt y: CGFloat, rightSide: Bool) -> Int? {
                    let line = rects.indices.filter { abs(rects[$0].minY - y) < 1 }
                    return rightSide ? line.max { rects[$0].maxX < rects[$1].maxX } : line.min { rects[$0].minX < rects[$1].minX }
                }
                if range.location == whole.location, let index = outermost(onLineAt: top, rightSide: rightToLeft) {
                    corners[index].formUnion(rightToLeft ? right : left)
                }
                if NSMaxRange(range) == NSMaxRange(whole), let index = outermost(onLineAt: bottom, rightSide: !rightToLeft) {
                    corners[index].formUnion(rightToLeft ? left : right)
                }
                for (rect, corner) in zip(rects, corners) {
                    let shape = slimmed(rect, in: container)
                    let radius = min(Self.cornerRadius, shape.height * 0.25)
                    UIBezierPath(roundedRect: shape, byRoundingCorners: corner, cornerRadii: CGSize(width: radius, height: radius)).fill()
                }
            }
        }

        /// The direction of the first strong letter in the span, or nil when it has none (digits, punctuation).
        private static func isRightToLeft(_ string: NSString, range: NSRange) -> Bool? {
            for scalar in string.substring(with: range).unicodeScalars where scalar.properties.isAlphabetic {
                switch scalar.value {
                case 0x0590 ... 0x08FF, 0xFB1D ... 0xFDFF, 0xFE70 ... 0xFEFF: return true
                default: return false
                }
            }
            return nil
        }

        /// Trims a line-height background rect to the text's own vertical extent around the baseline.
        private func slimmed(_ rect: CGRect, in container: NSTextContainer) -> CGRect {
            guard let storage = textStorage, rect.width > 0 else { return rect }
            let glyph = glyphIndex(for: CGPoint(x: rect.midX - drawingOrigin.x, y: rect.midY - drawingOrigin.y), in: container)
            guard glyph < numberOfGlyphs else { return rect }
            var lineGlyphs = NSRange()
            let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineGlyphs)
            // Diacritic glyphs report shifted positions, so derive the baseline from the line's tallest font
            // (TextKit places it one ascender below the fragment top; line spacing is added underneath).
            var ascent: CGFloat = 0, above: CGFloat = 0, below: CGFloat = 0
            storage.enumerateAttribute(.font, in: characterRange(forGlyphRange: lineGlyphs, actualGlyphRange: nil)) { value, _, _ in
                guard let font = value as? UIFont else { return }
                let size = font.pointSize
                ascent = max(ascent, font.ascender)
                above = max(above, min(font.ascender, size * Self.ascentLimit) + size * Self.padding)
                below = max(below, min(-font.descender, size * Self.descentLimit) + size * Self.padding)
            }
            guard ascent > 0 else { return rect }
            let baseline = drawingOrigin.y + line.minY + ascent
            let top = max(rect.minY, baseline - above)
            let bottom = min(rect.maxY, baseline + below)
            return bottom > top ? CGRect(x: rect.minX, y: top, width: rect.width, height: bottom - top) : rect
        }

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
            context.setFillColor((color ?? PlatformColor(Color.accentColor)).cgColor)
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
#endif

extension SearchMatch {
    static func applying(to text: NSMutableAttributedString, query: String) -> NSMutableAttributedString {
        for range in ranges(in: text.string, terms: QuranSearchText.queryTerms(query)) {
            text.addAttributes([.underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: PlatformColor(Color.accentColor)], range: range)
        }
        return text
    }
}
