import SwiftUI

/// Shaded moon with maria and earthshine. With a sun position, the lit limb and lunar north
/// point the way the observer sees them; otherwise it falls back to an upright schematic phase.
struct MoonDisc: View {
    let moon: MoonPosition
    var sun: SolarPosition?

    var body: some View {
        let phase = acos(min(1, max(-1, 2 * moon.illuminatedFraction - 1)))
        let limb = sun.map { moon.brightLimbAngle(toward: $0) } ?? (moon.isWaxing ? 90 : -90)
        let north = sun == nil ? 0 : moon.parallacticAngle
        Rectangle().fill(ShaderLibrary.moonFace(
            .boundingRect, .float(phase), .float(limb * .pi / 180), .float(north * .pi / 180)
        ))
    }
}

#Preview("Phases") {
    let fractions = [0.04, 0.25, 0.5, 0.75, 0.97]
    VStack(spacing: 16) {
        ForEach([true, false], id: \.self) { waxing in
            HStack(spacing: 16) {
                ForEach(fractions, id: \.self) { fraction in
                    MoonDisc(moon: MoonPosition(elevation: 30, azimuth: 180, illuminatedFraction: fraction,
                                                isWaxing: waxing, visibleProgress: 0.5, parallacticAngle: 0))
                        .frame(width: 48, height: 48)
                }
            }
        }
    }
    .padding(24)
    .background(Color(red: 0.02, green: 0.03, blue: 0.08))
}
