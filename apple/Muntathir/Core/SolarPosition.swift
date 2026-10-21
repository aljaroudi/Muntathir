import Foundation

struct SolarPosition: Sendable {
    /// Degrees above the astronomical horizon, before atmospheric refraction.
    let elevation: Double
    /// Degrees above the horizon, including NOAA's standard atmospheric refraction.
    let apparentElevation: Double
    /// Degrees clockwise from true north.
    let azimuth: Double
    let isRising: Bool

    /// Sunrise = 0, solar noon = 0.5, sunset = 1; nil while the sun is below the horizon.
    let daylightProgress: Double?

    static func calculate(at date: Date, latitude: Double, longitude: Double) -> Self? {
        guard date.timeIntervalSince1970.isFinite, latitude.isFinite, longitude.isFinite,
              (-90 ... 90).contains(latitude), (-180 ... 180).contains(longitude) else { return nil }
        // NOAA/Meeus: https://gml.noaa.gov/grad/solcalc/calcdetails.html
        let t = (date.timeIntervalSince1970 / 86400 + 2_440_587.5 - 2_451_545) / 36525
        func radians(_ degrees: Double) -> Double {
            degrees * .pi / 180
        }
        func degrees(_ radians: Double) -> Double {
            radians * 180 / .pi
        }
        func normalized(_ angle: Double) -> Double {
            (angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        }
        let meanLongitude = normalized(280.46646 + t * (36000.76983 + t * 0.0003032))
        let anomaly = radians(357.52911 + t * (35999.05029 - 0.0001537 * t))
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let center = sin(anomaly) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * anomaly) * (0.019993 - 0.000101 * t) + sin(3 * anomaly) * 0.000289
        let omega = radians(125.04 - 1934.136 * t)
        let apparentLongitude = radians(meanLongitude + center - 0.00569 - 0.00478 * sin(omega))
        let obliquity = radians(23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60 + 0.00256 * cos(omega))
        let declination = asin(sin(obliquity) * sin(apparentLongitude))
        let y = pow(tan(obliquity / 2), 2)
        let l = radians(meanLongitude)
        let equationOfTime = 4 * degrees(y * sin(2 * l) - 2 * eccentricity * sin(anomaly)
            + 4 * eccentricity * y * sin(anomaly) * cos(2 * l)
            - 0.5 * y * y * sin(4 * l) - 1.25 * eccentricity * eccentricity * sin(2 * anomaly))
        let utcMinutes = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400) / 60
        let hourAngle = radians(normalized((utcMinutes + equationOfTime + 4 * longitude) / 4) - 180)
        let phi = radians(latitude)
        let altitude = asin(min(1, max(-1, sin(phi) * sin(declination) + cos(phi) * cos(declination) * cos(hourAngle))))
        let elevation = degrees(altitude)
        let azimuth = normalized(degrees(atan2(sin(hourAngle), cos(hourAngle) * sin(phi) - tan(declination) * cos(phi))) + 180)
        let tangent = tan(altitude)
        let refraction: Double = if elevation > 85 {
            0
        } else if elevation > 5 {
            (58.1 / tangent - 0.07 / pow(tangent, 3) + 0.000086 / pow(tangent, 5)) / 3600
        } else if elevation > -0.575 {
            (1735 + elevation * (-518.2 + elevation * (103.4 + elevation * (-12.79 + elevation * 0.711)))) / 3600
        } else {
            -20.772 / tangent / 3600
        }
        // Standard sunrise includes the solar radius and atmospheric refraction.
        let horizon = sin(radians(-0.833))
        let base = sin(phi) * sin(declination)
        let amplitude = cos(phi) * cos(declination)
        let progress: Double?
        if base - amplitude >= horizon {
            // Polar day has no sunrise or sunset; show progress through the full solar day.
            progress = (hourAngle + .pi) / (2 * .pi)
        } else if base + amplitude <= horizon || elevation < -0.833 {
            progress = nil
        } else {
            let sunsetAngle = acos(min(1, max(-1, (horizon - base) / amplitude)))
            progress = min(1, max(0, (hourAngle + sunsetAngle) / (2 * sunsetAngle)))
        }
        return Self(elevation: elevation, apparentElevation: elevation + refraction, azimuth: azimuth, isRising: hourAngle < 0, daylightProgress: progress)
    }
}
