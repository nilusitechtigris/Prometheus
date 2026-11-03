// Renders the Medonom app icon as a 1024×1024 PNG.  Usage: swift scripts/make-icon.swift out.png
// An "M" drawn as a glowing telemetry line, with a spark on its peak and a green → yellow → red range
// bar underneath, the same ranges the app's telemetry uses. Mirrors BrandMark in Brand.swift.
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

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

func circle(_ c: CGPoint, _ r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2) }

/// Four-point spark with pinched sides.
func spark(at c: CGPoint, radius r: CGFloat) -> CGPath {
    let pinch: CGFloat = 0.16
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + r * pinch, y: c.y + r * pinch))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + r * pinch, y: c.y - r * pinch))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - r * pinch, y: c.y - r * pinch))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - r * pinch, y: c.y + r * pinch))
    p.closeSubpath()
    return p
}

// Apple's icon grid: 824pt body centred on a 1024 canvas.
let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let tile = CGPath(roundedRect: tileRect, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(tile)
ctx.setFillColor(rgb(0x000000))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tile)
ctx.clip()

// Night tile with aurora glows
ctx.drawLinearGradient(gradient([rgb(0x1F1B4D), rgb(0x0A0A1C)]),
                       start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
func glow(_ hex: UInt32, _ alpha: CGFloat, at p: CGPoint, radius: CGFloat) {
    ctx.drawRadialGradient(gradient([rgb(hex, alpha), rgb(hex, 0)]), startCenter: p, startRadius: 0,
                           endCenter: p, endRadius: radius, options: [])
}
glow(0x6366F1, 0.55, at: CGPoint(x: 512, y: 540), radius: 460)
glow(0xA855F7, 0.35, at: CGPoint(x: 880, y: 900), radius: 400)
glow(0x22D3EE, 0.28, at: CGPoint(x: 150, y: 140), radius: 400)

// Faint chart grid
ctx.setStrokeColor(rgb(0xFFFFFF, 0.06))
ctx.setLineWidth(4)
for y: CGFloat in [330, 453, 577, 700, 823] {
    ctx.move(to: CGPoint(x: 180, y: y))
    ctx.addLine(to: CGPoint(x: 844, y: y))
}
ctx.strokePath()

// Range bar with its marker
let segments: [(CGFloat, CGFloat, UInt32)] = [(252, 494, 0x30D158), (506, 658, 0xFFD60A), (670, 772, 0xFF453A)]
for (x0, x1, hex) in segments {
    ctx.addPath(CGPath(roundedRect: CGRect(x: x0, y: 201, width: x1 - x0, height: 26), cornerWidth: 13, cornerHeight: 13, transform: nil))
    ctx.setFillColor(rgb(hex))
    ctx.fillPath()
}
ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: rgb(0x000000, 0.4))
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillEllipse(in: circle(CGPoint(x: 430, y: 214), 20))
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// The "M" as a telemetry line: glow, then the gradient stroke
let letter = CGMutablePath()
letter.addLines(between: [CGPoint(x: 252, y: 330), CGPoint(x: 352, y: 700), CGPoint(x: 512, y: 450),
                          CGPoint(x: 672, y: 700), CGPoint(x: 772, y: 330)])
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setLineWidth(80)

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 70, color: rgb(0x818CF8, 0.95))
ctx.addPath(letter)
ctx.setStrokeColor(rgb(0x6366F1))
ctx.strokePath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(letter)
ctx.replacePathWithStrokedPath()
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x22D3EE), rgb(0x6366F1), rgb(0xA855F7), rgb(0xFF6FB5)], [0, 0.35, 0.7, 1]),
                       start: CGPoint(x: 240, y: 0), end: CGPoint(x: 784, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// Light from the top
ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.30), rgb(0xFFFFFF, 0)]),
                       start: CGPoint(x: 0, y: 740), end: CGPoint(x: 0, y: 420), options: [])
ctx.restoreGState()

// Spark on the right peak
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 50, color: rgb(0xFFFFFF, 0.9))
ctx.setFillColor(rgb(0xFFFFFF))
ctx.addPath(spark(at: CGPoint(x: 672, y: 790), radius: 92))
ctx.fillPath()
ctx.restoreGState()

ctx.restoreGState()

// Hairline border
ctx.addPath(tile)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.14))
ctx.setLineWidth(3)
ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
