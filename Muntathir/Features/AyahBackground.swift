import SwiftUI

struct AyahBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        wash
            .overlay { glow.opacity(0.7) }
            .overlay {
                Canvas { context, size in
                    var contours = Path()
                    for index in 0 ..< 4 {
                        let inset = CGFloat(index) * 22
                        contours.addEllipse(in: CGRect(
                            x: size.width * 0.62 + inset,
                            y: -size.height * 0.6 + inset,
                            width: size.width * 0.95,
                            height: size.height * 1.5
                        ))
                    }
                    context.stroke(contours, with: .color(Color.accentColor.opacity(colorScheme == .dark ? 0.14 : 0.09)), lineWidth: 0.7)
                    var darkGrain = Path()
                    var lightGrain = Path()
                    // Fixed positions keep the paper texture consistent between renders.
                    for row in 0 ..< Int(ceil(size.height / 4)) {
                        for column in 0 ..< Int(ceil(size.width / 4)) {
                            let seed = (row &* 73_856_093) ^ (column &* 19_349_663)
                            let x = CGFloat(column * 4) + CGFloat(seed % 17) / 5
                            let y = CGFloat(row * 4) + CGFloat((seed / 17) % 17) / 5
                            let speck = CGRect(x: x, y: y, width: 0.8, height: 0.8)
                            if seed.isMultiple(of: 2) {
                                darkGrain.addEllipse(in: speck)
                            } else {
                                lightGrain.addEllipse(in: speck)
                            }
                        }
                    }
                    context.fill(darkGrain, with: .color(.black.opacity(0.08)))
                    context.fill(lightGrain, with: .color(.white.opacity(0.16)))
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var wash: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.04, green: 0.21, blue: 0.18), Color(red: 0.06, green: 0.12, blue: 0.17)]
                : [Color(red: 0.77, green: 0.89, blue: 0.82), Color(red: 0.98, green: 0.93, blue: 0.81)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var glow: some View {
        GeometryReader { geometry in
            ZStack {
                RadialGradient(
                    colors: [Color(red: 0.29, green: 0.70, blue: 0.55).opacity(0.32), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: geometry.size.width * 0.85
                )
                RadialGradient(
                    colors: [Color(red: 0.88, green: 0.70, blue: 0.36).opacity(colorScheme == .dark ? 0.16 : 0.3), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: geometry.size.width * 0.7
                )
            }
        }
    }
}
