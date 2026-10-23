import AVFoundation
import Foundation
@testable import Muntathir
import Testing
import UserNotifications

struct PrayerAlertSoundTests {
    @Test func preservesExistingPrayerChoicesAndRoundTripsSounds() throws {
        var preferences = try JSONDecoder().decode(Preferences.self, from: Data(#"{"enabledPrayers":["fajr"]}"#.utf8))
        #expect(preferences.enabledPrayers == [.fajr])
        #expect(preferences.timeSensitiveNotifications)
        #expect(preferences.sound(for: .fajr) == .chime)
        preferences.prayerSounds[PrayerName.fajr.rawValue] = .chime
        preferences.prayerSounds[PrayerName.maghrib.rawValue] = .silent
        preferences.timeSensitiveNotifications = false
        let saved = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        #expect(saved == preferences)
        #expect(saved.sound(for: .fajr) == .chime)
        #expect(saved.sound(for: .dhuhr) == .chime)
    }

    @MainActor @Test func prayerContentUsesSelectedSoundAndInterruptionLevel() {
        var preferences = Preferences()
        preferences.prayerSounds[PrayerName.fajr.rawValue] = .silent
        let silent = NotificationService.content(for: .fajr, preferences: preferences)
        #expect(silent.sound == nil)
        #expect(silent.interruptionLevel == .timeSensitive)
        #expect(silent.body == PrayerName.fajr.notificationBody)
        preferences.timeSensitiveNotifications = false
        let normal = NotificationService.content(for: .dhuhr, preferences: preferences)
        #expect(normal.sound != nil)
        #expect(normal.interruptionLevel == .active)
        #expect(normal.threadIdentifier != silent.threadIdentifier)
    }

    @Test func bundledSoundsAreNotificationCompatible() throws {
        for sound in [PrayerAlertSound.chime, .bell] {
            let file = try AVAudioFile(forReading: #require(sound.audioURL))
            #expect(file.length > 0)
            #expect(Double(file.length) / file.fileFormat.sampleRate < 30)
            #expect(file.fileFormat.settings[AVFormatIDKey] as? UInt32 == kAudioFormatLinearPCM)
        }
    }

    @Test func removedRecordingChoiceFallsBackWithoutLosingPreferences() throws {
        let data = Data(#"{"enabledPrayers":["fajr"],"prayerSounds":{"fajr":"adhan","dhuhr":"system"}}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(preferences.enabledPrayers == [.fajr])
        #expect(preferences.sound(for: .fajr) == .chime)
        #expect(preferences.sound(for: .dhuhr) == .system)
    }
}
