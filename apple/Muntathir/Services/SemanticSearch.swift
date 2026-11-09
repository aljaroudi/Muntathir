import Foundation

struct SemanticSearchResult: Decodable, Identifiable, Sendable {
    enum Reference: Sendable {
        case quran(chapter: Int, verse: Int)
        case hadith(book: String, chapter: String, number: Int)
        case dua(id: String, passage: Int?)
    }

    let reference: Reference
    let score: Double?

    var id: String {
        switch reference {
        case let .quran(chapter, verse): "quran:\(chapter):\(verse)"
        case let .hadith(book, chapter, number): "hadith:\(book):\(chapter):\(number)"
        case let .dua(id, passage): "dua:\(id):\(passage.map(String.init) ?? "")"
        }
    }

    var title: String {
        switch reference {
        case let .quran(chapter, verse): "\(chapter):\(verse)"
        case let .hadith(book, _, number): "\(book) · \(number)"
        case let .dua(id, _): id
        }
    }

    var hadithSource: HadithSource? {
        guard case let .hadith(book, chapter, number) = reference else { return nil }
        return HadithSource(book: book, chapterFile: chapter, number: number, sourceID: nil)
    }

    private enum CodingKeys: String, CodingKey { case kind, chapter, verse, book, number, id, passage, score }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        score = try values.decodeIfPresent(Double.self, forKey: .score)
        if let score, !score.isFinite || !(-1.000001 ... 1.000001).contains(score) {
            throw DecodingError.dataCorruptedError(forKey: .score, in: values, debugDescription: "Invalid cosine similarity")
        }
        switch try values.decode(String.self, forKey: .kind) {
        case "quran":
            let chapter = try values.decode(Int.self, forKey: .chapter)
            let verse = try values.decode(Int.self, forKey: .verse)
            guard (1 ... 114).contains(chapter), (1 ... 286).contains(verse) else {
                throw DecodingError.dataCorruptedError(forKey: .chapter, in: values, debugDescription: "Invalid Quran reference")
            }
            reference = .quran(chapter: chapter, verse: verse)
        case "hadith":
            let book = try values.decode(String.self, forKey: .book)
            let chapter = try values.decode(String.self, forKey: .chapter)
            let number = try values.decode(Int.self, forKey: .number)
            guard !book.isEmpty, !chapter.isEmpty, number >= 0 else {
                throw DecodingError.dataCorruptedError(forKey: .book, in: values, debugDescription: "Invalid Hadith reference")
            }
            reference = .hadith(book: book, chapter: chapter, number: number)
        case "dua":
            reference = try .dua(id: values.decode(String.self, forKey: .id), passage: values.decodeIfPresent(Int.self, forKey: .passage))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unknown content kind")
        }
    }
}

struct SemanticSearchClient: Sendable {
    let endpoint: URL

    static var configured: Self? {
        #if DEBUG
            if usesTestFixture {
                return Self(endpoint: URL(string: "https://search.invalid/v1/search")!)
            }
        #endif
        let local: [String: String]? = Bundle.main.url(forResource: "SemanticSearchConfiguration", withExtension: "plist")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? PropertyListDecoder().decode([String: String].self, from: $0) }
        let configuredURL = Bundle.main.object(forInfoDictionaryKey: "SemanticSearchURL") as? String
        let value = configuredURL.flatMap { $0.hasPrefix("https://") ? $0 : nil } ?? local?["url"]
        guard let value, let url = URL(string: value), url.scheme == "https", url.host != nil,
              url.path == "/v1/search" else { return nil }
        return Self(endpoint: url)
    }

    #if DEBUG
        private static var usesTestFixture: Bool {
            let arguments = ProcessInfo.processInfo.arguments
            return arguments.contains("--ui-testing") && arguments.contains("--ui-testing-semantic-fixture")
        }
    #endif

    func search(_ query: String, kind: String? = nil, sources: [String]? = nil, chapter: String? = nil, session: URLSession = .shared) async throws -> [SemanticSearchResult] {
        #if DEBUG
            if Self.usesTestFixture {
                if query == "unavailable" {
                    throw URLError(.notConnectedToInternet)
                }
                let json = kind == "hadith"
                    ? #"[{"kind":"hadith","book":"bukhari","chapter":"1.json","number":105,"score":0.8}]"#
                    : #"[{"kind":"quran","chapter":2,"verse":255,"score":0.8}]"#
                let results = try JSONDecoder().decode([SemanticSearchResult].self, from: Data(json.utf8))
                return results.filter { result in
                    guard let chapter else { return true }
                    switch result.reference {
                    case let .quran(number, _): return String(number) == chapter
                    case let .hadith(_, file, _): return file == chapter
                    case .dua: return false
                    }
                }
            }
        #endif
        struct Payload: Decodable { let results: [SemanticSearchResult] }
        let request = try request(query, kind: kind, sources: sources, chapter: chapter)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.resourceUnavailable)
        }
        return try JSONDecoder().decode(Payload.self, from: data).results
    }

    func request(_ query: String, kind: String?, sources: [String]?, chapter: String?) throws -> URLRequest {
        struct Body: Encodable {
            let query: String
            let kinds: [String]?
            let sources: [String]?
            let chapter: String?
            let limit = 20
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Muntathir/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(Body(query: query, kinds: kind.map { [$0] }, sources: sources, chapter: chapter))
        return request
    }
}
