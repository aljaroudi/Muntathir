import Foundation
@testable import Muntathir
import Testing

@MainActor struct QiblaAccuracyTests {
    @Test(arguments: [nil, -1, 10.001, 20, Double.nan, .infinity, -.infinity] as [Double?])
    func blocksUnreliableAccuracy(accuracy: Double?) {
        let service = LocationService()
        service.heading = 90
        service.headingAccuracy = accuracy
        #expect(service.hasAccurateHeading == false)
    }

    @Test(arguments: [nil, -1, 360, Double.nan, .infinity, -.infinity] as [Double?])
    func blocksInvalidHeadings(heading: Double?) {
        let service = LocationService()
        service.heading = heading
        service.headingAccuracy = 5
        #expect(service.hasAccurateHeading == false)
    }

    @Test(arguments: [0.0, 5, 10], [0.0, 90, 359.99])
    func acceptsAccurateHeadings(accuracy: Double, heading: Double) {
        let service = LocationService()
        service.heading = heading
        service.headingAccuracy = accuracy
        #expect(service.hasAccurateHeading)
    }

    @Test func respondsToRecoveryDegradationAndStopping() {
        let service = LocationService()
        #expect(service.hasAccurateHeading == false)
        service.heading = 90
        service.headingAccuracy = 5
        #expect(service.hasAccurateHeading)
        service.headingAccuracy = 11
        #expect(service.hasAccurateHeading == false)
        service.headingAccuracy = 10
        #expect(service.hasAccurateHeading)
        service.stopHeading(owner: UUID())
        #expect(service.hasAccurateHeading == false)
        #expect(service.heading == nil)
    }
}
