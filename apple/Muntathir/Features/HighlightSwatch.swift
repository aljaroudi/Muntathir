import SwiftUI

struct HighlightSwatch: View {
    let color: HighlightColor
    let size: CGFloat
    var isSelected = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheenTrigger = 0

    var body: some View {
        Circle()
            .fill(color.fillStyle)
            .overlay {
                if color == .cyan, !reduceMotion {
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, .white.opacity(0.65), .clear],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: size * 0.35, height: size * 2)
                        .rotationEffect(.degrees(25))
                        .keyframeAnimator(initialValue: -size, trigger: sheenTrigger) { content, offset in
                            content.offset(x: offset)
                        } keyframes: { _ in
                            MoveKeyframe(-size)
                            LinearKeyframe(size, duration: 1.2)
                        }
                        .allowsHitTesting(false)
                }
            }
            .clipShape(Circle())
            .frame(width: size, height: size)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.bold())
                        .foregroundStyle([HighlightColor.indigo, .brown, .blue, .purple].contains(color) ? .white : .black)
                }
            }
            .onAppear { playSheen() }
            .onChange(of: isSelected) { _, selected in
                if selected { playSheen() }
            }
    }

    private func playSheen() {
        if color == .cyan, !reduceMotion { sheenTrigger += 1 }
    }
}

struct HighlightMarker: View {
    let color: HighlightColor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Capsule()
            .fill(color.fillStyle)
            .overlay {
                if color == .cyan, !reduceMotion, scenePhase == .active {
                    PearlMarkerSheen()
                }
            }
            .clipShape(Capsule())
    }
}

private struct PearlMarkerSheen: View {
    @State private var trigger = 0

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.65), .clear],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: 28)
                .keyframeAnimator(initialValue: CGFloat(-28), trigger: trigger) { content, offset in
                    content.offset(y: offset)
                } keyframes: { _ in
                    MoveKeyframe(CGFloat(-28))
                    LinearKeyframe(geometry.size.height, duration: 1.5)
                }
                .onAppear { trigger += 1 }
        }
        .allowsHitTesting(false)
    }
}

#Preview("Pearl marker") {
    HStack {
        HighlightMarker(color: .cyan).frame(width: 4, height: 120)
        Text("Pearl highlight")
    }
    .padding()
}

#Preview("Pearl") {
    HStack {
        HighlightSwatch(color: .teal, size: 32)
        HighlightSwatch(color: .cyan, size: 32)
        HighlightSwatch(color: .cyan, size: 36, isSelected: true)
        HighlightSwatch(color: .blue, size: 32)
    }
    .padding()
}
