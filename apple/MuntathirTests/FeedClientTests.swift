import Foundation
@testable import Muntathir
import Synchronization
import Testing

private final class FeedURLProtocol: URLProtocol, @unchecked Sendable {
    struct State: Sendable {
        var statuses: [Int] = []
        var bodies: [Data] = []
        var tags: [String?] = []
        var beforeDelivery: (@Sendable () async -> Void)?
    }

    static let state = Mutex(State())
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let next = Self.state.withLock { value -> (Int, Data, (@Sendable () async -> Void)?) in
            value.tags.append(request.value(forHTTPHeaderField: "If-None-Match"))
            return (value.statuses.removeFirst(), value.bodies.removeFirst(), value.beforeDelivery)
        }
        Task {
            await next.2?()
            let response = HTTPURLResponse(url: request.url!, statusCode: next.0, httpVersion: nil, headerFields: ["ETag": "fixture-v1"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: next.1)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct FeedClientTests {
    @Test func conditionalRefreshAndLastGoodCache() async throws {
        let good = Data(#"{"schemaVersion":1,"announcements":[]}"#.utf8)
        FeedURLProtocol.state.withLock { $0 = .init(statuses: [200, 304, 200, 503], bodies: [good, Data(), Data("broken".utf8), Data()], tags: []) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FeedURLProtocol.self]
        let session = URLSession(configuration: config)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder); session.invalidateAndCancel() }
        let client = try FeedClient(url: #require(URL(string: "https://example.invalid/feed.json")), cacheURL: folder.appendingPathComponent("cache.json"), session: session)
        for _ in 0 ..< 4 {
            #expect(try await client.refresh().schemaVersion == 1)
        }
        let tags = FeedURLProtocol.state.withLock { $0.tags }
        #expect(tags == [nil, "fixture-v1", "fixture-v1", "fixture-v1"])
    }
}

extension FeedClientTests {
    @MainActor @Test func backgroundRefreshAppliesSampleJSONAndRecoversCache() async throws {
        let fixture = try #require(Bundle(for: FixtureBundle.self).url(forResource: "corrections-v1", withExtension: "json"))
        let good = try Data(contentsOf: fixture)
        let row = try #require(CorrectionsFeed.decode(good).announcements.first)
        FeedURLProtocol.state.withLock {
            $0 = .init(statuses: [200, 304, 200, 503], bodies: [good, Data(), Data("broken".utf8), Data()], tags: [])
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeedURLProtocol.self]
        let session = URLSession(configuration: config)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "FeedIntegration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: suite)
            session.invalidateAndCancel()
        }
        let client = try FeedClient(url: #require(URL(string: "https://example.invalid/feed.json")),
                                    cacheURL: folder.appendingPathComponent("cache.json"), session: session)
        var preferences = Preferences()
        preferences.selectedSourceID = row.sourceID
        try defaults.set(JSONEncoder().encode(preferences), forKey: "preferences.v1")
        let model = AppModel(defaults: defaults, cloud: nil, feedClient: client)
        model.select(.init(latitude: 24, longitude: 46, name: "Fixture coverage", countryCode: "SA", timeZoneID: "Asia/Riyadh"))
        for _ in 0 ..< 4 {
            #expect(await model.refreshInBackground())
            #expect(model.confirmations == [row])
            let day = try model.engine.resolve(#require(row.start.date(in: model.zone)))
            #expect(day.month == row.month)
            #expect(day.day == 1)
            #expect(day.provenance == .confirmed)
        }
        #expect(FeedURLProtocol.state.withLock { $0.tags } == [nil, "fixture-v1", "fixture-v1", "fixture-v1"])

        let restored = AppModel(defaults: defaults, cloud: nil, feedClient: client)
        #expect(restored.confirmations == [row])
        #expect(restored.engine.start(of: row.month) == model.engine.start(of: row.month))

        // Following a source is independent of physical coverage.
        FeedURLProtocol.state.withLock { $0 = .init(statuses: [304], bodies: [Data()], tags: []) }
        model.select(.init(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh"))
        #expect(await model.refreshInBackground())
        #expect(model.confirmations == [row])
    }
}

private final class FixtureBundle: NSObject {}

extension FeedClientTests {
    @MainActor @Test func conflictingRefreshPreservesLastAppliedCalendar() async throws {
        let suite = "FeedConflict.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, cloud: nil)
        let location = SavedLocation(latitude: 51.5, longitude: -0.1, name: "London", countryCode: "GB", timeZoneID: "Europe/London")
        model.select(location)
        model.update { $0.selectedSourceID = CalendarSource.middleEast }
        let month = HijriMonth(year: 1448, month: 1)
        let baseline = try CalendarEngine(timeZone: location.timeZone)
        let original = Announcement(id: "first", revision: 1, method: .nakedEye, sourceID: CalendarSource.middleEast,
                                    coverage: .init(countries: ["SA"], polygons: []), month: month,
                                    start: CivilDate(baseline.start(of: month), in: location.timeZone))
        try await model.receive(.init(schemaVersion: 1, announcements: [original]))
        try model.correct(month: month, offset: -2)
        let before = model.engine.start(of: month)
        let next = Announcement(id: "next", revision: 1, method: .nakedEye, sourceID: CalendarSource.middleEast,
                                coverage: original.coverage, month: month.advanced(1),
                                start: CivilDate(baseline.start(of: month.advanced(1)), in: location.timeZone))
        await #expect(throws: CalendarError.self) {
            try await model.receive(.init(schemaVersion: 1, announcements: [original, next]))
        }
        #expect(model.confirmations == [original])
        #expect(model.engine.start(of: month) == before)
        model.update { $0.selectedSourceID = "government-SA" }
        #expect(model.confirmations.isEmpty)
        #expect(model.preferences.monthOffsets == [.init(month: month, days: -2)])
        try await model.receive(.init(schemaVersion: 1, announcements: []))
        #expect(model.confirmations.isEmpty)
    }
}

extension FeedClientTests {
    @MainActor @Test func staleResponseCannotRestoreAnOldSource() async throws {
        let suite = "FeedStale.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FeedURLProtocol.self]
        let session = URLSession(configuration: config)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
            session.invalidateAndCancel()
        }
        let fixture = try #require(Bundle(for: FixtureBundle.self).url(forResource: "corrections-v1", withExtension: "json"))
        let body = try Data(contentsOf: fixture)
        var preferences = Preferences()
        preferences.selectedSourceID = CalendarSource.middleEast
        try defaults.set(JSONEncoder().encode(preferences), forKey: "preferences.v1")
        let client = try FeedClient(url: #require(URL(string: "https://example.invalid/feed.json")),
                                    cacheURL: folder.appendingPathComponent("cache.json"), session: session)
        let model = AppModel(defaults: defaults, cloud: nil, feedClient: client)
        model.select(.init(latitude: 24, longitude: 46, name: "Riyadh", countryCode: "SA", timeZoneID: "Asia/Riyadh"))
        FeedURLProtocol.state.withLock {
            $0 = .init(statuses: [200], bodies: [body], beforeDelivery: {
                await MainActor.run { model.update { $0.selectedSourceID = nil } }
            })
        }
        #expect(await model.refreshInBackground() == false)
        #expect(model.preferences.selectedSourceID == nil)
        #expect(model.confirmations.isEmpty)
    }
}

extension FeedClientTests {
    @MainActor @Test func incompatibleSourceChangeKeepsSavedCalendar() async throws {
        let suite = "SourceConflict.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, cloud: nil)
        model.select(.init(latitude: 24, longitude: 46, name: "Riyadh", countryCode: "SA", timeZoneID: "Asia/Riyadh"))
        model.update { $0.selectedSourceID = CalendarSource.middleEast }
        let base = try CalendarEngine(timeZone: model.zone)
        let month = try #require((1 ... 12).map { HijriMonth(year: 1448, month: $0) }.first { base.baselineLength($0) == 29 })
        let next = month.advanced(1)
        let row = Announcement(id: "thirty-day-month", revision: 1, method: .nakedEye, sourceID: CalendarSource.middleEast,
                               coverage: .init(countries: ["SA"], polygons: []), month: next,
                               start: CivilDate(base.addingDays(1, to: base.start(of: next)), in: model.zone))
        try await model.receive(.init(schemaVersion: 1, announcements: [row]))
        try model.correct(month: next, offset: -1)
        try model.correct(month: month, offset: -2)
        let saved = model.preferences
        #expect(model.update { $0.selectedSourceID = "government-SA" } == false)
        #expect(model.preferences == saved)
        #expect(model.confirmations == [row])
        #expect(model.error != nil)
    }
}
