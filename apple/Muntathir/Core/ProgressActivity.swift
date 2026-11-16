import Foundation

enum ProgressActivityKind: String, Codable, CaseIterable, Sendable {
    case quranReading, hadithReading, supplicationReading, tasbih

    static let reading: [Self] = [.quranReading, .hadithReading, .supplicationReading]

    var title: String {
        switch self {
        case .quranReading: String(localized: "Holy Quran")
        case .hadithReading: String(localized: "Hadith")
        case .supplicationReading: String(localized: "Supplications")
        case .tasbih: String(localized: "Tasbih")
        }
    }

    var symbol: String {
        switch self {
        case .quranReading: "book.closed.fill"
        case .hadithReading: "text.book.closed.fill"
        case .supplicationReading: "hands.sparkles.fill"
        case .tasbih: "circle.dotted"
        }
    }
}

struct ProgressActivity: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    let kind: ProgressActivityKind
    let amount: Double
    var date = Date.now

    var isValid: Bool {
        amount.isFinite && amount > 0 && (kind != .tasbih || amount.rounded(.down) == amount)
    }

    static func totals(_ activities: [Self]) -> [ProgressActivityKind: Double] {
        var sessions: [UUID: ProgressActivity] = [:]
        for activity in activities where activity.isValid {
            if let existing = sessions[activity.id], existing.amount >= activity.amount {
                continue
            }
            sessions[activity.id] = activity
        }
        var result: [ProgressActivityKind: Double] = [:]
        for activity in sessions.values {
            result[activity.kind, default: 0] += activity.amount
        }
        return result
    }
}

/// Uses monotonic uptime; a clock change cannot inflate reading time.
struct ReadingActivityClock {
    static let idleLimit: TimeInterval = 300
    private var lastTick: TimeInterval?
    private var lastInteraction: TimeInterval = 0
    private(set) var elapsed: TimeInterval = 0

    mutating func resume(at now: TimeInterval) {
        guard lastTick == nil else { return }
        lastTick = now
        lastInteraction = now
    }

    mutating func advance(to now: TimeInterval) {
        guard let previous = lastTick else { return }
        elapsed += max(0, min(now, lastInteraction + Self.idleLimit) - previous)
        lastTick = now
    }

    mutating func interact(at now: TimeInterval) {
        guard lastTick != nil else { return }
        advance(to: now)
        lastInteraction = now
    }

    mutating func pause(at now: TimeInterval) {
        advance(to: now)
        lastTick = nil
    }

    mutating func drain() -> TimeInterval {
        defer { elapsed = 0 }
        return elapsed
    }
}
