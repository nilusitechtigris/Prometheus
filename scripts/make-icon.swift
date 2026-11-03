// Renders the app icon as a 1024×1024 PNG.  Usage: swift scripts/make-icon.swift out.png
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Apple's icon grid: 824pt body centred on a 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

// Drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill()
squircle.fill()
ctx.restoreGState()

// Background gradient
ctx.saveGState()
squircle.addClip()
let gradient = NSGradient(colors: [
    NSColor(red: 0.30, green: 0.33, blue: 0.95, alpha: 1),
    NSColor(red: 0.36, green: 0.42, blue: 0.98, alpha: 1),
    NSColor(red: 0.10, green: 0.72, blue: 0.80, alpha: 1),
])!
gradient.draw(in: body, angle: -50)

// Soft top highlight
let highlight = NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
highlight.draw(in: NSBezierPath(ovalIn: CGRect(x: 40, y: 520, width: 944, height: 560)), relativeCenterPosition: .zero)

// Subtle circuit rings
NSColor.white.withAlphaComponent(0.10).setStroke()
for r in [300.0, 380.0] {
    let ring = NSBezierPath(ovalIn: CGRect(x: 512 - r, y: 512 - r, width: r * 2, height: r * 2))
    ring.lineWidth = 6
    ring.stroke()
}

// Glyph
let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let s = symbol.size
    let rect = CGRect(x: 512 - s.width / 2, y: 512 - s.height / 2, width: s.width, height: s.height)
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    symbol.draw(in: rect)
}
ctx.restoreGState()

// Hairline border
NSColor.white.withAlphaComponent(0.18).setStroke()
squircle.lineWidth = 3
squircle.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
