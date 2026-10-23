import Foundation
@testable import Muntathir
import Testing

#if DEBUG
    struct CaptureClockTests {
        @Test func requiresExplicitTestMode() {
            #expect(CaptureClock(arguments: ["--sky-date", "2026-10-21T03:19:00Z"]) == nil)
            #expect(CaptureClock(arguments: ["--ui-testing", "--sky-date"]) == nil)
            #expect(CaptureClock(arguments: ["--ui-testing", "--sky-date", "invalid"]) == nil)
        }

        @Test func clampsAndInterpolates() throws {
            let clock = try #require(CaptureClock(arguments: ["--ui-testing", "--sky-date", "2026-10-21T03:19:00Z",
                                                              "--sky-end", "2026-10-21T14:52:00Z", "--sky-duration", "20",
                                                              "--sky-begins-at", "1000"]))
            #expect(clock.date(at: Date(timeIntervalSince1970: 999)) == clock.start)
            #expect(clock.date(at: Date(timeIntervalSince1970: 1010)) == clock.start.addingTimeInterval(clock.end.timeIntervalSince(clock.start) / 2))
            #expect(clock.date(at: Date(timeIntervalSince1970: 1021)) == clock.end)
            #expect(clock.isAnimated)
        }

        @Test func fixedDateAndInvalidDurationStaySafe() throws {
            let clock = try #require(CaptureClock(arguments: ["--ui-testing", "--sky-date", "2026-10-21T03:19:00Z",
                                                              "--sky-duration", "nan"]))
            #expect(clock.isAnimated == false)
            #expect(clock.duration == 20)
            #expect(clock.date(at: .distantFuture) == clock.start)
        }
    }
#endif
