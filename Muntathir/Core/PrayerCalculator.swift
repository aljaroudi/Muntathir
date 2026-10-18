import Adhan
import Foundation

struct SavedLocation: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var name: String
    var countryCode: String
    var timeZoneID: String
    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? .gmt
    }

    var hasValidCoordinates: Bool {
        latitude.isFinite && longitude.isFinite && (-90 ... 90).contains(latitude) && (-180 ... 180).contains(longitude)
    }

    var isValid: Bool {
        hasValidCoordinates && TimeZone(identifier: timeZoneID) != nil && !name.isEmpty
    }
}

enum PrayerMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case jafari, tehran, muslimWorldLeague, egyptian, karachi, ummAlQura, dubai, moonsightingCommittee, northAmerica, kuwait, qatar, singapore, turkey
    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .jafari: String(localized: "Shia — Jafari (Qum)")
        case .tehran: String(localized: "Shia — Tehran (recommended)")
        case .muslimWorldLeague: String(localized: "Muslim World League")
        case .egyptian: String(localized: "Egyptian General Authority")
        case .karachi: String(localized: "University of Karachi")
        case .ummAlQura: String(localized: "Umm al-Qura — Makkah")
        case .dubai: String(localized: "Dubai")
        case .moonsightingCommittee: String(localized: "Moonsighting Committee")
        case .northAmerica: String(localized: "ISNA — North America")
        case .kuwait: String(localized: "Kuwait")
        case .qatar: String(localized: "Qatar")
        case .singapore: String(localized: "Singapore")
        case .turkey: String(localized: "Turkey")
        }
    }
}

enum PrayerName: String, Codable, CaseIterable, Identifiable, Sendable {
    case imsak, fajr, sunrise, dhuhr, asr, sunset, maghrib, isha, midnight
    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .imsak: String(localized: "Imsak")
        case .fajr: String(localized: "Fajr")
        case .sunrise: String(localized: "Sunrise")
        case .dhuhr: String(localized: "Dhuhr")
        case .asr: String(localized: "Asr")
        case .midnight: String(localized: "Islamic midnight")
        case .sunset: String(localized: "Sunset")
        case .maghrib: String(localized: "Maghrib")
        case .isha: String(localized: "Isha")
        }
    }

    var symbol: String {
        switch self {
        case .imsak: "moonset"
        case .fajr: "sun.horizon"
        case .sunrise: "sunrise"
        case .dhuhr: "sun.max"
        case .asr: "sun.haze"
        case .sunset: "sunset"
        case .maghrib: "moon.haze"
        case .isha: "moon.stars"
        case .midnight: "moon.zzz"
        }
    }

    var isRequired: Bool {
        self == .fajr || self == .dhuhr || self == .maghrib
    }

    var rakaaCount: Int? {
        switch self {
        case .fajr: 2
        case .dhuhr, .asr, .isha: 4
        case .maghrib: 3
        default: nil
        }
    }

    var isPrayer: Bool {
        [.fajr, .dhuhr, .asr, .maghrib, .isha].contains(self)
    }

    func isVisible(hidden: Set<Self>) -> Bool {
        isRequired || !hidden.contains(self)
    }

    static var optionalTimes: [Self] {
        allCases.filter { !$0.isRequired }
    }

    static var notifiable: [Self] {
        allCases.filter(\.isPrayer)
    }
}

struct PrayerMoment: Identifiable, Sendable {
    let name: PrayerName
    let date: Date
    var id: String {
        name.rawValue
    }
}

enum PrayerCalculator {
    static func times(on date: Date, location: SavedLocation, method: PrayerMethod, imsakMinutes: Int = 10) -> [PrayerMoment] {
        // Display metadata must not suppress astronomical calculations for a valid coordinate.
        guard location.hasValidCoordinates else { return [] }
        let engine = try! CalendarEngine(timeZone: location.timeZone)
        let components = engine.gregorian.dateComponents([.year, .month, .day], from: date)
        let coordinates = Coordinates(latitude: location.latitude, longitude: location.longitude)
        var parameters = CalculationMethod(rawValue: method.rawValue)?.params ?? CalculationMethod.other.params
        if method == .jafari {
            // PrayTimes Jafari/Qum convention: https://praytimes.org/docs/methods
            parameters.fajrAngle = 16
            parameters.maghribAngle = 4
            parameters.ishaAngle = 14
        }
        parameters.madhab = .shafi
        parameters.highLatitudeRule = HighLatitudeRule.recommended(for: coordinates)
        // Use the independent calculated calendar for the preset's Ramadan interval.
        if method == .ummAlQura || method == .qatar, engine.baseline.component(.month, from: date) == 9 {
            parameters.ishaInterval += 30
        }
        guard let times = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: parameters) else { return [] }
        // A neutral preset avoids method-specific Maghrib offsets when obtaining sunset.
        var solarParameters = CalculationMethod.other.params
        solarParameters.fajrAngle = parameters.fajrAngle
        solarParameters.ishaAngle = 18
        solarParameters.highLatitudeRule = parameters.highLatitudeRule
        guard let solar = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: solarParameters) else { return [] }
        if method == .tehran || method == .jafari {
            var sunsetParameters = parameters; sunsetParameters.maghribAngle = nil
            guard let sunset = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: sunsetParameters),
                  times.maghrib > sunset.maghrib else { return [] }
        }
        var result: [PrayerMoment] = [.init(name: .imsak, date: times.fajr.addingTimeInterval(-Double(min(120, max(0, imsakMinutes))) * 60)), .init(name: .fajr, date: times.fajr), .init(name: .sunrise, date: times.sunrise),
                                      .init(name: .dhuhr, date: times.dhuhr), .init(name: .asr, date: times.asr),
                                      .init(name: .sunset, date: solar.maghrib), .init(name: .maghrib, date: times.maghrib), .init(name: .isha, date: times.isha)]
        let tomorrow = engine.addingDays(1, to: date)
        let nextComponents = engine.gregorian.dateComponents([.year, .month, .day], from: tomorrow)
        if let next = PrayerTimes(coordinates: coordinates, date: nextComponents, calculationParameters: parameters) {
            let midpoint = solar.maghrib.addingTimeInterval(next.fajr.timeIntervalSince(solar.maghrib) / 2)
            result.append(.init(name: .midnight, date: Date(timeIntervalSince1970: (midpoint.timeIntervalSince1970 / 60).rounded() * 60)))
        }
        return result
    }

    static func qibla(_ location: SavedLocation) -> Double {
        Qibla(coordinates: Coordinates(latitude: location.latitude, longitude: location.longitude)).direction
    }
}
