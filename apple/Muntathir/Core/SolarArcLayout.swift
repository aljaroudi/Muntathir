import CoreGraphics
import Foundation

/// A stable path in both Arabic and English, matching the sky as seen facing the sun: left to right
/// in the northern hemisphere, `mirrored` (right to left) in the southern. Progress determines
/// horizontal position; elevation uses a fixed 0–90° vertical scale.
enum SolarArcLayout {
    static func point(progress: Double, elevation: Double, in bounds: CGRect, mirrored: Bool = false) -> CGPoint {
        let progress = min(1, max(0, progress))
        return CGPoint(x: bounds.minX + bounds.width * (mirrored ? 1 - progress : progress),
                       y: bounds.maxY - bounds.height * (min(90, max(0, elevation)) / 90))
    }
}
