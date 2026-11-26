// Renders the 1024x500 Play feature graphic: feature_graphic <icon.png> <font.ttf> <rtl|ltr> <title> <tagline> <out.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 7, let icon = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: feature_graphic icon font rtl|ltr title tagline out\n".utf8))
    exit(2)
}
CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: args[2]) as CFURL, .process, nil)
let rtl = args[3] == "rtl"
let (title, tagline) = (args[4], args[5])
let width = 1024, height = 500
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context

func hex(_ value: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(value >> 16 & 255) / 255, green: CGFloat(value >> 8 & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
}
let canvas = NSRect(x: 0, y: 0, width: width, height: height)
NSGradient(starting: hex(0x174F45), ending: hex(0x082F2B))!.draw(in: canvas, angle: -25)

let side: CGFloat = 280
let margin: CGFloat = 96
let iconX = rtl ? CGFloat(width) - margin - side : margin
let iconRect = NSRect(x: iconX, y: (CGFloat(height) - side) / 2, width: side, height: side)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -8)
shadow.set()
NSBezierPath(roundedRect: iconRect, xRadius: 64, yRadius: 64).addClip()
icon.draw(in: iconRect)
NSGraphicsContext.restoreGraphicsState()

let gap: CGFloat = 56
let textWidth = CGFloat(width) - margin * 2 - side - gap
let textX = rtl ? margin : iconRect.maxX + gap
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = rtl ? .right : .left
paragraph.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
func draw(_ value: String, size: CGFloat, weight: String, color: NSColor, y: CGFloat, height: CGFloat) {
    let family = rtl ? "IBM Plex Sans Arabic" : "Helvetica Neue"
    let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: weight == "bold" ? 9 : 5, size: size)
        ?? NSFont.systemFont(ofSize: size, weight: weight == "bold" ? .bold : .regular)
    (value as NSString).draw(with: NSRect(x: textX, y: y, width: textWidth, height: height), options: [.usesLineFragmentOrigin],
                             attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
}
draw(title, size: rtl ? 92 : 84, weight: "bold", color: hex(0xF5F0DF), y: 250, height: 130)
draw(tagline, size: 32, weight: "regular", color: hex(0xDCC18A), y: 120, height: 120)

context.flushGraphics()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[6]))
