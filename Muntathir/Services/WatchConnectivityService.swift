import Observation
import WatchConnectivity
import WidgetKit

@MainActor @Observable
final class WatchConnectivityService: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityService()
    private(set) var settings = WatchSettings.read()
    private(set) var syncError: String?
    private var pending: WatchSettings?

    override private init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ settings: WatchSettings) {
        pending = settings
        flush()
    }

    func refresh() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.activationState != .activated {
            session.activate()
            return
        }
        #if os(watchOS)
            receive(session.receivedApplicationContext[WatchSettings.storageKey] as? Data)
        #else
            flush()
        #endif
    }

    #if os(watchOS)
        /// Keep the background task alive until WCSession has delivered its context.
        func finishBackgroundTransfer() async {
            refresh()
            let session = WCSession.default
            while session.activationState != .activated || session.hasContentPending {
                guard syncError == nil else { return }
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
            refresh()
        }
    #endif

    private func flush() {
        #if os(iOS)
            guard WCSession.isSupported(), let pending else { return }
            let session = WCSession.default
            guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
            do {
                let data = try pending.encoded()
                if session.applicationContext[WatchSettings.storageKey] as? Data != data {
                    try session.updateApplicationContext([WatchSettings.storageKey: data])
                }
                syncError = nil
            } catch {
                syncError = error.localizedDescription
            }
        #endif
    }

    private func receive(_ data: Data?) {
        #if os(watchOS)
            guard let data else { return }
            do {
                let value = try WatchSettings.receive(data)
                if value != settings {
                    settings = value
                    WidgetCenter.shared.reloadAllTimelines()
                }
                syncError = nil
            } catch {
                syncError = String(localized: "Unable to sync settings. Open Muntathir on your iPhone.")
            }
        #endif
    }

    nonisolated func session(_: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            guard activationState == .activated else {
                syncError = error?.localizedDescription
                return
            }
            syncError = nil
            refresh()
        }
    }

    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[WatchSettings.storageKey] as? Data
        Task { @MainActor in receive(data) }
    }

    nonisolated func sessionReachabilityDidChange(_: WCSession) {
        Task { @MainActor in refresh() }
    }

    #if os(iOS)
        nonisolated func sessionDidBecomeInactive(_: WCSession) {}
        nonisolated func sessionDidDeactivate(_ session: WCSession) {
            session.activate()
        }

        nonisolated func sessionWatchStateDidChange(_: WCSession) {
            Task { @MainActor in flush() }
        }
    #endif
}
