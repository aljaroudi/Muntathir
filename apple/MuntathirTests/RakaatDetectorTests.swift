@testable import Muntathir
import Testing

struct RakaatDetectorTests {
    private func feed(_ light: Double, seconds: Double, detector: inout RakaatDetector, time: inout Double) {
        for _ in 0 ..< Int(seconds * 10) {
            time += 0.1
            detector.sample(light, at: time)
        }
    }

    @Test(arguments: [2, 3, 4])
    func countsPairsAndStopsAtTarget(_ target: Int) {
        var detector = RakaatDetector(target: target)
        var time = 0.0
        feed(0.8, seconds: 2, detector: &detector, time: &time)
        #expect(detector.baseline != nil)
        for sujood in 1 ... target * 2 {
            feed(0.1, seconds: 2, detector: &detector, time: &time)
            #expect(detector.sujoodCount == sujood)
            #expect(detector.rakaat == sujood / 2)
            feed(0.8, seconds: 1, detector: &detector, time: &time)
        }
        #expect(detector.complete)
        feed(0.1, seconds: 3, detector: &detector, time: &time)
        #expect(detector.sujoodCount == target * 2)
    }

    @Test func rejectsBriefShadowsAndRequiresSustainedRecovery() {
        var detector = RakaatDetector(target: 2)
        var time = 0.0
        feed(0.8, seconds: 2, detector: &detector, time: &time)
        for _ in 0 ..< 5 {
            feed(0.1, seconds: 0.3, detector: &detector, time: &time)
            feed(0.8, seconds: 0.3, detector: &detector, time: &time)
        }
        #expect(detector.sujoodCount == 0)
        feed(0.1, seconds: 10, detector: &detector, time: &time)
        #expect(detector.sujoodCount == 1)
        feed(0.8, seconds: 0.3, detector: &detector, time: &time)
        feed(0.1, seconds: 2, detector: &detector, time: &time)
        #expect(detector.sujoodCount == 1)
        feed(0.8, seconds: 1, detector: &detector, time: &time)
        feed(0.1, seconds: 1, detector: &detector, time: &time)
        #expect(detector.sujoodCount == 2)
    }

    @Test func calibrationNeedsStableUsableLight() {
        var detector = RakaatDetector(target: 2)
        var time = 0.0
        feed(0.02, seconds: 3, detector: &detector, time: &time)
        #expect(detector.baseline == nil)
        for _ in 0 ..< 20 {
            feed(0.2, seconds: 0.1, detector: &detector, time: &time)
            feed(0.8, seconds: 0.1, detector: &detector, time: &time)
        }
        #expect(detector.baseline == nil)
        feed(0.8, seconds: 2, detector: &detector, time: &time)
        #expect(detector.baseline != nil)
        #expect(detector.sujoodCount == 0)
    }

    @Test func gapsAndInvalidSamplesCannotCompleteADarkTransition() {
        var detector = RakaatDetector(target: 2)
        var time = 0.0
        feed(0.8, seconds: 2, detector: &detector, time: &time)
        feed(0.1, seconds: 0.3, detector: &detector, time: &time)
        detector.sample(.nan, at: time + 0.1)
        detector.sample(0.1, at: time - 1)
        time += 2
        feed(0.1, seconds: 0.3, detector: &detector, time: &time)
        #expect(detector.sujoodCount == 0)
    }

    @Test func gradualLightDriftDoesNotCount() {
        var detector = RakaatDetector(target: 2)
        var time = 0.0
        feed(0.8, seconds: 2, detector: &detector, time: &time)
        for index in 0 ..< 200 {
            feed(0.8 - Double(index) * 0.001, seconds: 0.1, detector: &detector, time: &time)
        }
        #expect(detector.sujoodCount == 0)
        #expect((detector.baseline ?? 1) < 0.8)
    }
}
