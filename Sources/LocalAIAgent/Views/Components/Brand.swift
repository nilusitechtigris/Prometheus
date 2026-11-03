import SwiftUI

/// Name and voice in one place, so a rename is a one-line change.
enum Brand {
    static let name = "Medonom"
    static let tagline = "Local AI, measured."
}

/// The Medonom mark: an "M" drawn as a glowing telemetry line, with a spark on its peak and the
/// app's green / yellow / red range bar underneath. Same drawing as the app icon
/// (scripts/make-icon.swift), with the line in the current theme's colours.
struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        let detailed = size >= 44
        let lineColors = [Palette.accent2, Palette.accent, Palette.glow]
        tile
            .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.11, blue: 0.29), Color(red: 0.04, green: 0.04, blue: 0.12)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                RadialGradient(colors: [Palette.accent.opacity(0.5), .clear], center: .center,
                               startRadius: 0, endRadius: size * 0.6)
            }
            .overlay {
                Canvas { ctx, canvas in
                    let m = MarkGeometry(side: canvas.width)
                    if detailed {
                        for y in MarkGeometry.gridLines {
                            var line = Path()
                            line.move(to: m.point(180, y))
                            line.addLine(to: m.point(844, y))
                            ctx.stroke(line, with: .color(.white.opacity(0.06)), lineWidth: max(m.scale(4), 0.5))
                        }
                        for segment in m.rangeSegments {
                            ctx.fill(Path(roundedRect: segment.rect, cornerRadius: segment.rect.height / 2), with: .color(segment.color))
                        }
                        ctx.fill(Path(ellipseIn: m.circle(m.marker, radius: m.scale(20))), with: .color(.white))
                    }
                    let stroke = StrokeStyle(lineWidth: m.scale(detailed ? 80 : 104), lineCap: .round, lineJoin: .round)
                    var glow = ctx
                    glow.addFilter(.shadow(color: Palette.accent.opacity(0.9), radius: m.scale(36)))
                    glow.stroke(m.letter, with: .linearGradient(Gradient(colors: lineColors), startPoint: m.point(240, 0), endPoint: m.point(784, 0)),
                                style: stroke)
                    var spark = ctx
                    spark.addFilter(.shadow(color: .white.opacity(0.85), radius: m.scale(30)))
                    spark.fill(SparkShape().path(in: m.circle(m.sparkCenter, radius: m.scale(detailed ? 92 : 120))), with: .color(.white))
                }
            }
            .clipShape(tile)
            .overlay(tile.strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .frame(width: size, height: size)
            .shadow(color: Palette.accent.opacity(0.35), radius: size * 0.12, y: size * 0.05)
    }
}

/// Mark geometry in the 1024-point icon space (y up, tile from 100 to 924), mapped onto a square view.
struct MarkGeometry {
    let side: CGFloat

    func scale(_ v: CGFloat) -> CGFloat { v / 824 * side }
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - 100) / 824 * side, y: (924 - y) / 824 * side) }
    func circle(_ c: CGPoint, radius r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2) }

    /// The "M": two peaks, like a telemetry line.
    static let letterPoints: [CGPoint] = [
        CGPoint(x: 252, y: 330), CGPoint(x: 352, y: 700), CGPoint(x: 512, y: 450),
        CGPoint(x: 672, y: 700), CGPoint(x: 772, y: 330),
    ]
    static let gridLines: [CGFloat] = [330, 453, 577, 700, 823]

    var letter: Path {
        var p = Path()
        p.addLines(Self.letterPoints.map { point($0.x, $0.y) })
        return p
    }

    var sparkCenter: CGPoint { point(672, 790) }

    struct Segment { let rect: CGRect; let color: Color }

    /// The range bar under the letter: green, yellow, red, like every metric in the app.
    var rangeSegments: [Segment] {
        let y: CGFloat = 214, h: CGFloat = 26, gap: CGFloat = 12
        let spans: [(CGFloat, CGFloat, Color)] = [(252, 500, Palette.good), (500, 664, Palette.warning), (664, 772, Palette.critical)]
        return spans.enumerated().map { i, s in
            let x0 = s.0 + (i == 0 ? 0 : gap / 2), x1 = s.1 - (i == spans.count - 1 ? 0 : gap / 2)
            return Segment(rect: CGRect(origin: point(x0, y + h / 2), size: CGSize(width: scale(x1 - x0), height: scale(h))), color: s.2)
        }
    }

    var marker: CGPoint { point(430, 227) }
}

/// Four-point spark with pinched sides.
struct SparkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2, ry = rect.height / 2
        let pinch: CGFloat = 0.16
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - ry))
        p.addQuadCurve(to: CGPoint(x: c.x + rx, y: c.y), control: CGPoint(x: c.x + rx * pinch, y: c.y - ry * pinch))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + ry), control: CGPoint(x: c.x + rx * pinch, y: c.y + ry * pinch))
        p.addQuadCurve(to: CGPoint(x: c.x - rx, y: c.y), control: CGPoint(x: c.x - rx * pinch, y: c.y + ry * pinch))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - ry), control: CGPoint(x: c.x - rx * pinch, y: c.y - ry * pinch))
        p.closeSubpath()
        return p
    }
}

/// "Medonom" in the brand type, its "M" in the theme gradient like the mark.
struct BrandWordmark: View {
    var size: CGFloat = 28

    var body: some View {
        (Text("M").foregroundStyle(Palette.gradient) + Text("edonom"))
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .tracking(-size * 0.01)
            .accessibilityLabel(Brand.name)
    }
}
