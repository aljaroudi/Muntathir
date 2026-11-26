import AppIntents
import CoreSpotlight
import Foundation

enum MuntathirIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noLocation
    case hadithMissing
    case supplicationsMissing
    case rulingsMissing
    case notFound
    case unavailableOnThisDevice

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noLocation: "Choose a location in Muntathir to see prayer times."
        case .hadithMissing: "Hadith isn't downloaded yet. Open Muntathir to download it."
        case .supplicationsMissing: "Supplications aren't downloaded yet. Open Muntathir to download them."
        case .rulingsMissing: "Rulings aren't downloaded yet. Open Muntathir to download them."
        case .notFound: "Muntathir couldn't find that."
        case .unavailableOnThisDevice: "This tool isn't available on this device."
        }
    }
}

/// Readers for the downloadable packs, installed from what's already on the device. Never starts a download.
@MainActor enum PackAccess {
    static func hadith() async throws -> HadithReader {
        try await ready(AssetPackUpdates.shared.hadith, missing: .hadithMissing)
    }

    static func supplications() async throws -> HadithReader {
        try await ready(AssetPackUpdates.shared.supplications, missing: .supplicationsMissing)
    }

    static func rulings() async throws -> RulingsReader {
        let store = AssetPackUpdates.shared.rulings
        if store.state != .ready {
            await store.refresh()
            // Another refresh may already be running, such as the app's launch check.
            for _ in 0 ..< 50 where store.state == .checking {
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        guard store.state == .ready else { throw MuntathirIntentError.rulingsMissing }
        return store.reader
    }

    private static func ready(_ store: HadithAssetStore, missing: MuntathirIntentError) async throws -> HadithReader {
        if store.state != .ready {
            await store.refresh()
            for _ in 0 ..< 50 where store.state == .checking || store.state == .installing {
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        guard store.state == .ready else { throw missing }
        return store.reader
    }
}

extension Rulings.ID {
    /// Reverses `key`'s length-prefixed encoding.
    init?(key: String) {
        let bytes = Array(key.utf8)
        var parts: [String] = []
        var index = 0
        while index < bytes.count {
            guard let colon = bytes[index...].firstIndex(of: UInt8(ascii: ":")),
                  let count = Int(String(decoding: bytes[index ..< colon], as: UTF8.self)),
                  count >= 0, colon + 1 + count <= bytes.count else { return nil }
            parts.append(String(decoding: bytes[colon + 1 ..< colon + 1 + count], as: UTF8.self))
            index = colon + 1 + count
        }
        guard parts.count == 3 else { return nil }
        self.init(authority: parts[0], language: parts[1], siteID: parts[2])
    }
}

/// Puts the bundled surahs, figures, and events in Spotlight, again only when the app or its language changes.
enum SpotlightEntities {
    private static let key = "spotlightEntities.v1"

    static func update(defaults: UserDefaults = .standard) async {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let stamp = build + "|" + (Locale.preferredLanguages.first ?? "")
        guard defaults.string(forKey: key) != stamp else { return }
        do {
            let index = CSSearchableIndex.default()
            try await index.indexAppEntities(SurahQuery().suggestedEntities())
            try await index.indexAppEntities(FigureQuery().suggestedEntities())
            try await index.indexAppEntities(IslamicEventQuery().suggestedEntities())
            defaults.set(stamp, forKey: key)
        } catch {
            // Tried again on the next launch.
        }
    }
}
