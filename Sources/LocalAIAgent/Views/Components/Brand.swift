import SwiftUI

/// Name, voice and type in one place, so a rename is a one-line change.
///
/// There is no logo view here. The mark is the flame, and it burns in one place only: the middle of Home
/// (see `FlameView`).
enum Brand {
    /// "Prometheus Lab" is the private app, which keeps every harness version to compare and test.
    static let name = Edition.current.isLab ? "Prometheus Lab" : "Prometheus"
    static let tagline = "Bring the fire home."

    /// Display type, used for page titles.
    static func display(_ size: CGFloat) -> Font { .geist(size, weight: .semibold) }
}
