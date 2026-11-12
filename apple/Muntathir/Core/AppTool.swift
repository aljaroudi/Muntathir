import Foundation

enum AppTool: String, Codable, CaseIterable, Identifiable, Sendable {
    case calendar, events, quran, hadith, supplications, figures, tasbih, rakaat, qibla

    var id: String {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .calendar: "Calendar"
        case .events: "Events"
        case .quran: "The Holy Quran"
        case .hadith: "Hadith"
        case .supplications: "Supplications"
        case .figures: "Figures"
        case .tasbih: "Tasbih"
        case .rakaat: "Rakaat Tracker"
        case .qibla: "Qibla"
        }
    }

    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .events: "list.bullet.rectangle"
        case .quran: "book.closed"
        case .hadith: "text.book.closed"
        case .supplications: "hands.sparkles"
        case .figures: "person.2"
        case .tasbih: "circle.dotted"
        case .rakaat: "camera.metering.center.weighted"
        case .qibla: "location.north.circle"
        }
    }

    var accessibilityID: String {
        switch self {
        case .quran: "holy-quran"
        case .rakaat: "rakaat-tracker"
        default: rawValue
        }
    }

    static let maximumShortcuts = 3
    static let groups: [[AppTool]] = [
        [.quran, .hadith, .supplications], [.calendar, .events, .figures], [.tasbih, .rakaat, .qibla],
    ]

    static func normalized(_ identifiers: [String]) -> [AppTool] {
        var seen: Set<AppTool> = []
        return Array(identifiers.compactMap { identifier in
            guard let tool = AppTool(rawValue: identifier), seen.insert(tool).inserted else { return nil }
            return tool
        }.prefix(maximumShortcuts))
    }
}
