import AppIntents

// Raw values are saved in people's shortcuts; never rename or remove a case.

extension AppTool: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tool"

    static let caseDisplayRepresentations: [AppTool: DisplayRepresentation] = [
        .calendar: DisplayRepresentation(title: "Calendar", image: .init(systemName: "calendar")),
        .events: DisplayRepresentation(title: "Events", image: .init(systemName: "list.bullet.rectangle")),
        .quran: DisplayRepresentation(title: "Holy Quran", image: .init(systemName: "book.closed")),
        .hadith: DisplayRepresentation(title: "Hadith", image: .init(systemName: "text.book.closed")),
        .supplications: DisplayRepresentation(title: "Supplications", image: .init(systemName: "hands.sparkles")),
        .sermons: DisplayRepresentation(title: "Sermons", image: .init(systemName: "text.quote")),
        .rulings: DisplayRepresentation(title: "Rulings", image: .init(systemName: "text.page")),
        .figures: DisplayRepresentation(title: "Figures", image: .init(systemName: "person.2")),
        .tasbih: DisplayRepresentation(title: "Tasbih", image: .init(systemName: "circle.dotted")),
        .rakaat: DisplayRepresentation(title: "Rakaat Tracker", image: .init(systemName: "camera.metering.center.weighted")),
        .prayerProgress: DisplayRepresentation(title: "Activity", image: .init(systemName: "chart.bar.fill")),
        .qibla: DisplayRepresentation(title: "Qibla", image: .init(systemName: "location.north.circle")),
    ]
}

extension PrayerName: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Prayer"

    static let caseDisplayRepresentations: [PrayerName: DisplayRepresentation] = [
        .imsak: "Imsak",
        .fajr: "Fajr",
        .sunrise: "Sunrise",
        .dhuhr: "Dhuhr",
        .asr: "Asr",
        .sunset: "Sunset",
        .maghrib: "Maghrib",
        .isha: "Isha",
        .midnight: "Midnight",
    ]
}

/// The tools an in-app search can target.
enum SearchArea: String, AppEnum {
    case quran, hadith, supplications, rulings, figures

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Search Area"

    static let caseDisplayRepresentations: [SearchArea: DisplayRepresentation] = [
        .quran: "Holy Quran",
        .hadith: "Hadith",
        .supplications: "Supplications",
        .rulings: "Rulings",
        .figures: "Figures",
    ]

    var tool: AppTool {
        switch self {
        case .quran: .quran
        case .hadith: .hadith
        case .supplications: .supplications
        case .rulings: .rulings
        case .figures: .figures
        }
    }
}
