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
        #expect(preferences.sound(for: .fajr) == .system)
        preferences.prayerSounds[PrayerName.fajr.rawValue] = .chime
        preferences.prayerSounds[PrayerName.maghrib.rawValue] = .silent
        preferences.timeSensitiveNotifications = false
        let saved = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        #expect(saved == preferences)
        #expect(saved.sound(for: .fajr) == .chime)
        #expect(saved.sound(for: .dhuhr) == .system)
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

    @Test func importedAudioIsTrimmedAndFailedImportPreservesRecording() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "source.wav")
        let destination = directory.appending(path: "Sounds/adhan.wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000 * 35))
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData?[0].initialize(repeating: 0.1, count: Int(buffer.frameLength))
        do {
            let file = try AVAudioFile(forWriting: source, settings: format.settings)
            try file.write(from: buffer)
            file.close()
        }
        try PrayerAlertSound.importAdhan(from: source, to: destination)
        let result = try AVAudioFile(forReading: destination)
        #expect(result.length == 8000 * 29)
        #expect(result.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int == 16)
        let original = try Data(contentsOf: destination)
        #expect(throws: (any Error).self) {
            try PrayerAlertSound.importAdhan(from: directory.appending(path: "missing.wav"), to: destination)
        }
        #expect(try Data(contentsOf: destination) == original)
        try PrayerAlertSound.importAdhan(from: source, to: destination)
        #expect(try Data(contentsOf: destination) == original)
    }
}
