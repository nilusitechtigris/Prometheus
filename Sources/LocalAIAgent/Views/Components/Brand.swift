import SwiftUI

/// Name, voice and type in one place, so a rename is a one-line change.
enum Brand {
    static let name = "Prometheus"
    static let tagline = "Bring the fire home."

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

/// The Prometheus mark: the AI-generated flame from the app icon (scripts/make-icon.swift), in the brand's lime.
struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        if let flame = Art.flame {
            Image(nsImage: flame)
                .renderingMode(.template)
                .interpolation(.high)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Brand.lime)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
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
