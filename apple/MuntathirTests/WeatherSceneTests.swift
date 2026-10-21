@testable import Muntathir
import Testing
import WeatherKit

struct WeatherSceneTests {
    @Test func conditionFamilies() {
        #expect(WeatherSceneStyle(.clear) == .clear)
        #expect(WeatherSceneStyle(.partlyCloudy) == .cloudy)
        #expect(WeatherSceneStyle(.rain) == .rain)
        #expect(WeatherSceneStyle(.freezingRain) == .rain)
        #expect(WeatherSceneStyle(.snow) == .snow)
        #expect(WeatherSceneStyle(.wintryMix) == .snow)
        #expect(WeatherSceneStyle(.foggy) == .fog)
        #expect(WeatherSceneStyle(.thunderstorms) == .storm)
        #expect(WeatherSceneStyle(.windy) == .wind)
        #expect(WeatherSceneStyle(nil) == .cloudy)
    }

    @Test @MainActor func daylightFollowsSolarState() {
        for progress: Double? in [nil, 0, 0.5, 1] {
            let sun = SolarPosition(elevation: 0, apparentElevation: 0, azimuth: 0, isRising: true, daylightProgress: progress)
            #expect(WeatherCardScene.isDaylight(sun) == (progress != nil))
        }
        #expect(!WeatherCardScene.isDaylight(nil))
    }
}
