import AVFoundation
import Foundation
@testable import Muntathir
import Testing
import UserNotifications

struct PrayerAlertSoundTests {
    @Test func roundTripsSharedNotificationSound() throws {
        var preferences = try JSONDecoder().decode(Preferences.self, from: Data(#"{"enabledPrayers":["fajr"]}"#.utf8))
        #expect(preferences.enabledPrayers == [.fajr])
        #expect(preferences.timeSensitiveNotifications)
        #expect(preferences.notificationSound == .chime)
        preferences.notificationSound = .bell
        preferences.timeSensitiveNotifications = false
        let saved = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        #expect(saved == preferences)
        #expect(saved.notificationSound == .bell)
    }

    @MainActor @Test func prayerContentUsesSelectedSoundAndInterruptionLevel() {
        var preferences = Preferences()
        preferences.notificationSound = .silent
        let silent = NotificationService.content(for: .fajr, preferences: preferences)
        #expect(silent.sound == nil)
        #expect(silent.interruptionLevel == .timeSensitive)
        #expect(silent.body == PrayerName.fajr.notificationBody)
        preferences.timeSensitiveNotifications = false
        let normal = NotificationService.content(for: .dhuhr, preferences: preferences)
        #expect(normal.sound == nil)
        preferences.notificationSound = .bell
        for prayer in PrayerName.allCases {
            #expect(NotificationService.content(for: prayer, preferences: preferences).sound == (prayer.isPrayer ? PrayerAlertSound.bell : .system).notificationSound)
        }
        #expect(normal.interruptionLevel == .active)
        #expect(normal.threadIdentifier != silent.threadIdentifier)
    }

    @MainActor @Test func previewDoesNotScheduleNotification() async throws {
        var scheduled: [UNNotificationRequest] = []
        let service = NotificationService { scheduled.append($0) }
        defer { service.stopPreview() }
        try await service.preview(sound: .bell)
        try await service.preview(sound: .silent)
        #expect(scheduled.isEmpty)
    }

    @Test func bundledSoundsAreNotificationCompatible() throws {
        for sound in PrayerAlertSound.allCases where sound.audioURL != nil {
            let file = try AVAudioFile(forReading: #require(sound.audioURL))
            #expect(file.length > 0)
            #expect(Double(file.length) / file.fileFormat.sampleRate < 30)
            #expect(file.fileFormat.settings[AVFormatIDKey] as? UInt32 == kAudioFormatLinearPCM)
        }
    }
}

extension PrayerAlertSoundTests {
    @Test func legacyAdhanStaysOnPrayersOnly() throws {
        var prefs = Preferences()
        prefs.notificationSound = .bell
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(prefs)) as? [String: Any])
        json.removeValue(forKey: "sunsetSound")
        json.removeValue(forKey: "otherTimesSound")
        json.removeValue(forKey: "calendarEventNotifications")
        let migrated = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(migrated.notificationSound == .bell)
        #expect(migrated.sunsetSound == .system)
        #expect(migrated.otherTimesSound == .system)
        #expect(!migrated.calendarEventNotifications)
    }

    @MainActor @Test func calendarEventsAreAlwaysSilentAndNotTimeSensitive() {
        let content = NotificationService.eventContent([.init(id: "test", month: 1, day: 1, title: ["en": "Event"])])
        #expect(content.sound == nil)
        #expect(content.interruptionLevel == .active)
        #expect(content.body == "Event")
    }
}
