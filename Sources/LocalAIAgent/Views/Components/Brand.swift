import SwiftUI

/// Name and voice in one place, so a rename is a one-line change.
enum Brand {
    static let name = "Loupe"
    static let tagline = "Local AI, up close."
}

/// The Loupe mark: a lens with a spark inside, on a night tile, like the app icon.
/// Larger sizes add the measuring bezel with its green / yellow / red zone.
struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        tile
            .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.11, blue: 0.29), Color(red: 0.04, green: 0.04, blue: 0.12)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                RadialGradient(colors: [Palette.accent.opacity(0.6), .clear], center: .center,
                               startRadius: 0, endRadius: size * 0.5)
            }
            .overlay {
                if size >= 44 { BezelTicks().padding(size * 0.07) }
            }
            .overlay {
                LensGlyph(lineWidth: size * 0.075, spark: AnyShapeStyle(.white), detailed: size >= 44)
                    .padding(size * (size >= 44 ? 0.22 : 0.18))
            }
            .clipShape(tile)
            .overlay(tile.strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .frame(width: size, height: size)
            .shadow(color: Palette.accent.opacity(0.35), radius: size * 0.12, y: size * 0.05)
    }
}

/// The lens on its own: a ring in the theme colours with a spark inside.
/// It also stands in for the "o" of the wordmark.
struct LensGlyph: View {
    var lineWidth: CGFloat
    var spark: AnyShapeStyle? = nil
    /// Glass fill, highlight and the second, smaller spark — only where there's room to see them.
    var detailed = false

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                if detailed {
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.18), .white.opacity(0.02)],
                                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: d * 0.6))
                }
                Circle().strokeBorder(
                    AngularGradient(colors: [Palette.accent2, Palette.accent, Palette.glow, Palette.accent2], center: .center),
                    lineWidth: lineWidth)
                if detailed {
                    // Specular highlight on the glass, upper left.
                    Circle()
                        .trim(from: 0.56, to: 0.68)
                        .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: lineWidth * 0.32, lineCap: .round))
                        .padding(lineWidth * 1.7)
                }
                if let spark {
                    SparkShape()
                        .fill(spark)
                        .frame(width: d * 0.44, height: d * 0.44)
                        .offset(x: detailed ? -d * 0.03 : 0, y: detailed ? d * 0.03 : 0)
                        .shadow(color: .white.opacity(detailed ? 0.6 : 0), radius: d * 0.06)
                    if detailed {
                        SparkShape()
                            .fill(spark)
                            .frame(width: d * 0.14, height: d * 0.14)
                            .offset(x: d * 0.17, y: -d * 0.17)
                    }
                }
            }
            .frame(width: d, height: d)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
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

/// Measuring ring around the lens. The lower-right ticks run green → yellow → red,
/// the same ranges the telemetry uses.
struct BezelTicks: View {
    var count = 48

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            let zone = (count * 7 / 24)...(count * 10 / 24)
            for i in 0..<count {
                let angle = Double(i) / Double(count) * 2 * .pi - .pi / 2
                let major = i % 4 == 0
                let inner = r * (major ? 0.88 : 0.93)
                var tick = Path()
                tick.move(to: CGPoint(x: c.x + cos(angle) * inner, y: c.y + sin(angle) * inner))
                tick.addLine(to: CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r))
                let color: Color
                if zone.contains(i) {
                    let t = Double(i - zone.lowerBound) / Double(zone.upperBound - zone.lowerBound)
                    color = t < 0.4 ? Palette.good : t < 0.75 ? Palette.warning : Palette.critical
                } else {
                    color = .white.opacity(major ? 0.5 : 0.25)
                }
                ctx.stroke(tick, with: .color(color), style: StrokeStyle(lineWidth: max(r * 0.03, 0.8), lineCap: .round))
            }
        }
    }
}

/// "Loupe" in the brand type, with the lens standing in for the "o".
struct BrandWordmark: View {
    var size: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("L")
            LensGlyph(lineWidth: size * 0.12, spark: size >= 24 ? AnyShapeStyle(Palette.gradient) : nil)
                .frame(width: size * 0.56, height: size * 0.56)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - size * 0.01 }
                .padding(.leading, size * 0.02)
                .padding(.trailing, size * 0.03)
            Text("upe")
        }
        .font(.system(size: size, weight: .bold, design: .rounded))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Brand.name)
    }
}
