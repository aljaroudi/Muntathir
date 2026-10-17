import Foundation
import UserNotifications

struct ScheduledPrayer: Identifiable, Sendable {
    let id: String
    let name: PrayerName
    let date: Date
}
enum NotificationPlan {
    static func make(now: Date, preferences: Preferences, location: SavedLocation) -> [ScheduledPrayer] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = location.timeZone
        return (0..<10).flatMap { offset -> [ScheduledPrayer] in
            let day = calendar.date(byAdding: .day, value: offset, to: now)!
            return PrayerCalculator.times(on: day, location: location, method: preferences.prayerMethod, asrRule: preferences.asrRule).compactMap { prayer in
                guard preferences.enabledPrayers.contains(prayer.name), prayer.date > now else { return nil }
                return ScheduledPrayer(id: "prayer.\(Int(prayer.date.timeIntervalSince1970)).\(prayer.name.rawValue)", name: prayer.name, date: prayer.date)
            }
        }.sorted { $0.date < $1.date }
    }
}
@MainActor final class NotificationService {
    private let center = UNUserNotificationCenter.current()
    private var generation = UUID()
    func authorize() async -> Bool { (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false }
    func rebuild(preferences: Preferences, location: SavedLocation?) async {
        let token = UUID(); generation = token
        let pending = await center.pendingNotificationRequests()
        guard generation == token, !Task.isCancelled else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("prayer.") }.map(\.identifier))
        guard let location else { return }
        let settings = await center.notificationSettings()
        guard generation == token, !Task.isCancelled, settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        for prayer in NotificationPlan.make(now: Date(), preferences: preferences, location: location).prefix(50) {
            guard generation == token, !Task.isCancelled else { return }
            let content = UNMutableNotificationContent(); content.title = prayer.name.title
            content.body = location.name; content.sound = .default
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: prayer.date); parts.timeZone = .gmt
            let request = UNNotificationRequest(identifier: prayer.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
            if generation != token || Task.isCancelled { center.removePendingNotificationRequests(withIdentifiers: [prayer.id]); return }
        }
    }
    func announce(_ rows: [Announcement], enabled: Bool, defaults: UserDefaults = .standard) async {
        guard enabled else { return }
        var delivered = Set(defaults.stringArray(forKey: "announcements.delivered") ?? [])
        for row in rows {
            let key = "\(row.id).\(row.revision)"
            guard !delivered.contains(key) else { continue }
            let content = UNMutableNotificationContent(); content.title = String(localized: "Month confirmed")
            content.body = row.sourceID; content.sound = .default
            do {
                try await center.add(UNNotificationRequest(identifier: "announcement.\(key)", content: content, trigger: nil))
                delivered.insert(key)
            } catch { continue }
        }
        defaults.set(Array(delivered), forKey: "announcements.delivered")
    }
}
