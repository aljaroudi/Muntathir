import SwiftUI

@main
struct MuntathirWatchApp: App {
    @State private var connectivity = WatchConnectivityService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchPrayerView(settings: connectivity.settings)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        connectivity.refresh()
                    }
                }
        }
        .backgroundTask(.watchConnectivity) {
            await WatchConnectivityService.shared.finishBackgroundTransfer()
        }
    }
}

struct WatchPrayerView: View {
    let settings: WatchSettings?

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if let settings, let location = settings.prayers.location {
                    let next = settings.prayers.nextPrayer(after: context.date)
                    let prayers = settings.prayers.prayers(on: context.date)
                    List(prayers) { prayer in
                        HStack(spacing: 6) {
                            Image(systemName: prayer.name.symbol)
                                .frame(width: 20).accessibilityHidden(true)
                            Text(prayer.name.title).font(.headline)
                            Spacer(minLength: 2)
                            Text(prayer.date.formatted(.dateTime.hour().minute().inZone(location.timeZone)))
                                .monospacedDigit().font(.body)
                        }
                        .foregroundStyle(prayer.date == next?.date ? Color.accentColor : .primary)
                        .accessibilityElement(children: .combine)
                    }
                    .overlay {
                        if prayers.isEmpty {
                            Text("Prayer times unavailable for this location and date.")
                                .font(.caption).multilineTextAlignment(.center).padding()
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Prayer times", systemImage: "moon")
                    } description: {
                        Text("Open Muntathir on your iPhone to sync your location and settings.")
                    }
                }
            }
            .navigationTitle("Prayer times")
        }
        .tint(.mint)
    }
}

#Preview("Prayer times") {
    WatchPrayerView(settings: .init(prayers: .init(location: .init(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh"), method: .tehran, asrRule: .standard, hiddenPrayers: [.asr, .isha]), calendar: .init(timeZoneID: "Asia/Riyadh")))
}

#Preview("Waiting for iPhone") {
    WatchPrayerView(settings: nil)
}
