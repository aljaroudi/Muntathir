@testable import Muntathir
import Testing

struct HadithBookGroupTests {
    @Test func groupsCollectionsBySourceIdentity() {
        for id in ["bukhari", "muslim", "abudawud", "tirmidhi", "nasai", "ibnmajah"] {
            #expect(HadithBookGroup(collectionID: id) == .six)
        }
        for id in ["alkafi", "additional-Man-La-Yahduruh-al-Faqih-Saduq",
                   "additional-Tahdhib-al-Ahkam-Tusi", "additional-Al-Istibsar-Tusi"] {
            #expect(HadithBookGroup(collectionID: id) == .four)
        }
        #expect(HadithBookGroup(collectionID: "additional-Nahj-al-Balagha-Radi") == .other)
        #expect(HadithBookGroup(collectionID: "new-book") == .other)
        #expect(HadithBookGroup.allCases == [.six, .four, .other])
    }
}
