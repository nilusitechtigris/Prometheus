import SwiftUI

/// Name, voice and type in one place, so a rename is a one-line change.
enum Brand {
    static let name = "Prometheus"
    static let tagline = "The fire is yours."

    /// Display type: a serif for the mythic name, used for the wordmark and page titles.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.usesGeist ? .geistPixel(size) : .system(size: size, weight: weight, design: .serif)
    }

    /// The brand's fire, the same in every theme.
    static let fire = LinearGradient(colors: [Color(hex: 0xFFB13D), Color(hex: 0xF4631E), Color(hex: 0xD92D20)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
    /// The same fire, deep enough to read on light backgrounds.
    static let deepFire = LinearGradient(colors: [Color(hex: 0xE8590C), Color(hex: 0xD9401A), Color(hex: 0xB91C1C)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The Prometheus mark: a flame with the AI spark at its heart, on a dark ember tile. Same drawing as
/// the app icon (scripts/make-icon.swift). Small sizes drop the finer layers so it stays a clear flame.
struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        let detailed = size >= 44
        tile
            .fill(LinearGradient(colors: [Color(hex: 0x0C0705), Color(hex: 0x2A1710)], startPoint: .top, endPoint: .bottom))
            .overlay {
                RadialGradient(colors: [Color(hex: 0xFF6A00).opacity(0.5), .clear], center: UnitPoint(x: 0.5, y: 0.62),
                               startRadius: 0, endRadius: size * 0.58)
            }
            .overlay {
                Canvas { ctx, canvas in
                    let mark = FlameGeometry(side: canvas.width)
                    var glow = ctx
                    glow.addFilter(.shadow(color: Color(hex: 0xFF5A1F).opacity(0.8), radius: mark.scale(44)))
                    glow.fill(mark.flame(), with: .linearGradient(
                        Gradient(colors: [Color(hex: 0xFF8A1E), Color(hex: 0xF04A0C), Color(hex: 0xC81E1E)]),
                        startPoint: mark.point(512, 890), endPoint: mark.point(512, 168)))
                    if detailed {
                        ctx.fill(mark.flame(scale: 0.70, shift: CGPoint(x: 6, y: 18)), with: .linearGradient(
                            Gradient(colors: [Color(hex: 0xFFA928), Color(hex: 0xFF7A12)]),
                            startPoint: mark.point(512, 700), endPoint: mark.point(512, 180)))
                    }
                    ctx.fill(mark.flame(scale: detailed ? 0.42 : 0.5, shift: CGPoint(x: 8, y: 34)), with: .linearGradient(
                        Gradient(colors: [Color(hex: 0xFFF0B8), Color(hex: 0xFFC93C)]),
                        startPoint: mark.point(512, 520), endPoint: mark.point(512, 200)))
                    if detailed {
                        var spark = ctx
                        spark.addFilter(.shadow(color: .white.opacity(0.9), radius: mark.scale(20)))
                        spark.fill(SparkShape().path(in: mark.circle(mark.point(518, 306), radius: mark.scale(74))), with: .color(.white))
                    }
                }
            }
            .clipShape(tile)
            .overlay(tile.strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .frame(width: size, height: size)
            .shadow(color: Color(hex: 0xF4631E).opacity(0.35), radius: size * 0.12, y: size * 0.05)
    }
}

/// Mark geometry in the 1024-point icon space (y up, tile from 100 to 924), mapped onto a square view.
private struct FlameGeometry {
    let side: CGFloat

    func scale(_ v: CGFloat) -> CGFloat { v / 824 * side }
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - 100) / 824 * side, y: (924 - y) / 824 * side) }
    func circle(_ c: CGPoint, radius r: CGFloat) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2) }

    /// The flame, scaled about its base.
    func flame(scale s: CGFloat = 1, shift: CGPoint = .zero) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            point(512 + shift.x + (x - 512) * s, 168 + shift.y + (y - 168) * s)
        }
        var path = Path()
        path.move(to: p(512, 168))
        path.addCurve(to: p(756, 420), control1: p(650, 168), control2: p(756, 276))
        path.addCurve(to: p(618, 720), control1: p(756, 556), control2: p(650, 620))
        path.addCurve(to: p(556, 890), control1: p(600, 776), control2: p(592, 842))
        path.addCurve(to: p(446, 640), control1: p(548, 800), control2: p(476, 730))
        path.addCurve(to: p(436, 556), control1: p(436, 608), control2: p(432, 584))
        path.addCurve(to: p(346, 704), control1: p(404, 590), control2: p(360, 640))
        path.addCurve(to: p(268, 420), control1: p(296, 624), control2: p(268, 524))
        path.addCurve(to: p(512, 168), control1: p(268, 276), control2: p(374, 168))
        path.closeSubpath()
        return path
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

/// "PROMETHEUS" in the display serif: wide-set capitals in the brand's fire.
struct BrandWordmark: View {
    var size: CGFloat = 28
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(Brand.name.uppercased())
            .font(Brand.display(size))
            .tracking(Font.usesGeist ? size * 0.02 : size * 0.14)
            .foregroundStyle(scheme == .dark ? Brand.fire : Brand.deepFire)
            .fixedSize()
            .accessibilityLabel(Brand.name)
    }
}
