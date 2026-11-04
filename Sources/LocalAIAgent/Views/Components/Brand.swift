import SwiftUI

/// Name, voice and type in one place, so a rename is a one-line change.
enum Brand {
    static let name = "Prometheus"
    static let greekName = "Προμηθεύς"
    static let tagline = "The fire is yours."

    /// Display type, used for the wordmark and page titles.
    static func display(_ size: CGFloat) -> Font { .pixel(size) }

    /// The brand's blue fire in hard bands, the same in every theme.
    static let fire = LinearGradient(stops: [.init(color: Color(hex: 0xBDE3FF), location: 0), .init(color: Color(hex: 0xBDE3FF), location: 0.4),
                                             .init(color: Color(hex: 0x6CB6FF), location: 0.4), .init(color: Color(hex: 0x6CB6FF), location: 0.7),
                                             .init(color: Color(hex: 0x2F7BFF), location: 0.7), .init(color: Color(hex: 0x2F7BFF), location: 1)],
                                     startPoint: .top, endPoint: .bottom)
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The Prometheus mark: a pixel-art blue flame with a white-hot heart, on a black tile. The same sprite
/// as the app icon (scripts/make-icon.swift). Each sprite pixel is a whole or half point, so it stays
/// sharp at any size.
struct BrandMark: View {
    var size: CGFloat = 28

    static let flame = [
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
    private static let palette: [Character: Color] = [
        "d": Color(hex: 0x1238C8), "b": Color(hex: 0x2F7BFF), "l": Color(hex: 0x6CB6FF),
        "c": Color(hex: 0xBDE3FF), "w": .white,
    ]

    var body: some View {
        let tile = PixelRect(radius: size * 0.2)
        ZStack {
            tile.fill(Color(hex: 0x05070D))
            PixelSprite(rows: Self.flame, palette: Self.palette, cell: max(1, (size / 18 * 2).rounded(.down) / 2))
        }
        .overlay(tile.strokeBorder(Color(hex: 0x2F7BFF).opacity(0.5), lineWidth: Pixel.line))
        .frame(width: size, height: size)
    }
}

/// "PROMETHEUS" in the display type and the brand's blue fire.
struct BrandWordmark: View {
    var size: CGFloat = 28

    var body: some View {
        Text(Brand.name.uppercased())
            .font(Brand.display(size))
            .tracking(size * 0.02)
            .foregroundStyle(Brand.fire)
            .fixedSize()
            .accessibilityLabel(Brand.name)
    }
}
