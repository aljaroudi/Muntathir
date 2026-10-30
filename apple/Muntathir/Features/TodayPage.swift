import SwiftUI

struct TodayPage<Content: View>: View {
    let transparentBackground: Bool
    @ViewBuilder var content: Content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var minimumColumnWidth = 320
    @State private var geometry = TodayPageGeometry()

    var body: some View {
        let layout = horizontalSizeClass == .regular && !typeSize.isAccessibilitySize
            ? AnyLayout(TodayColumnsLayout(minimumColumnWidth: minimumColumnWidth, geometry: geometry))
            : AnyLayout(VStackLayout(spacing: 18))
        ScrollView {
            layout { content }
                .frame(maxWidth: maximumWidth)
                .onGeometryChange(for: TodayPageGeometry.self) { proxy in
                    TodayPageGeometry.read(proxy)
                } action: { geometry = $0 }
                .padding(16)
                .frame(maxWidth: .infinity)
        }
        .background(transparentBackground ? Color.clear : Color(.systemGroupedBackground))
    }

    private var maximumWidth: CGFloat {
        horizontalSizeClass == .regular && !typeSize.isAccessibilitySize ? 1120 : 760
    }
}

nonisolated struct TodayColumnKey: LayoutValueKey {
    static let defaultValue = 0
}

nonisolated struct TodayPageGeometry: Equatable, Sendable {
    var division: CGRect = .zero
    var leadingMargin: CGFloat = 0
    var trailingMargin: CGFloat = 0
    var active = false

    static func read(_ proxy: GeometryProxy) -> Self {
        var result = Self()
        if #available(iOS 27.1, *),
           let region = proxy.reservedRegions(kind: .division, options: .includeInactive)
           .first(where: { $0.frame.height > $0.frame.width && $0.frame.width > 0 })
        {
            // Scrolling changes vertical coordinates, but only the horizontal fold affects these columns.
            result.division = CGRect(x: region.frame.minX, y: 0, width: region.frame.width, height: 0)
            result.leadingMargin = region.margins.leading
            result.trailingMargin = region.margins.trailing
            result.active = region.isActive
        }
        return result
    }

    func columns(in width: CGFloat, minimumWidth: CGFloat) -> TodayColumns? {
        let center = division.width > 0 ? division.midX : width / 2
        let start = active ? min(center - 9, division.minX - leadingMargin) : center - 9
        let end = active ? max(center + 9, division.maxX + trailingMargin) : center + 9
        guard start >= minimumWidth, width - end >= minimumWidth else { return nil }
        return TodayColumns(leadingWidth: start, trailingOrigin: end, trailingWidth: width - end)
    }
}

nonisolated struct TodayColumns: Equatable {
    let leadingWidth: CGFloat
    let trailingOrigin: CGFloat
    let trailingWidth: CGFloat

    func width(for column: Int) -> CGFloat {
        column == 0 ? leadingWidth : trailingWidth
    }

    func origin(for column: Int) -> CGFloat {
        column == 0 ? 0 : trailingOrigin
    }
}

struct TodayColumnsLayout: Layout {
    let minimumColumnWidth: CGFloat
    var geometry = TodayPageGeometry()

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? minimumColumnWidth
        return CGSize(width: width, height: frames(in: width, subviews: subviews).map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for (view, frame) in zip(subviews, frames(in: bounds.width, subviews: subviews)) {
            // SwiftUI mirrors custom Layout placement and reserved-region frames together in RTL.
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(in width: CGFloat, subviews: Subviews) -> [CGRect] {
        let columns = geometry.columns(in: width, minimumWidth: minimumColumnWidth)
        var heights: [CGFloat] = [0, 0]
        return subviews.map { view in
            let column = columns == nil ? 0 : view[TodayColumnKey.self]
            let columnWidth = columns?.width(for: column) ?? width
            let size = view.sizeThatFits(.init(width: columnWidth, height: nil))
            let frame = CGRect(x: columns?.origin(for: column) ?? 0, y: heights[column],
                               width: columnWidth, height: size.height)
            heights[column] += size.height + 18
            return frame
        }
    }
}
