import CoreLocation
import Observation
import UIKit

@MainActor @Observable
final class QiblaLocationSession: NSObject, CLLocationManagerDelegate {
    enum Status { case locating, ready, settings, failed }
    private(set) var status: Status = .locating
    private(set) var location: CLLocation?
    private(set) var heading: CLHeading?
    private(set) var startedAt: Date?
    private let manager = CLLocationManager()
    private var requestedPrecision = false
    private let usesDeviceLocation: Bool

    init(usesDeviceLocation: Bool = true) {
        #if DEBUG
            self.usesDeviceLocation = usesDeviceLocation && !ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
            self.usesDeviceLocation = usesDeviceLocation
        #endif
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    static func accepts(_ location: CLLocation, since start: Date, now: Date) -> Bool {
        CLLocationCoordinate2DIsValid(location.coordinate)
            && location.horizontalAccuracy.isFinite
            && (0 ... 20).contains(location.horizontalAccuracy)
            && location.timestamp >= start
            && (0 ... 15).contains(now.timeIntervalSince(location.timestamp))
    }

    static func acceptsHeading(_ heading: Double, accuracy: Double, timestamp: Date, now: Date) -> Bool {
        heading.isFinite && (0 ..< 360).contains(heading)
            && accuracy.isFinite && (0 ... 10).contains(accuracy)
            && (0 ... 15).contains(now.timeIntervalSince(timestamp))
    }

    func start(now: Date = .now) {
        stop()
        startedAt = now
        status = .locating
        requestedPrecision = false
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                if ProcessInfo.processInfo.arguments.contains("--qibla-ready") {
                    location = CLLocation(coordinate: .init(latitude: 24.7136, longitude: 46.6753), altitude: 0,
                                          horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: now)
                    if ProcessInfo.processInfo.arguments.contains("--qibla-heading") {
                        heading = QiblaTestHeading(sampleTime: now, direction: ProcessInfo.processInfo.arguments.contains("--qibla-aligned") ? 244 : 90)
                    }
                    status = .ready
                } else {
                    status = .settings
                }
                return
            }
        #endif
        if usesDeviceLocation {
            authorize()
        }
    }

    func orientHeading(to orientation: UIInterfaceOrientation) {
        let deviceOrientation: CLDeviceOrientation
        switch orientation {
        case .portrait: deviceOrientation = .portrait
        case .portraitUpsideDown: deviceOrientation = .portraitUpsideDown
        case .landscapeLeft: deviceOrientation = .landscapeRight
        case .landscapeRight: deviceOrientation = .landscapeLeft
        default: return
        }
        guard manager.headingOrientation != deviceOrientation else { return }
        heading = nil
        manager.headingOrientation = deviceOrientation
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        startedAt = nil
        location = nil
        heading = nil
    }

    private func authorize() {
        guard usesDeviceLocation, startedAt != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard manager.accuracyAuthorization == .fullAccuracy else {
                location = nil
                heading = nil
                status = .settings
                manager.stopUpdatingLocation()
                manager.stopUpdatingHeading()
                if !requestedPrecision {
                    requestedPrecision = true
                    manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "QiblaPreciseLocation")
                }
                return
            }
            status = location == nil ? .locating : .ready
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        default:
            location = nil
            heading = nil
            status = .settings
            manager.stopUpdatingLocation()
            manager.stopUpdatingHeading()
        }
    }

    func refresh(now: Date = .now) {
        guard let startedAt else { return }
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
               ProcessInfo.processInfo.arguments.contains("--qibla-ready"), let location
            {
                if ProcessInfo.processInfo.arguments.contains("--qibla-heading") {
                    heading = QiblaTestHeading(sampleTime: now, direction: ProcessInfo.processInfo.arguments.contains("--qibla-aligned") ? 244 : 90)
                }
                // Simulate continuing GPS samples for screenshots, never a production fallback.
                receive([CLLocation(coordinate: location.coordinate, altitude: 0, horizontalAccuracy: 5,
                                    verticalAccuracy: -1, timestamp: now)], precise: true, now: now)
            }
        #endif
        if let heading, !Self.acceptsHeading(heading.trueHeading, accuracy: heading.headingAccuracy,
                                             timestamp: heading.timestamp, now: now)
        {
            self.heading = nil
        }
        if let location, !Self.accepts(location, since: startedAt, now: now) {
            self.location = nil
            status = .failed
        }
        if status == .locating, now.timeIntervalSince(startedAt) >= 30 {
            status = .failed
        }
    }

    func receive(_ locations: [CLLocation], precise: Bool, now: Date = .now) {
        guard let startedAt else { return }
        guard precise else {
            location = nil
            heading = nil
            status = .settings
            return
        }
        if let fix = locations.last(where: { Self.accepts($0, since: startedAt, now: now) }) {
            location = fix
            status = .ready
        } else {
            refresh(now: now)
        }
    }

    func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        authorize()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let authorized = manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
        receive(locations, precise: authorized && manager.accuracyAuthorization == .fullAccuracy)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard startedAt != nil, manager.accuracyAuthorization == .fullAccuracy,
              manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
        else { return }
        heading = Self.acceptsHeading(newHeading.trueHeading, accuracy: newHeading.headingAccuracy,
                                      timestamp: newHeading.timestamp, now: .now) ? newHeading : nil
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        guard startedAt != nil else { return }
        if (error as? CLError)?.code == .locationUnknown {
            return
        }
        location = nil
        heading = nil
        status = (error as? CLError)?.code == .denied ? .settings : .failed
    }
}

#if DEBUG
    private final class QiblaTestHeading: CLHeading {
        private let sampleTime: Date
        private let direction: Double

        init(sampleTime: Date, direction: Double) {
            self.sampleTime = sampleTime
            self.direction = direction
            super.init()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var trueHeading: CLLocationDirection {
            direction
        }

        override var magneticHeading: CLLocationDirection {
            direction
        }

        override var headingAccuracy: CLLocationDirection {
            5
        }

        override var timestamp: Date {
            sampleTime
        }
    }
#endif
