import AVFoundation
import SwiftUI

struct RakaatSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var camera = RakaatCamera()
    @State private var qibla = QiblaLocationSession(optional: true)
    let target: Int
    @State private var update: RakaatCamera.Update?
    @State private var ended = false
    @State private var denied = false
    @State private var failed = false
    @State private var oldIdleState: Bool?

    private var preparing: Bool {
        !ended && update?.calibrated != true
    }

    private var showsQibla: Bool {
        preparing && scenePhase == .active
    }

    var body: some View {
        prayerView
            .background { RakaatHeadingOrientation(onChange: qibla.orientHeading).allowsHitTesting(false) }
            .navigationTitle("Rakaat Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .task(id: target) {
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
            .onDisappear {
                ended = true
                qibla.stop()
                restoreIdle()
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
            .overlay(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .overlay(.black.opacity(0.25))
            .overlay {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Color.black.opacity(0.45)
                            .frame(height: showsSujoodProgress ? geometry.size.height / 2 : 0)
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.7), value: showsSujoodProgress)
                }
            }
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
                RakaatQiblaHint(qibla: qibla)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(16)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rakaat-prayer-screen")
    }

    private func run(target: Int) async {
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
                update = .init(preview: nil, count: 0, calibrated: false, complete: false)
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard !ended else { return }
                update = .init(preview: nil, count: 2, calibrated: true, complete: false)
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard !ended else { return }
                update = .init(preview: nil, count: target * 2, calibrated: true, complete: true)
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
                if value.complete || value.failure != nil {
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
        dismiss()
    }
}
