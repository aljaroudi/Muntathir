import SwiftUI

struct PrayerCounterView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var sensor = ProximityCounterService()
    @State private var prayer = PrayerName.fajr
    @State private var sessionID = UUID()

    var body: some View {
        Group {
            if let counter = sensor.counter {
                PrayerCounterDisplay(counter: counter, exit: exit)
            } else {
                setup
            }
        }
        .interactiveDismissDisabled()
        .toolbar(sensor.counter == nil ? .visible : .hidden, for: .tabBar)
        .task(id: sessionID) {
            guard scenePhase == .active else { return }
            if sensor.counter?.stopped == true {
                sensor = ProximityCounterService()
            }
            if sensor.counter == nil {
                prayer = WidgetPrayerSettings(location: model.location, method: model.preferences.prayerMethod,
                                              hiddenPrayers: model.preferences.hiddenPrayers, imsakMinutes: model.preferences.imsakMinutes)
                    .previousPrayer(at: .now)?.name ?? .fajr
            }
            await sensor.monitor()
        }
        .onDisappear { sensor.exit() }
        .onChange(of: scenePhase) { _, phase in
            // Proximity blanking can make a scene inactive. Only backgrounding ends counting.
            if phase == .background {
                sensor.interrupt()
            } else if phase == .active, sensor.counter == nil {
                exit()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in
            sensor.interrupt()
        }
    }

    private var setup: some View {
        NavigationStack {
            Form {
                Picker("Prayer", selection: $prayer) {
                    ForEach(PrayerName.notifiable) { prayer in
                        Text(prayer.title).tag(prayer)
                    }
                }
                Section("Placement test") {
                    Text("Place your iPhone face-up on the prayer mat, with the top of the screen near where your face lowers. Test that the sensor changes when you lower and lift your face.")
                    if sensor.available {
                        Label(sensor.near ? "Near" : "Far", systemImage: sensor.near ? "sensor.fill" : "sensor")
                        Text("The display may turn off while your face is near the sensor. The count appears again when you lift your face.")
                    } else {
                        Label("Proximity sensing is unavailable on this device.", systemImage: "exclamationmark.circle")
                    }
                }
                Section {
                    Button("Start counting") { sensor.start(prayer: prayer) }
                        .disabled(!sensor.available || sensor.near)
                } footer: {
                    Text("Keep the app open during prayer. Each pair of sujoods advances one rakaa. Leaving the app interrupts counting.")
                }
            }
            .navigationTitle("Prayer counter")
        }
    }

    private func exit() {
        sensor.exit()
        sensor = ProximityCounterService()
        sessionID = UUID()
    }
}

struct PrayerCounterDisplay: View {
    let counter: PrayerCounter
    var exit: () -> Void
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize = 160

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Text(counter.rakaa, format: .number.locale(locale))
                    .font(.system(size: numberSize, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(counter.firstSujood ? Color.gray : Color.white)
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
                    .accessibilityLabel(Text("Rakaa \(counter.rakaa) of \(counter.total)"))
                    .accessibilityValue(accessibilityStatus)
                if counter.interrupted {
                    Text("Counting interrupted. Exit to start a new session.")
                        .font(.body)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
        }
        .overlay(alignment: .topTrailing) {
            Button("Exit counter", systemImage: "xmark", action: exit)
                .labelStyle(.iconOnly)
                .font(.body)
                .foregroundStyle(.gray)
                .frame(width: 44, height: 44)
                .padding(8)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
    }

    private var accessibilityStatus: Text {
        if counter.interrupted {
            Text("Counting interrupted")
        } else if counter.complete {
            Text("Counting complete")
        } else if counter.firstSujood {
            Text("First sujood counted")
        } else {
            Text("Awaiting first sujood")
        }
    }
}

#Preview("Initial — English") {
    PrayerCounterDisplay(counter: PrayerCounter(prayer: .fajr), exit: {})
}

#Preview("First sujood — Arabic") {
    PrayerCounterDisplay(counter: counterPreview(sujoods: 1), exit: {})
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
}

#Preview("Final") {
    PrayerCounterDisplay(counter: counterPreview(sujoods: 4), exit: {})
}

#Preview("Interrupted") {
    PrayerCounterDisplay(counter: counterPreview(sujoods: 1, interrupted: true), exit: {})
}

#Preview("Setup — unsupported simulator") { PrayerCounterView().environment(AppModel()) }

private func counterPreview(sujoods: Int, interrupted: Bool = false) -> PrayerCounter {
    var counter = PrayerCounter(prayer: .fajr)
    counter.sample(near: false, at: 0)
    counter.sample(near: false, at: 1)
    for index in 0 ..< sujoods {
        let time = Double(index * 3 + 2)
        counter.sample(near: true, at: time)
        counter.sample(near: false, at: time + 1)
        counter.sample(near: false, at: time + 2)
    }
    if interrupted {
        counter.interrupt()
    }
    return counter
}
