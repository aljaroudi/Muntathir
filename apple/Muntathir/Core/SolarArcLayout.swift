import CoreGraphics
import Foundation

/// A stable left-to-right path in both Arabic and English. Only solar progress determines position.
enum SolarArcLayout {
    static func point(progress: Double, in bounds: CGRect) -> CGPoint {
        let progress = min(1, max(0, progress))
        return CGPoint(x: bounds.minX + bounds.width * progress,
                       y: bounds.maxY - bounds.height * sin(.pi * progress))
    }
}
