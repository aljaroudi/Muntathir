import SwiftUI
import UIKit

@MainActor @Observable
final class ProximityCounterService {
    private weak static var owner: ProximityCounterService?
    private var monitoring = false
    private(set) var available = false
    private(set) var near = false
    private(set) var counter: PrayerCounter?
    private var previousIdleSetting: Bool?

    func start(prayer: PrayerName) {
        guard available, counter == nil else { return }
        counter = PrayerCounter(prayer: prayer)
        previousIdleSetting = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        sample()
    }

    /// Owned by the presentation's SwiftUI task; cancellation always releases hardware.
    func monitor() async {
        Self.owner = self
        monitoring = true
        UIDevice.current.isProximityMonitoringEnabled = true
        available = UIDevice.current.isProximityMonitoringEnabled
        defer { releaseHardware() }
        guard available else { return }
        while !Task.isCancelled, monitoring {
            sample()
            if counter?.complete == true || counter?.interrupted == true || counter?.stopped == true {
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
        }
    }

    private func sample() {
        near = UIDevice.current.proximityState
        counter?.sample(near: near, at: ProcessInfo.processInfo.systemUptime)
    }

    func interrupt() {
        counter?.interrupt()
        releaseHardware()
    }

    func exit() {
        counter?.stop()
        releaseHardware()
    }

    private func releaseHardware() {
        monitoring = false
        if Self.owner === self {
            UIDevice.current.isProximityMonitoringEnabled = false
            Self.owner = nil
        }
        if let previousIdleSetting {
            UIApplication.shared.isIdleTimerDisabled = previousIdleSetting
            self.previousIdleSetting = nil
        }
    }
}
