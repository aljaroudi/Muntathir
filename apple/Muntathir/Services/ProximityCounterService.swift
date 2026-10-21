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

    private var simulatesSensor: Bool {
        #if DEBUG && targetEnvironment(simulator)
            let arguments = ProcessInfo.processInfo.arguments
            return arguments.contains("--ui-testing") && arguments.contains("--ui-testing-counter-sensor")
        #else
            return false
        #endif
    }

    func start(prayer: PrayerName) {
        guard available, monitoring, counter == nil else { return }
        near = UIDevice.current.proximityState
        guard !near else { return }
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
        available = UIDevice.current.isProximityMonitoringEnabled || simulatesSensor
        defer { releaseHardware() }
        guard available else { return }
        if simulatesSensor {
            // Keep UI tests idle; simulator availability does not simulate sensor samples.
            try? await Task.sleep(for: .seconds(3600))
            return
        }
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
