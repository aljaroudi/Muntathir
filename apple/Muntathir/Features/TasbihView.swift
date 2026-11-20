import RealityKit
import SwiftUI

struct TasbihView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @Environment(\.progressStore) private var progress
    @ScaledMetric(relativeTo: .largeTitle) private var countHeight = 48
    @State private var activityID = UUID()
    @State private var startedAt = Date.now
    @State private var session = TasbihSession.testStart
    @State private var beads = TasbihBeadScene()
    @State private var pull: Float = 0
    @State private var settling = false
    @State private var showingSwipeHint = false
    @GestureState private var dragging = false

    var body: some View {
        GeometryReader { geometry in
            beadView
                .frame(height: max(320, geometry.size.height))
        }
        .padding(24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Tasbih")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(trigger: session) { old, new in
            guard new.total > old.total else { return nil }
            return old.phrase == new.phrase ? .impact(weight: .light) : .success
        }
        .task {
            showingSwipeHint = true
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            showingSwipeHint = false
        }
        .task(id: settling) {
            guard settling else { return }
            do { try await Task.sleep(for: .milliseconds(220)) } catch { return }
            settling = false
        }
        .onChange(of: dragging) { _, active in
            if !active, pull != 0 {
                settle()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                pull = 0; settling = false
            }
        }
        .onDisappear {
            showingSwipeHint = false
            reset()
        }
    }

    private var beadView: some View {
        ZStack {
            beadLayer(beads.rearRoot)
                .blur(radius: 3)
            VStack(spacing: 12) {
                ZStack {
                    Text(session.count.formatted(.number.locale(locale)))
                        .font(.largeTitle.monospacedDigit())
                        .id(session.total)
                        .transition(reduceMotion ? .identity : .asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .move(edge: .bottom).combined(with: .opacity)))
                        .accessibilityIdentifier("tasbih-count")
                }
                .frame(height: countHeight)
                .clipped()
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: session.total)
                if session.complete {
                    Image(systemName: "checkmark")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Count complete")
                        .accessibilityIdentifier("tasbih-complete")
                } else {
                    Text(verbatim: session.phrase)
                        .font(.largeTitle)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .accessibilityIdentifier("tasbih-phrase")
                }
            }
            beadLayer(beads.frontRoot)
        }
        .overlay {
            Color.clear
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .updating($dragging) { _, active, _ in active = true }
                        .onChanged { value in
                            guard !settling, !session.complete else { return }
                            pull = TasbihSession.pullProgress(value.translation)
                        }
                        .onEnded { value in
                            guard !settling, !session.complete else { return }
                            if TasbihSession.acceptsPull(value.translation) {
                                advance()
                                showingSwipeHint = false
                            }
                            settle()
                        }
                )
                .accessibilityLabel("Count one bead")
                .accessibilityHint("Pull a bead down to count")
                .accessibilityValue(Text("\(session.phrase) \(session.count) / \(session.target)"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    guard !settling, !session.complete else { return }
                    advance()
                    showingSwipeHint = false
                    settle()
                }
                .accessibilityIdentifier("tasbih-beads")
                .accessibilityHidden(session.complete)
        }
        .overlay {
            if showingSwipeHint {
                GeometryReader { geometry in
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.primary)
                        .padding(12)
                        .background(.regularMaterial, in: .circle)
                        .keyframeAnimator(initialValue: CGFloat.zero, repeating: !reduceMotion) { content, offset in
                            content.offset(y: offset)
                        } keyframes: { _ in
                            CubicKeyframe(56, duration: 1.3)
                            LinearKeyframe(56, duration: 0.3)
                            MoveKeyframe(0)
                            LinearKeyframe(0, duration: 0.4)
                        }
                        .position(x: geometry.size.width / 2 + geometry.size.height * 0.11, y: geometry.size.height * 0.35)
                        .accessibilityLabel("Pull a bead down to count")
                        .accessibilityIdentifier("tasbih-swipe-hint")
                }
                .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func beadLayer(_ root: Entity) -> some View {
        RealityView { content in
            content.camera = .virtual
            content.add(root)
        } update: { _ in
            beads.update(phase: Float(session.total) + (reduceMotion ? 0 : pull), animated: settling && !reduceMotion)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func advance() {
        let previous = session.total
        session.advance()
        if session.total > previous {
            progress?.saveActivity(ProgressActivity(id: activityID, kind: .tasbih, amount: Double(session.total), date: startedAt))
        }
    }

    private func settle() {
        settling = !reduceMotion
        pull = 0
    }

    private func reset() {
        settling = false
        pull = 0
        session.reset()
        activityID = UUID()
        startedAt = .now
    }
}

private extension TasbihSession {
    /// UI tests can start near a stage boundary instead of pulling up to 100 beads.
    static var testStart: TasbihSession {
        var session = TasbihSession()
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ui-testing"), let index = arguments.firstIndex(of: "--ui-testing-tasbih-total"),
               arguments.indices.contains(index + 1), let total = Int(arguments[index + 1])
            {
                for _ in 0 ..< total {
                    session.advance()
                }
            }
        #endif
        return session
    }
}
