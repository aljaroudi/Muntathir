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

    @Test func namesAndBrowserGroupsMatchTheSimplifiedDataset() throws {
        let library = try productionLibrary()
        let prophet = try #require(library.byID["prophet-muhammad"])
        #expect(prophet.names(.personal, locale: Locale(identifier: "ar")) == ["محمد"])
        #expect(prophet.names(.full, locale: Locale(identifier: "ar")) == ["محمد بن عبد الله"])
        #expect(library.people.filter { FigureGroup.group(for: $0.id) == .infallibles }.count == 5)
        #expect(library.people.filter { FigureGroup.group(for: $0.id) == .companions }.count == 1)
        #expect(library.people.filter { FigureGroup.group(for: $0.id) == .messengers }.count == 3)
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

    @Test func figureGroupsHaveTheRequestedOrderAndMembership() {
        #expect(FigureGroup.allCases == [.infallibles, .otherInfallibles, .messengers, .prophets,
                                         .prophetRelatives, .companions, .otherCompanions, .other])
        #expect(FigureGroup.group(for: "prophet-muhammad") == .infallibles)
        for id in ["abbas-ibn-ali", "ali-al-akbar", "zaynab-bint-ali", "fatima-al-masuma"] {
            #expect(FigureGroup.group(for: id) == .otherInfallibles)
        }
        #expect(FigureGroup.group(for: "prophet-musa") == .messengers)
        #expect(FigureGroup.group(for: "prophet-example") == .prophets)
        #expect(FigureGroup.group(for: "hamza-ibn-abd-al-muttalib") == .prophetRelatives)
        #expect(FigureGroup.group(for: "salman-al-muhammadi") == .companions)
        for id in ["jabir-ibn-abdullah", "hani-ibn-urwa"] {
            #expect(FigureGroup.group(for: id) == .otherCompanions)
        }
        #expect(FigureGroup.group(for: "unknown") == .other)
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
        func date(_ year: Int, era: String = "AH", calendar: String = "hijri") -> String {
            """
            [{"calendar":"\(calendar)","era":"\(era)","precision":"approximate","start":{"year":\(year)},"original":"estimate","status":"accepted"}]
            """
        }
        #expect(try person(birth: date(26), death: date(61)).age == 35)
        #expect(try person(birth: date(53, era: "BH"), death: date(11)).age == 63)
        #expect(try person(birth: date(85, era: "BH"), death: date(4, era: "BH")).age == 81)
        #expect(try person(birth: date(1, era: "BCE", calendar: "gregorian"), death: date(1, era: "CE", calendar: "gregorian")).age == 1)
        #expect(try person(birth: "[]", death: date(61)).age == nil)
        #expect(try person(birth: date(255), death: "[]").age == nil)
        #expect(try person(birth: date(61), death: date(26)).age == nil)
        #expect(try person(birth: date(26), death: date(680, era: "CE", calendar: "gregorian")).age == nil)
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
