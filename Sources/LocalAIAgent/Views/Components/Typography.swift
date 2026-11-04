import SwiftUI

/// App text styles, all in Geist.
extension Font {
    static func geist(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .custom("Geist", size: size).weight(weight) }
    static func geistMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .custom("Geist Mono", size: size).weight(weight) }
    static func geistPixel(_ size: CGFloat) -> Font { .custom("Geist Pixel", size: size) }
    /// Greek letters. Geist has none, so these use the system serif, which suits them anyway.
    static func greek(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .serif) }

    static var uiBody: Font { geist(14) }
    static var uiCallout: Font { geist(13) }
    static var uiCaption: Font { geist(11.5) }
    static var uiCaption2: Font { geist(10.5) }
    static var uiHeadline: Font { geist(14, weight: .semibold) }
    static var uiTitle3: Font { geist(16) }
    static var uiTitle2: Font { geist(19) }

    /// Numbers and display text.
    static func uiDisplay(size: CGFloat, weight: Font.Weight = .regular) -> Font { geistMono(size, weight: weight) }
}
