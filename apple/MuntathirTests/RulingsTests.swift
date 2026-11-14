import Foundation
@testable import Muntathir
import SQLite3
import Testing

struct RulingsTests {
    @Test func scopeAndStableReferences() async throws {
        let fixture = try RulingsFixture()
        defer { fixture.remove() }
        let reader = RulingsReader()
        try await reader.install(fixture.url)
        let found = try await reader.questions(authority: "sistani", language: "ar", query: "الصلاة")
        #expect(found.count == 1)
        #expect(found.first?.id == Rulings.ID(authority: "sistani", language: "ar", siteID: "42"))
        #expect(try await reader.questions(authority: "shirazi", language: "ar", query: "الصلاة").first?.answer == "جواب آخر")
        #expect(try await reader.questions(authority: "sistani", language: "en", query: "الصلاة").isEmpty)
        #expect(try await reader.questions(authority: "sistani", language: "ar", query: "\" OR nope").isEmpty)
        let id = try #require(found.first?.id)
        #expect(try await reader.question(id)?.answer == "نص أصلي")
        #expect(try await reader.topics(authority: "sistani", language: "ar").count == 1)
        #expect(try await reader.questions(authority: "shirazi", language: "ar", topic: 1).isEmpty)
        let task = Task {
            try Task.checkCancellation()
            return try await reader.questions(authority: "sistani", language: "ar", query: "الصلاة")
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test func languageMustBeAvailable() {
        let persian = RulingsLanguage(id: "fa", name: "فارسی", rightToLeft: true)
        #expect(RulingsReader.preferredLanguage(saved: nil, locale: "ar-SA", available: [persian]) == nil)
        #expect(RulingsReader.preferredLanguage(saved: "fa", locale: "ar", available: [persian]) == "fa")
        #expect(RulingsReader.preferredLanguage(saved: "en", locale: "fa-IR", available: [persian]) == "fa")
    }

    @Test func semanticReferenceAndRequestRetainScope() throws {
        let result = try JSONDecoder().decode(SemanticSearchResult.self, from: Data(#"{"kind":"rulings","authority":"sistani","language":"ar","id":"42","score":0.8}"#.utf8))
        #expect(result.id == "rulings:sistani:ar:42")
        let client = try SemanticSearchClient(endpoint: #require(URL(string: "https://example.org/v1/search")))
        let request = try client.request("الصلاة", kind: "rulings", sources: ["sistani"], chapter: nil, languages: ["ar"])
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["languages"] as? [String] == ["ar"])
        #expect(body["sources"] as? [String] == ["sistani"])
    }

    @MainActor @Test func downloadRetryRelaunchAndRemoval() async throws {
        let fixture = try RulingsFixture()
        defer { fixture.remove() }
        let backend = RulingsTestBackend(url: fixture.url)
        let store = RulingsAssetStore(backend: backend)
        await store.refresh()
        #expect(store.state == .missing)
        await backend.setFailure(true)
        await store.download()
        #expect(store.state == .failed)
        await backend.setFailure(false)
        await backend.setDownloading(true)
        await store.refresh()
        #expect(store.state == .downloading)
        await store.download()
        #expect(store.state == .ready)
        let relaunch = RulingsAssetStore(backend: backend)
        await relaunch.refresh()
        #expect(relaunch.state == .ready)
        #expect(try await relaunch.reader.authorities().count == 2)
        await backend.setFailure(true)
        await store.remove()
        #expect(store.storageError)
        #expect(store.state == .ready)
        await backend.setFailure(false)
        await store.remove()
        #expect(store.state == .missing)
        await #expect(throws: HadithDatabaseError.self) { _ = try await store.reader.authorities() }
        await store.download()
        #expect(store.state == .ready)
    }

    @Test func incompatibleAndCorruptFilesAreRejected() async throws {
        let fixture = try RulingsFixture()
        defer { fixture.remove() }
        var db: OpaquePointer?
        #expect(sqlite3_open(fixture.url.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "PRAGMA user_version=99", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let reader = RulingsReader()
        await #expect(throws: HadithDatabaseError.self) { try await reader.install(fixture.url) }
        try Data("invalid".utf8).write(to: fixture.url)
        await #expect(throws: HadithDatabaseError.self) { try await reader.install(fixture.url) }
    }
}

private actor RulingsTestBackend: AssetPackBackend {
    let url: URL
    var installed = false
    var failing = false
    var downloading = false
    init(url: URL) {
        self.url = url
    }

    func setFailure(_ value: Bool) {
        failing = value
    }

    func setDownloading(_ value: Bool) {
        downloading = value
    }

    func localURL() -> URL? {
        installed ? url : nil
    }

    func isDownloading() -> Bool {
        downloading
    }

    func download() throws {
        if failing {
            throw URLError(.notConnectedToInternet)
        }
        installed = true
        downloading = false
    }

    func remove() throws {
        if failing {
            throw URLError(.cannotRemoveFile)
        }
        installed = false
    }

    nonisolated func updates() -> AsyncStream<AssetPackEvent> {
        AsyncStream { $0.finish() }
    }
}

extension RulingsTests {
    @Test func repeatedReaderQueriesAndRemoval() async throws {
        let fixture = try RulingsFixture()
        defer { fixture.remove() }
        let reader = RulingsReader()
        try await reader.install(fixture.url)
        let duration = try await ContinuousClock().measure { () async throws in
            for _ in 0 ..< 200 {
                #expect(try await reader.languages(authority: "sistani").count == 2)
                #expect(try await reader.question(.init(authority: "sistani", language: "en", siteID: "42"))?.answer == "Original answer")
            }
        }
        print("Rulings 400 queries: \(duration)")
        try await reader.install(nil)
        await #expect(throws: HadithDatabaseError.self) { _ = try await reader.languages(authority: "sistani") }
        try await reader.install(fixture.url)
        #expect(try await reader.authorities().count == 2)
    }
}

extension RulingsTests {
    @Test func connectionReuseMeasurement() throws {
        let fixture = try RulingsFixture()
        defer { fixture.remove() }
        let sql = "SELECT site_id FROM question WHERE authority_code = ? AND language_code = ?"
        let parameters = ["sistani", "en"]
        var reopenedRows = 0
        let reopening = try ContinuousClock().measure {
            for _ in 0 ..< 400 {
                let database = try HadithConnection(url: fixture.url)
                reopenedRows += try database.query(sql, parameters: parameters) { sqlite3_column_int($0, 0) }.count
            }
        }
        let database = try HadithConnection(url: fixture.url)
        var reusedRows = 0
        let reusing = try ContinuousClock().measure {
            for _ in 0 ..< 400 {
                reusedRows += try database.query(sql, parameters: parameters) { sqlite3_column_int($0, 0) }.count
            }
        }
        #expect(reopenedRows == 400)
        #expect(reusedRows == reopenedRows)
        print("Rulings connection comparison (400 identical lookups): reopen \(reopening), reuse \(reusing)")
    }
}
