import Foundation
@testable import Muntathir
import SQLite3
import Testing

struct HadithLocalLibraryTests {
    @Test func removalReclaimsSpaceAndRestorationPreservesOtherChoices() async throws {
        let fixture = try HadithFixture(count: 600)
        defer { fixture.remove() }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = HadithLocalLibrary(root: root)
        let reader = HadithReader()
        let original = try await library.prepare(source: fixture.url)
        try await reader.commit(original, to: library.url)
        let before = try library.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(try await library.books().filter(\.installed).count == 2)
        let source = try #require(try await reader.source(id: 1))
        let removal = try await library.prepare(source: library.url, removing: "merged")
        try await reader.commit(removal, to: library.url)
        let after = try library.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(after < before)
        #expect(try await reader.resolve(source) == nil)
        #expect(try await reader.catalog().map(\.id) == ["other"])
        #expect(try await reader.page(HadithRequest(query: "intentions")).rows.isEmpty)
        #expect(try await reader.page(HadithRequest(query: "نص")).rows.map(\.id) == [100_001])
        #expect(try await library.books().count == 2)
        let removeOther = try await library.prepare(source: library.url, removing: "other")
        try await reader.commit(removeOther, to: library.url)
        #expect(try await reader.catalog().isEmpty)
        let restore = try await library.prepare(source: fixture.url, restoring: "merged")
        try await reader.commit(restore, to: library.url)
        #expect(try await library.books().filter(\.installed).map(\.id) == ["merged"])
        #expect(try await reader.detail(id: 1).narration.source?.book == "v1")
        #expect(try await reader.resolve(source) == 1)
        #expect(try await reader.page(HadithRequest(query: "intentions")).rows.count == HadithReader.pageSize)
        #expect(try await reader.page(HadithRequest(query: "الأعمال")).rows.count == HadithReader.pageSize)
        let relaunched = HadithLocalLibrary(root: root)
        #expect(try await relaunched.books().filter(\.installed).map(\.id) == ["merged"])
    }

    @Test func cancelledPreparationKeepsTheCurrentLibrary() async throws {
        let fixture = try HadithFixture(count: 2)
        defer { fixture.remove() }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = HadithLocalLibrary(root: root)
        let reader = HadithReader()
        let initial = try await library.prepare(source: fixture.url)
        try await reader.commit(initial, to: library.url)
        let cancellation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await library.prepare(source: library.url, removing: "merged")
        }
        await #expect(throws: CancellationError.self) { _ = try await cancellation.value }
        #expect(try await reader.detail(id: 1).narration.id == 1)
        #expect(try await library.books().filter(\.installed).count == 2)
    }

    @Test func failedReplacementPreservesReadableLibrary() async throws {
        let fixture = try HadithFixture(count: 2)
        defer { fixture.remove() }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = HadithLocalLibrary(root: root)
        let reader = HadithReader()
        let staged = try await library.prepare(source: fixture.url)
        try await reader.commit(staged, to: library.url)
        let corrupt = root.appending(path: "corrupt.db")
        try Data("invalid".utf8).write(to: corrupt)
        await #expect(throws: (any Error).self) { _ = try await library.prepare(source: corrupt) }
        #expect(try await reader.detail(id: 1).narration.id == 1)
        #expect(try await library.books().filter(\.installed).count == 2)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(!leftovers.contains { $0.hasPrefix("staging-") })
    }
}
