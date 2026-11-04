import SwiftUI

/// App text styles. They're the system styles, or Geist while the draft layout is on.
extension Font {
    /// Follows the draft layout. Set only from the main actor, by AppSettings.
    nonisolated(unsafe) static var usesGeist = false

    static func geist(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .custom("Geist", size: size).weight(weight) }
    static func geistMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .custom("Geist Mono", size: size).weight(weight) }
    static func geistPixel(_ size: CGFloat) -> Font { .custom("Geist Pixel", size: size) }

    private static func ui(_ system: Font, _ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        usesGeist ? geist(size, weight: weight) : system
    }

    static var uiBody: Font { ui(.body, 14) }
    static var uiCallout: Font { ui(.callout, 13) }
    static var uiCaption: Font { ui(.caption, 11.5) }
    static var uiCaption2: Font { ui(.caption2, 10.5) }
    static var uiHeadline: Font { ui(.headline, 14, .semibold) }
    static var uiTitle3: Font { ui(.title3, 16) }
    static var uiTitle2: Font { ui(.title2, 19) }

    /// Numbers and display text: rounded system type, or Geist Mono.
    static func uiDisplay(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        usesGeist ? geistMono(size, weight: weight) : .system(size: size, weight: weight, design: .rounded)
    }
}
