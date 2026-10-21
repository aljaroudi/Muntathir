import WeatherKit

/// Small visual families keep the card schematic while retaining the spoken condition.
enum WeatherSceneStyle {
    case clear, cloudy, rain, snow, fog, storm, wind

    init(_ condition: WeatherCondition?) {
        switch condition {
        case .clear, .mostlyClear, .hot, .frigid: self = .clear
        case .drizzle, .freezingDrizzle, .freezingRain, .heavyRain, .rain, .sunShowers: self = .rain
        case .blizzard, .blowingSnow, .flurries, .heavySnow, .snow, .sunFlurries, .sleet, .hail, .wintryMix: self = .snow
        case .foggy, .haze, .smoky, .blowingDust: self = .fog
        case .hurricane, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms, .thunderstorms, .tropicalStorm: self = .storm
        case .breezy, .windy: self = .wind
        default: self = .cloudy
        }
    }

    var detailSymbol: String? {
        switch self {
        case .clear, .cloudy, .rain: nil
        case .snow: "snowflake"
        case .fog: "line.3.horizontal"
        case .storm: "bolt.fill"
        case .wind: "wind"
        }
    }
}
