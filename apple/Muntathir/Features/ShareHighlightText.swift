import SwiftUI

struct ShareHighlightText: View {
    let text: AttributedString
    let highlights: [ReadingHighlight]
    let block: String
    var sourceText: String?
    var offset = 0

    var body: some View {
        rendered.textRenderer(HighlightRenderer())
            // Selectable text uses a native drawing path that bypasses image highlight rendering.
            .textSelection(.disabled)
    }

    private var rendered: Text {
        guard !highlights.isEmpty else { return Text(text) }
        return segments.reduce(Text("")) { result, segment in
            let part = Text(segment.text)
            if let color = segment.color {
                return Text("\(result)\(part.customAttribute(Background(color: Color(uiColor: color))))")
            }
            return Text("\(result)\(part)")
        }
    }

    var segments: [(text: AttributedString, color: UIColor?)] {
        let raw = String(text.characters)
        let colored = HighlightTextContent.applying(highlights, to: NSAttributedString(string: sourceText ?? raw), block: block)
        let slice = colored.attributedSubstring(from: NSRange(location: offset, length: raw.utf16.count))
        var result: [(text: AttributedString, color: UIColor?)] = []
        slice.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: slice.length)) { color, range, _ in
            guard let indices = Range(range, in: raw),
                  let start = AttributedString.Index(indices.lowerBound, within: text),
                  let end = AttributedString.Index(indices.upperBound, within: text) else { return }
            result.append((AttributedString(text[start ..< end]), color as? UIColor))
        }
        return result
    }

    private struct Background: TextAttribute {
        let color: Color
    }

    private struct HighlightRenderer: TextRenderer {
        func draw(layout: Text.Layout, in context: inout GraphicsContext) {
            for line in layout {
                for run in line {
                    if let background = run[Background.self] {
                        context.fill(Path(run.typographicBounds.rect), with: .color(background.color))
                    }
                }
                context.draw(line)
            }
        }
    }
}
