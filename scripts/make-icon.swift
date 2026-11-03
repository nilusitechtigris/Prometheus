// Renders the Loupe app icon as a 1024×1024 PNG.  Usage: swift scripts/make-icon.swift out.png
// A lens with a spark inside, on a night tile. The measuring bezel's lower-right ticks run
// green → yellow → red, the same ranges the app's telemetry uses.
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

/// Four-point spark with pinched sides (y-up coordinates).
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

let center = CGPoint(x: 512, y: 512)

// Apple's icon grid: 824pt body centred on a 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(squircle)
ctx.setFillColor(rgb(0x000000))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()

// Night tile with aurora glows
ctx.drawLinearGradient(gradient([rgb(0x1F1B4D), rgb(0x0A0A1C)]),
                       start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
func glow(_ hex: UInt32, _ alpha: CGFloat, at p: CGPoint, radius: CGFloat) {
    ctx.drawRadialGradient(gradient([rgb(hex, alpha), rgb(hex, 0)]), startCenter: p, startRadius: 0,
                           endCenter: p, endRadius: radius, options: [])
}
glow(0x6366F1, 0.60, at: center, radius: 430)
glow(0xA855F7, 0.40, at: CGPoint(x: 860, y: 880), radius: 420)
glow(0x22D3EE, 0.30, at: CGPoint(x: 160, y: 150), radius: 420)

// Measuring bezel
let ticks = 60
let zoneColors: [UInt32] = [0x30D158, 0x30D158, 0x30D158, 0x30D158, 0xFFD60A, 0xFFD60A, 0xFFD60A, 0xFF453A, 0xFF453A]
let zoneStart = 15
ctx.setLineCap(.round)
for i in 0..<ticks {
    let angle = CGFloat.pi / 2 - CGFloat(i) / CGFloat(ticks) * 2 * .pi   // clockwise from 12 o'clock
    let major = i % 5 == 0
    let outer: CGFloat = 378, inner: CGFloat = major ? 338 : 356
    let zone = i - zoneStart
    if zoneColors.indices.contains(zone) {
        ctx.setStrokeColor(rgb(zoneColors[zone]))
        ctx.setLineWidth(major ? 12 : 9)
    } else {
        ctx.setStrokeColor(rgb(0xFFFFFF, major ? 0.55 : 0.24))
        ctx.setLineWidth(major ? 10 : 6)
    }
    ctx.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
    ctx.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
    ctx.strokePath()
}

// Lens
let lensOuter: CGFloat = 262, ringWidth: CGFloat = 58
let lensInner = lensOuter - ringWidth

// Glass
ctx.saveGState()
ctx.addEllipse(in: circle(center, lensInner))
ctx.clip()
ctx.drawRadialGradient(gradient([rgb(0x4F46E5, 0.55), rgb(0x1E1B4B, 0.35), rgb(0x0A0A1C, 0.6)], [0, 0.6, 1]),
                       startCenter: CGPoint(x: 470, y: 560), startRadius: 0,
                       endCenter: center, endRadius: lensInner, options: [.drawsAfterEndLocation])
ctx.restoreGState()

// Ring glow, then the ring itself in a conic gradient
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 70, color: rgb(0x818CF8, 0.9))
ctx.setStrokeColor(rgb(0x6366F1))
ctx.setLineWidth(ringWidth)
ctx.strokeEllipse(in: circle(center, lensOuter - ringWidth / 2))
ctx.restoreGState()

ctx.saveGState()
ctx.addEllipse(in: circle(center, lensOuter))
ctx.addEllipse(in: circle(center, lensInner))
ctx.clip(using: .evenOdd)
// Conic gradient, drawn as thin wedges (CGContext's conic gradient isn't exposed to Swift here).
let ringStops: [(CGFloat, CGFloat, CGFloat)] = [0x22D3EE, 0x6366F1, 0xA855F7, 0xFF6FB5, 0x22D3EE].map { (hex: UInt32) in
    (CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
}
let wedges = 720
for i in 0..<wedges {
    let t = CGFloat(i) / CGFloat(wedges) * CGFloat(ringStops.count - 1)
    let a = ringStops[Int(t)], b = ringStops[min(Int(t) + 1, ringStops.count - 1)], f = t - floor(t)
    ctx.setFillColor(CGColor(srgbRed: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f, alpha: 1))
    let start = CGFloat.pi / 2 - CGFloat(i) / CGFloat(wedges) * 2 * .pi
    ctx.move(to: center)
    ctx.addArc(center: center, radius: lensOuter + 2, startAngle: start + 0.003, endAngle: start - 2 * .pi / CGFloat(wedges) - 0.003, clockwise: true)
    ctx.closePath()
    ctx.fillPath()
}
// Bevel: light from the top
ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.35), rgb(0xFFFFFF, 0), rgb(0x000000, 0.25)], [0, 0.5, 1]),
                       start: CGPoint(x: 512, y: 512 + lensOuter), end: CGPoint(x: 512, y: 512 - lensOuter), options: [])
ctx.restoreGState()

ctx.setStrokeColor(rgb(0xFFFFFF, 0.28))
ctx.setLineWidth(3)
ctx.strokeEllipse(in: circle(center, lensOuter - 1.5))

// Specular highlight on the glass, upper left
ctx.setStrokeColor(rgb(0xFFFFFF, 0.6))
ctx.setLineWidth(16)
ctx.addArc(center: center, radius: lensInner - 30, startAngle: .pi * 0.62, endAngle: .pi * 0.86, clockwise: false)
ctx.strokePath()

// Sparks
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 46, color: rgb(0xFFFFFF, 0.85))
ctx.setFillColor(rgb(0xFFFFFF))
ctx.addPath(spark(at: CGPoint(x: 498, y: 498), radius: 132))
ctx.fillPath()
ctx.addPath(spark(at: CGPoint(x: 600, y: 606), radius: 40))
ctx.fillPath()
ctx.restoreGState()

ctx.restoreGState()

// Hairline border
ctx.addPath(squircle)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.14))
ctx.setLineWidth(3)
ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
