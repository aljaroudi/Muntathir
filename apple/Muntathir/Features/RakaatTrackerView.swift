// iPhone and iPad only: Macs have no compass or front-camera sujood tracking.
#if os(iOS)
    import SwiftUI

    struct RakaatTrackerView: View {
        struct Start: Hashable {
            let target: Int
            let prayer: PrayerName?
        }

        @Environment(\.scenePhase) private var scenePhase
        @Environment(AppModel.self) private var model
        @Environment(\.progressStore) private var history
        @State private var qibla = QiblaLocationSession(optional: true)
        @State private var selection: Start?

        var body: some View {
            setupView
                .background { RakaatHeadingOrientation(onChange: qibla.orientHeading).allowsHitTesting(false) }
                .navigationTitle("Rakaat Tracker")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(item: $selection) { start in
                    RakaatSessionView(target: start.target, prayer: start.prayer)
                }
                .task(id: scenePhase == .active && selection == nil) {
                    guard scenePhase == .active, selection == nil else { qibla.stop(); return }
                    qibla.start()
                    while !Task.isCancelled {
                        qibla.refresh()
                        do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    }
                }
                .onDisappear { qibla.stop() }
        }

        private func start(_ prayer: PrayerName) {
            selection = Start(target: PrayerProgress.rakaat(for: prayer), prayer: prayer)
        }

        private func prayerLabel(_ prayer: PrayerName, prominent: Bool) -> some View {
            Label(prayer.title, systemImage: prayer.symbol)
                .font(prominent ? .title2.weight(.semibold) : .headline)
                .frame(maxWidth: .infinity, minHeight: prominent ? 88 : 56)
        }

        private func prayerChoices(suggested: PrayerName?) -> some View {
            VStack(spacing: 16) {
                Text("Choose prayer").font(.title2.bold())
                if let suggested {
                    Button { start(suggested) } label: { prayerLabel(suggested, prominent: true) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("rakaat-prayer-\(suggested.rawValue)")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    ForEach(PrayerProgress.prayers.filter { $0 != suggested }) { prayer in
                        Button { start(prayer) } label: { prayerLabel(prayer, prominent: false) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("rakaat-prayer-\(prayer.rawValue)")
                    }
                }
                Menu {
                    Section("Rakaat") {
                        ForEach(2 ... 4, id: \.self) { number in
                            Button { selection = Start(target: number, prayer: nil) } label: {
                                Text(number, format: .number)
                            }
                            .accessibilityLabel(Text("\(number) rakaat"))
                            .accessibilityIdentifier("rakaat-target-\(number)")
                        }
                    }
                } label: {
                    Text("Other")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("rakaat-other")
            }
        }

        private var setupView: some View {
            ScrollView {
                VStack(spacing: 32) {
                    TimelineView(.everyMinute) { context in
                        prayerChoices(suggested: PrayerProgress.suggestedPrayer(
                            at: context.date, location: model.location, method: model.preferences.prayerMethod,
                            completed: history?.records ?? []
                        ))
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
#endif
