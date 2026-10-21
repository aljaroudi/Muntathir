import SwiftUI

/// Keep compact cards square, but grow for translated text and weather error details.
struct InfoCardLayout: Layout {
    let square: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? 160
        let content = subviews.first?.sizeThatFits(.init(width: width, height: nil)) ?? .zero
        return CGSize(width: width, height: max(square ? width : 0, content.height))
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                              proposal: .init(width: bounds.width, height: nil))
    }
}
