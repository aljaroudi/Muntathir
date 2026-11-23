import SwiftUI

/// The frame sets the disc size; the corona spills four times wider without affecting layout.
struct SunDisc: View {
    let elevation: Double
    /// Slowly turns the rays; paused for Reduce Motion, Low Power Mode and inactive scenes.
    var animated = false
    /// Lifts the core above SDR white on HDR displays.
    var hdr = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        let moving = animated && !reduceMotion && !lowPower && scenePhase == .active
        GeometryReader { geometry in
            let disc = min(geometry.size.width, geometry.size.height)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { context in
                // Wrapping at an hour keeps float precision; every shader period divides 3600 seconds.
                let time = animated ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600) : 0
                Rectangle()
                    .fill(ShaderLibrary.sunGlow(.boundingRect, .float(elevation), .float(time)))
                    .frame(width: disc * 4, height: disc * 4)
            }
            .overlay {
                if hdr {
                    let white = Color(.sRGBLinear, white: 1).exposureAdjust(0.7).headroom(2)
                    Circle()
                        .fill(EllipticalGradient(colors: [white, white.opacity(0)], startRadiusFraction: 0, endRadiusFraction: 0.5))
                        .frame(width: disc * 0.7, height: disc * 0.7)
                }
            }
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .task {
            guard animated else { return }
            for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }
}

#Preview("Sun elevations") {
    HStack(spacing: 70) {
        ForEach([1.0, 8, 40], id: \.self) { elevation in
            SunDisc(elevation: elevation, animated: true, hdr: true).frame(width: 30, height: 30)
        }
    }
    .frame(width: 360, height: 180)
    .background(Color(red: 0.2, green: 0.45, blue: 0.75))
}
