@testable import Muntathir
import SwiftUI
import Testing

struct TodayPageTests {
    @Test func columnThresholds() throws {
        let geometry = TodayPageGeometry()
        let columns = try #require(geometry.columns(in: 658, minimumWidth: 320))
        #expect(columns.leadingWidth == 320)
        #expect(columns.trailingWidth == 320)
        #expect(columns.trailingOrigin == 338)
        #expect(geometry.columns(in: 657, minimumWidth: 320) == nil)
        #expect(geometry.columns(in: 658, minimumWidth: 321) == nil)
    }

    @Test func asymmetricFoldMargins() throws {
        var geometry = TodayPageGeometry(division: CGRect(x: 420, y: 0, width: 20, height: 900),
                                         leadingMargin: 12, trailingMargin: 28, active: true)
        let columns = try #require(geometry.columns(in: 1000, minimumWidth: 320))
        #expect(columns.leadingWidth == 408)
        #expect(columns.trailingOrigin == 468)
        #expect(columns.trailingWidth == 532)
        geometry.active = false
        let inactive = try #require(geometry.columns(in: 1000, minimumWidth: 320))
        #expect(inactive.leadingWidth == 421)
        #expect(inactive.trailingOrigin == 439)
        geometry.division = .zero
        #expect(geometry.columns(in: 1000, minimumWidth: 320)?.leadingWidth == 491)
        geometry.division = CGRect(x: 250, y: 0, width: 20, height: 900)
        geometry.active = true
        #expect(geometry.columns(in: 1000, minimumWidth: 320) == nil)
    }

    @MainActor @Test(arguments: [LayoutDirection.leftToRight, .rightToLeft])
    func masonryPlacementAndRTL(direction: LayoutDirection) throws {
        let geometry = TodayPageGeometry(division: CGRect(x: 360, y: 0, width: 20, height: 900),
                                         leadingMargin: 20, trailingMargin: 20, active: true)
        let content = TodayColumnsLayout(minimumColumnWidth: 320, geometry: geometry) {
            Color.red.frame(height: 80)
            Color.blue.frame(height: 30).layoutValue(key: TodayColumnKey.self, value: 1)
            Color.green.frame(height: 40).layoutValue(key: TodayColumnKey.self, value: 1)
        }.environment(\.layoutDirection, direction)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 800, height: nil)
        let image = try #require(renderer.uiImage?.cgImage)
        #expect(image.width == 800)
        #expect(image.height == 88)
        var pixels = [UInt8](repeating: 0, count: 800 * 88 * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(data: bytes.baseAddress, width: 800, height: 88, bitsPerComponent: 8,
                                                 bytesPerRow: 800 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 800, height: 88))
        }
        let leadingX = direction == .leftToRight ? 10 : 790
        let trailingX = direction == .leftToRight ? 790 : 10
        #expect(pixels[(10 * 800 + leadingX) * 4] > 200)
        #expect(pixels[(10 * 800 + trailingX) * 4 + 2] > 200)
        #expect(pixels[(60 * 800 + trailingX) * 4 + 1] > 80)
        #expect(pixels[(10 * 800 + (direction == .leftToRight ? 370 : 430)) * 4 + 3] == 0)
    }

    @MainActor @Test func repeatedProposalsReflowWithoutRetainingWideDimensions() throws {
        let renderer = ImageRenderer(content: TodayColumnsLayout(minimumColumnWidth: 320) {
            Color.red.frame(height: 80)
            Color.blue.frame(height: 30).layoutValue(key: TodayColumnKey.self, value: 1)
            Color.green.frame(height: 40).layoutValue(key: TodayColumnKey.self, value: 1)
        })
        renderer.scale = 1
        for width in [434, 919, 434, 877, 350] {
            renderer.proposedSize = ProposedViewSize(width: CGFloat(width), height: nil)
            let image = try #require(renderer.uiImage)
            #expect(image.size.width == CGFloat(width))
            #expect(image.size.height == (width >= 658 ? 88 : 186))
        }
    }

    @MainActor @Test func longAyahFitsAfterReflow() throws {
        let verse = try #require(ContentLibrary().verses.max { $0.text.count < $1.text.count })
        let ayah = Ayah(surah: verse.surah, number: verse.number, text: verse.text,
                        translations: ["test": String(repeating: "A long translation must wrap within the card padding. ", count: 12)])
        let renderer = ImageRenderer(content: TodayColumnsLayout(minimumColumnWidth: 320) {
            Color.clear.frame(height: 80)
            DailyAyahCard(ayah: ayah).layoutValue(key: TodayColumnKey.self, value: 1)
        })
        renderer.scale = 1
        for width in [434, 919, 434] {
            renderer.proposedSize = ProposedViewSize(width: CGFloat(width), height: nil)
            let image = try #require(renderer.uiImage)
            #expect(image.size.width == CGFloat(width))
            #expect(image.size.height > 80)
        }
    }
}
