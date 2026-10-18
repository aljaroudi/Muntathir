import SwiftUI

struct QiblaView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Page {
            if let location = model.location {
                let bearing = PrayerCalculator.qibla(location)
                let degrees = Measurement(value: bearing, unit: UnitAngle.degrees)
                Card {
                    Text(location.name).font(.headline)
                    ZStack {
                        Circle()
                            .stroke(Color.accentColor.opacity(0.18), lineWidth: 2)
                        Circle()
                            .stroke(Color.accentColor.opacity(0.08), lineWidth: 20)
                            .padding(25)
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(Color.accentColor)
                            .rotationEffect(
                                .degrees(bearing - (model.locationService.heading ?? 0))
                            )
                    }
                        .frame(maxWidth: 280).aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity).padding(.vertical)
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityHidden(true)
                    Text(
                        "\(degrees, format: .measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1)))) from true north"
                    ).font(.title3)
                    if model.locationService.heading == nil {
                        Text(
                            "Compass unavailable. Use the bearing from true north."
                        ).foregroundStyle(.secondary)
                    } else if (model.locationService.headingAccuracy ?? 180) > 20 {
                        Text(
                            "Compass accuracy is low. Move away from magnets and metal."
                        ).foregroundStyle(.secondary)
                    } else {
                        Text("Keep your device flat and follow the arrow.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Choose a location",
                    systemImage: "location",
                    description: Text("Set your location in Settings to find Qibla.")
                )
            }
        }
        .navigationTitle("Qibla")
        .onAppear { model.locationService.startHeading() }
        .onDisappear { model.locationService.stopHeading() }
    }
}
