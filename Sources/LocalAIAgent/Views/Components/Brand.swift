import SwiftUI

/// Name, voice and type in one place, so a rename is a one-line change.
///
/// There is no logo view here any more. The mark is the flame, and there is only ever one on screen:
/// `ForgeShell` draws it (see `FlameView`), beside the name in the header or in the middle of Home.
enum Brand {
    static let name = "Prometheus"
    static let tagline = "Bring the fire home."

    /// Display type, used for page titles.
    static func display(_ size: CGFloat) -> Font { .geist(size, weight: .semibold) }
}
