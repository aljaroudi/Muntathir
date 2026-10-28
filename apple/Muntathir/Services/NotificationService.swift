import AVFoundation
import AudioToolbox
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
    override init() {
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

    func preview(sound: PrayerAlertSound) throws {
        stopPreview()
        switch sound {
        case .silent:
            return
        case .system:
            AudioServicesPlaySystemSound(1007)
        default:
            guard let url = sound.audioURL else { throw CocoaError(.fileNoSuchFile) }
            let player = try AVAudioPlayer(contentsOf: url)
            guard player.play() else { throw CocoaError(.fileReadUnknown) }
            previewPlayer = player
        }
    }

    func authorize() async -> Bool {
        await (try? center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

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
            let content = Self.content(for: prayer.name, preferences: preferences)
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: prayer.date); parts.timeZone = .gmt
            let request = UNNotificationRequest(identifier: prayer.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
            if generation != token || Task.isCancelled {
                center.removePendingNotificationRequests(withIdentifiers: [prayer.id]); return
            }
        }
    }

    static func content(for prayer: PrayerName, preferences: Preferences) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = prayer.isPrayer ? String(localized: "Time for prayer") : prayer.title
        content.body = prayer.notificationBody
        content.sound = preferences.notificationSound.notificationSound
        content.interruptionLevel = preferences.timeSensitiveNotifications ? .timeSensitive : .active
        content.threadIdentifier = "prayer.\(prayer.rawValue)"
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
                try await center.add(UNNotificationRequest(identifier: "announcement.\(key)", content: content, trigger: nil))
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
