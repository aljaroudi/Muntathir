import SwiftUI

struct RakaatTrackerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var qibla = QiblaLocationSession(optional: true)
    @State private var target: Int?
    @State private var choosingPrayer = false
    @State private var selectedCount = 2
    @State private var selectedPrayer: PrayerName?

    var body: some View {
        setupView
            .background { RakaatHeadingOrientation(onChange: qibla.orientHeading).allowsHitTesting(false) }
            .navigationTitle("Rakaat Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $target) { target in
                RakaatSessionView(target: target, prayer: selectedPrayer)
            }
            .confirmationDialog("Prayer", isPresented: $choosingPrayer, titleVisibility: .visible) {
                ForEach(PrayerProgress.choices(for: selectedCount)) { prayer in
                    Button(prayer.title) { start(prayer) }
                        .accessibilityIdentifier("rakaat-prayer-\(prayer.rawValue)")
                }
                Button("Other") { start(nil) }
                    .accessibilityIdentifier("rakaat-prayer-other")
            }
            .task(id: scenePhase == .active && target == nil) {
                guard scenePhase == .active, target == nil else { qibla.stop(); return }
                qibla.start()
                while !Task.isCancelled {
                    qibla.refresh()
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
            .onDisappear { qibla.stop() }
    }

    private func start(_ prayer: PrayerName?) {
        selectedPrayer = prayer
        target = selectedCount
    }

    private var setupView: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 16) {
                    Text("Choose rakaat").font(.title2.bold())
                    HStack(spacing: 16) {
                        ForEach(2 ... 4, id: \.self) { number in
                            Button { selectedCount = number; choosingPrayer = true } label: {
                                Text(number, format: .number)
                                    .font(.largeTitle.weight(.medium))
                                    .frame(maxWidth: .infinity, minHeight: 72)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel(Text("\(number) rakaat"))
                            .accessibilityIdentifier("rakaat-target-\(number)")
                        }
                    }
                }
                RakaatQiblaHint(qibla: qibla)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tint)
                VStack(spacing: 16) {
                    RakaatPlacementDiagram()
                    Text("Place the phone screen-up, with the front camera just behind your mouth’s position during sujood, so your face covers it.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 24))
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }
}
