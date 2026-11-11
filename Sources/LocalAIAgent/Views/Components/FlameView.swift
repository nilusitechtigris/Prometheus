import SwiftUI

/// The glass flame, the app's one light. It burns on Home and nowhere else: arriving there lights it, and
/// leaving puts it out with the page.
///
/// Lit, its tip sways, its glow breathes and it turns slowly around its own axis. With Reduce Motion on it
/// is simply there, standing still.
struct FlameView: View {
    /// How large the flame is on Home.
    static let size = CGSize(width: 165, height: 260)
    /// Seconds from nothing to a full flame.
    private static let ignition = 0.9

    /// When this flame was lit. A new one is lit each time Home is shown.
    @State private var lit = Date.now

    var body: some View {
        if let picture = Art.flame(for: ThemeStore.shared.theme) {
            GeometryReader { box in
                if Motion.isReduced {
                    Flame(picture: picture, size: box.size, time: 0, kindled: 1)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                        Flame(picture: picture, size: box.size, time: timeline.date.timeIntervalSinceReferenceDate,
                              kindled: min(1, max(0, timeline.date.timeIntervalSince(lit) / Self.ignition)))
                    }
                }
            }
            .onAppear { lit = .now }
            .accessibilityHidden(true)
        }
    }
}

private struct Flame: View {
    let picture: NSImage
    let size: CGSize
    let time: Double
    /// How far the flame has caught, from 0 (just struck) to 1 (burning).
    let kindled: Double

    /// Where the rigid glass ends and the loose flame above it begins, as a share of the height.
    private static let split = 0.37
    /// How far down the picture the glass ends. The flame grows from here when it is lit.
    private static let foot = UnitPoint(x: 0.5, y: 0.92)
    /// Seconds for one full turn.
    private static let turn = 9.0
    private static let anchor = UnitPoint(x: 0.5, y: split)
    private static let glass = LinearGradient(stops: [.init(color: .clear, location: 0.34), .init(color: .black, location: 0.34)],
                                              startPoint: .top, endPoint: .bottom)
    private static let tip = LinearGradient(stops: [.init(color: .black, location: 0.38), .init(color: .clear, location: 0.40)],
                                            startPoint: .top, endPoint: .bottom)

    var body: some View {
        let angle = time.truncatingRemainder(dividingBy: Self.turn) / Self.turn * 360
        // Two waves that never line up, so the tip doesn't swing like a pendulum.
        let sway = 4 * sin(time * 1.9) + 2 * sin(time * 3.1 + 1)
        let stretch = 1 + 0.035 * sin(time * 2.3 + 0.5)
        let glow = 0.5 + 0.12 * sin(time * 2.7) + 0.08 * sin(time * 6.1 + 2)
        // Catching: it shoots up a little past its height and settles, and flares brighter while it does.
        let rest = kindled - 1
        let grown = 1 + 2.4 * rest * rest * rest + 1.4 * rest * rest
        let flare = (1 - kindled) * 0.5
        ZStack {
            image.blur(radius: max(1.5, size.height * (0.04 + flare * 0.06))).opacity(min(1, glow + flare))
            // Three copies crossed at 60 degrees. One flat picture would go thin as a card when it turns.
            ForEach(0..<3, id: \.self) { plane in
                ZStack {
                    image.mask(Self.glass)
                    image.mask(Self.tip)
                        .scaleEffect(x: 1, y: stretch, anchor: Self.anchor)
                        .rotationEffect(.degrees(sway), anchor: Self.anchor)
                }
                // A flat picture turning about its upright axis, seen from far away, only changes width.
                // Drawn that way and not with a 3D rotation, which window snapshots put in the wrong place.
                .scaleEffect(x: cos((angle + Double(plane) * 60) * .pi / 180), y: 1)
            }
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(x: 0.4 + 0.6 * grown, y: grown, anchor: Self.foot)
        .opacity(min(1, kindled * 4))
    }

    private var image: some View {
        Image(nsImage: picture)
            .interpolation(.high)
            .resizable()
            .frame(width: size.width, height: size.height)
    }
}
