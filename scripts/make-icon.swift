// Renders the Prometheus app icon as a 1024×1024 PNG.  Usage: swift scripts/make-icon.swift out.png
// The lime flame and diamond from BrandMark in Brand.swift, on a near-black tile with a soft glow.
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor]) -> CGGradient { CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)! }

// Apple's icon grid: 824pt body centred on a 1024 canvas.
let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let tile = CGPath(roundedRect: tileRect, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(tile)
ctx.setFillColor(rgb(0x000000))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tile)
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x141611), rgb(0x070807)]), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.drawRadialGradient(gradient([rgb(0xA8E22A, 0.34), rgb(0xA8E22A, 0)]), startCenter: CGPoint(x: 512, y: 500), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 500), endRadius: 400, options: [])
ctx.restoreGState()

// The mark on its 100-point grid, the same points as FlameMark in Brand.swift. y runs down there.
let outline: [(CGFloat, CGFloat)] = [(50, 3), (63, 27), (73, 15), (91, 50), (68, 94), (32, 94), (9, 50), (27, 15), (37, 27)]
let cut: [(CGFloat, CGFloat)] = [(50, 38), (69, 63), (50, 88), (31, 63)]
let inner: [(CGFloat, CGFloat)] = [(50, 53), (58, 63), (50, 73), (42, 63)]
let scale: CGFloat = 5.9
let originX = 512 - 50 * scale, originY = 512 + 50 * scale

let mark = CGMutablePath()
for shape in [outline, cut, inner] {
    mark.addLines(between: shape.map { CGPoint(x: originX + $0.0 * scale, y: originY - $0.1 * scale) })
    mark.closeSubpath()
}

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 70, color: rgb(0xC6F135, 0.55))
ctx.addPath(mark)
ctx.setFillColor(rgb(0xC6F135))
ctx.fillPath(using: .evenOdd)
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(mark)
ctx.clip(using: .evenOdd)
ctx.drawLinearGradient(gradient([rgb(0xE4FF62), rgb(0xA8E22A)]), start: CGPoint(x: 512, y: 810), end: CGPoint(x: 512, y: 230), options: [])
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
