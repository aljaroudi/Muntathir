import CoreGraphics
import Foundation
@testable import Muntathir
import Testing
import UIKit

struct AyahImageTests {
    @MainActor @Test func quranFontIsBundledAndRegistered() throws {
        #expect(Bundle.main.url(forResource: "QPCHafs", withExtension: "woff2") != nil)
        let font = try #require(UIFont(name: "KFGQPCHAFSUthmanicScript-Regula", size: 28))
        #expect(font.fontName == "KFGQPCHAFSUthmanicScript-Regula")
    }

    @MainActor @Test func shareImageExpandsForLongVerses() throws {
        let library = ContentLibrary()
        let short = try #require(library.verses.min { $0.text.count < $1.text.count })
        let long = try #require(library.verses.max { $0.text.count < $1.text.count })
        let shortImage = try #require(AyahImageRenderer.image(for: short, locale: Locale(identifier: "en")))
        // Repeat an existing verse to exercise overflow beyond the artwork's minimum height.
        let overflowing = Ayah(surah: long.surah, number: long.number, text: Array(repeating: long.text, count: 10).joined(separator: "\n"))
        let longImage = try #require(AyahImageRenderer.image(for: overflowing, locale: Locale(identifier: "ar")))
        try Attachment.record(#require(shortImage.pngData()), named: "ayah-share.png")
        #expect(shortImage.cgImage?.width == 1080)
        #expect(longImage.cgImage?.width == 1080)
        #expect(longImage.size.height > shortImage.size.height)
        #expect(longImage.pngData()?.isEmpty == false)
    }
}
