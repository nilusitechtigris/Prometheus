import SwiftUI

/// Name, voice and type in one place, so a rename is a one-line change.
enum Brand {
    static let name = "Prometheus"
    static let tagline = "Bring the fire home."

    /// Display type, used for the wordmark and page titles.
    static func display(_ size: CGFloat) -> Font { .geist(size, weight: .semibold) }
}

/// The Prometheus mark: the glass flame of the current theme, standing still.
struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        if let flame = Art.flame(for: ThemeStore.shared.theme) {
            Image(nsImage: flame)
                .interpolation(.high)
                .resizable()
                .scaledToFit()
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
