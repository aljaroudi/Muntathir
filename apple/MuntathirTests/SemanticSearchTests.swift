import Foundation
@testable import Muntathir
import SQLite3
import Testing

struct SemanticSearchTests {
    @Test func compactHadithReferencePreservesBookAndChapter() throws {
        let json = #"{"kind":"hadith","book":"alkafi-1","chapter":"1.json","number":1,"score":0.74}"#
        let result = try JSONDecoder().decode(SemanticSearchResult.self, from: Data(json.utf8))
        let source = try #require(result.hadithSource)
        #expect(source.book == "alkafi-1")
        #expect(source.chapterFile == "1.json")
        #expect(source.number == 1)
        #expect(source.sourceID == nil)
        #expect(result.score == 0.74)
    }

    @Test func directQuranReferenceHasNoSimilarity() throws {
        let json = #"{"kind":"quran","chapter":2,"verse":255,"score":null}"#
        let result = try JSONDecoder().decode(SemanticSearchResult.self, from: Data(json.utf8))
        #expect(result.id == "quran:2:255")
        #expect(result.score == nil)
        #expect(result.hadithSource == nil)
    }

    @Test(arguments: [
        #"{"kind":"quran","chapter":0,"verse":1,"score":0.5}"#,
        #"{"kind":"quran","chapter":2,"verse":1,"score":2}"#,
        #"{"kind":"unknown","score":0.5}"#,
    ]) func invalidResponsesAreRejected(_ json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SemanticSearchResult.self, from: Data(json.utf8))
        }
    }
}

extension SemanticSearchTests {
    @Test func compactHadithLookupRejectsAmbiguity() async throws {
        let fixture = try HadithFixture(count: 2)
        defer { fixture.remove() }
        let reader = HadithReader(database: HadithDatabase(url: fixture.url))
        #expect(try await reader.resolveSearch(book: "v1", chapter: "1.json", number: 1) == 1)
        var handle: OpaquePointer?
        #expect(sqlite3_open(fixture.url.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        #expect(sqlite3_exec(handle, "UPDATE hadith SET id_in_book = 1 WHERE id = 2", nil, nil, nil) == SQLITE_OK)
        #expect(try await reader.resolveSearch(book: "v1", chapter: "1.json", number: 1) == nil)
        #expect(try await reader.resolveSearch(book: "missing", chapter: "1.json", number: 1) == nil)
    }
}

extension SemanticSearchTests {
    @Test func onlineScopePreservesVolumesAndChapter() async throws {
        let fixture = try HadithFixture(count: 2)
        defer { fixture.remove() }
        let reader = HadithReader(database: HadithDatabase(url: fixture.url))
        let collection = try await reader.meaningSearchScope(HadithRequest(collectionID: "merged"))
        #expect(collection.sources == ["v1", "v2"])
        #expect(collection.chapter == nil)
        let chapterID = try #require(await reader.chapterID(for: HadithSource(book: "v1", chapterFile: "1.json", number: 0, sourceID: nil)))
        let chapter = try await reader.meaningSearchScope(HadithRequest(collectionID: "merged", chapterID: chapterID))
        #expect(chapter.sources == ["v1"])
        #expect(chapter.chapter == "1.json")
        await #expect(throws: URLError.self) {
            try await reader.meaningSearchScope(HadithRequest(collectionID: "missing"))
        }
        let all = try await reader.meaningSearchScope(HadithRequest())
        #expect(all.sources == nil && all.chapter == nil)
    }

    @Test func requestEncodesScopeAndOmitsAbsentFilters() throws {
        let client = try SemanticSearchClient(endpoint: #require(URL(string: "https://example.com/v1/search")))
        let scoped = try client.request("patience", kind: "hadith", sources: ["v1"], chapter: "1.json")
        let scopedData = try #require(scoped.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: scopedData) as? [String: Any])
        #expect(body["sources"] as? [String] == ["v1"])
        #expect(body["chapter"] as? String == "1.json")
        #expect(body["kinds"] as? [String] == ["hadith"])
        let chapterRequest = try client.request("patience", kind: "quran", sources: nil, chapter: "2")
        let chapterData = try #require(chapterRequest.httpBody)
        let chapterBody = try #require(JSONSerialization.jsonObject(with: chapterData) as? [String: Any])
        #expect(chapterBody["chapter"] as? String == "2")
        #expect(chapterBody["kinds"] as? [String] == ["quran"])
        let quran = try client.request("patience", kind: "quran", sources: nil, chapter: nil)
        let quranData = try #require(quran.httpBody)
        let unscoped = try #require(JSONSerialization.jsonObject(with: quranData) as? [String: Any])
        #expect(unscoped["sources"] == nil && unscoped["chapter"] == nil)
    }
}
