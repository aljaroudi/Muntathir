import Foundation
@testable import Muntathir
import Testing

struct HadithBookGroupTests {
    @Test func groupsCollectionsBySourceIdentity() {
        for id in ["bukhari", "muslim", "abudawud", "tirmidhi", "nasai", "ibnmajah"] {
            #expect(HadithBookGroup(collectionID: id) == .six)
        }
        for id in ["alkafi", "additional-Man-La-Yahduruh-al-Faqih-Saduq",
                   "additional-Tahdhib-al-Ahkam-Tusi", "additional-Al-Istibsar-Tusi"]
        {
            #expect(HadithBookGroup(collectionID: id) == .four)
        }
        #expect(HadithBookGroup(collectionID: "additional-Nahj-al-Balagha-Radi") == .other)
        #expect(HadithBookGroup(collectionID: "new-book") == .other)
        #expect(HadithBookGroup.allCases == [.four, .six, .other])
    }

    @Test func scopedRequestsSurviveSessionCoding() throws {
        let legacy = try JSONDecoder().decode(HadithRequest.self, from: Data(#"{"query":"x","cursor":{"phase":0,"afterID":0}}"#.utf8))
        #expect(legacy.group == nil)
        let scoped = HadithRequest(query: "x", group: .six)
        #expect(try JSONDecoder().decode(HadithRequest.self, from: JSONEncoder().encode(scoped)) == scoped)
    }
}
