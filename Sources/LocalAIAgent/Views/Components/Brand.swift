import SwiftUI

/// Name, voice and type in one place, so a rename is a one-line change.
enum Brand {
    static let name = "Prometheus"
    static let tagline = "Intelligence, directed."

    /// Display type, used for the wordmark and page titles.
    static func display(_ size: CGFloat) -> Font { .geist(size, weight: .semibold) }

    /// The brand's lime, the same in every theme.
    static let lime = LinearGradient(colors: [Color(hex: 0xDDFF57), Color(hex: 0xA8E22A)], startPoint: .top, endPoint: .bottom)
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The Prometheus mark: a faceted flame around a diamond. The same drawing as the app icon
/// (scripts/make-icon.swift).
struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        FlameMark()
            .fill(Brand.lime, style: FillStyle(eoFill: true))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The mark on a 100-point grid: the flame's outline, a diamond cut from it, and a smaller diamond inside.
struct FlameMark: Shape {
    static let outline: [CGPoint] = [(50, 3), (63, 27), (73, 15), (91, 50), (68, 94), (32, 94), (9, 50), (27, 15), (37, 27)]
        .map { CGPoint(x: $0.0, y: $0.1) }
    static let cut: [CGPoint] = [(50, 38), (69, 63), (50, 88), (31, 63)].map { CGPoint(x: $0.0, y: $0.1) }
    static let core: [CGPoint] = [(50, 53), (58, 63), (50, 73), (42, 63)].map { CGPoint(x: $0.0, y: $0.1) }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 100
        var path = Path()
        for shape in [Self.outline, Self.cut, Self.core] {
            path.addLines(shape.map { CGPoint(x: rect.minX + $0.x * scale, y: rect.minY + $0.y * scale) })
            path.closeSubpath()
        }
        return path
    }
}

/// "PROMETHEUS", widely spaced.
struct BrandWordmark: View {
    var size: CGFloat = 28

    var body: some View {
        Text(Brand.name.uppercased())
            .font(.geist(size, weight: .semibold))
            .tracking(size * 0.16)
            .foregroundStyle(.white)
            .fixedSize()
            .accessibilityLabel(Brand.name)
    }
}
