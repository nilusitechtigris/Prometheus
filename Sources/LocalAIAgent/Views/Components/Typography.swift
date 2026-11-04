import SwiftUI

/// App text styles, all in Geist Pixel, which has one weight: hierarchy comes from size and colour.
/// One of its pixels is 0.095 em, so these sizes land each pixel on whole or half device pixels.
extension Font {
    static func pixel(_ size: CGFloat) -> Font { .custom("Geist Pixel", size: size) }
    /// Monospaced type for code, where columns have to line up. The pixel font is proportional.
    static func code(_ size: CGFloat) -> Font { .custom("Geist Mono", size: size) }

    static var uiBody: Font { pixel(15.79) }
    static var uiCallout: Font { pixel(13.16) }
    static var uiCaption: Font { pixel(11.84) }
    static var uiCaption2: Font { pixel(10.53) }
    static var uiHeadline: Font { pixel(15.79) }
    static var uiTitle3: Font { pixel(18.42) }
    static var uiTitle2: Font { pixel(21.05) }

    /// Numbers and display text.
    static func uiDisplay(size: CGFloat, weight: Font.Weight = .regular) -> Font { pixel((size / 2.63).rounded() * 2.632) }
}
