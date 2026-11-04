// Renders the Prometheus app icon as a 1024×1024 PNG.  Usage: swift scripts/make-icon.swift out.png
// Pixel art: the blue flame from BrandMark in Brand.swift, on a black stepped tile over a Greek key:
// the fire, brought down to your own machine.
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let flame = [
    "........d.......",
    ".......dd.......",
    ".......dbd......",
    "......dbbd...d..",
    "...d..dbbbd..dd.",
    "...dd.dbbbbddbd.",
    "..dbd.dbblbbbbd.",
    "..dbbddbllbbbbd.",
    "..dbbbbbllbblbd.",
    "..dblbbllllllbd.",
    "..dbllblcclllbd.",
    "..dbllccccllbd..",
    "...dblcwwcllbd..",
    "...dbblcwclbd...",
    "....ddbbbbbd....",
    "......dddd......",
]
let palette: [Character: UInt32] = ["d": 0x1238C8, "b": 0x2F7BFF, "l": 0x6CB6FF, "c": 0xBDE3FF, "w": 0xFFFFFF]

// One turn of Greek key, the same path as Meander in GreekMotifs.swift.
let key = [
    "#####.",
    "#...#.",
    "#.###.",
    "#.#...",
    "#.####",
]

// Apple's icon grid is an 824-point body on a 1024 canvas, which here is 24 pixels of 34 points.
let grid = 24
let cell: CGFloat = 34
let origin = (1024 - CGFloat(grid) * cell) / 2

/// Fills one pixel. Row 0 is the top.
func pixel(_ column: Int, _ row: Int, _ color: CGColor) {
    ctx.setFillColor(color)
    ctx.fill(CGRect(x: origin + CGFloat(column) * cell, y: 1024 - origin - CGFloat(row + 1) * cell, width: cell, height: cell))
}

/// How many pixels the stepped corners cut from each row.
func cut(_ row: Int) -> Int {
    let edge = min(row, grid - 1 - row)
    return edge < 3 ? 3 - edge : 0
}

// The stepped tile, with one row of lighter edge along its top.
for row in 0..<grid {
    for column in cut(row)..<(grid - cut(row)) {
        pixel(column, row, rgb(row < 2 ? 0x0F1A30 : (row > 19 ? 0x0A1224 : 0x05070D)))
    }
}

// The flame.
for (y, line) in flame.enumerated() {
    for (x, character) in line.enumerated() {
        if let hex = palette[character] { pixel(x + 4, y + 2, rgb(hex)) }
    }
}

// Three turns of Greek key along the foot of the tile.
for (y, line) in key.enumerated() {
    let cells = Array(String(repeating: line, count: 3))
    for x in 0..<(cells.count - 1) where cells[x] == "#" {
        pixel(x + 3, y + 18, rgb(0x6CB6FF))
    }
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
