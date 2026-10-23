import Foundation

struct WidgetPrayerSettings: Codable, Equatable, Sendable {
    var location: SavedLocation?
    var method: PrayerMethod
    var hiddenPrayers: Set<PrayerName>
    var imsakMinutes = 10

    init(location: SavedLocation?, method: PrayerMethod, hiddenPrayers: Set<PrayerName>, imsakMinutes: Int = 10) {
        self.location = location
        self.method = method
        self.hiddenPrayers = hiddenPrayers
        self.imsakMinutes = min(120, max(0, imsakMinutes))
    }

    private enum CodingKeys: String, CodingKey { case location, method, hiddenPrayers, imsakMinutes }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(location: c.decodeIfPresent(SavedLocation.self, forKey: .location),
                      method: c.decode(PrayerMethod.self, forKey: .method),
                      hiddenPrayers: c.decodeIfPresent(Set<PrayerName>.self, forKey: .hiddenPrayers) ?? [],
                      imsakMinutes: c.decodeIfPresent(Int.self, forKey: .imsakMinutes) ?? 10)
    }

    func prayers(on date: Date) -> [PrayerMoment] {
        guard let location else { return [] }
        return PrayerCalculator.times(on: date, location: location, method: method, imsakMinutes: imsakMinutes)
            .filter { $0.name.isVisible(hidden: hiddenPrayers) }
    }

    func upcomingPrayers(after date: Date, limit: Int = 3) -> [PrayerMoment] {
        guard let location else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = location.timeZone
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date)!
        return Array((prayers(on: date) + prayers(on: tomorrow))
            .filter { $0.name.isPrayer && $0.date > date }
            .sorted { $0.date < $1.date }.prefix(max(0, limit)))
    }

    func nextPrayer(after date: Date) -> PrayerMoment? {
        upcomingPrayers(after: date, limit: 1).first
    }

    func timelineDates(from date: Date) -> [Date] {
        guard let location else { return [date] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = location.timeZone
        var dates: Set<Date> = [date]
        // Plain text countdowns remain renderable in WidgetKit's archived views.
        let nextMinute = floor(date.timeIntervalSince1970 / 60) * 60 + 60
        for minute in 0 ..< 360 {
            dates.insert(Date(timeIntervalSince1970: nextMinute + Double(minute) * 60))
        }
        for offset in -1 ..< 3 {
            let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date))!
            if day > date {
                dates.insert(day)
            }
            for prayer in prayers(on: day) where prayer.date > date {
                dates.insert(prayer.date)
            }
        }
        return dates.sorted()
    }
}

enum WidgetPrayerStore {
    static let groupID = "group.com.aljaroudi.Muntathir"
    static let key = "widgetPrayerSettings.v1"
    static func read(from defaults: UserDefaults? = UserDefaults(suiteName: groupID)) -> WidgetPrayerSettings? {
        defaults?.data(forKey: key).flatMap { try? JSONDecoder().decode(WidgetPrayerSettings.self, from: $0) }
    }

    @discardableResult static func write(_ settings: WidgetPrayerSettings, to defaults: UserDefaults? = UserDefaults(suiteName: groupID)) -> Bool {
        guard let defaults, let data = try? JSONEncoder().encode(settings),
              read(from: defaults) != settings else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}

/// Discrete boundaries let WidgetKit update the minute label without a running timer.
struct PrayerCountdownFormat: DiscreteFormatStyle {
    let target: Date
    var locale = Locale.current

    func format(_ date: Date) -> AttributedString {
        let minutes = max(0, ceil(target.timeIntervalSince(date) / 60))
        let value = Duration.seconds(minutes * 60)
        return AttributedString(
            value.formatted(
                .units(
                    allowed: [.hours, .minutes],
                    width: .wide,
                    maximumUnitCount: 1
                ).locale(locale)
            )
        )
    }

    func discreteInput(after date: Date) -> Date? {
        let minutes = ceil(target.timeIntervalSince(date) / 60)
        guard minutes > 0 else { return nil }
        return target.addingTimeInterval(-(minutes - 1) * 60)
    }

    func discreteInput(before date: Date) -> Date? {
        let minutes = max(0, ceil(target.timeIntervalSince(date) / 60))
        return target.addingTimeInterval(-minutes * 60 - 0.001)
    }
}

struct WidgetCalendarSettings: Codable, Equatable, Sendable {
    var timeZoneID: String?
    var showFeelsLikeTemperature: Bool?
    var manual: [MonthCorrection] = []
    var confirmed: [MonthCorrection] = []
    var zone: TimeZone {
        timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    var engine: CalendarEngine {
        (try? CalendarEngine(timeZone: zone, manual: manual, confirmed: confirmed))
            ?? (try! CalendarEngine(timeZone: zone))
    }

    func timelineDates(from date: Date) -> [Date] {
        let calendar = engine.gregorian
        let midnight = calendar.startOfDay(for: date)
        return [date] + (1 ... 7).compactMap { calendar.date(byAdding: .day, value: $0, to: midnight) }
    }

    static let key = "widgetCalendarSettings.v1"
    static func read(from defaults: UserDefaults? = UserDefaults(suiteName: WidgetPrayerStore.groupID)) -> Self {
        defaults?.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }

    @discardableResult func write(to defaults: UserDefaults? = UserDefaults(suiteName: WidgetPrayerStore.groupID)) -> Bool {
        guard let defaults, let data = try? JSONEncoder().encode(self),
              defaults.data(forKey: Self.key) == nil || Self.read(from: defaults) != self else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }
}
