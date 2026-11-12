import SwiftUI

struct RakaatQiblaHint: View {
    let qibla: QiblaLocationSession

    var body: some View {
        if let location = qibla.location, let heading = qibla.heading {
            let saved = SavedLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                      name: "", countryCode: "", timeZoneID: TimeZone.current.identifier)
            if let alignment = QiblaAlignment(bearing: PrayerCalculator.qibla(saved), heading: heading.trueHeading) {
                if alignment.isAligned(previously: false) {
                    Label("Aligned with Kaaba", systemImage: "checkmark.circle")
                } else if alignment.error < 0 {
                    Label("Tilt left", systemImage: "arrow.counterclockwise")
                        .environment(\.layoutDirection, .leftToRight)
                } else {
                    Label("Tilt right", systemImage: "arrow.clockwise")
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
        }
    }
}
