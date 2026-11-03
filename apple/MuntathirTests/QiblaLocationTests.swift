import CoreLocation
import MapKit
@testable import Muntathir
import Testing

@MainActor struct QiblaLocationTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fix(accuracy: Double = 5, age: Double = 0, latitude: Double = 24.7) -> CLLocation {
        CLLocation(coordinate: .init(latitude: latitude, longitude: 46.7), altitude: 0,
                   horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: now.addingTimeInterval(-age))
    }

    @Test(arguments: [-1, 20.001, Double.nan, .infinity])
    func rejectsPoorAccuracy(_ accuracy: Double) {
        #expect(!QiblaLocationSession.accepts(fix(accuracy: accuracy), since: now, now: now))
    }

    @Test(arguments: [0.0, 20])
    func acceptsAccuracyBoundary(_ accuracy: Double) {
        #expect(QiblaLocationSession.accepts(fix(accuracy: accuracy), since: now, now: now))
    }

    @Test func rejectsCachedFutureStaleAndInvalidFixes() {
        #expect(!QiblaLocationSession.accepts(fix(age: 1), since: now, now: now))
        #expect(!QiblaLocationSession.accepts(fix(age: -1), since: now, now: now))
        #expect(!QiblaLocationSession.accepts(fix(age: 15.01), since: now.addingTimeInterval(-30), now: now))
        #expect(QiblaLocationSession.accepts(fix(age: 15), since: now.addingTimeInterval(-30), now: now))
        #expect(!QiblaLocationSession.accepts(fix(latitude: 91), since: now, now: now))
    }

    @Test func preciseAuthorizationExpiryAndRecovery() {
        let session = QiblaLocationSession(usesDeviceLocation: false)
        session.start(now: now)
        session.receive([fix()], precise: false, now: now)
        #expect(session.location == nil)
        #expect(session.status == .settings)
        session.receive([fix()], precise: true, now: now)
        #expect(session.status == .ready)
        session.refresh(now: now.addingTimeInterval(16))
        #expect(session.location == nil)
        #expect(session.status == .failed)
        session.receive([fix(age: -16)], precise: true, now: now.addingTimeInterval(16))
        #expect(session.status == .ready)
        session.receive([fix(age: -16)], precise: false, now: now.addingTimeInterval(16))
        #expect(session.location == nil)
    }

    @Test func restartAndStopRejectEarlierCallbacks() {
        let session = QiblaLocationSession(usesDeviceLocation: false)
        session.start(now: now)
        session.receive([fix()], precise: true, now: now)
        session.start(now: now.addingTimeInterval(1))
        #expect(session.location == nil)
        session.receive([fix()], precise: true, now: now.addingTimeInterval(1))
        #expect(session.location == nil)
        session.stop()
        session.receive([fix(age: -2)], precise: true, now: now.addingTimeInterval(2))
        #expect(session.location == nil)
    }

    @Test func denialAndFailureHideResults() {
        let session = QiblaLocationSession(usesDeviceLocation: false)
        let manager = CLLocationManager()
        session.start(now: now)
        session.receive([fix()], precise: true, now: now)
        session.locationManager(manager, didFailWithError: CLError(.denied))
        #expect(session.status == .settings)
        #expect(session.location == nil)
        session.start(now: now)
        session.locationManager(manager, didFailWithError: CLError(.network))
        #expect(session.status == .failed)
        #expect(session.location == nil)
    }

    @Test func qiblaPermissionDoesNotRequestPrayerLocation() {
        let prayerLocation = LocationService()
        prayerLocation.locationManagerDidChangeAuthorization(AuthorizedLocationManager())
        #expect(prayerLocation.current == nil)
        #expect(prayerLocation.message == nil)
        #expect(!prayerLocation.isBusy)
    }

    @Test(arguments: [320.0, 720.0])
    func mapKeepsBuildingScaleAcrossWidths(_ width: Double) {
        let map = QiblaMapView(frame: CGRect(x: 0, y: 0, width: width, height: 400))
        map.centerOnFix(.init(latitude: 24.7, longitude: 46.7))
        map.layoutIfNeeded()
        let meters = map.visibleMapRect.width * MKMetersPerMapPointAtLatitude(24.7)
        #expect((140 ... 160).contains(meters))
        #expect(abs(map.camera.heading) < 0.01)
        #expect(abs(map.camera.pitch) < 0.01)
    }

    @Test func timeoutAndRetry() {
        let session = QiblaLocationSession(usesDeviceLocation: false)
        session.start(now: now)
        session.refresh(now: now.addingTimeInterval(30))
        #expect(session.status == .failed)
        session.start(now: now.addingTimeInterval(31))
        #expect(session.status == .locating)
        session.receive([fix(age: -31)], precise: true, now: now.addingTimeInterval(31))
        #expect(session.status == .ready)
    }

    @Test(arguments: [-1.0, 10.001, Double.nan, .infinity])
    func rejectsUnreliableHeading(_ accuracy: Double) {
        #expect(!QiblaLocationSession.acceptsHeading(90, accuracy: accuracy, timestamp: now, now: now))
    }

    @Test func headingAccuracyAndFreshness() {
        #expect(QiblaLocationSession.acceptsHeading(90, accuracy: 10, timestamp: now, now: now))
        #expect(!QiblaLocationSession.acceptsHeading(-1, accuracy: 5, timestamp: now, now: now))
        #expect(!QiblaLocationSession.acceptsHeading(360, accuracy: 5, timestamp: now, now: now))
        #expect(!QiblaLocationSession.acceptsHeading(90, accuracy: 5, timestamp: now, now: now.addingTimeInterval(16)))
    }

    @Test(arguments: [CLLocationCoordinate2D(latitude: 24.7, longitude: 46.7),
                      CLLocationCoordinate2D(latitude: 37.8, longitude: -122.4),
                      CLLocationCoordinate2D(latitude: -36.8, longitude: 174.8)])
    func geodesicMatchesQibla(_ coordinate: CLLocationCoordinate2D) {
        var coordinates = [coordinate, QiblaMap.kaaba]
        let line = MKGeodesicPolyline(coordinates: &coordinates, count: 2)
        let first = line.points()[0]
        let next = line.points()[1]
        let width = MKMapRect.world.size.width
        var dx = next.x - first.x
        if dx > width / 2 {
            dx -= width
        }
        if dx < -width / 2 {
            dx += width
        }
        let direction = (atan2(dx, first.y - next.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let saved = SavedLocation(latitude: coordinate.latitude, longitude: coordinate.longitude,
                                  name: "Test", countryCode: "", timeZoneID: "UTC")
        let difference = abs(direction - PrayerCalculator.qibla(saved))
        #expect(min(difference, 360 - difference) < 1)
    }
}

private final class AuthorizedLocationManager: CLLocationManager {
    override var authorizationStatus: CLAuthorizationStatus {
        .authorizedWhenInUse
    }
}
