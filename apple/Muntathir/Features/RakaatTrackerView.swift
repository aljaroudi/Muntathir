import AVFoundation
import SwiftUI

struct RakaatTrackerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var camera = RakaatCamera()
    @State private var qibla = QiblaLocationSession(optional: true)
    @State private var target: Int?
    @State private var update: RakaatCamera.Update?
    @State private var ended = false
    @State private var running = false
    @State private var denied = false
    @State private var failed = false
    @State private var oldIdleState: Bool?

    private var preparing: Bool {
        target != nil && !ended && update?.calibrated != true
    }

    private var showsQibla: Bool {
        (target == nil || preparing) && scenePhase == .active
    }

    var body: some View {
        ZStack {
            if target != nil {
                prayerView
            } else {
                setupView
            }
        }
        .background { RakaatHeadingOrientation(onChange: qibla.orientHeading).allowsHitTesting(false) }
        .navigationTitle("Rakaat Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(target != nil ? .hidden : .visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task(id: target) {
            guard let target else { return }
            await run(target: target)
        }
        .task(id: ended) {
            if ended {
                await camera.stop()
                guard !Task.isCancelled, ended else { return }
                restoreIdle()
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: AVCaptureSession.wasInterruptedNotification) {
                if target != nil, !ended {
                    failed = true; ended = true
                }
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: AVCaptureSession.runtimeErrorNotification) {
                if target != nil, !ended {
                    failed = true; ended = true
                }
            }
        }
        .task(id: showsQibla) {
            guard showsQibla else { qibla.stop(); return }
            qibla.start()
            while !Task.isCancelled {
                qibla.refresh()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onChange(of: scenePhase) {
            if target != nil, scenePhase == .background || (scenePhase == .inactive && update != nil) {
                ended = true
            }
        }
        .onDisappear {
            ended = true
            qibla.stop()
            restoreIdle()
            Task { await camera.stop() }
        }
    }

    private var count: some View {
        Text((update?.count ?? 0) / 2, format: .number)
            .font(.largeTitle.scaled(by: 4)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.3)
            .accessibilityLabel(Text("\((update?.count ?? 0) / 2) rakaat"))
            .accessibilityIdentifier("rakaat-count")
    }

    private var prayerView: some View {
        ZStack {
            GeometryReader { geometry in
                if !ended, let image = update?.preview {
                    Image(decorative: image, scale: 1)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            }
            .background(.black)
            .overlay(.black.opacity(0.25))
            .ignoresSafeArea()
            .accessibilityHidden(true)

            VStack(spacing: 20) {
                if denied || failed {
                    Label("Camera unavailable", systemImage: "camera")
                        .font(.title2.bold())
                    if denied {
                        Text("Allow camera access in Settings to count sujood.")
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Text("Camera capture ended. Start a new session to try again.")
                    }
                } else if preparing {
                    if let seconds = update?.countdown, seconds > 0 {
                        Text("Starting in \(seconds)…")
                            .font(.largeTitle.bold())
                    } else {
                        ProgressView().tint(.white)
                    }
                    Text("Keep the camera uncovered in steady light while it calibrates.")
                        .font(.body)
                } else {
                    count
                        .shadow(color: .black.opacity(0.6), radius: 8)
                    if update?.complete == true {
                        Label("Count complete", systemImage: "checkmark.circle")
                            .font(.headline)
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("rakaat-complete")
                    }
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(32)
        }
        .safeAreaInset(edge: .top) {
            if preparing {
                qiblaHint
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(16)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await returnToSelection() }
            } label: {
                Text(ended ? LocalizedStringKey("Finish") : LocalizedStringKey("End"))
                    .font(.headline)
                    .frame(minWidth: 120, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .padding(.bottom, 20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rakaat-prayer-screen")
    }

    private var setupView: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 16) {
                    Text("Choose rakaat").font(.title2.bold())
                    HStack(spacing: 16) {
                        ForEach(2 ... 4, id: \.self) { number in
                            Button { ended = false; target = number } label: {
                                Text(number, format: .number)
                                    .font(.largeTitle.weight(.medium))
                                    .frame(maxWidth: .infinity, minHeight: 72)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel(Text("\(number) rakaat"))
                            .accessibilityIdentifier("rakaat-target-\(number)")
                            .disabled(running)
                        }
                    }
                }
                qiblaHint
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

    @ViewBuilder private var qiblaHint: some View {
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

    private func run(target: Int) async {
        running = true
        defer { running = false }
        let authorized: Bool
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--rakaat-denied") {
                denied = true; ended = true; return
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--rakaat-demo") {
                update = .init(preview: nil, count: 0, countdown: 5, calibrated: false, complete: false)
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard !ended else { return }
                update = .init(preview: nil, count: 2, countdown: 0, calibrated: true, complete: false)
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard !ended else { return }
                update = .init(preview: nil, count: target * 2, countdown: 0, calibrated: true, complete: true)
                ended = true
                return
            }
        #endif
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorized = true
        case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
        default: authorized = false
        }
        guard !Task.isCancelled, !ended else { return }
        guard authorized else { denied = true; ended = true; return }
        oldIdleState = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        do {
            let stream = try await camera.start(target: target)
            for await value in stream {
                guard !Task.isCancelled, !ended else { break }
                update = value
                if value.complete {
                    ended = true
                }
            }
            if !ended, !Task.isCancelled {
                failed = true; ended = true
            }
        } catch { failed = true; ended = true }
        await camera.stop()
        restoreIdle()
    }

    private func restoreIdle() {
        if let oldIdleState {
            UIApplication.shared.isIdleTimerDisabled = oldIdleState
        }
        oldIdleState = nil
    }

    private func returnToSelection() async {
        ended = true
        await camera.stop()
        restoreIdle()
        target = nil; update = nil; denied = false; failed = false
    }
}
