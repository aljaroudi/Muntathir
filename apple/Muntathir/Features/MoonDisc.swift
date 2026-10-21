import SwiftUI

/// Upright schematic phase: waxing light on the right, waning on the left.
struct MoonDisc: View {
    let fraction: Double
    let waxing: Bool

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var light = Path()
            for step in 0 ... 120 {
                let limb = step <= 60
                let y = limb ? Double(step) / 30 - 1 : 3 - Double(step) / 30
                let x = sqrt(max(0, 1 - y * y)) * (limb ? 1 : 1 - 2 * fraction)
                let point = CGPoint(x: center.x + (waxing ? x : -x) * radius, y: center.y + y * radius)
                if step == 0 {
                    light.move(to: point)
                } else {
                    light.addLine(to: point)
                }
            }
            light.closeSubpath()
            context.fill(light, with: .linearGradient(Gradient(colors: [.white, Color(red: 0.7, green: 0.78, blue: 0.88)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
        }
    }
}
