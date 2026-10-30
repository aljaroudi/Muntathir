import Foundation
import UserNotifications

enum PrayerAlertSound: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, chime, bell, alhalwachi, aliMulla, alsarraf, silent
    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .system: String(localized: "System sound")
        case .chime: String(localized: "Chime")
        case .bell: String(localized: "Bell")
        case .alhalwachi: String(localized: "Alhalwachi")
        case .aliMulla: String(localized: "Ali Mulla")
        case .alsarraf: String(localized: "Al-Sarraf")
        case .silent: String(localized: "Silent")
        }
    }

    var audioURL: URL? {
        switch self {
        case .system: nil
        default: Bundle.main.url(forResource: rawValue, withExtension: "wav")
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
