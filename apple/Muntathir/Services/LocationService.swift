import CoreLocation
import MapKit
import Observation

@MainActor @Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    var results: [MKMapItem] = []
    var current: SavedLocation?
    var heading: Double?
    var headingAccuracy: Double?
    var message: String?
    var isBusy = false
    private let manager = CLLocationManager()
    private var requestID = UUID()
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func search(_ query: String) async {
        let id = UUID()
        requestID = id
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        isBusy = true
        message = nil
        defer {
            if requestID == id {
                isBusy = false
            }
        }
        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .address
            let response = try await MKLocalSearch(request: request).start()
            guard requestID == id, !Task.isCancelled else { return }
            results = response.mapItems
            if results.isEmpty {
                message = String(localized: "No places found.")
            }
        } catch {
            if requestID == id, !Task.isCancelled {
                message = String(
                    localized:
                    "Place search is unavailable. Try again when online."
                )
            }
        }
    }

    func saved(_ item: MKMapItem) -> SavedLocation? {
        guard let zone = item.timeZone else {
            message = String(
                localized: "This place has no time zone. Choose a nearby city."
            )
            return nil
        }
        let name = [item.addressRepresentations?.cityWithContext, item.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return SavedLocation(
            latitude: item.location.coordinate.latitude,
            longitude: item.location.coordinate.longitude,
            name: name ?? String(localized: "Selected location"),
            countryCode: item.addressRepresentations?.region?.identifier ?? "",
            timeZoneID: zone.identifier
        )
    }

    func locate() {
        message = nil
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            isBusy = true
            manager.requestLocation()
        default:
            message = String(
                localized:
                "Location access is disabled. Search for a city instead."
            )
        }
    }

    func startHeading() {
        guard CLLocationManager.headingAvailable() else {
            message = String(
                localized:
                "Compass unavailable. Use the bearing from true north."
            )
            return
        }
        manager.startUpdatingHeading()
    }

    func stopHeading() {
        manager.stopUpdatingHeading()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways
        {
            locate()
        }
    }

    func locationManager(
        _: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last, location.horizontalAccuracy >= 0,
              CLLocationCoordinate2DIsValid(location.coordinate)
        else { return }
        // Coordinates are sufficient. Device time zone supplies local civil time.
        current = SavedLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            name: String(localized: "Device location"),
            countryCode: "",
            timeZoneID: TimeZone.current.identifier
        )
        isBusy = false
    }

    func locationManager(
        _: CLLocationManager,
        didFailWithError _: Error
    ) {
        isBusy = false
        message = String(
            localized:
            "Could not find your location. Search for a city instead."
        )
    }

    func locationManager(
        _: CLLocationManager,
        didUpdateHeading newHeading: CLHeading
    ) {
        headingAccuracy = newHeading.headingAccuracy
        heading =
            newHeading.trueHeading >= 0 && newHeading.headingAccuracy >= 0
                ? newHeading.trueHeading : nil
    }
}
