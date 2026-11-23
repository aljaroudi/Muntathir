// iPhone and iPad only: Macs have no compass or front-camera sujood tracking.
#if os(iOS)
    import AVFoundation
    import SwiftUI

    struct RakaatSessionView: View {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.scenePhase) private var scenePhase
        @Environment(\.openURL) private var openURL
        @State private var camera = RakaatCamera()
        @State private var qibla = QiblaLocationSession(optional: true)
        @Environment(AppModel.self) private var model
        @Environment(\.progressStore) private var history
        @State private var target: Int
        @State private var prayer: PrayerName?
        /// Changing the session restarts counting; `resuming` keeps the previous calibration.
        @State private var session = 0
        @State private var resuming = false
        @State private var recording = PrayerSessionRecording()
        @State private var update: RakaatCamera.Update?
        @State private var ended = false
        @State private var denied = false
        @State private var failed = false
        @State private var oldIdleState: Bool?
        @State private var screen: UIScreen?
        /// Kept so brightness is restored on the same screen after the view leaves its window.
        @State private var dimmed: (screen: UIScreen, brightness: CGFloat)?

        init(target: Int, prayer: PrayerName?) {
            _target = State(initialValue: target)
            _prayer = State(initialValue: prayer)
        }

        private var preparing: Bool {
            !ended && update?.calibrated != true
        }

        private var showsQibla: Bool {
            preparing && scenePhase == .active
        }

        var body: some View {
            prayerView
                .background { RakaatHeadingOrientation(onChange: qibla.orientHeading).allowsHitTesting(false) }
                .background { WindowScreenReader { screen = $0 }.allowsHitTesting(false) }
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
                .task(id: session) {
                    await run(target: target, resuming: resuming)
                }
                .task(id: ended) {
                    if ended {
                        await camera.stop()
                        guard !Task.isCancelled, ended else { return }
                        restoreScreen()
                    }
                }
                .task {
                    for await _ in NotificationCenter.default.notifications(named: AVCaptureSession.wasInterruptedNotification) {
                        if !ended {
                            failed = true; ended = true
                        }
                    }
                }
                .task {
                    for await _ in NotificationCenter.default.notifications(named: AVCaptureSession.runtimeErrorNotification) {
                        if !ended {
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
                    if scenePhase == .background || (scenePhase == .inactive && update != nil) {
                        ended = true
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if update?.complete == true, history?.unavailable == true {
                        VStack {
                            Text("Unable to save or load prayer history.")
                            Button("Try again") { history?.retry() }
                        }
                        .padding().background(.regularMaterial)
                    }
                }
                .onDisappear {
                    ended = true
                    qibla.stop()
                    restoreScreen()
                    Task { await camera.stop() }
                }
        }

        private var rakaatCount: Int {
            (update?.count ?? 0) / 2
        }

        private var showsMilestoneTint: Bool {
            guard let update, update.calibrated, update.failure == nil, !denied, !failed else { return false }
            return update.count.isMultiple(of: 2) && (rakaatCount == 2 || rakaatCount == target)
        }

        private var showsSujoodProgress: Bool {
            guard let update, update.calibrated, update.failure == nil, !denied, !failed else { return false }
            return !update.count.isMultiple(of: 2)
        }

        private var count: some View {
            Text(rakaatCount, format: .number)
                .font(.largeTitle.scaled(by: 4)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.3)
                .accessibilityLabel(Text("\(rakaatCount) rakaat"))
                .accessibilityValue(showsSujoodProgress ? Text("First sujood") : Text(verbatim: ""))
                .accessibilityIdentifier("rakaat-count")
        }

        /// Half-fills after the first sujood of a rakaah. Thin strokes add little light that could reach the camera.
        private var sujoodRing: some View {
            GeometryReader { geometry in
                let side = max(geometry.size.width, geometry.size.height)
                ZStack {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: showsSujoodProgress ? 0.5 : 0)
                        .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: side, height: side)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.7), value: showsSujoodProgress)
            .accessibilityHidden(true)
        }

        private var tasbihLink: some View {
            NavigationLink {
                TasbihView()
            } label: {
                Text("Start Tasbih")
                    .font(.headline)
            }
            .accessibilityIdentifier("rakaat-complete")
        }

        @ViewBuilder private var completionActions: some View {
            if let next = prayer.flatMap(PrayerProgress.followUp(after:)) {
                Button { continueWith(next) } label: {
                    Text("Start \(next.title)")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("rakaat-next-prayer")
                tasbihLink
                    .buttonStyle(.bordered)
            } else {
                tasbihLink
                    .buttonStyle(.borderedProminent)
            }
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
                .overlay(.thinMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(.black.opacity(0.3))
                .overlay {
                    // Darken the preview without adding screen light that can reflect into the camera.
                    Color.green.opacity(showsMilestoneTint ? 0.65 : 0)
                        .blendMode(.multiply)
                }
                .compositingGroup()
                .overlay(Color.green.opacity(update?.complete == true ? 0.32 : 0))
                .ignoresSafeArea()
                .accessibilityHidden(true)

                VStack(spacing: 20) {
                    if let failure = update?.failure {
                        Label(failure == .tooDark ? LocalizedStringKey("Too dark to count reliably") : LocalizedStringKey("Unable to calibrate"), systemImage: "exclamationmark.triangle")
                            .font(.title2.bold())
                        Text(failure == .tooDark ? LocalizedStringKey("Increase the light and keep the camera uncovered, then try again.") : LocalizedStringKey("Keep the phone still in steady light, then try again."))
                        Button("Try again") { Task { await returnToSelection() } }
                            .buttonStyle(.bordered)
                    } else if denied || failed {
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
                        ProgressView().tint(.white)
                        Text("Keep the camera uncovered in steady light while it calibrates.")
                            .font(.body)
                    } else {
                        if let prayer {
                            Text(prayer.title)
                                .font(.largeTitle.scaled(by: 1.25).bold())
                                .shadow(color: .black.opacity(0.6), radius: 8)
                        }
                        count
                            .shadow(color: .black.opacity(0.6), radius: 8)
                            .padding(24)
                            .background { sujoodRing }
                        if update?.complete == true {
                            ViewThatFits {
                                HStack(spacing: 12) { completionActions }
                                VStack(spacing: 12) { completionActions }
                            }
                        }
                    }
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(32)
            }
            .safeAreaInset(edge: .top) {
                if preparing {
                    RakaatQiblaHint(qibla: qibla)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(16)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("rakaat-prayer-screen")
        }

        private func continueWith(_ next: PrayerName) {
            prayer = next
            target = PrayerProgress.rakaat(for: next)
            recording = PrayerSessionRecording()
            // Keep showing a calibrated count so the calibration message doesn't flash before the first frame.
            update = .init(preview: update?.preview, count: 0, calibrated: true, complete: false)
            failed = false
            ended = false
            resuming = true
            session += 1
        }

        private func run(target: Int, resuming: Bool) async {
            guard !ended else { return }
            let authorized: Bool
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--rakaat-denied") {
                    denied = true; ended = true; return
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--rakaat-dark") {
                    update = .init(preview: nil, count: 0, calibrated: false, complete: false, failure: .tooDark)
                    ended = true
                    return
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--rakaat-demo") {
                    if !resuming {
                        update = .init(preview: nil, count: 0, calibrated: false, complete: false)
                        do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    }
                    guard !ended else { return }
                    accept(.init(preview: nil, count: 2, calibrated: true, complete: false))
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                    guard !ended else { return }
                    accept(.init(preview: nil, count: target * 2, calibrated: true, complete: true))
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
            // Dim before the camera locks exposure and measures its baseline; changing screen light after
            // calibration would shift the measured light.
            if let screen {
                dimmed = (screen, screen.brightness)
                screen.brightness = min(screen.brightness, 0.2)
            }
            do {
                // Resuming relies on the screen being dimmed as it was during calibration; fall back to recalibrating.
                let stream = if resuming, let resumed = try? await camera.resume(target: target) {
                    resumed
                } else {
                    try await camera.start(target: target)
                }
                for await value in stream {
                    guard !Task.isCancelled, !ended else { break }
                    accept(value)
                    if value.complete || value.failure != nil {
                        ended = true
                    }
                }
                if !ended, !Task.isCancelled {
                    failed = true; ended = true
                }
            } catch { failed = true; ended = true }
            await camera.stop()
            restoreScreen()
        }

        private func accept(_ value: RakaatCamera.Update) {
            update = value
            let now = Date.now
            if let completed = recording.update(calibrated: value.calibrated, complete: value.complete,
                                                failed: value.failure != nil, at: now, makeSnapshot: {
                                                    guard let prayer else { return nil }
                                                    return PrayerProgress.snapshot(prayer: prayer, at: now, location: model.location,
                                                                                   method: model.preferences.prayerMethod)
                                                })
            {
                history?.save(completed)
            }
        }

        private func restoreScreen() {
            if let oldIdleState {
                UIApplication.shared.isIdleTimerDisabled = oldIdleState
            }
            oldIdleState = nil
            if let dimmed {
                dimmed.screen.brightness = dimmed.brightness
            }
            dimmed = nil
        }

        private func returnToSelection() async {
            ended = true
            await camera.stop()
            restoreScreen()
            dismiss()
        }
    }

    /// Reports the screen of this view's own window scene.
    private struct WindowScreenReader: UIViewRepresentable {
        let onChange: (UIScreen?) -> Void

        func makeUIView(context _: Context) -> ReaderView {
            let view = ReaderView()
            view.onChange = onChange
            return view
        }

        func updateUIView(_ view: ReaderView, context _: Context) {
            view.onChange = onChange
        }

        final class ReaderView: UIView {
            var onChange: ((UIScreen?) -> Void)?

            override func didMoveToWindow() {
                super.didMoveToWindow()
                onChange?(window?.windowScene?.screen)
            }
        }
    }
#endif
