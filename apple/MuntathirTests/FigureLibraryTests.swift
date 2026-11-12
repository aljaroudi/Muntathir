import Foundation
@testable import Muntathir
import Testing

struct FigureLibraryTests {
    @Test func productionDataRetainsDateAlternativesAndSearchesAliases() throws {
        let library = try productionLibrary()
        let prophet = try #require(library.byID["prophet-muhammad"])
        let arabic = try #require(prophet.displayNames["ar"])
        let english = try #require(prophet.displayNames["en"])
        #expect(prophet.title(Locale(identifier: "ar-SA")) == arabic)
        #expect(prophet.title(Locale(identifier: "fr-FR")) == english)
        #expect(library.search("مُحَمَّد", locale: Locale(identifier: "ar")).contains { $0.id == prophet.id })
        #expect(library.search("MUHAMMAD", locale: Locale(identifier: "en")).first?.id == prophet.id)
        #expect(Set(prophet.birthDates.map(\.status)) == [.accepted])
        #expect(library.events[prophet.id]?.contains { $0.id == "prophet-khadija-marriage" } == true)
    }

    @Test func productionDataUsesSimplifiedNames() throws {
        let library = try productionLibrary()
        let prophet = try #require(library.byID["prophet-muhammad"])
        #expect(prophet.names(.personal, locale: Locale(identifier: "ar")) == ["محمد"])
        #expect(prophet.names(.full, locale: Locale(identifier: "ar")) == ["محمد بن عبد الله"])
    }

    @Test func exampleDerivesFullAndHalfSiblingsAndGroupsChildren() throws {
        let library = try FigureLibrary(data: exampleData(), verifiedOnly: false)
        let id = "example-child-a"
        let claim = try #require(library.parents[id]?.first)
        let siblings = library.siblings(of: id, account: claim)
        #expect(siblings[.full]?.map(\.id) == ["example-child-b"])
        #expect(siblings[.half]?.map(\.id) == ["example-child-c"])
        #expect(library.partners["example-father"]?.count == 2)
        #expect(library.childGroups(of: "example-father").map(\.count) == [2, 1])
    }

    @Test func unknownParentAndConflictingAccountsStaySeparate() throws {
        var dataset = try #require(JSONSerialization.jsonObject(with: exampleData()) as? [String: Any])
        var parentages = try #require(dataset["parentages"] as? [[String: Any]])
        parentages[2]["mother_id"] = NSNull()
        parentages[2].removeValue(forKey: "union_id")
        dataset["parentages"] = parentages
        let unknown = try FigureLibrary(data: JSONSerialization.data(withJSONObject: dataset), verifiedOnly: false)
        let first = try #require(unknown.parents["example-child-a"]?.first)
        #expect(unknown.siblings(of: first.childId, account: first)[.unknown]?.map(\.id) == ["example-child-c"])

        var alternative = parentages[2]
        alternative["id"] = "alternate-parentage"
        alternative["mother_id"] = "example-mother-a"
        parentages.append(alternative)
        dataset["parentages"] = parentages
        let conflict = try FigureLibrary(data: JSONSerialization.data(withJSONObject: dataset), verifiedOnly: false)
        #expect(conflict.childGroups(of: "example-father").flatMap(\.self).count == 2)
        #expect(conflict.childGroups(of: "example-father", choices: ["example-child-c": "alternate-parentage"])
            .flatMap(\.self).count == 3)

