import SwiftUI

/// Transient scroll samples deliberately do not publish SwiftUI updates.
@MainActor final class HadithScrollTracking {
    var visibleRows: [String: CGFloat] = [:]
    var offset: Double = 0
    var isActive = true
    private var settleTask: Task<Void, Never>?

    func update(_ id: String, position: CGFloat?, settled: @escaping @MainActor () -> Void) {
        let previous = firstVisibleRow
        visibleRows[id] = position
        guard isActive, firstVisibleRow != previous else { return }
        settleTask?.cancel()
        // List does not consistently deliver scroll-phase callbacks. Coalesce row-boundary changes instead.
        settleTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) }
            catch { return }
            self?.settleTask = nil
            settled()
        }
    }

    func stop() {
        isActive = false
        settleTask?.cancel()
        settleTask = nil
    }

    var firstVisibleRow: String? {
        visibleRows.min { $0.value < $1.value }?.key
    }
}

/// List restores stable row identities rather than ScrollView-only pixel positions.
struct HadithListAnchor: ViewModifier {
    let id: String
    let tracking: HadithScrollTracking
    let settled: @MainActor () -> Void

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat?.self) { geometry in
                let frame = geometry.frame(in: .named("hadith-list"))
                let height = geometry.bounds(of: .named("hadith-list"))?.height ?? 0
                return frame.maxY > 0 && frame.minY < height ? frame.minY : nil
            } action: { value in
                tracking.update(id, position: value, settled: settled)
            }
            .onDisappear { tracking.update(id, position: nil, settled: settled) }
    }
}
