@testable import Muntathir
import Testing

struct QiblaAlignmentTests {
    @Test func shortestTurnAcrossNorth() throws {
        #expect(try #require(QiblaAlignment(bearing: 2, heading: 358)).error == 4)
        #expect(try #require(QiblaAlignment(bearing: 358, heading: 2)).error == -4)
        #expect(try #require(QiblaAlignment(bearing: 180, heading: 0)).error == -180)
    }

    @Test func alignmentHysteresis() throws {
        let close = try #require(QiblaAlignment(bearing: 5, heading: 0))
        #expect(close.isAligned(previously: false))
        let edge = try #require(QiblaAlignment(bearing: 8, heading: 0))
        #expect(!edge.isAligned(previously: false))
        #expect(edge.isAligned(previously: true))
        #expect(try !#require(QiblaAlignment(bearing: 8.01, heading: 0)).isAligned(previously: true))
    }

    @Test func feedbackStrengthAndSilence() throws {
        let far = try #require(QiblaAlignment(bearing: 61, heading: 0))
        #expect(far.feedback(aligned: false) == .none)
        #expect(far.feedback(aligned: false).pulse == nil)
        let gentle = try #require(QiblaAlignment(bearing: 60, heading: 0)).feedback(aligned: false)
        let medium = try #require(QiblaAlignment(bearing: 30, heading: 0)).feedback(aligned: false)
        let strong = try #require(QiblaAlignment(bearing: 10, heading: 0)).feedback(aligned: false)
        #expect(gentle == .gentle)
        #expect(medium == .medium)
        #expect(strong == .strong)
        #expect(try #require(gentle.pulse).intensity < #require(medium.pulse).intensity)
        #expect(try #require(medium.pulse).intensity < #require(strong.pulse).intensity)
        #expect(try #require(gentle.pulse).interval > #require(strong.pulse).interval)
        let aligned = try #require(QiblaAlignment(bearing: 3, heading: 0)).feedback(aligned: true)
        #expect(aligned == .aligned)
        #expect(aligned.pulse == nil)
    }

    @Test(arguments: [Double.nan, .infinity, -1, 360])
    func invalidReadingsNeverGuide(_ value: Double) {
        #expect(QiblaAlignment(bearing: value, heading: 0) == nil)
        #expect(QiblaAlignment(bearing: 0, heading: value) == nil)
    }
}
