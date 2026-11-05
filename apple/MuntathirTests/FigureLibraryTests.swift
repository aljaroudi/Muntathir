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
        #expect(library.people.filter { FigureGroup.group(for: $0.id) == .infallibles }.count == 14)
        #expect(library.people.filter { FigureGroup.group(for: $0.id) == .companions }.count == 4)
        #expect(library.people.filter { FigureGroup.group(for: $0.id) == .prophets }.count == 3)
    }

    @Test func exampleDerivesFullAndHalfSiblingsAndGroupsChildren() throws {
        let library = try FigureLibrary(data: exampleData())
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
        let unknown = try FigureLibrary(data: JSONSerialization.data(withJSONObject: dataset))
        let first = try #require(unknown.parents["example-child-a"]?.first)
        #expect(unknown.siblings(of: first.childId, account: first)[.unknown]?.map(\.id) == ["example-child-c"])

        var alternative = parentages[2]
        alternative["id"] = "alternate-parentage"
        alternative["mother_id"] = "example-mother-a"
        parentages.append(alternative)
        dataset["parentages"] = parentages
        let conflict = try FigureLibrary(data: JSONSerialization.data(withJSONObject: dataset))
        #expect(conflict.childGroups(of: "example-father").flatMap(\.self).count == 2)
        #expect(conflict.childGroups(of: "example-father", choices: ["example-child-c": "alternate-parentage"])
            .flatMap(\.self).count == 3)

        parentages[2]["father_id"] = "missing-person"
        dataset["parentages"] = parentages
        let invalid = try JSONSerialization.data(withJSONObject: dataset)
        #expect(throws: FigureLibrary.Failure.invalidRelationships) { try FigureLibrary(data: invalid) }
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
