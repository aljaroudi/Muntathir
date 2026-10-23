import AVFoundation
import Foundation
import UserNotifications

enum PrayerAlertSound: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, chime, bell, adhan, silent
    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .system: String(localized: "System sound")
        case .chime: String(localized: "Chime")
        case .bell: String(localized: "Bell")
        case .adhan: String(localized: "My adhan")
        case .silent: String(localized: "Silent")
        }
    }

    static var adhanURL: URL {
        URL.libraryDirectory.appending(path: "Sounds/adhan.wav")
    }

    var audioURL: URL? {
        switch self {
        case .chime, .bell: Bundle.main.url(forResource: rawValue, withExtension: "wav")
        case .adhan: FileManager.default.fileExists(atPath: Self.adhanURL.path) ? Self.adhanURL : nil
        default: nil
        }
    }

    var notificationSound: UNNotificationSound? {
        switch self {
        case .silent: nil
        case .system: .default
        default: audioURL.map { UNNotificationSound(named: .init($0.lastPathComponent)) } ?? .default
        }
    }

    /// Convert user audio to notification-compatible PCM. Keep the old recording if conversion fails.
    static func importAdhan(from source: URL, to destination: URL = adhanURL) throws {
        let access = source.startAccessingSecurityScopedResource()
        defer {
            if access {
                source.stopAccessingSecurityScopedResource()
            }
        }
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let count = AVAudioFrameCount(min(input.length, AVAudioFramePosition(format.sampleRate * 29)))
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: min(count, 8192)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appending(path: "\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            let output = try AVAudioFile(forWriting: temporary, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            ], commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            var remaining = count
            while remaining > 0 {
                try input.read(into: buffer, frameCount: min(remaining, buffer.frameCapacity))
                guard buffer.frameLength > 0 else { break }
                try output.write(from: buffer)
                remaining -= buffer.frameLength
            }
            output.close()
            guard remaining < count else { throw CocoaError(.fileReadCorruptFile) }
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }
}
