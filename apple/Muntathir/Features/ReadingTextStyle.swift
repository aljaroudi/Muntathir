import SwiftUI
import UIKit

struct ReadingTextStyle: ViewModifier {
    var arabic = false
    var heading: Int?
    var adjustable = true
    @AppStorage("readingSizePercent") private var percent = 100
    @ScaledMetric(relativeTo: .body) private var bodySize = 17
    @ScaledMetric(relativeTo: .title2) private var arabicSize = 28

    func body(content: Content) -> some View {
        let scale = adjustable ? Double(min(160, max(80, percent))) / 100 : 1
        let size = (arabic ? arabicSize : bodySize) * scale * (heading.map { $0 <= 2 ? 1.3 : 1.1 } ?? 1)
        let font = arabic
            ? UIFont(name: "KFGQPCHAFSUthmanicScript-Regula", size: size) ?? UIFont.systemFont(ofSize: size)
            : UIFont.systemFont(ofSize: size, weight: heading == nil ? .regular : .semibold)
        content
            .font(Font(font))
            // Subtract native leading; never compress the font’s diacritics below its natural line height.
            .lineSpacing(adjustable ? max(0, size * 1.5 - font.lineHeight) : (arabic ? 12 : 0))
    }
}

extension View {
    func readingText(arabic: Bool = false, heading: Int? = nil, adjustable: Bool = true) -> some View {
        modifier(ReadingTextStyle(arabic: arabic, heading: heading, adjustable: adjustable))
    }

    func readingColumn() -> some View {
        frame(maxWidth: 640).frame(maxWidth: .infinity)
    }
}
