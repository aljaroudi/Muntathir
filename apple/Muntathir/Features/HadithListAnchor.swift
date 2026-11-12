import SwiftUI

/// List restores stable row identities rather than ScrollView-only pixel positions.
struct HadithListAnchor: ViewModifier {
    let id: String
    @Binding var visibleRows: [String: CGFloat]

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat?.self) { geometry in
                let frame = geometry.frame(in: .named("hadith-list"))
                let height = geometry.bounds(of: .named("hadith-list"))?.height ?? 0
                return frame.maxY > 0 && frame.minY < height ? frame.minY : nil
            } action: { value in
                visibleRows[id] = value
            }
            .onDisappear { visibleRows[id] = nil }
    }
}
