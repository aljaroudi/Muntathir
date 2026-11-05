import AudioToolbox
import AVFoundation
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
        return (0 ..< 10).flatMap { offset -> [ScheduledPrayer] in
            let day = calendar.date(byAdding: .day, value: offset, to: now)!
            return PrayerCalculator.times(on: day, location: location, method: preferences.prayerMethod, imsakMinutes: preferences.imsakMinutes).compactMap { prayer in
                guard preferences.enabledPrayers.contains(prayer.name), prayer.date > now else { return nil }
                return ScheduledPrayer(id: "prayer.\(Int(prayer.date.timeIntervalSince1970)).\(prayer.name.rawValue)", name: prayer.name, date: prayer.date)
            }
        }.sorted { $0.date < $1.date }
    }
}

@MainActor final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var generation = UUID()
    private var previewPlayer: AVAudioPlayer?
    private let addRequest: (UNNotificationRequest) async throws -> Void
    init(addRequest: @escaping (UNNotificationRequest) async throws -> Void = { try await UNUserNotificationCenter.current().add($0) }) {
        self.addRequest = addRequest
        super.init()
        center.delegate = self
    }

    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
    }

    func preview(sound: PrayerAlertSound) async throws {
        stopPreview()
        switch sound {
        case .silent:
            return
        case .system:
            await Self.playSystemSound()
        default:
            guard let url = sound.audioURL else { throw CocoaError(.fileNoSuchFile) }
            previewPlayer = try await Self.playAudio(at: url)
        }
    }

    private nonisolated static func playSystemSound() async {
        AudioServicesPlaySystemSound(1007)
    }

    private nonisolated static func playAudio(at url: URL) async throws -> AVAudioPlayer {
        let player = try AVAudioPlayer(contentsOf: url)
        guard player.play() else { throw CocoaError(.fileReadUnknown) }
        return player
    }

    func authorize() async -> Bool {
        await (try? center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func rebuild(preferences: Preferences, location: SavedLocation?, engine: CalendarEngine? = nil, events: [IslamicEvent] = []) async {
        let token = UUID(); generation = token
        let pending = await center.pendingNotificationRequests()
        guard generation == token, !Task.isCancelled else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("prayer.") || $0.identifier.hasPrefix("event.") }.map(\.identifier))
        guard let location else { return }
        let settings = await center.notificationSettings()
        guard generation == token, !Task.isCancelled, settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let now = Date()
        let prayers = NotificationPlan.make(now: now, preferences: preferences, location: location)
            .map { ScheduledAlert(id: $0.id, date: $0.date, prayer: $0.name, events: []) }
        let reminders = engine.map { NotificationPlan.events(now: now, preferences: preferences, location: location, engine: $0, events: events) } ?? []
        for prayer in NotificationPlan.nearest(prayers + reminders) {
            guard generation == token, !Task.isCancelled else { return }
            let content = prayer.prayer.map { Self.content(for: $0, preferences: preferences) } ?? Self.eventContent(prayer.events)
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: prayer.date); parts.timeZone = .gmt
            let request = UNNotificationRequest(identifier: prayer.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await addRequest(request)
            if generation != token || Task.isCancelled {
                center.removePendingNotificationRequests(withIdentifiers: [prayer.id]); return
            }
        }
    }

    static func content(for prayer: PrayerName, preferences: Preferences) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = prayer.isPrayer ? String(localized: "Time for prayer") : prayer.title
        content.body = prayer.notificationBody
        content.sound = preferences.sound(for: prayer).notificationSound
        content.interruptionLevel = preferences.timeSensitiveNotifications ? .timeSensitive : .active
        content.threadIdentifier = "prayer.\(prayer.rawValue)"
        return content
    }

    static func eventContent(_ events: [IslamicEvent]) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "This evening")
        content.body = events.map { $0.title(locale: .current) }.joined(separator: " · ")
        content.sound = nil
        content.interruptionLevel = .active
        content.threadIdentifier = "calendar.events"
        return content
    }

    func announce(_ rows: [Announcement], enabled: Bool, sound: PrayerAlertSound, defaults: UserDefaults = .standard) async {
        guard enabled else { return }
        var delivered = Set(defaults.stringArray(forKey: "announcements.delivered") ?? [])
        for row in rows {
            let key = "\(row.id).\(row.revision)"
            guard !delivered.contains(key) else { continue }
            let content = UNMutableNotificationContent(); content.title = String(localized: "Month confirmed")
            content.body = row.sourceID; content.sound = sound.notificationSound
            do {
                try await addRequest(UNNotificationRequest(identifier: "announcement.\(key)", content: content, trigger: nil))
                delivered.insert(key)
            } catch { continue }
        }
        defaults.set(Array(delivered), forKey: "announcements.delivered")
    }
}

extension PrayerName {
    var notificationBody: String {
        switch self {
        case .fajr: String(localized: "Fajr prayer")
        case .dhuhr: String(localized: "Dhuhr prayer")
        case .asr: String(localized: "Asr prayer")
        case .maghrib: String(localized: "Maghrib prayer")
        case .isha: String(localized: "Isha prayer")
        default: title
        }
    }
}

struct ScheduledAlert: Sendable {
    let id: String
    let date: Date
    let prayer: PrayerName?
    let events: [IslamicEvent]
}

extension NotificationPlan {
    static func nearest(_ alerts: [ScheduledAlert]) -> [ScheduledAlert] {
        Array(alerts.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }.prefix(50))
    }

    static func events(now: Date, preferences: Preferences, location: SavedLocation,
                       engine: CalendarEngine, events: [IslamicEvent]) -> [ScheduledAlert]
    {
        guard preferences.calendarEventNotifications else { return [] }
        let settings = WidgetPrayerSettings(location: location, method: preferences.prayerMethod,
                                            hiddenPrayers: [], imsakMinutes: preferences.imsakMinutes)
        return (0 ..< 10).compactMap { offset in
            let day = engine.addingDays(offset, to: now)
            guard let sunset = settings.sunset(on: day), sunset > now else { return nil }
            let tomorrow = engine.resolve(engine.addingDays(1, to: day))
            let matching = events.filter { $0.month == tomorrow.month.month && $0.day == tomorrow.day }.sorted { $0.id < $1.id }
            guard !matching.isEmpty else { return nil }
            return ScheduledAlert(id: "event.\(Int(sunset.timeIntervalSince1970))", date: sunset, prayer: nil, events: matching)
        }
    }
}
