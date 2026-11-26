import Foundation
@testable import Muntathir
import Testing

struct AppIntentsTests {
    @Test func surahsResolveByNumberAndName() async throws {
        let query = SurahQuery()
        let byID = try await query.entities(for: [36, 1, 999])
        #expect(byID.map(\.id) == [36, 1])
        #expect(try await query.suggestedEntities().count == 114)
        #expect(try await query.entities(matching: "Yaseen").map(\.id).contains(36))
        #expect(try await query.entities(matching: "kahf").map(\.id).contains(18))
        #expect(try await query.entities(matching: "الكهف").map(\.id).contains(18))
        #expect(try await query.entities(matching: "2").map(\.id) == [2])
    }

    @Test func ayahsResolveByReference() async throws {
        let query = AyahQuery()
        let ayah = try #require(try await query.entities(for: ["2:255"]).first)
        #expect(ayah.id == "2:255")
        #expect(ayah.surah == 2 && ayah.verse == 255)
        #expect(!ayah.text.isEmpty)
        #expect(try await query.entities(matching: "112:1").map(\.id) == ["112:1"])
        #expect(try await query.entities(for: ["not-a-verse", "115:1"]).isEmpty)
    }

    @Test func figuresAndEventsRoundTrip() async throws {
        let figures = try await FigureQuery().suggestedEntities()
        let figure = try #require(figures.first)
        #expect(try await FigureQuery().entities(for: [figure.id]).map(\.id) == [figure.id])

        let events = try await IslamicEventQuery().suggestedEntities()
        let event = try #require(events.first)
        #expect(try await IslamicEventQuery().entities(for: [event.id]).map(\.id) == [event.id])
    }

    @Test(arguments: [
        Rulings.ID(authority: "sistani", language: "en", siteID: "123"),
        Rulings.ID(authority: "a:b", language: "ar", siteID: "١٢:٣"),
        Rulings.ID(authority: "", language: "", siteID: ""),
    ])
    func rulingKeysRoundTrip(id: Rulings.ID) {
        #expect(Rulings.ID(key: id.key) == id)
    }

    @Test func malformedRulingKeysAreRejected() {
        #expect(Rulings.ID(key: "3:abc") == nil)
        #expect(Rulings.ID(key: "9:short") == nil)
        #expect(Rulings.ID(key: "x:abc") == nil)
    }

    @Test func toolsAndPrayersHaveDisplayNames() {
        for tool in AppTool.allCases {
            #expect(AppTool.caseDisplayRepresentations[tool] != nil)
        }
        for prayer in PrayerName.allCases {
            #expect(PrayerName.caseDisplayRepresentations[prayer] != nil)
        }
    }

    @MainActor @Test func searchIsTakenOnlyByItsTool() {
        let router = IntentRouter.shared
        router.search = IntentRouter.Search(tool: .quran, term: "patience")
        #expect(router.takeSearch(for: .figures) == nil)
        #expect(router.takeSearch(for: .quran) == "patience")
        #expect(router.search == nil)
    }
}
