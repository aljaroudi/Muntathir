import CoreGraphics
import Foundation

/// A stable left-to-right path in both Arabic and English. Progress determines horizontal position; elevation uses a fixed 0–90° vertical scale.
enum SolarArcLayout {
    static func point(progress: Double, elevation: Double, in bounds: CGRect) -> CGPoint {
        let progress = min(1, max(0, progress))
        return CGPoint(x: bounds.minX + bounds.width * progress,
                       y: bounds.maxY - bounds.height * (min(90, max(0, elevation)) / 90))
    }
}
