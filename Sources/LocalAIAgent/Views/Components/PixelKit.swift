import AppKit
import SwiftUI

/// The pixel-art look's building blocks. One art pixel is `Pixel.unit` points, so a corner, a bar and an
/// icon all step by the same amount.
enum Pixel {
    static let unit: CGFloat = 2
    /// Borders are whole device pixels, so they stay crisp.
    static let line: CGFloat = 1
}

// MARK: - Shapes

/// A box with stepped corners, standing in for a rounded rectangle.
struct PixelRect: InsettableShape {
    var radius: CGFloat = 6
    private var inset: CGFloat = 0

    init(radius: CGFloat = 6) { self.radius = radius }

    /// For controls that would otherwise be capsules.
    static let pill = PixelRect(radius: 8)
    /// For anything that would otherwise be a circle: the steps grow with its size.
    static let round = PixelRect(radius: .infinity)

    func inset(by amount: CGFloat) -> PixelRect {
        var shape = self
        shape.inset += amount
        return shape
    }

    private func steps(in rect: CGRect) -> Int {
        let side = min(rect.width, rect.height)
        let wanted = radius == .infinity ? (side < 9 ? 0 : Int(side / 9)) : Int(radius / 4)
        return max(min(wanted, 4, Int(side / (Pixel.unit * 2.5))), 0)
    }

    func path(in frame: CGRect) -> Path {
        let rect = frame.insetBy(dx: inset, dy: inset)
        var path = Path()
        guard rect.width > 0, rect.height > 0 else { return path }
        let count = steps(in: rect)
        guard count > 0 else { return Path(rect) }

        // One corner as distances from its two edges, walking from the top edge to the side edge.
        var corner = [(x: count, y: 0)]
        for step in 1...count {
            corner.append((count - step + 1, step))
            corner.append((count - step, step))
        }
        let u = Pixel.unit
        var points = corner.map { CGPoint(x: rect.maxX - CGFloat($0.x) * u, y: rect.minY + CGFloat($0.y) * u) }
        points += corner.reversed().map { CGPoint(x: rect.maxX - CGFloat($0.x) * u, y: rect.maxY - CGFloat($0.y) * u) }
        points += corner.map { CGPoint(x: rect.minX + CGFloat($0.x) * u, y: rect.maxY - CGFloat($0.y) * u) }
        points += corner.reversed().map { CGPoint(x: rect.minX + CGFloat($0.x) * u, y: rect.minY + CGFloat($0.y) * u) }
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

// MARK: - Rasterizing

/// Turns smooth drawings into hard pixels: draw small, then keep each cell or drop it.
enum PixelRaster {
    /// Which cells of a width × height grid a drawing covers, top row first. The drawing gets a context
    /// one point per cell, with its origin at the bottom left.
    static func cells(width: Int, height: Int, threshold: UInt8 = 105, draw: (CGContext) -> Void) -> [Bool] {
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return [] }
        draw(context)
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        return (0..<(width * height)).map { bytes[$0 * 4 + 3] >= threshold }
    }

    /// A template image with one image pixel per cell.
    static func image(_ cells: [Bool], width: Int, height: Int) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)
        if let pixels = rep?.bitmapData {
            for row in 0..<height {
                for column in 0..<width where cells[row * width + column] {
                    pixels[(row * width + column) * 4 + 3] = 255
                }
            }
        }
        let image = NSImage(size: NSSize(width: width, height: height))
        if let rep { image.addRepresentation(rep) }
        image.isTemplate = true
        return image
    }

    /// The cells as one path, for drawing in a Canvas.
    static func path(_ cells: [Bool], width: Int, height: Int, unit: CGFloat) -> Path {
        var path = Path()
        for row in 0..<height {
            for column in 0..<width where cells[row * width + column] {
                path.addRect(CGRect(x: CGFloat(column) * unit, y: CGFloat(row) * unit, width: unit, height: unit))
            }
        }
        return path
    }
}

/// Any shape, drawn on the pixel grid in the foreground style.
struct PixelatedShape<S: Shape>: View {
    let shape: S
    /// Stroke it at this width instead of filling it.
    var stroke: CGFloat?
    var unit: CGFloat = Pixel.unit

    var body: some View {
        Canvas { context, size in
            let width = Int(size.width / unit), height = Int(size.height / unit)
            var outline = shape.path(in: CGRect(origin: .zero, size: size))
            if let stroke { outline = outline.strokedPath(StrokeStyle(lineWidth: stroke)) }
            let cells = PixelRaster.cells(width: width, height: height) { cg in
                cg.scaleBy(x: 1 / unit, y: 1 / unit)
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: 1, y: -1)
                cg.addPath(outline.cgPath)
                cg.fillPath()
            }
            context.fill(PixelRaster.path(cells, width: width, height: height, unit: unit), with: .foreground)
        }
    }
}

// MARK: - Icons

/// An SF Symbol redrawn in hard pixels. The real symbol stays, invisible, to set the size, so fonts,
/// frames and foreground styles work exactly as they do on any icon.
struct PixelIcon: View {
    let name: String

    init(_ name: String) { self.name = name }

