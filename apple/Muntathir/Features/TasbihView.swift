import RealityKit
import SwiftUI

struct TasbihView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("tasbihSwipeHintSeen") private var swipeHintSeen = false
    @State private var session = TasbihSession()
    @State private var beads = TasbihBeadScene()
    @State private var pull: Float = 0
    @State private var settling = false
    @State private var confirmingReset = false
    @State private var showingSwipeHint = false
    @GestureState private var dragging = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    beadView
                        .frame(height: max(320, min(640, geometry.size.height - (dynamicTypeSize.isAccessibilitySize ? 200 : 120))))
                    if session.complete {
                        Label("Count complete", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .accessibilityIdentifier("tasbih-complete")
                        Button("Restart", action: reset)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("tasbih-restart")
                    }
                    Text("\(session.total) / \(100)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("tasbih-total")
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text("\(session.count) / \(session.target)"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset", systemImage: "arrow.counterclockwise") { confirmingReset = true }
                    .disabled(session.total == 0 || session.complete || settling)
                    .accessibilityIdentifier("tasbih-reset")
            }
        }
        .alert("Reset Tasbih?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive, action: reset)
            Button("Cancel", role: .cancel) {}
        }
        .sensoryFeedback(.impact(weight: .light), trigger: session.total) { old, new in new > old }
        .task {
            guard !swipeHintSeen else { return }
            showingSwipeHint = true
            swipeHintSeen = true
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
            Text(verbatim: session.phrase)
                .font(.largeTitle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("tasbih-phrase")
            beadLayer(beads.frontRoot)
        }
        .clipped()
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
                                session.advance()
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
                    session.advance()
                    showingSwipeHint = false
                    settle()
                }
                .accessibilityIdentifier("tasbih-beads")
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

    private func settle() {
        settling = !reduceMotion
        pull = 0
    }

    private func reset() {
        settling = false
        pull = 0
        session.reset()
    }
}
