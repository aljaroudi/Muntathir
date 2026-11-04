import Foundation

enum AssetDownloadSize {
    private static let sizes: [String: Int64] = {
        guard let url = Bundle.main.url(forResource: "AssetDownloadSizes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: Int64].self, from: data) else { return [:] }
        return values
    }()

    static func roundedBytes(_ bytes: Int64) -> Int64 {
        // ByteCountFormatStyle chooses localized units; round the input to avoid fractional digits.
        let unit: Int64 = bytes >= 1_000_000_000 ? 1_000_000_000 : bytes >= 1_000_000 ? 1_000_000 : bytes >= 1000 ? 1000 : 1
        return Int64((Double(bytes) / Double(unit)).rounded()) * unit
    }

    static func bytes(for pack: String) -> Int64? {
        sizes[pack]
    }
}
