import Foundation

struct RakaatPreparation: Sendable {
    enum Failure: Sendable { case tooDark, unstable }
    private var darkSince: Double?
    private var lastTime: Double?

    mutating func sample(_ light: Double, elapsed: Double) -> Failure? {
        guard light.isFinite, (0 ... 1).contains(light), elapsed.isFinite, elapsed >= 5 else { return nil }
        if let lastTime, elapsed <= lastTime {
            return nil
        }
        if let lastTime, elapsed - lastTime > 0.3 {
            darkSince = nil
        }
        lastTime = elapsed
        if light < 0.08 {
            if darkSince == nil {
                darkSince = elapsed
            }
            if elapsed - (darkSince ?? elapsed) >= 1 {
                return .tooDark
            }
        } else {
            darkSince = nil
        }
        return elapsed >= 10 ? .unstable : nil
    }
}
