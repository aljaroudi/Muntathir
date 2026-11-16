import SwiftUI

private struct ReadingActivity: ViewModifier {
    let kind: ProgressActivityKind
    let enabled: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.progressStore) private var store
    @State private var clock = ReadingActivityClock()
    @State private var activityID = UUID()
    @State private var accumulated: TimeInterval = 0
    @State private var startedAt = Date.now
    @State private var visible = false

    private var running: Bool {
        visible && enabled && scenePhase == .active
    }

    private var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    func body(content: Content) -> some View {
        content
            .onAppear { visible = true }
            .onDisappear { visible = false; pause() }
            .onChange(of: running) { _, active in
                if active {
                    clock.resume(at: now)
                } else {
                    pause()
                }
            }
            .onChange(of: kind) { old, _ in
                clock.pause(at: now)
                flush(kind: old)
                activityID = UUID(); accumulated = 0; startedAt = .now
                if running {
                    clock.resume(at: now)
                }
            }
            .simultaneousGesture(TapGesture().onEnded { clock.interact(at: now) })
            .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in clock.interact(at: now) })
            .onScrollPhaseChange { _, phase in
                if phase != .idle {
                    clock.interact(at: now)
                }
            }
            .task(id: running) {
                guard running else { return }
                while !Task.isCancelled {
                    // shortcut: forced termination can lose 15 seconds; shorten checkpoints if exact recovery is needed.
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    guard running, !Task.isCancelled else { return }
                    clock.advance(to: now)
                    flush(kind: kind)
                }
            }
    }

    private func pause() {
        clock.pause(at: now)
        flush(kind: kind)
    }

    private func flush(kind: ProgressActivityKind) {
        let amount = clock.drain()
        if amount > 0 {
            accumulated += amount
            store?.saveActivity(ProgressActivity(id: activityID, kind: kind, amount: accumulated, date: startedAt))
        }
    }
}

extension View {
    func trackReading(_ kind: ProgressActivityKind, enabled: Bool) -> some View {
        modifier(ReadingActivity(kind: kind, enabled: enabled))
    }
}
