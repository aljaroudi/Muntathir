import Foundation

/// Sensor-independent state. Times are monotonic seconds, never wall-clock dates.
struct PrayerCounter: Equatable, Sendable {
    let total: Int
    private(set) var sujoods = 0
    private(set) var interrupted = false
    private(set) var stopped = false
    private var wasNear: Bool?
    private var nearStart: TimeInterval?
    private var farStart: TimeInterval?
    private var pendingSujood = false
    private var armed = false

    private let minNearDuration: CGFloat = 1
    private let minFarDuration: CGFloat = 1

    init(prayer: PrayerName) {
        precondition(prayer.rakaaCount != nil)
        total = prayer.rakaaCount!
    }

    var rakaa: Int {
        min(sujoods / 2 + 1, total)
    }

    var firstSujood: Bool {
        sujoods % 2 == 1
    }

    var complete: Bool {
        sujoods == total * 2
    }

    mutating func sample(near: Bool, at time: TimeInterval) {
        guard !stopped, !interrupted, !complete else { return }
        if near != wasNear {
            wasNear = near
            if near {
                pendingSujood = false
                nearStart = armed ? time : nil
                farStart = nil
            } else {
                pendingSujood = nearStart.map { time - $0 >= minNearDuration } ?? false
                nearStart = nil
                farStart = time
                armed = false
            }
        }
        if !near, let farStart, time - farStart >= minFarDuration {
            if pendingSujood {
                sujoods += 1
                pendingSujood = false
            }
            armed = true
        }
    }

    mutating func interrupt() {
        guard !complete, !stopped else { return }
        interrupted = true
        discardCycle()
    }

    mutating func stop() {
        stopped = true
        discardCycle()
    }

    private mutating func discardCycle() {
        nearStart = nil
        farStart = nil
        pendingSujood = false
        armed = false
    }
}
