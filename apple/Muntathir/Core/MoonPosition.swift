import Foundation

/// Approximate lunar ephemeris for the decorative sky.
/// Orbital elements and perturbations: https://www.stjarnhimlen.se/comp/ppcomp.html
/// Angles exposed here are degrees; elevation is topocentric, geometric (no refraction).
struct MoonPosition: Sendable {
    let elevation: Double
    let azimuth: Double
    let illuminatedFraction: Double
    let isWaxing: Bool
    /// Schematic rise → transit → set progress using the current declination, not a rise/set forecast.
    let visibleProgress: Double?

    static func calculate(at date: Date, latitude: Double, longitude: Double) -> Self? {
        guard date.timeIntervalSince1970.isFinite, latitude.isFinite, longitude.isFinite,
              (-90 ... 90).contains(latitude), (-180 ... 180).contains(longitude) else { return nil }
        let radians = Double.pi / 180
        let days = date.timeIntervalSince1970 / 86400 + 2_440_587.5 - 2_451_543.5
        func angle(_ degrees: Double) -> Double {
            degrees.truncatingRemainder(dividingBy: 360) * radians
        }
        func eccentricAnomaly(_ mean: Double, _ eccentricity: Double) -> Double {
            var result = mean
            for _ in 0 ..< 5 {
                result -= (result - eccentricity * sin(result) - mean) / (1 - eccentricity * cos(result))
            }
            return result
        }
        let solarPerigee = angle(282.9404 + 4.70935e-5 * days)
        let solarMean = angle(356.0470 + 0.9856002585 * days)
        let solarEccentricity = 0.016709 - 1.151e-9 * days
        let solarE = eccentricAnomaly(solarMean, solarEccentricity)
        let solarX = cos(solarE) - solarEccentricity
        let solarY = sqrt(1 - solarEccentricity * solarEccentricity) * sin(solarE)
        let solarLongitude = atan2(solarY, solarX) + solarPerigee

        let node = angle(125.1228 - 0.0529538083 * days)
        let inclination = angle(5.1454)
        let perigee = angle(318.0634 + 0.1643573223 * days)
        let mean = angle(115.3654 + 13.0649929509 * days)
        let eccentricity = 0.0549
        let eccentric = eccentricAnomaly(mean, eccentricity)
        let orbitalX = 60.2666 * (cos(eccentric) - eccentricity)
        let orbitalY = 60.2666 * sqrt(1 - eccentricity * eccentricity) * sin(eccentric)
        let orbitalAngle = atan2(orbitalY, orbitalX) + perigee
        var distance = hypot(orbitalX, orbitalY)
        let x = cos(node) * cos(orbitalAngle) - sin(node) * sin(orbitalAngle) * cos(inclination)
        let y = sin(node) * cos(orbitalAngle) + cos(node) * sin(orbitalAngle) * cos(inclination)
        let z = sin(orbitalAngle) * sin(inclination)
        var lunarLongitude = atan2(y, x)
        var lunarLatitude = atan2(z, hypot(x, y))
        let elongation = mean + perigee + node - solarMean - solarPerigee
        let latitudeArgument = mean + perigee
        // Principal solar perturbations of the lunar orbit, in degrees and Earth radii.
        let longitudeTerms: [(Double, Double)] = [
            (-1.274, mean - 2 * elongation), (0.658, 2 * elongation), (-0.186, solarMean),
            (-0.059, 2 * mean - 2 * elongation), (-0.057, mean - 2 * elongation + solarMean),
            (0.053, mean + 2 * elongation), (0.046, 2 * elongation - solarMean),
            (0.041, mean - solarMean), (-0.035, elongation), (-0.031, mean + solarMean),
            (-0.015, 2 * latitudeArgument - 2 * elongation), (0.011, mean - 4 * elongation),
        ]
        lunarLongitude += longitudeTerms.reduce(0) { $0 + $1.0 * sin($1.1) } * radians
        let latitudeTerms: [(Double, Double)] = [
            (-0.173, latitudeArgument - 2 * elongation), (-0.055, mean - latitudeArgument - 2 * elongation),
            (-0.046, mean + latitudeArgument - 2 * elongation), (0.033, latitudeArgument + 2 * elongation),
            (0.017, 2 * mean + latitudeArgument),
        ]
        lunarLatitude += latitudeTerms.reduce(0) { $0 + $1.0 * sin($1.1) } * radians
        distance -= 0.58 * cos(mean - 2 * elongation) + 0.46 * cos(2 * elongation)

        let obliquity = angle(23.4393 - 3.563e-7 * days)
        let eclipticX = distance * cos(lunarLongitude) * cos(lunarLatitude)
        let eclipticY = distance * sin(lunarLongitude) * cos(lunarLatitude)
        let eclipticZ = distance * sin(lunarLatitude)
        let sidereal = angle(280.46061837 + 360.98564736629 * (days - 1.5) + longitude)
        let phi = latitude * radians
        let geocentricLatitude = phi - angle(0.1924) * sin(2 * phi)
        let observerRadius = 0.99833 + 0.00167 * cos(2 * phi)
        // Subtract the observer's position before converting to the local horizon (lunar parallax).
        let equatorialX = eclipticX - observerRadius * cos(geocentricLatitude) * cos(sidereal)
        let equatorialY = eclipticY * cos(obliquity) - eclipticZ * sin(obliquity)
            - observerRadius * cos(geocentricLatitude) * sin(sidereal)
        let equatorialZ = eclipticY * sin(obliquity) + eclipticZ * cos(obliquity)
            - observerRadius * sin(geocentricLatitude)
        let declination = atan2(equatorialZ, hypot(equatorialX, equatorialY))
        let hourAngle = atan2(sin(sidereal - atan2(equatorialY, equatorialX)), cos(sidereal - atan2(equatorialY, equatorialX)))
        let base = sin(phi) * sin(declination)
        let amplitude = cos(phi) * cos(declination)
        let elevation = asin(min(1, max(-1, base + amplitude * cos(hourAngle)))) / radians
        let azimuth = atan2(sin(hourAngle), cos(hourAngle) * sin(phi) - tan(declination) * cos(phi)) / radians + 180
        let progress: Double?
        if elevation < 0 {
            progress = nil
        } else if base - amplitude >= 0 {
            progress = (hourAngle + .pi) / (2 * .pi)
        } else {
            let settingAngle = acos(min(1, max(-1, -base / amplitude)))
            progress = settingAngle > 0 ? min(1, max(0, (hourAngle + settingAngle) / (2 * settingAngle))) : 0.5
        }
        let separation = acos(min(1, max(-1, cos(lunarLatitude) * cos(lunarLongitude - solarLongitude))))
        let solarDistance = hypot(solarX, solarY) * 23454.8 // AU in Earth equatorial radii
        let phaseAngle = atan2(solarDistance * sin(separation), distance - solarDistance * cos(separation))
        return Self(elevation: elevation, azimuth: azimuth,
                    illuminatedFraction: (1 + cos(phaseAngle)) / 2,
                    isWaxing: sin(lunarLongitude - solarLongitude) >= 0, visibleProgress: progress)
    }
}
