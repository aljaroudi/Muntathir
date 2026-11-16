import AppKit

/// AppKit shapes Arabic correctly and uses the same system typography as the app.
let arguments = CommandLine.arguments
precondition(arguments.count == 9, "compose frame output width height locale screen kind config")
struct ScreenshotConfig: Decodable {
    let brand: String
    let background: [[CGFloat]]
    let headlines: [String: [String: String]]
}

let config = try JSONDecoder().decode(ScreenshotConfig.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[8])))
let kind = arguments[7]
let framePath = arguments[1], output = arguments[2]
let width = CGFloat(Int(arguments[3])!), height = CGFloat(Int(arguments[4])!)
let rightToLeft = Locale.Language(identifier: arguments[5]).characterDirection == .rightToLeft
guard let headline = config.headlines[arguments[5]]?[arguments[6]],
      config.background.count == 2, config.background.allSatisfy({ $0.count == 3 })
else {
    fatalError("Invalid screenshot headline or gradient configuration")
}

guard let device = NSImage(contentsOfFile: framePath),
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create screenshot canvas") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let bounds = NSRect(x: 0, y: 0, width: width, height: height)
let colors = config.background.map { NSColor(srgbRed: $0[0], green: $0[1], blue: $0[2], alpha: 1) }
NSGradient(starting: colors[0], ending: colors[1])!.draw(in: bounds, angle: 90)
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
paragraph.baseWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
paragraph.lineBreakMode = .byWordWrapping
func text(_ value: String, size: CGFloat, color: NSColor, rect: NSRect, weight: NSFont.Weight) {
    (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                        .foregroundColor: color, .paragraphStyle: paragraph])
}

let tablet = kind == "tablet" || width > height * 0.6
let headlineRect = NSRect(x: width * 0.08, y: height * 0.79, width: width * 0.84, height: height * 0.105)
var headlineSize = width * (tablet ? 0.043 : 0.055)
// Measure shaped text, including RTL scripts, before committing to the device placement.
while headlineSize > width * 0.028 {
    let measured = (headline as NSString).boundingRect(with: NSSize(width: headlineRect.width, height: .greatestFiniteMagnitude),
                                                       options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                       attributes: [.font: NSFont.systemFont(ofSize: headlineSize, weight: .semibold), .paragraphStyle: paragraph])
    if measured.height <= headlineRect.height {
        break
    }
    headlineSize -= 1
}

text(config.brand, size: width * 0.029, color: NSColor.white.withAlphaComponent(0.78),
     rect: NSRect(x: width * 0.1, y: height * 0.915, width: width * 0.8, height: height * 0.045), weight: .medium)
text(headline, size: headlineSize, color: .white, rect: headlineRect, weight: .semibold)
let available = NSSize(width: width * 0.9, height: height * 0.735)
let scale = min(available.width / device.size.width, available.height / device.size.height)
let size = NSSize(width: device.size.width * scale, height: device.size.height * scale)
let deviceRect = NSRect(x: (width - size.width) / 2, y: height * 0.765 - size.height, width: size.width, height: size.height)
device.draw(in: deviceRect)

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
try data.write(to: URL(fileURLWithPath: output))
