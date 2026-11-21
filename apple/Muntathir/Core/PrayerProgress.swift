import Foundation

struct PrayerCompletion: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let prayer: PrayerName
    let startedAt: Date
    var completedAt: Date
    let prayerDay: String
    let timeZoneID: String
    let location: SavedLocation?
    let method: PrayerMethod
    let athan: Date?
    let deadline: Date?
    let timing: PrayerTiming
}

enum PrayerTiming: String, Codable, CaseIterable, Sendable {
    case onTime, outsideTime, unavailable

    var title: String {
        switch self {
        case .onTime: String(localized: "On time")
        case .outsideTime: String(localized: "Recorded outside time")
        case .unavailable: String(localized: "Timing unavailable")
        }
    }

    var symbol: String {
        switch self {
        case .onTime: "checkmark.circle.fill"
        case .outsideTime: "circle"
        case .unavailable: "questionmark.circle"
        }
    }

    var priority: Int {
        switch self {
        case .onTime: 2
        case .outsideTime: 1
        case .unavailable: 0
        }
    }
}

enum PrayerProgress {
    static let prayers: [PrayerName] = [.fajr, .dhuhr, .asr, .maghrib, .isha]

    static func rakaat(for prayer: PrayerName) -> Int {
        switch prayer {
        case .fajr: 2
        case .maghrib: 3
        default: 4
        }
    }

    /// The prayer commonly combined right after `prayer`, offered without recalibrating.
    static func followUp(after prayer: PrayerName) -> PrayerName? {
        switch prayer {
        case .dhuhr: .asr
        case .maghrib: .isha
        default: nil
        }
    }

    /// The first prayer that is on time now and not yet recorded for its prayer day; otherwise the next one to begin.
    static func suggestedPrayer(at date: Date, location: SavedLocation?, method: PrayerMethod, completed: [PrayerCompletion],
                                calculate: (Date, SavedLocation, PrayerMethod) -> [PrayerMoment] = { PrayerCalculator.times(on: $0, location: $1, method: $2) }) -> PrayerName?
    {
        guard let location, location.isValid else { return nil }
        var upcoming: PrayerName?
        for prayer in prayers {
            let record = snapshot(prayer: prayer, at: date, location: location, method: method, calculate: calculate)
            guard days(for: prayer, in: completed)[record.prayerDay] == nil else { continue }
            if record.timing == .onTime {
                return prayer
            }
            if upcoming == nil, let athan = record.athan, athan > date {
                upcoming = prayer
            }
        }
        // Once the evening prayers' day has ended, Fajr is the next prayer to begin.
        return upcoming ?? .fajr
    }

    static func dayKey(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func snapshot(prayer: PrayerName, at date: Date, location: SavedLocation?, method: PrayerMethod,
                         fallbackTimeZone: TimeZone = .current,
                         calculate: (Date, SavedLocation, PrayerMethod) -> [PrayerMoment] = { PrayerCalculator.times(on: $0, location: $1, method: $2) }) -> PrayerCompletion
    {
        let zone = location?.timeZone ?? fallbackTimeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var day = date
        var moments: [PrayerMoment] = []
        if let location, location.isValid {
            moments = calculate(day, location, method)
            if [.maghrib, .isha].contains(prayer), let fajr = moments.first(where: { $0.name == .fajr })?.date, date < fajr {
                day = calendar.date(byAdding: .day, value: -1, to: day)!
                moments = calculate(day, location, method)
            }
        }
        let end: PrayerName = prayer == .fajr ? .sunrise : ([.dhuhr, .asr].contains(prayer) ? .sunset : .midnight)
        let start: PrayerName = switch prayer {
        case .asr: .dhuhr
        case .isha: .maghrib
        default: prayer
        }
        let athan = moments.first { $0.name == start }?.date
        let deadline = moments.first { $0.name == end }?.date
        let timing: PrayerTiming = if prayer.isPrayer, let athan, let deadline, deadline > athan {
            date >= athan && date < deadline ? .onTime : .outsideTime
        } else {
            .unavailable
        }
        return PrayerCompletion(id: UUID(), prayer: prayer, startedAt: date, completedAt: date,
                                prayerDay: dayKey(day, timeZone: zone), timeZoneID: zone.identifier,
                                location: location, method: method, athan: athan, deadline: deadline, timing: timing)
    }

    static func days(for prayer: PrayerName, in records: [PrayerCompletion]) -> [String: PrayerTiming] {
        var seen: Set<UUID> = []
        var days: [String: PrayerTiming] = [:]
        for record in records.sorted(by: { $0.completedAt < $1.completedAt }) where record.prayer == prayer {
            guard seen.insert(record.id).inserted else { continue }
            if let existing = days[record.prayerDay], existing.priority >= record.timing.priority {
                continue
            }
            days[record.prayerDay] = record.timing
        }
        return days
    }
}

struct PrayerSessionRecording {
    private(set) var snapshot: PrayerCompletion?
    private var finished = false

    mutating func update(calibrated: Bool, complete: Bool, failed: Bool, at date: Date,
                         makeSnapshot: () -> PrayerCompletion?) -> PrayerCompletion?
    {
        guard !finished else { return nil }
        guard !failed else { finished = true; return nil }
        if calibrated, snapshot == nil {
            snapshot = makeSnapshot()
        }
        guard complete else { return nil }
        finished = true
        guard var record = snapshot else { return nil }
        record.completedAt = date
        return record
    }
}
