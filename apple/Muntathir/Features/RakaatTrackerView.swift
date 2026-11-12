import SwiftUI

struct RakaatTrackerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var qibla = QiblaLocationSession(optional: true)
    @State private var target: Int?

    var body: some View {
        setupView
            .background { RakaatHeadingOrientation(onChange: qibla.orientHeading).allowsHitTesting(false) }
            .navigationTitle("Rakaat Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .navigationDestination(item: $target) { target in
                RakaatSessionView(target: target)
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

    private var setupView: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 16) {
                    Text("Choose rakaat").font(.title2.bold())
                    HStack(spacing: 16) {
                        ForEach(2 ... 4, id: \.self) { number in
                            Button { target = number } label: {
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
