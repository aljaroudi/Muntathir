import CoreGraphics
import Foundation
@testable import Muntathir
import Testing
import UIKit

struct AyahImageTests {
    @MainActor @Test func shareImageExpandsForLongVerses() throws {
        let library = ContentLibrary()
        let short = try #require(library.verses.min { $0.text.count < $1.text.count })
        let long = try #require(library.verses.max { $0.text.count < $1.text.count })
        let shortImage = try #require(AyahImageRenderer.image(for: short, locale: Locale(identifier: "en")))
        let longImage = try #require(AyahImageRenderer.image(for: long, locale: Locale(identifier: "ar")))
        try Attachment.record(#require(shortImage.pngData()), named: "ayah-share.png")
        #expect(shortImage.cgImage?.width == 1080)
        #expect(longImage.cgImage?.width == 1080)
        #expect(longImage.size.height > shortImage.size.height)
        #expect(longImage.pngData()?.isEmpty == false)
    }
}
