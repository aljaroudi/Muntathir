import SwiftUI

struct QiblaView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var headingOwner = UUID()
    @State private var visible = false
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
                                .degrees(model.locationService.hasAccurateHeading ? bearing - (model.locationService.heading ?? 0) : 0)
                            )
                    }
                    .frame(maxWidth: 280).aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity).padding(.vertical)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityHidden(true)
                    .blur(radius: model.locationService.hasAccurateHeading ? 0 : 18)
                    .overlay {
                        if !model.locationService.hasAccurateHeading {
                            Label {
                                if model.locationService.heading == nil {
                                    Text("Compass unavailable")
                                } else {
                                    Text("Compass accuracy is low")
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.triangle")
                            }
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .padding()
                            .background(.regularMaterial, in: .rect(cornerRadius: 16))
                            .padding()
                        }
                    }
                    Text(
                        "\(degrees, format: .measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))) from true north"
                    ).font(.title3)
                    if model.locationService.heading == nil {
                        Text(
                            "Compass unavailable. Use the bearing from true north."
                        ).foregroundStyle(.secondary)
                    } else if !model.locationService.hasAccurateHeading {
                        Text(
                            "Compass accuracy is low. Move away from magnets and metal."
                        ).foregroundStyle(.secondary)
                    } else {
                        Text("Keep your device flat and follow the arrow.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("qibla-compass-ready")
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
        .onAppear { visible = true; updateHeading() }
        .onDisappear { visible = false; updateHeading() }
        .onChange(of: scenePhase) { updateHeading() }
    }

    private func updateHeading() {
        if visible, scenePhase == .active {
            model.locationService.startHeading(owner: headingOwner)
        } else {
            model.locationService.stopHeading(owner: headingOwner)
        }
    }
}
