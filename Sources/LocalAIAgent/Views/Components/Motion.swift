import AppKit
import SwiftUI

/// The app's motion: small and quick, so it shows what changed without making anyone wait for it.
/// With Reduce Motion on in System Settings, everything changes at once instead.
enum Motion {
    private static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Pages and tabs changing.
    static var page: Animation? { reduced ? nil : .snappy(duration: 0.28) }
    /// Panels, rows and small things opening, closing, appearing and going.
    static var quick: Animation? { reduced ? nil : .snappy(duration: 0.2) }
}

extension AnyTransition {
    /// A page or tab swapping in. The old one leaves fast, so two pages of text are never readable at once.
    static var page: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 10)),
                    removal: .opacity.animation(.easeOut(duration: 0.09)))
    }

    /// Something small arriving: a banner, a bar, a new message.
    static var arrive: AnyTransition { .opacity.combined(with: .offset(y: 8)) }
}

/// Shows one of several pages, moving between them when `value` changes.
struct PageSwap<Value: Hashable, Content: View>: View {
    let value: Value
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .id(value)
                .transition(.page)
        }
        .animation(Motion.page, value: value)
    }
}
