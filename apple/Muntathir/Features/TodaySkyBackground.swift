import SwiftUI

struct TodaySkyBackground: View {
    let sun: SolarPosition
    var bandHeight: CGFloat = 148
    var headerHeight: CGFloat = 0
    var moon: MoonPosition?
    var markers: [SolarArcMarker] = []
    /// Southern-hemisphere observers face north, so the sun crosses right to left.
    var mirrored = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Rectangle().fill(ShaderLibrary.todaySky(
                    .float(sun.elevation), .float(sun.isRising ? 1 : 0),
                    .float(geometry.safeAreaInsets.top + headerHeight + bandHeight - 12)
                ))
                .ignoresSafeArea()

                SolarArc(sun: sun, markers: markers, moon: moon, mirrored: mirrored)
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
    let sun: SolarPosition
    let markers: [SolarArcMarker]
    let moon: MoonPosition?
    let mirrored: Bool

    var body: some View {
        GeometryReader { geometry in
            // Leave room for the prayer symbols below the horizon (22-point offset plus half their height).
            let bounds = CGRect(x: 36, y: 24, width: max(0, geometry.size.width - 72),
                                height: max(0, geometry.size.height - 60))
            let progress = sun.daylightProgress
            ZStack {
                if let arc = sun.arc, progress != nil {
                    Path { path in
                        for step in 0 ... 60 {
                            let point = SolarArcLayout.point(progress: Double(step) / 60, elevation: arc.elevation(at: Double(step) / 60), in: bounds, mirrored: mirrored)
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
                    MoonDisc(moon: moon, sun: sun)
                        .frame(width: 20, height: 20)
                        .opacity(progress == nil ? 0.9 : 0.65)
                        .position(SolarArcLayout.point(progress: moonProgress, elevation: moon.elevation, in: bounds, mirrored: mirrored))
                }
                if let progress {
                    let center = SolarArcLayout.point(progress: progress, elevation: sun.elevation, in: bounds, mirrored: mirrored)
                    SunDisc(elevation: sun.elevation, animated: true, hdr: true)
                        .frame(width: 30, height: 30)
                        .position(center)

                    ForEach(markers) { marker in
                        SolarPrayerIndicator(marker: marker)
                            .offset(y: 22)
                            .position(SolarArcLayout.point(progress: marker.progress, elevation: marker.elevation, in: bounds, mirrored: mirrored))
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

struct SkyCardSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Rectangle().fill(.background.opacity(reduceTransparency || contrast == .increased ? 1 : 0.86))
    }
}

#Preview("Sunrise to sunset") {
    VStack(spacing: 0) {
        ForEach([6, 9, 12, 15, 18], id: \.self) { hour in
            let date = Date(timeIntervalSince1970: 1_773_964_800 + Double(hour) * 3600)
            TodaySkyBackground(sun: SolarPosition.calculate(at: date, latitude: 0, longitude: 0)!)
                .frame(height: 148).clipped()
        }
    }
}
