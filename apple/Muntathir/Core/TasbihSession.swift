import Foundation

struct TasbihSession: Equatable {
    private(set) var total = 0

    var phrase: String {
        if total < 34 {
            return "الله أكبر"
        }
        if total < 67 {
            return "الحمد لله"
        }
        return "سبحان الله"
    }

    var target: Int {
        total < 34 ? 34 : 33
    }

    var count: Int {
        total < 34 ? total : total < 67 ? total - 34 : total - 67
    }

    var complete: Bool {
        total == 100
    }

    mutating func advance() {
        guard !complete else { return }
        total += 1
    }

    mutating func reset() {
        total = 0
    }

    static func pullProgress(_ translation: CGSize) -> Float {
        guard translation.height > 0, translation.height > abs(translation.width) else { return 0 }
        return Float(min(translation.height / 80, 1))
    }

    static func acceptsPull(_ translation: CGSize) -> Bool {
        translation.height > 40 && translation.height > abs(translation.width)
    }
}
