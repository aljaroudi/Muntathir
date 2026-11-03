@testable import Muntathir
import Foundation
import Testing

struct SettingsBundleTests {
    @Test func systemSettingsContainsLicensesAndTranslationCredits() throws {
        let bundle = try #require(Bundle.main.url(forResource: "Settings", withExtension: "bundle"))
        func specifiers(_ name: String) throws -> [[String: Any]] {
            let data = try Data(contentsOf: bundle.appendingPathComponent(name + ".plist"))
            let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            return try #require(plist["PreferenceSpecifiers"] as? [[String: Any]])
        }
        let root = try specifiers("Root")
        #expect(root.contains { $0["File"] as? String == "Credits" })
        let credits = try specifiers("Credits")
        #expect(credits.contains { $0["File"] as? String == "Adhan" })
        for translation in QuranTranslation.catalog {
            #expect(credits.contains {
                $0["Title"] as? String == translation.translator
                    && $0["FooterText"] as? String == "https://tanzil.net/trans/\(translation.id)"
            })
        }
        let licenseURL = try #require(Bundle.main.url(forResource: "Adhan-LICENSE", withExtension: "txt"))
        let license = try String(contentsOf: licenseURL, encoding: .utf8)
        #expect(try specifiers("Adhan").contains { $0["FooterText"] as? String == license })
    }
}
