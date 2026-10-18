import Foundation

/// A complete settings snapshot, transferred by WatchConnectivity and cached on the watch.
struct WatchSettings: Codable, Equatable, Sendable {
    var version = 1
    var prayers: WidgetPrayerSettings
    var calendar: WidgetCalendarSettings

    static let storageKey = "watchSettings.v1"

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == 1,
              value.prayers.location.map({ $0.hasValidCoordinates && TimeZone(identifier: $0.timeZoneID) != nil }) ?? true,
              value.calendar.timeZoneID.map({ TimeZone(identifier: $0) != nil }) ?? true
        else { throw CocoaError(.coderReadCorrupt) }
        _ = try CalendarEngine(timeZone: value.calendar.zone, manual: value.calendar.manual, confirmed: value.calendar.confirmed)
        return value
    }

    static func read(from defaults: UserDefaults? = UserDefaults(suiteName: WidgetPrayerStore.groupID)) -> Self? {
        defaults?.data(forKey: storageKey).flatMap { try? decode($0) }
    }

    @discardableResult
    static func receive(_ data: Data, in defaults: UserDefaults? = UserDefaults(suiteName: WidgetPrayerStore.groupID)) throws -> Self {
        let value = try decode(data)
        guard let defaults else { throw CocoaError(.fileWriteUnknown) }
        defaults.set(data, forKey: storageKey)
        return value
    }
}
