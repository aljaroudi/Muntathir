import Foundation
@testable import Muntathir
import Testing

struct ReadingTimeTests {
    @Test(arguments: [(0, 0), (1, 1), (200, 1), (201, 2), (11800, 59), (11801, 60), (12001, 61)])
    func roundsUp(words: Int, minutes: Int) {
        #expect(ReadingTime.minutes(words: words) == minutes)
    }

    @Test func usesOneUnitAndOmitsEmptyText() throws {
        #expect(ReadingTime.duration(words: 0) == nil)
        let short = try #require(ReadingTime.duration(words: 11800))
        #expect(short.unit == .minutes)
        #expect(short.value == 59)
        let hour = try #require(ReadingTime.duration(words: 11801))
        #expect(hour.unit == .hours)
        #expect(hour.value == 1)
        #expect(ReadingTime.duration(words: 12001)?.value == 2)
    }

    @Test func primaryTextExcludesFormattingAndTranslation() {
        #expect(ReadingTime.words(arabic: "نص عربي", english: "A much longer English translation") == 2)
        #expect(ReadingTime.words(arabic: " \n", english: "**Two** [words](https://example.com)") == 2)
        #expect(ReadingTime.words(arabic: "# عنوان\n\nنص آخر") == 3)
        #expect(ReadingTime.words(arabic: "١٢٣ - …") == 0)
    }
}
