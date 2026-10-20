import Foundation
@testable import Muntathir
import Synchronization
import Testing

private final class FeedURLProtocol: URLProtocol, @unchecked Sendable {
    struct State: Sendable {
        var statuses: [Int] = []
        var bodies: [Data] = []
        var tags: [String?] = []
    }

    static let state = Mutex(State())
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let next = Self.state.withLock { value -> (Int, Data) in
            value.tags.append(request.value(forHTTPHeaderField: "If-None-Match"))
            return (value.statuses.removeFirst(), value.bodies.removeFirst())
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: next.0, httpVersion: nil, headerFields: ["ETag": "fixture-v1"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: next.1)
        client?.urlProtocolDidFinishLoading(self)
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
        let model = AppModel(defaults: defaults, cloud: nil, feedClient: client)
        model.select(.init(latitude: 24, longitude: 46, name: "Fixture coverage", countryCode: "SA", timeZoneID: "Asia/Riyadh"))
        model.update { $0.selectedSourceID = row.sourceID }
        for _ in 0 ..< 4 {
            #expect(await model.refreshInBackground())
            #expect(model.confirmations == [row])
            let day = try model.engine.resolve(#require(row.start.date(in: model.zone)))
            #expect(day.month == row.month)
            #expect(day.day == 1)
            #expect(day.provenance == .confirmed)
        }
        #expect(FeedURLProtocol.state.withLock { $0.tags } == [nil, "fixture-v1", "fixture-v1", "fixture-v1"])

        // Changing coverage must remove the prior confirmation even when HTTP returns the cache.
        FeedURLProtocol.state.withLock { $0 = .init(statuses: [304], bodies: [Data()], tags: []) }
        model.select(.init(latitude: 21.4225, longitude: 39.8262, name: "Mecca", countryCode: "SA", timeZoneID: "Asia/Riyadh"))
        #expect(await model.refreshInBackground())
        #expect(model.confirmations.isEmpty)
    }
}

private final class FixtureBundle: NSObject {}
