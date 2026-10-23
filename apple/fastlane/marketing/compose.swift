import AppKit

/// AppKit shapes Arabic correctly and uses the same system typography as the app.
let arguments = CommandLine.arguments
precondition(arguments.count == 8, "compose frame output width height locale headline kind")
let kind = arguments[7]
let framePath = arguments[1], output = arguments[2]
let width = CGFloat(Int(arguments[3])!), height = CGFloat(Int(arguments[4])!)
let rightToLeft = Locale.Language(identifier: arguments[5]).characterDirection == .rightToLeft
let headline = arguments[6]
guard let device = NSImage(contentsOfFile: framePath),
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create screenshot canvas") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let bounds = NSRect(x: 0, y: 0, width: width, height: height)
NSGradient(starting: NSColor(srgbRed: 0.06, green: 0.15, blue: 0.25, alpha: 1),
           ending: NSColor(srgbRed: 0.17, green: 0.35, blue: 0.43, alpha: 1))!.draw(in: bounds, angle: 90)
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
paragraph.baseWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
paragraph.lineBreakMode = .byWordWrapping
func text(_ value: String, size: CGFloat, color: NSColor, rect: NSRect, weight: NSFont.Weight) {
    (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                        .foregroundColor: color, .paragraphStyle: paragraph])
}

let brand = "منتظِر"
text(brand, size: width * 0.029, color: NSColor.white.withAlphaComponent(0.78),
     rect: NSRect(x: width * 0.1, y: height * 0.91, width: width * 0.8, height: height * 0.045), weight: .medium)
text(headline, size: width * (rightToLeft ? 0.051 : 0.049), color: .white,
     rect: NSRect(x: width * 0.08, y: height * 0.79, width: width * 0.84, height: height * 0.12), weight: .semibold)
let available = NSSize(width: width * 0.87, height: height * 0.73)
let scale = min(available.width / device.size.width, available.height / device.size.height)
let size = NSSize(width: device.size.width * scale, height: device.size.height * scale)
let deviceRect = NSRect(x: (width - size.width) / 2, y: (height * 0.83) - size.height, width: size.width, height: size.height)
if kind == "duo" {
    let bezel = deviceRect.insetBy(dx: -width * 0.012, dy: -width * 0.012)
    NSColor(srgbRed: 0.08, green: 0.09, blue: 0.10, alpha: 1).setFill()
    NSBezierPath(roundedRect: bezel, xRadius: width * 0.035, yRadius: width * 0.035).fill()
}

NSGraphicsContext.saveGraphicsState()
if kind == "duo" {
    NSBezierPath(roundedRect: deviceRect, xRadius: width * 0.023, yRadius: width * 0.023).addClip()
}

device.draw(in: deviceRect)
NSGraphicsContext.restoreGraphicsState()
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
try data.write(to: URL(fileURLWithPath: output))
