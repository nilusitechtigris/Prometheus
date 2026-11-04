// Renders the Prometheus app icon as a 1024×1024 PNG.  Usage: swift scripts/make-icon.swift out.png
// A blue flame in three layers with the AI spark at its heart, on a black tile over a Greek key: the
// fire, brought down to your own machine. Mirrors BrandMark in Brand.swift.
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

/// The flame, in icon coordinates, scaled about its base.
func flame(scale: CGFloat = 1, shift: CGPoint = .zero) -> CGPath {
    let base = CGPoint(x: 512, y: 168)
    let transform = CGAffineTransform(translationX: base.x + shift.x, y: base.y + shift.y)
        .scaledBy(x: scale, y: scale)
        .translatedBy(x: -base.x, y: -base.y)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 512, y: 168), transform: transform)
    p.addCurve(to: CGPoint(x: 756, y: 420), control1: CGPoint(x: 650, y: 168), control2: CGPoint(x: 756, y: 276), transform: transform)
    p.addCurve(to: CGPoint(x: 618, y: 720), control1: CGPoint(x: 756, y: 556), control2: CGPoint(x: 650, y: 620), transform: transform)
    p.addCurve(to: CGPoint(x: 556, y: 890), control1: CGPoint(x: 600, y: 776), control2: CGPoint(x: 592, y: 842), transform: transform)
    p.addCurve(to: CGPoint(x: 446, y: 640), control1: CGPoint(x: 548, y: 800), control2: CGPoint(x: 476, y: 730), transform: transform)
    p.addCurve(to: CGPoint(x: 436, y: 556), control1: CGPoint(x: 436, y: 608), control2: CGPoint(x: 432, y: 584), transform: transform)
    p.addCurve(to: CGPoint(x: 346, y: 704), control1: CGPoint(x: 404, y: 590), control2: CGPoint(x: 360, y: 640), transform: transform)
    p.addCurve(to: CGPoint(x: 268, y: 420), control1: CGPoint(x: 296, y: 624), control2: CGPoint(x: 268, y: 524), transform: transform)
    p.addCurve(to: CGPoint(x: 512, y: 168), control1: CGPoint(x: 268, y: 276), control2: CGPoint(x: 374, y: 168), transform: transform)
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

// Black tile, lit from below
ctx.drawLinearGradient(gradient([rgb(0x0F1A30), rgb(0x05070D)]),
                       start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
func glow(_ hex: UInt32, _ alpha: CGFloat, at p: CGPoint, radius: CGFloat) {
    ctx.drawRadialGradient(gradient([rgb(hex, alpha), rgb(hex, 0)]), startCenter: p, startRadius: 0,
                           endCenter: p, endRadius: radius, options: [])
}
glow(0x1F6BFF, 0.55, at: CGPoint(x: 512, y: 400), radius: 470)
glow(0x1238C8, 0.40, at: CGPoint(x: 512, y: 170), radius: 420)

// A Greek key at the foot of the tile: eight turns, wholly inside the rounded corners. Same as Meander.
let keyUnit: CGFloat = 11
let keyBase: CGFloat = 112
let key = CGMutablePath()
key.move(to: CGPoint(x: 248, y: keyBase))
for turn in 0..<8 {
    let x = 248 + CGFloat(turn) * keyUnit * 6
    key.addLine(to: CGPoint(x: x, y: keyBase + keyUnit * 4))
    key.addLine(to: CGPoint(x: x + keyUnit * 4, y: keyBase + keyUnit * 4))
    key.addLine(to: CGPoint(x: x + keyUnit * 4, y: keyBase + keyUnit * 2))
    key.addLine(to: CGPoint(x: x + keyUnit * 2, y: keyBase + keyUnit * 2))
    key.addLine(to: CGPoint(x: x + keyUnit * 2, y: keyBase))
    key.addLine(to: CGPoint(x: x + keyUnit * 6, y: keyBase))
}
ctx.addPath(key)
ctx.setStrokeColor(rgb(0x6CB6FF, 0.6))
ctx.setLineWidth(7)
ctx.setLineJoin(.miter)
ctx.strokePath()

// Rising sparks
for (x, y, r, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) in [
    (250, 800, 8, 0.55), (300, 862, 5, 0.4), (726, 842, 9, 0.6), (786, 748, 6, 0.45),
    (668, 874, 5, 0.35), (210, 660, 6, 0.4), (820, 610, 5, 0.3), (392, 846, 4, 0.35),
] {
    ctx.setFillColor(rgb(0x9FD0FF, alpha))
    ctx.fillEllipse(in: circle(CGPoint(x: x, y: y), r))
}

// Outer flame with its glow
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 80, color: rgb(0x2F7BFF, 0.85))
ctx.addPath(flame())
ctx.setFillColor(rgb(0x1F5FE8))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(flame())
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x1238C8), rgb(0x2F7BFF), rgb(0x6CB6FF)], [0, 0.5, 1]),
                       start: CGPoint(x: 512, y: 168), end: CGPoint(x: 512, y: 890), options: [])
ctx.restoreGState()

// Middle flame
ctx.saveGState()
ctx.addPath(flame(scale: 0.70, shift: CGPoint(x: 6, y: 18)))
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x3FA2FF), rgb(0x7FD4FF)]),
                       start: CGPoint(x: 512, y: 180), end: CGPoint(x: 512, y: 700), options: [])
ctx.restoreGState()

// Inner flame
ctx.saveGState()
ctx.addPath(flame(scale: 0.42, shift: CGPoint(x: 8, y: 34)))
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0x8FDCFF), rgb(0xEAF7FF)]),
                       start: CGPoint(x: 512, y: 200), end: CGPoint(x: 512, y: 520), options: [])
ctx.restoreGState()

// The spark at the heart of the fire
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 34, color: rgb(0xFFFFFF, 0.95))
ctx.setFillColor(rgb(0xFFFFFF))
ctx.addPath(spark(at: CGPoint(x: 518, y: 306), radius: 74))
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
