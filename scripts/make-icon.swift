// Turns the AI-generated flame into the 1024×1024 macOS app icon, and optionally the logo the app draws.
// Usage: swift scripts/make-icon.swift assets/icon-source.png out.png [assets/art/flame.png]
import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 3,
      let source = NSImage(contentsOfFile: arguments[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    print("usage: make-icon.swift source.png icon.png [logo.png]")
    exit(1)
}

// The flame's place in the picture, as fractions of its side. The picture is black everywhere else.
let flameCentre = CGPoint(x: 0.499, y: 0.464)
let flameHeight: CGFloat = 0.616
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func canvas(_ wide: Int, _ high: Int) -> CGContext {
    CGContext(data: nil, width: wide, height: high, bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func save(_ context: CGContext, to path: String) {
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func writeIcon(to path: String) {
    let size = 1024
    let context = canvas(size, size)
    context.interpolationQuality = .high

    // Apple's icon grid: an 824 tile centred on the 1024 canvas.
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                      cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                      color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
    context.addPath(tile)
    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // The flame stands about 70% of the tile's height, centred on it.
    let side = 580 / flameHeight
    let frame = CGRect(x: 512 - flameCentre.x * side, y: 512 - (1 - flameCentre.y) * side, width: side, height: side)
    context.saveGState()
    context.addPath(tile)
    context.clip()
    context.draw(source, in: frame)
    context.restoreGState()

    // A hairline keeps the black tile visible on a dark Dock.
    context.addPath(tile)
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14))
    context.setLineWidth(3)
    context.strokePath()
    save(context, to: path)
}

/// The flame alone on transparency, in a square so it sits in the same frame the app gives its logo.
func writeLogo(to path: String) {
    let wide = source.width
    let crop = Int(CGFloat(wide) * flameHeight / 0.98)
    let origin = CGPoint(x: CGFloat(wide) * flameCentre.x - CGFloat(crop) / 2,
                         y: CGFloat(source.height) * flameCentre.y - CGFloat(crop) / 2)
    let square = source.cropping(to: CGRect(origin: origin, size: CGSize(width: crop, height: crop)))!

    let context = canvas(crop, crop)
    context.draw(square, in: CGRect(x: 0, y: 0, width: crop, height: crop))
    let pixels = context.data!.bindMemory(to: UInt8.self, capacity: crop * context.bytesPerRow)
    for offset in stride(from: 0, to: crop * context.bytesPerRow, by: 4) {
        // Green is the flame's brightest channel, so it says how much of each edge pixel is flame.
        let green = pixels[offset + 1]
        pixels[offset] = green
        pixels[offset + 2] = green
        pixels[offset + 3] = green
    }
    save(context, to: path)
}

writeIcon(to: arguments[2])
if arguments.count > 3 { writeLogo(to: arguments[3]) }
