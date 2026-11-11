// Turns an AI-generated glass flame into the 1024×1024 macOS app icon.
// Usage: swift scripts/make-icon.swift source.png out.png centreY height ground glow
//
// `source` is a flame on black, of any shape: assets/art/originals/flame-ember.png for the public app,
// flame-rose.png for Prometheus Lab. `centreY` and `height` say where the flame is in that picture, as
// fractions of the picture's height: the middle of the flame from the top, and how tall it is. Across, the
// flame is taken to be in the middle. `ground` and `glow` are the theme's dark ground and its accent, as
// six hex digits, so each app's tile has its own colour behind the flame.
import AppKit

func colour(_ hex: String, alpha: CGFloat = 1) -> CGColor? {
    guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
    return CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                   blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
}

let arguments = CommandLine.arguments
guard arguments.count >= 7,
      let source = NSImage(contentsOfFile: arguments[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let centreY = Double(arguments[3]), let flameHeight = Double(arguments[4]), flameHeight > 0,
      let ground = colour(arguments[5]), let glow = colour(arguments[6], alpha: 0.3), let noGlow = colour(arguments[6], alpha: 0)
else {
    print("usage: make-icon.swift source.png icon.png centreY height ground glow")
    exit(1)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.interpolationQuality = .high

// Apple's icon grid: an 824 tile centred on the 1024 canvas.
let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                  cornerWidth: 185, cornerHeight: 185, transform: nil)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
context.addPath(tile)
context.setFillColor(ground)
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tile)
context.clip()
// The flame's light on the tile, strongest behind the glass.
let light = CGGradient(colorsSpace: space, colors: [glow, noGlow] as CFArray, locations: [0, 1])!
context.drawRadialGradient(light, startCenter: CGPoint(x: 512, y: 470), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 470), endRadius: 470, options: [])
// The flame stands about 84% of the tile's height, centred on it. It is drawn as light added to the
// tile, so the black around it in the picture leaves the tile's colour as it is.
let scale = 690 / (flameHeight * Double(source.height))
let wide = Double(source.width) * scale
let high = Double(source.height) * scale
let frame = CGRect(x: 512 - wide / 2, y: 512 - (1 - centreY) * high, width: wide, height: high)
context.setBlendMode(.screen)
context.draw(source, in: frame)
context.restoreGState()

// A hairline keeps the dark tile visible on a dark Dock.
context.addPath(tile)
context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14))
context.setLineWidth(3)
context.strokePath()

let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