    var body: some View {
        Image(systemName: name)
            .hidden()
            .overlay {
                GeometryReader { geo in
                    let side = max(geo.size.width, geo.size.height)
                    // Small icons get one-point pixels. Big ones keep about 16 cells, on half-point steps.
                    let cell = max(1, (side / 16 * 2).rounded() / 2)
                    let grid = max(Int((side / cell).rounded(.up)), 8)
                    Image(nsImage: PixelSymbols.image(name, grid: grid))
                        .renderingMode(.template)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: CGFloat(grid) * cell, height: CGFloat(grid) * cell)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .accessibilityHidden(true)
    }
}

/// A title with a pixel icon.
struct PixelLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label { Text(title) } icon: { PixelIcon(systemImage) }
    }
}

private enum PixelSymbols {
    private static var cache: [String: NSImage] = [:]

    @MainActor static func image(_ name: String, grid: Int) -> NSImage {
        let key = "\(name)@\(grid)"
        if let cached = cache[key] { return cached }
        let config = NSImage.SymbolConfiguration(pointSize: CGFloat(grid) * 0.78, weight: .semibold)
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        let cells = PixelRaster.cells(width: grid, height: grid) { cg in
            guard let symbol else { return }
            let drawing = NSGraphicsContext(cgContext: cg, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = drawing
            let size = symbol.size
            symbol.draw(in: NSRect(x: (CGFloat(grid) - size.width) / 2, y: (CGFloat(grid) - size.height) / 2,
                                   width: size.width, height: size.height))
            NSGraphicsContext.restoreGraphicsState()
        }
        let image = PixelRaster.image(cells, width: grid, height: grid)
        cache[key] = image
        return image
    }
}

/// Text in a script the pixel font doesn't have, drawn small and pixelated.
struct PixelText: View {
    let text: String
    var size: CGFloat = 14

    init(_ text: String, size: CGFloat = 14) {
        self.text = text
        self.size = size
    }

    var body: some View {
        let string = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold)])
        let bounds = string.size()
        let width = Int(bounds.width.rounded(.up)) + 1, height = Int(bounds.height.rounded(.up))
        Canvas { context, _ in
            let cells = PixelRaster.cells(width: width, height: height) { cg in
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
                string.draw(at: .zero)
                NSGraphicsContext.restoreGraphicsState()
            }
            context.fill(PixelRaster.path(cells, width: width, height: height, unit: 1), with: .foreground)
        }
        .frame(width: CGFloat(width), height: CGFloat(height))
        .accessibilityLabel(text)
    }
}

// MARK: - Sprites

/// Hand-placed pixel art: one character per pixel, with `.` left empty.
struct PixelSprite: View {
    let rows: [String]
    let palette: [Character: Color]
    var cell: CGFloat = Pixel.unit

    var body: some View {
        Canvas { context, _ in
            for (y, row) in rows.enumerated() {
                for (x, character) in row.enumerated() {
                    guard let color = palette[character] else { continue }
                    context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)), with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(rows.first?.count ?? 0) * cell, height: CGFloat(rows.count) * cell)
    }
}

// MARK: - Motion and progress

/// Blocks chasing round a square, in place of the system spinner.
struct PixelSpinner: View {
    var size: CGFloat = 14
    private static let frame = 0.11
    private static let ring = [(0, 0), (1, 0), (2, 0), (2, 1), (2, 2), (1, 2), (0, 2), (0, 1)]

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.frame)) { timeline in
            let head = Int(timeline.date.timeIntervalSinceReferenceDate / Self.frame) % Self.ring.count
            Canvas { context, canvas in
                let cell = canvas.width / 3
                for (index, spot) in Self.ring.enumerated() {
                    let behind = (head - index + Self.ring.count) % Self.ring.count
                    let rect = CGRect(x: CGFloat(spot.0) * cell, y: CGFloat(spot.1) * cell, width: cell, height: cell)
                    context.fill(Path(rect.insetBy(dx: 0.5, dy: 0.5)),
                                 with: .color(Palette.accent.opacity(behind > 3 ? 0.14 : 1 - Double(behind) * 0.25)))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Working")
    }
}

/// A progress bar made of blocks.
struct PixelBar: View {
    let fraction: Double
    var height: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            let pitch: CGFloat = 6
            let count = Int(size.width / pitch)
            let filled = Int((min(max(fraction, 0), 1) * Double(count)).rounded(.up))
            for index in 0..<count {
                let block = CGRect(x: CGFloat(index) * pitch, y: 0, width: pitch - 2, height: size.height)
                context.fill(Path(block), with: .color(index < filled ? Palette.accent : Color.primary.opacity(0.1)))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

// MARK: - Buttons

/// A chunky button with a hard edge that presses down one step.
struct PixelButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = PixelRect(radius: 6)
        configuration.label
            .font(.uiCaption)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(prominent ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Color.white.opacity(configuration.isPressed ? 0.14 : 0.08)), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(prominent ? 0.3 : 0.16), lineWidth: Pixel.line))
            .opacity(enabled ? 1 : 0.45)
            .offset(y: configuration.isPressed ? Pixel.unit / 2 : 0)
    }
}
