import Foundation
@testable import Muntathir
import Testing

struct PrayerCounterTests {
    @Test(arguments: [PrayerName.fajr, .dhuhr, .asr, .maghrib, .isha])
    func eachPrayerCountsPairsAndStops(prayer: PrayerName) throws {
        let expected = [PrayerName.fajr: 2, .dhuhr: 4, .asr: 4, .maghrib: 3, .isha: 4]
        let total = try #require(expected[prayer])
        var counter = PrayerCounter(prayer: prayer)
        #expect(counter.total == total)
        #expect(counter.rakaa == 1)
        arm(&counter)
        for index in 0 ..< (total * 2) {
            cycle(&counter, at: Double(index * 4 + 2))
            #expect(counter.sujoods == index + 1)
            #expect(counter.rakaa == min((index + 1) / 2 + 1, total))
            #expect(counter.firstSujood == (index % 2 == 0))
        }
        #expect(counter.complete)
        #expect(counter.firstSujood == false)
        cycle(&counter, at: 100)
        counter.interrupt()
        #expect(counter.sujoods == total * 2)
        #expect(counter.interrupted == false)
        #expect(PrayerName.sunset.rakaaCount == nil)
    }

    @Test func initiallyCoveredDoesNotCount() {
        var counter = PrayerCounter(prayer: .fajr)
        counter.sample(near: true, at: 0)
        counter.sample(near: true, at: 5)
        counter.sample(near: false, at: 6)
        counter.sample(near: false, at: 7)
        #expect(counter.sujoods == 0)
        cycle(&counter, at: 8)
        #expect(counter.sujoods == 1)
    }

    @Test func shortObstructionAndDuplicateSamplesDoNotCountTwice() {
        var counter = PrayerCounter(prayer: .fajr)
        arm(&counter)
        counter.sample(near: true, at: 2)
        counter.sample(near: false, at: 2.3)
        counter.sample(near: false, at: 3.4)
        #expect(counter.sujoods == 0)
        counter.sample(near: true, at: 4)
        counter.sample(near: true, at: 4.5)
        counter.sample(near: true, at: 5)
        #expect(counter.sujoods == 0)
        counter.sample(near: false, at: 6)
        counter.sample(near: false, at: 6.2)
        #expect(counter.sujoods == 0)
        counter.sample(near: false, at: 6.5)
        counter.sample(near: false, at: 7)
        #expect(counter.sujoods == 1)
    }

    @Test func farBounceDoesNotCreateExtraSujood() {
        var counter = PrayerCounter(prayer: .fajr)
        arm(&counter)
        counter.sample(near: true, at: 2)
        counter.sample(near: false, at: 3)
        counter.sample(near: true, at: 3.1)
        counter.sample(near: false, at: 4)
        counter.sample(near: false, at: 5)
        #expect(counter.sujoods == 0)
        cycle(&counter, at: 6)
        #expect(counter.sujoods == 1)
    }

    @Test(arguments: [false, true])
    func interruptionAndExitDiscardPendingCycle(exit: Bool) {
        var counter = PrayerCounter(prayer: .fajr)
        arm(&counter)
        cycle(&counter, at: 2)
        counter.sample(near: true, at: 6)
        counter.sample(near: false, at: 7)
        if exit {
            counter.stop()
        } else {
            counter.interrupt()
        }
        counter.sample(near: false, at: 8)
        cycle(&counter, at: 10)
        #expect(counter.sujoods == 1)
        #expect(counter.firstSujood)
        #expect(counter.stopped == exit)
        #expect(counter.interrupted == !exit)
    }

    private func arm(_ counter: inout PrayerCounter) {
        counter.sample(near: false, at: 0)
        counter.sample(near: false, at: 1)
    }

    private func cycle(_ counter: inout PrayerCounter, at time: Double) {
        counter.sample(near: true, at: time)
        counter.sample(near: false, at: time + 1)
        counter.sample(near: false, at: time + 2)
    }
}
