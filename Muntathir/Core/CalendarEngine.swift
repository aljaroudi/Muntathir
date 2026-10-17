import Foundation

struct CivilDate: Codable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
    init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }
    init(_ date: Date, in zone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year!; month = parts.month!; day = parts.day!
    }
    func date(in zone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              CivilDate(date, in: zone) == self else { return nil }
        return date
    }
}

struct HijriMonth: Codable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    var index: Int { year * 12 + month - 1 }
    var isValid: Bool { (1300...1600).contains(year) && (1...12).contains(month) }
    func advanced(_ count: Int) -> Self {
        let value = index + count
        return Self(year: value / 12, month: value % 12 + 1)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.index < rhs.index }
}

enum DateProvenance: String, Codable, Sendable { case calculated, confirmed, manual }
struct MonthCorrection: Codable, Hashable, Sendable {
    let month: HijriMonth
    let start: CivilDate
    let provenance: DateProvenance
    let sourceID: String?
}
struct ResolvedDay: Sendable {
    let month: HijriMonth
    let day: Int
    let provenance: DateProvenance
    let sourceID: String?
}
enum CalendarError: Error, LocalizedError {
    case invalidDate, conflictingMonths
    var errorDescription: String? {
        switch self {
        case .invalidDate: String(localized: "Invalid calendar date.")
        case .conflictingMonths: String(localized: "Month starts must preserve 29 or 30 day months.")
        }
    }
}

struct CalendarEngine: Sendable {
    let timeZone: TimeZone
    private(set) var corrections: [HijriMonth: MonthCorrection] = [:]
    var gregorian: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = timeZone; return c }
    var baseline: Calendar { var c = Calendar(identifier: .islamicUmmAlQura); c.timeZone = timeZone; return c }

    init(timeZone: TimeZone, manual: [MonthCorrection] = [], confirmed: [MonthCorrection] = []) throws {
        self.timeZone = timeZone
        for rows in [confirmed, manual] {
            var seen = Set<HijriMonth>()
            for row in rows {
                guard row.month.isValid, row.start.date(in: timeZone) != nil,
                      row.provenance != .calculated, seen.insert(row.month).inserted else { throw CalendarError.invalidDate }
                corrections[row.month] = row
            }
        }
        let anchors = corrections.keys.sorted()
        for (left, right) in zip(anchors, anchors.dropFirst()) {
            let days = distance(corrections[left]!.start.date(in: timeZone)!, corrections[right]!.start.date(in: timeZone)!)
            let months = right.index - left.index
            guard (29 * months ... 30 * months).contains(days) else { throw CalendarError.conflictingMonths }
        }
        // Limit corrections to nearby baseline starts, preventing mislabeled years or unbounded searches.
        for row in corrections.values {
            guard abs(distance(baselineStart(row.month), row.start.date(in: timeZone)!)) <= 7 else { throw CalendarError.invalidDate }
        }
    }
    func distance(_ from: Date, _ to: Date) -> Int { gregorian.dateComponents([.day], from: from, to: to).day! }
    func addingDays(_ days: Int, to date: Date) -> Date { gregorian.date(byAdding: .day, value: days, to: date)! }
    func baselineStart(_ month: HijriMonth) -> Date {
        baseline.date(from: DateComponents(year: month.year, month: month.month, day: 1))!
    }
    func baselineLength(_ month: HijriMonth) -> Int {
        distance(baselineStart(month), baselineStart(month.advanced(1)))
    }
    func start(of month: HijriMonth) -> Date {
        if let exact = corrections[month] { return exact.start.date(in: timeZone)! }
        guard let previous = corrections.keys.filter({ $0 < month }).max() else {
            guard let next = corrections.keys.filter({ $0 > month }).min() else { return baselineStart(month) }
            var cursor = next
            var end = corrections[next]!.start.date(in: timeZone)!
            while cursor > month {
                cursor = cursor.advanced(-1)
                let candidate = baselineStart(cursor)
                end = (29...30).contains(distance(candidate, end)) ? candidate : addingDays(-baselineLength(cursor), to: end)
            }
            return end
        }
        var cursor = previous
        var date = corrections[previous]!.start.date(in: timeZone)!
        let next = corrections.keys.filter { $0 > previous }.min()
        while cursor < month {
            var length = baselineLength(cursor)
            if let next, cursor < next {
                let remaining = next.index - cursor.index - 1
                let days = distance(date, corrections[next]!.start.date(in: timeZone)!)
                length = min(max(length, days - 30 * remaining), days - 29 * remaining)
            } else {
                let candidate = baselineStart(cursor.advanced(1))
                if (29...30).contains(distance(date, candidate)) { length = distance(date, candidate) }
            }
            date = addingDays(length, to: date)
            cursor = cursor.advanced(1)
        }
        return date
    }
    func resolve(_ date: Date) -> ResolvedDay {
        let parts = baseline.dateComponents([.year, .month], from: date)
        var month = HijriMonth(year: parts.year!, month: parts.month!)
        while date < start(of: month) { month = month.advanced(-1) }
        while date >= start(of: month.advanced(1)) { month = month.advanced(1) }
        return ResolvedDay(month: month, day: distance(start(of: month), gregorian.startOfDay(for: date)) + 1,
                           provenance: corrections[month]?.provenance ?? .calculated, sourceID: corrections[month]?.sourceID)
    }
    func days(in month: HijriMonth) -> [Date] {
        let start = start(of: month)
        return (0..<distance(start, self.start(of: month.advanced(1)))).map { addingDays($0, to: start) }
    }
}

extension Date.FormatStyle {
    func inZone(_ zone: TimeZone) -> Self { var style = self; style.timeZone = zone; style.calendar = Calendar(identifier: .gregorian); return style }
}
