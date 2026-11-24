#if os(macOS)
    import AppKit
    import SwiftUI

    /// The macOS counterpart of the iOS reader text view: selectable, highlightable text backed by `NSTextView`.
    struct SelectableHighlightText: NSViewRepresentable {
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

        func makeNSView(context: Context) -> HighlightNSTextView {
            // TextKit 1 keeps the glyph-based hit testing below simple.
            let view = HighlightNSTextView(usingTextLayoutManager: false)
            view.isEditable = false
            view.isSelectable = true
            view.drawsBackground = false
            view.isRichText = true
            view.textContainerInset = .zero
            view.textContainer?.lineFragmentPadding = 0
            view.textContainer?.widthTracksTextView = true
            view.isVerticallyResizable = false
            view.isHorizontallyResizable = false
            view.delegate = context.coordinator
            view.coordinator = context.coordinator
            view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return view
        }

        func updateNSView(_ view: HighlightNSTextView, context: Context) {
            context.coordinator.parent = self
            let rendered = HighlightTextContent.applying(highlights, to: attributed, block: block, differentiate: differentiate, mappedRanges: mappedRanges)
            view.setRenderedText(rendered)
            if let focused, let range = ranges(for: focused).first {
                view.scroll(to: range, id: focused.id)
            }
        }

        func sizeThatFits(_ proposal: ProposedViewSize, nsView: HighlightNSTextView, context _: Context) -> CGSize? {
            guard let width = proposal.width, let container = nsView.textContainer, let layout = nsView.layoutManager else { return nil }
            container.size = CGSize(width: width, height: .greatestFiniteMagnitude)
            layout.ensureLayout(for: container)
            return CGSize(width: width, height: ceil(layout.usedRect(for: container).height))
        }

        @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
            var parent: SelectableHighlightText
            init(_ parent: SelectableHighlightText) {
                self.parent = parent
            }

            func highlights(at point: CGPoint, in view: NSTextView) -> [ReadingHighlight] {
                guard let layout = view.layoutManager, let container = view.textContainer else { return [] }
                let location = CGPoint(x: point.x - view.textContainerOrigin.x, y: point.y - view.textContainerOrigin.y)
                let glyph = layout.glyphIndex(for: location, in: container)
                guard glyph < layout.numberOfGlyphs,
                      layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
                      .insetBy(dx: -2, dy: -2).contains(location) else { return [] }
                let offset = layout.characterIndexForGlyph(at: glyph)
                return parent.highlights.filter { highlight in
                    parent.ranges(for: highlight).contains { NSLocationInRange(offset, $0) }
                }
            }

            func textViewDidChangeSelection(_ notification: Notification) {
                guard let view = notification.object as? NSTextView, view.selectedRange().length > 0 else { return }
                parent.selectionChanged(view.selectedRange())
            }

            func textView(_ view: NSTextView, menu: NSMenu, for _: NSEvent, at _: Int) -> NSMenu? {
                let selected = view.selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
                var items: [NSMenuItem] = []
                if !selected.isEmpty, parent.canHighlight(selected) {
                    items.append(MenuAction.item(title: String(localized: "Highlight"), systemImage: "highlighter") { [weak self, weak view] in
                        view?.setSelectedRange(NSRange(location: 0, length: 0))
                        self?.parent.select(selected)
                    })
                }
                if !selected.isEmpty {
                    let value = selected.map { (view.string as NSString).substring(with: $0) }.joined(separator: " ")
                    items.append(MenuAction.item(title: String(localized: "Dictionary"), systemImage: "character.book.closed") { [weak self] in
                        self?.parent.lookupSelection(value)
                    })
                }
                items += parent.additionalActions(selected).map { MenuAction.item(title: $0.title, systemImage: $0.systemImage, perform: $0.perform) }
                guard !items.isEmpty else { return menu }
                items.append(.separator())
                for (index, item) in items.enumerated() {
                    menu.insertItem(item, at: index)
                }
                return menu
            }
        }
    }

    final class HighlightNSTextView: NSTextView {
        weak var coordinator: SelectableHighlightText.Coordinator?
        private var renderedText: NSAttributedString?
        private var scrolledID: String?

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            // NSTextView tracks the drag until mouse up, so a plain click on a highlight opens it while drags still select.
            super.mouseDown(with: event)
            guard event.clickCount == 1, selectedRange().length == 0, let coordinator else { return }
            let matches = coordinator.highlights(at: point, in: self)
            if !matches.isEmpty {
                coordinator.parent.tap(matches)
            }
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            textContainer?.size = CGSize(width: newSize.width, height: .greatestFiniteMagnitude)
        }

        func setRenderedText(_ rendered: NSAttributedString) {
            // Reassigning identical text would reset the selection on every SwiftUI update.
            guard renderedText != rendered, let textStorage else { return }
            let selection = selectedRange()
            let sameText = textStorage.string == rendered.string
            renderedText = NSAttributedString(attributedString: rendered)
            textStorage.setAttributedString(rendered)
            if sameText {
                setSelectedRange(selection)
            }
        }

        func scroll(to range: NSRange, id: String) {
            guard scrolledID != id else { return }
            scrolledID = id
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.scrollRangeToVisible(NSRange(location: range.location, length: min(range.length, 1)))
            }
        }
    }

    /// Bridges closures to `NSMenuItem`'s target–action.
    private final class MenuAction: NSObject {
        private let perform: () -> Void

        private init(_ perform: @escaping () -> Void) {
            self.perform = perform
        }

        @objc private func run() {
            perform()
        }

        static func item(title: String, systemImage: String, perform: @escaping () -> Void) -> NSMenuItem {
            let action = MenuAction(perform)
            let item = NSMenuItem(title: title, action: #selector(run), keyEquivalent: "")
            item.target = action
            item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
            // NSMenuItem holds its target weakly; keep the bridge alive for the menu's lifetime.
            item.representedObject = action
            return item
        }
    }
#endif
