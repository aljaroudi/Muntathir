import Foundation

struct SolarArcMarker: Identifiable, Sendable {
    enum State: Sendable {
        case past, future, upcoming
    }

    let name: PrayerName
    let progress: Double
    let state: State
    var id: PrayerName {
        name
    }

    /// Pass the same visible schedule as the prayer card. An off-path next time stays off-path.
    static func make(prayers: [PrayerMoment], now: Date, location: SavedLocation) -> [Self] {
        let next = prayers.filter { $0.date > now }.min { $0.date < $1.date }?.name
        return prayers.compactMap { prayer in
            guard let solar = SolarPosition.calculate(at: prayer.date, latitude: location.latitude, longitude: location.longitude) else { return nil }
            // Rounded schedule times still belong exactly at the sunrise/sunset endpoints.
            let progress: Double? = switch prayer.name {
            case .sunrise: 0
            case .sunset: 1
            default: solar.daylightProgress
            }
            guard let progress else { return nil }
            return Self(name: prayer.name, progress: progress,
                        state: prayer.date <= now ? .past : prayer.name == next ? .upcoming : .future)
        }
    }
}
