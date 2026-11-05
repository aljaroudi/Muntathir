import Foundation

struct QiblaAlignment: Equatable {
    enum Feedback: Equatable {
        case none, gentle, medium, strong, aligned

        var pulse: (intensity: Double, interval: Double)? {
            switch self {
            case .gentle: (0.25, 1)
            case .medium: (0.55, 0.65)
            case .strong: (0.85, 0.35)
            case .none, .aligned: nil
            }
        }
    }

    let error: Double

    init?(bearing: Double, heading: Double) {
        guard bearing.isFinite, heading.isFinite,
              (0 ..< 360).contains(bearing), (0 ..< 360).contains(heading)
        else { return nil }
        error = (bearing - heading + 540).truncatingRemainder(dividingBy: 360) - 180
    }

    func isAligned(previously: Bool) -> Bool {
        // Hysteresis prevents sensor jitter from repeating the success haptic.
        abs(error) <= (previously ? 8 : 5)
    }

    func feedback(aligned: Bool) -> Feedback {
        if aligned {
            return .aligned
        }
        switch abs(error) {
        case ...10: return .strong
        case ...30: return .medium
        case ...60: return .gentle
        default: return .none
        }
    }
}
