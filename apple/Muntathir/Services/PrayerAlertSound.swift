import Foundation
import UserNotifications

enum PrayerAlertSound: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, chime, bell, silent
    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .system: String(localized: "System sound")
        case .chime: String(localized: "Chime")
        case .bell: String(localized: "Bell")
        case .silent: String(localized: "Silent")
        }
    }

    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .chime
    }

    var audioURL: URL? {
        switch self {
        case .chime, .bell: Bundle.main.url(forResource: rawValue, withExtension: "wav")
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
}
