import Foundation

enum SightingMethod: String, Codable, CaseIterable, Sendable {
    case nakedEye, aidedSight, government, calculation
    var title: String {
        switch self {
        case .nakedEye: String(localized: "Naked-eye sighting")
        case .aidedSight: String(localized: "Aided sighting")
        case .government: String(localized: "Government announcement")
        case .calculation: String(localized: "Calculated calendar")
        }
    }
}
struct GeoPoint: Codable, Hashable, Sendable { let latitude: Double; let longitude: Double }
struct Coverage: Codable, Hashable, Sendable {
    var countries: [String]
    var polygons: [[GeoPoint]]
    var isValid: Bool {
        (!countries.isEmpty || !polygons.isEmpty) && countries.allSatisfy { $0.count == 2 && $0 == $0.uppercased() }
        && polygons.allSatisfy { $0.count >= 3 && $0.allSatisfy { $0.latitude.isFinite && $0.longitude.isFinite && (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) } }
    }
    func contains(_ location: SavedLocation) -> Bool {
        if countries.contains(location.countryCode.uppercased()) { return true }
        return polygons.contains { polygon in
            guard polygon.count >= 3 else { return false }
            // Unwrap consecutive vertices, then place the query in that same longitude band.
            var longitudes = [polygon[0].longitude]
            for point in polygon.dropFirst() {
                var longitude = point.longitude
                while longitude - longitudes.last! > 180 { longitude -= 360 }
                while longitude - longitudes.last! < -180 { longitude += 360 }
                longitudes.append(longitude)
            }
            let center = (longitudes.min()! + longitudes.max()!) / 2
            let query = location.longitude + ((center - location.longitude) / 360).rounded() * 360
            var inside = false
            for index in polygon.indices {
                let a = polygon[index], b = polygon[(index + 1) % polygon.count]
                let ax = longitudes[index] - query, bx = longitudes[(index + 1) % polygon.count] - query
                let ay = a.latitude - location.latitude, by = b.latitude - location.latitude
                if abs(ax * by - bx * ay) < 1e-9 && min(ax, bx) <= 0 && max(ax, bx) >= 0 && min(ay, by) <= 0 && max(ay, by) >= 0 { return true }
                if (ay > 0) != (by > 0), 0 < ax + (bx - ax) * (-ay) / (by - ay) { inside.toggle() }
            }
            return inside
        }
    }
}
struct Announcement: Codable, Hashable, Sendable {
    let id: String
    let revision: Int
    let method: SightingMethod
    let sourceID: String
    let coverage: Coverage
    let month: HijriMonth
    let start: CivilDate
    var correction: MonthCorrection { .init(month: month, start: start, provenance: .confirmed, sourceID: sourceID) }
}
struct CorrectionsFeed: Codable, Sendable {
    let schemaVersion: Int
    let announcements: [Announcement]
    static func decode(_ data: Data) throws -> Self {
        let feed = try JSONDecoder().decode(Self.self, from: data)
        guard feed.schemaVersion == 1, feed.announcements.count <= 10_000 else { throw CalendarError.invalidDate }
        var ids = Set<String>()
        for row in feed.announcements {
            guard !row.id.isEmpty, !row.sourceID.isEmpty, row.revision > 0, row.method != .calculation,
                  row.coverage.isValid, row.month.isValid, row.start.date(in: .gmt) != nil,
                  ids.insert(row.id).inserted else { throw CalendarError.invalidDate }
            _ = try CalendarEngine(timeZone: .gmt, confirmed: [row.correction])
        }
        return feed
    }
    func matching(location: SavedLocation, sourceID: String?) throws -> [Announcement] {
        guard let sourceID else { return [] }
        let rows = announcements.filter { $0.sourceID == sourceID && $0.coverage.contains(location) }
        var months: [HijriMonth: Announcement] = [:]
        for row in rows {
            if let previous = months[row.month], previous.start != row.start { throw CalendarError.conflictingMonths }
            months[row.month] = row
        }
        let result = Array(months.values)
        _ = try CalendarEngine(timeZone: location.timeZone, confirmed: result.map(\.correction))
        return result
    }
}

actor FeedClient {
    struct Cache: Codable { let etag: String?; let payload: Data }
    private let url: URL
    private let cacheURL: URL
    private let session: URLSession
    private var running: Task<CorrectionsFeed, Error>?
    init(url: URL, cacheURL: URL, session: URLSession = .shared) { self.url = url; self.cacheURL = cacheURL; self.session = session }
    func refresh() async throws -> CorrectionsFeed {
        if let running { return try await running.value }
        let task = Task { try await self.fetch() }
        running = task
        defer { running = nil }
        return try await task.value
    }
    private func fetch() async throws -> CorrectionsFeed {
        let cached = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
        let lastGood = cached.flatMap { try? CorrectionsFeed.decode($0.payload) }
        do {
            guard url.scheme == "https" else { throw URLError(.secureConnectionFailed) }
            var request = URLRequest(url: url); request.timeoutInterval = 20
            if lastGood != nil { request.setValue(cached?.etag, forHTTPHeaderField: "If-None-Match") }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.url?.scheme == "https" else { throw URLError(.badServerResponse) }
            if http.statusCode == 304, let lastGood { return lastGood }
            guard http.statusCode == 200, data.count <= 5_000_000 else { throw URLError(.badServerResponse) }
            let feed = try CorrectionsFeed.decode(data)
            let envelope = Cache(etag: http.value(forHTTPHeaderField: "ETag"), payload: data)
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(envelope).write(to: cacheURL, options: .atomic)
            return feed
        } catch {
            if let lastGood { return lastGood }
            throw error
        }
    }
}
