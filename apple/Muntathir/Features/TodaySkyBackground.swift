import SwiftUI

struct TodaySkyBackground: View {
    let sun: SolarPosition
    var bandHeight: CGFloat = 148
    var headerHeight: CGFloat = 0
    var moon: MoonPosition?
    var markers: [SolarArcMarker] = []

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Rectangle().fill(ShaderLibrary.todaySky(
                    .float(sun.elevation), .float(sun.isRising ? 1 : 0),
                    .float(geometry.safeAreaInsets.top + headerHeight + bandHeight - 12)
                ))
                .ignoresSafeArea()

                SolarArc(progress: sun.daylightProgress, warm: sun.elevation < 10, markers: markers, moon: moon)
                    .frame(maxWidth: 760)
                    .frame(height: bandHeight)
                    .frame(maxWidth: .infinity)
                    .padding(.top, headerHeight)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A deliberately enlarged sun on a schematic daily arc, not a compass or angular sky projection.
private struct SolarArc: View {
    let progress: Double?
    let warm: Bool
    let markers: [SolarArcMarker]
    let moon: MoonPosition?

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size).insetBy(dx: 36, dy: 24)
            ZStack {
                if progress != nil {
                    Path { path in
                        for step in 0 ... 60 {
                            let point = SolarArcLayout.point(progress: Double(step) / 60, in: bounds)
                            if step == 0 {
                                path.move(to: point)
                            } else {
                                path.addLine(to: point)
                            }
                        }
                    }
                    .stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                }
                if let moon, let moonProgress = moon.visibleProgress {
                    MoonDisc(fraction: moon.illuminatedFraction, waxing: moon.isWaxing)
                        .frame(width: 20, height: 20)
                        .opacity(progress == nil ? 0.9 : 0.65)
                        .position(SolarArcLayout.point(progress: moonProgress, in: bounds))
                }
                if let progress {
                    let center = SolarArcLayout.point(progress: progress, in: bounds)
                    Circle()
                        .fill(RadialGradient(colors: [Color.orange.opacity(0.4), .clear], center: .center, startRadius: 12, endRadius: 52))
                        .frame(width: 104, height: 104)
                        .position(center)
                    Circle()
                        .fill(RadialGradient(colors: [.white, warm ? Color(red: 1, green: 0.72, blue: 0.34) : Color(red: 1, green: 0.94, blue: 0.68)], center: .topLeading, startRadius: 0, endRadius: 30))
                        .frame(width: 30, height: 30)
                        .shadow(color: .orange.opacity(0.35), radius: 12)
                        .position(center)

                    ForEach(markers) { marker in
                        SolarPrayerIndicator(marker: marker)
                            .offset(y: 22)
                            .position(SolarArcLayout.point(progress: marker.progress, in: bounds))
                    }
                }
            }
        }
    }
}

private struct SolarPrayerIndicator: View {
    let marker: SolarArcMarker
    var body: some View {
        Image(systemName: marker.name.symbol)
            .font(.system(size: 13, weight: marker.state == .upcoming ? .bold : .regular))
            .foregroundStyle(marker.state == .upcoming ? Color(red: 1, green: 0.85, blue: 0.4) : .white)
            .opacity(marker.state == .past ? 0.45 : 1)
            .shadow(color: .black.opacity(0.6), radius: 2)
            .frame(width: 24, height: 24)
    }
}

/// Upright schematic phase: waxing light on the right, waning on the left.
private struct MoonDisc: View {
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

struct SkyCardSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Rectangle().fill(.background.opacity(reduceTransparency || contrast == .increased ? 1 : 0.86))
    }
}

#Preview("Sunrise to sunset") {
    VStack(spacing: 0) {
        ForEach([0.0, 0.25, 0.5, 0.75, 1], id: \.self) { progress in
            TodaySkyBackground(sun: SolarPosition(elevation: 15, apparentElevation: 15, azimuth: 0, isRising: progress < 0.5, daylightProgress: progress))
                .frame(height: 148).clipped()
        }
    }
}
