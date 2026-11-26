import Foundation

enum AppTool: String, Codable, CaseIterable, Identifiable, Sendable {
    case calendar, events, quran, hadith, supplications, sermons, dictionary, rulings, figures, tasbih, rakaat, prayerProgress, qibla

    var id: String {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .calendar: "Calendar"
        case .events: "Events"
        case .quran: "Holy Quran"
        case .hadith: "Hadith"
        case .rulings: "Rulings"
        case .supplications: "Supplications"
        case .dictionary: "Arabic Dictionary"
        case .sermons: "Sermons"
        case .figures: "Figures"
        case .tasbih: "Tasbih"
        case .rakaat: "Rakaat Tracker"
        case .prayerProgress: "Activity"
        case .qibla: "Qibla"
        }
    }

    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .events: "list.bullet.rectangle"
        case .quran: "book.closed"
        case .hadith: "text.book.closed"
        case .rulings: "text.page"
        case .supplications: "hands.sparkles"
        case .dictionary: "character.book.closed"
        case .sermons: "text.quote"
        case .figures: "person.2"
        case .tasbih: "circle.dotted"
        case .rakaat: "camera.metering.center.weighted"
        case .prayerProgress: "chart.bar.fill"
        case .qibla: "location.north.circle"
        }
    }

    var accessibilityID: String {
        switch self {
        case .quran: "holy-quran"
        case .rakaat: "rakaat-tracker"
        case .prayerProgress: "prayer-progress"
        default: rawValue
        }
    }

    var customizationID: String {
        "tool.\(rawValue)"
    }

    /// Qibla and Rakaat rely on a compass and front camera that Macs don't have.
    var isAvailable: Bool {
        #if os(macOS)
            self != .qibla && self != .rakaat
        #else
            true
        #endif
    }

    /// Tools that show their list beside the open item when the tab sidebar is available.
    var isSplitCapable: Bool {
        switch self {
        case .quran, .supplications, .sermons, .figures, .rulings: true
        default: false
        }
    }

    static var available: [AppTool] {
        allCases.filter(\.isAvailable)
    }

    struct ToolGroup: Identifiable, Sendable {
        let id: String
        let title: LocalizedStringResource
        let tools: [AppTool]
    }

    static let maximumShortcuts = 3
    static let groups: [ToolGroup] = [
        ToolGroup(id: "library", title: "Library", tools: [.quran, .hadith, .supplications, .sermons, .dictionary]),
        ToolGroup(id: "rulings", title: "Rulings", tools: [.rulings]),
        ToolGroup(id: "calendar", title: "Calendar", tools: [.calendar, .events, .figures]),
        ToolGroup(id: "practice", title: "Practice", tools: [.qibla, .rakaat, .tasbih, .prayerProgress]),
    ].map { ToolGroup(id: $0.id, title: $0.title, tools: $0.tools.filter(\.isAvailable)) }

    static func normalized(_ identifiers: [String]) -> [AppTool] {
        var seen: Set<AppTool> = []
        return Array(identifiers.compactMap { identifier in
            guard let tool = AppTool(rawValue: identifier), tool.isAvailable, seen.insert(tool).inserted else { return nil }
            return tool
        }.prefix(maximumShortcuts))
    }
}
