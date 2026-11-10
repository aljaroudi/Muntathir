import CoreLocation
@testable import Muntathir
import Testing

@MainActor struct RakaatQiblaTests {
    @Test func optionalModeAcceptsRecentCachedLocationButExpiresIt() {
        let now = Date.now
        let fix = CLLocation(coordinate: .init(latitude: 24.7, longitude: 46.7), altitude: 0,
                             horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: now.addingTimeInterval(-10))
        let session = QiblaLocationSession(usesDeviceLocation: false, optional: true)
        session.start(now: now)
        session.receive([fix], precise: true, now: now)
        #expect(session.location == fix)
        session.refresh(now: now.addingTimeInterval(6))
        #expect(session.location == nil)
        session.receive([fix], precise: false, now: now)
        #expect(session.location == nil)
    }

    @Test func optionalModeNeverRequestsAuthorization() {
        let manager = RakaatLocationManager()
        let session = QiblaLocationSession(optional: true, manager: manager)
        session.start()
        #expect(manager.permissionRequests == 0)
        #expect(manager.locationStarts == 0)
        #expect(session.location == nil)
        manager.authorized = true
        manager.precise = false
        session.locationManagerDidChangeAuthorization(manager)
        #expect(manager.permissionRequests == 0)
        #expect(manager.locationStarts == 0)
        #expect(session.location == nil)
    }

    @Test func optionalModeUsesAuthorizedAccurateFix() {
        let manager = RakaatLocationManager()
        manager.authorized = true
        manager.precise = true
        let session = QiblaLocationSession(optional: true, manager: manager)
        session.start()
        #expect(manager.permissionRequests == 0)
        #expect(manager.locationStarts == 1)
        #expect(session.location != nil)
        session.stop()
        #expect(session.location == nil)
        #expect(session.heading == nil)
    }
}

private final class RakaatLocationManager: CLLocationManager {
    var authorized = false
    var precise = true
    var permissionRequests = 0
    var locationStarts = 0
    override var authorizationStatus: CLAuthorizationStatus {
        authorized ? .authorizedWhenInUse : .notDetermined
    }

    override var accuracyAuthorization: CLAccuracyAuthorization {
        precise ? .fullAccuracy : .reducedAccuracy
    }

    override var location: CLLocation? {
        CLLocation(coordinate: .init(latitude: 24.7, longitude: 46.7), altitude: 0,
                   horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: .now)
    }

    override func requestWhenInUseAuthorization() {
        permissionRequests += 1
    }

    override func requestTemporaryFullAccuracyAuthorization(withPurposeKey _: String) {
        permissionRequests += 1
    }

    override func startUpdatingLocation() {
        locationStarts += 1
    }

    override func stopUpdatingLocation() {}
    override func startUpdatingHeading() {}
    override func stopUpdatingHeading() {}
}
