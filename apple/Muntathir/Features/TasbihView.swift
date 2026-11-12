import RealityKit
import SwiftUI

struct TasbihView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = TasbihSession()
    @State private var beads = TasbihBeadScene()
    @State private var pull: Float = 0
    @State private var settling = false
    @State private var confirmingReset = false
    @GestureState private var dragging = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    Text(verbatim: session.phrase)
                        .font(.largeTitle)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("tasbih-phrase")
                    Text("\(session.count) / \(session.target)")
                        .font(.title2.monospacedDigit())
                        .accessibilityIdentifier("tasbih-count")
                    beadView
                        .frame(height: max(240, min(480, geometry.size.height - (dynamicTypeSize.isAccessibilitySize ? 360 : 240))))
                    if session.complete {
                        Label("Count complete", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .accessibilityIdentifier("tasbih-complete")
                        Button("Restart", action: reset)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("tasbih-restart")
                    } else {
                        Text("Pull a bead down to count")
                            .font(.callout)
                            .foregroundStyle(.secondary)
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
        .navigationTitle("Tasbih")
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
        .onDisappear { reset() }
    }

    private var beadView: some View {
        RealityView { content in
            content.camera = .virtual
            content.add(beads.root)
        } update: { _ in
            beads.update(phase: Float(session.total) + (reduceMotion ? 0 : pull), animated: settling && !reduceMotion)
        }
        .allowsHitTesting(false)
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
                            }
                            settle()
                        }
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Count one bead")
        .accessibilityValue(Text("\(session.phrase) \(session.count) / \(session.target)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard !settling, !session.complete else { return }
            session.advance()
            settle()
        }
        .accessibilityIdentifier("tasbih-beads")
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