        parentages[2]["father_id"] = "missing-person"
        dataset["parentages"] = parentages
        let invalid = try JSONSerialization.data(withJSONObject: dataset)
        #expect(throws: FigureLibrary.Failure.invalidRelationships) { try FigureLibrary(data: invalid, verifiedOnly: false) }
    }

    @Test func bundledStoreLoadsWithoutNetwork() async throws {
        let library = try await FigureStore().load().get()
        #expect(!library.people.isEmpty)
        #expect(library.people.allSatisfy { $0.verified == true })
        #expect(library.byID["abbas-ibn-ali"]?.deathDates.first?.citations.isEmpty == true)
    }

    @Test func unverifiedPeopleAndTheirRelationshipsAreExcluded() throws {
        var dataset = try #require(JSONSerialization.jsonObject(with: exampleData()) as? [String: Any])
        var people = try #require(dataset["people"] as? [[String: Any]])
        #expect(try FigureLibrary(data: exampleData()).people.isEmpty)
        for index in people.indices {
            people[index]["verified"] = true
        }
        people[0]["verified"] = false
        let excluded = try #require(people[0]["id"] as? String)
        dataset["people"] = people
        let library = try FigureLibrary(data: JSONSerialization.data(withJSONObject: dataset))
        #expect(library.byID[excluded] == nil)
        #expect(library.parents.values.flatMap(\.self).allSatisfy {
            $0.childId != excluded && !$0.parentIDs.contains(excluded)
        })
        #expect(library.partners.values.flatMap(\.self).allSatisfy { !$0.partnerIds.contains(excluded) })
    }

    @Test func claimNotesAcceptLocalizedAndLegacyTextAndCitationsCanBeAbsent() throws {
        let base = #"{"calendar":"hijri","era":"AH","precision":"exact","start":{"year":61,"month":1,"day":10},"original":"61 AH","status":"accepted","notes":NOTES}"#
        for notes in [#"{"ar":"ملاحظة","en":"Note"}"#, #""Note""#] {
            let date = try JSONDecoder().decode(FigureDate.self, from: Data(base.replacingOccurrences(of: "NOTES", with: notes).utf8))
            #expect(date.citations.isEmpty)
            #expect(date.notes?.values["en"] == "Note")
        }
    }

    @Test func browserSectionsPreservePublishedFigureOrder() throws {
        let library = try productionLibrary()
        let locale = Locale(identifier: "en")
        let sections = library.browserSections(matching: "", locale: locale)
        #expect(sections.map(\.id) == [
            "infallibles", "otherInfallibles", "messengers", "prophetRelatives", "companions", "otherCompanions",
        ])
        #expect(sections.map { $0.figures.map(\.id) } == [
            [
                "prophet-muhammad", "ali-ibn-abi-talib", "fatima-al-zahra", "hasan-ibn-ali",
                "husayn-ibn-ali", "ali-zayn-al-abidin",
            ],
            ["zaynab-bint-ali", "abbas-ibn-ali", "ali-al-akbar"],
            ["prophet-ibrahim", "prophet-isa", "prophet-musa"],
            [
                "abd-al-muttalib", "abdullah-ibn-abd-al-muttalib", "amina-bint-wahb", "abu-talib",
                "khadija-bint-khuwaylid", "hamza-ibn-abd-al-muttalib", "umm-kulthum-bint-ali", "umm-al-banin",
                "ruqayya-bint-al-husayn", "muslim-ibn-aqil",
            ],
            ["salman-al-muhammadi", "abu-dharr-al-ghifari", "miqdad-ibn-al-aswad", "ammar-ibn-yasir"],
            ["hani-ibn-urwa", "jabir-ibn-abdullah"],
        ])

        let results = library.browserSections(matching: "abbas ibn ali", locale: locale)
        #expect(results.map(\.id) == ["otherInfallibles"])
        #expect(results.flatMap(\.figures).map(\.id) == ["abbas-ibn-ali"])
    }

    @Test func datasetsWithoutBrowserGroupsUseOneSection() throws {
        let library = try FigureLibrary(data: exampleData(), verifiedOnly: false)
        let sections = library.browserSections(matching: "", locale: Locale(identifier: "en"))
        #expect(sections.map(\.id) == ["all"])
        #expect(sections.flatMap(\.figures).map(\.id) == library.people.map(\.id))
    }

    @Test(arguments: ["duplicate group", "duplicate figure", "unknown figure", "unassigned figure"])
    func invalidBrowserGroupsAreRejected(_ problem: String) throws {
        let data = try exampleData()
        let library = try FigureLibrary(data: data, verifiedOnly: false)
        let ids = library.people.map(\.id)
        var dataset = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let groups: [[String: Any]]
        switch problem {
        case "duplicate group":
            groups = [["id": "group", "figure_ids": ids], ["id": "group", "figure_ids": [String]()]]
        case "duplicate figure":
            groups = [["id": "group", "figure_ids": ids + [ids[0]]]]
        case "unknown figure":
            groups = [["id": "group", "figure_ids": Array(ids.dropFirst()) + ["missing-figure"]]]
        default:
            groups = [["id": "group", "figure_ids": Array(ids.dropFirst())]]
        }
        dataset["browser_groups"] = groups
        let invalid = try JSONSerialization.data(withJSONObject: dataset)
        #expect(throws: FigureLibrary.Failure.invalidBrowserGroups) {
            try FigureLibrary(data: invalid)
        }
    }

    @Test func optionalPlacesDecodeAndLocalizeWithoutChangingLegacyRecords() throws {
        var dataset = try #require(JSONSerialization.jsonObject(with: exampleData()) as? [String: Any])
        var people = try #require(dataset["people"] as? [[String: Any]])
        people[0]["birth_place"] = ["en": "Birthplace", "ar": "مكان الولادة"]
        people[0]["death_place"] = ["en": "Deathplace"]
        dataset["people"] = people
        let library = try FigureLibrary(data: JSONSerialization.data(withJSONObject: dataset), verifiedOnly: false)
        let person = try #require(library.people.first)
        #expect(person.birthPlace.flatMap { Figure.localized($0, Locale(identifier: "ar")) } == "مكان الولادة")
        #expect(person.deathPlace?["en"] == "Deathplace")
        #expect(library.people.last?.birthPlace == nil)
    }

    @Test func ageEstimatesRespectEraBoundariesAndMissingDates() throws {
        func person(birth: String, death: String) throws -> Figure {
            let json = """
            {"id":"test","display_names":{},"names":{},"birth_dates":\(birth),"death_dates":\(death)}
            """
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(Figure.self, from: Data(json.utf8))
        }
        func date(_ year: Int, month: Int? = nil, day: Int? = nil, era: String = "AH", calendar: String = "hijri") -> String {
            var point = #""year":\#(year)"#
            if let month { point += #","month":\#(month)"# }
            if let day { point += #","day":\#(day)"# }
            return """
            [{"calendar":"\(calendar)","era":"\(era)","precision":"approximate","start":{\(point)},"original":"estimate","status":"accepted"}]
            """
        }
        #expect(try person(birth: date(26), death: date(61)).age == DateComponents(year: 35))
        #expect(try person(birth: date(53, era: "BH"), death: date(11)).age == DateComponents(year: 63))
        #expect(try person(birth: date(85, era: "BH"), death: date(4, era: "BH")).age == DateComponents(year: 81))
        #expect(try person(birth: date(1, era: "BCE", calendar: "gregorian"), death: date(1, era: "CE", calendar: "gregorian")).age == DateComponents(year: 1))
        #expect(try person(birth: "[]", death: date(61)).age == nil)
        #expect(try person(birth: date(255), death: "[]").age == nil)
        #expect(try person(birth: date(61), death: date(26)).age == nil)
        #expect(try person(birth: date(26), death: date(680, era: "CE", calendar: "gregorian")).age == nil)

        #expect(try person(birth: date(26, month: 12, day: 20), death: date(61)).age == DateComponents(year: 35))
        #expect(try person(birth: date(26, month: 12, day: 20), death: date(28, month: 1)).age == DateComponents(year: 1, month: 1))
        #expect(try person(birth: date(26, month: 12, day: 20), death: date(28, month: 1, day: 19)).age == DateComponents(year: 1, month: 0))
        #expect(try person(birth: date(26, month: 12, day: 20), death: date(28, month: 1, day: 20)).age == DateComponents(year: 1, month: 1))
        #expect(try person(birth: date(26, month: 12), death: date(26, month: 11)).age == nil)
        #expect(try person(birth: date(26, month: 12, day: 20), death: date(26, month: 12, day: 19)).age == nil)
    }

    private func productionLibrary() throws -> FigureLibrary {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "figures", withExtension: "json"))
        return try FigureLibrary(data: Data(contentsOf: url), events: FigureLibrary.bundledEvents)
    }

    private func exampleData() throws -> Data {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "figure-example", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private final class BundleToken {}
}
