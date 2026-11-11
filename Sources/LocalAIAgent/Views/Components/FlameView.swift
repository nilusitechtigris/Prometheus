import SwiftUI

/// The glass flame, the app's one light. Its tip sways, its glow breathes, and it turns slowly around its
/// own axis. With Reduce Motion on it stands still.
///
/// There is only ever one on screen. On Home it burns in the middle; anywhere else it stands beside the
/// title. `ForgeShell` draws it once and tells it where to be, and it flies there by itself.
struct FlameView: View {
    /// Where the flame belongs now, in the shell's coordinates.
    let target: CGRect

    /// The current flight: where it started, where it ends, and when it left. The end is kept here and
    /// not read from `target`, so the flame stays put for the one frame before a new flight is set up.
    @State private var origin: CGRect?
    @State private var destination: CGRect?
    @State private var departure = Date.distantPast
    /// Faster redraws while it flies, so the move is smooth. Half as many once it has landed.
    @State private var flying = false

    /// Seconds from one place to the other.
    private static let flightTime = 0.85

    var body: some View {
        if let picture = Art.flame(for: ThemeStore.shared.theme) {
            Group {
                if Motion.isReduced {
                    flame(picture, in: target, time: 0)
                } else {
                    TimelineView(.animation(minimumInterval: flying ? 1.0 / 60 : 1.0 / 30)) { timeline in
                        flame(picture, in: place(at: timeline.date), time: timeline.date.timeIntervalSinceReferenceDate)
                    }
                }
            }
            .onChange(of: target) { _, new in
                // Leave from wherever it is right now, so a change of mind mid-flight doesn't make it jump.
                let now = Date.now
                origin = place(at: now)
                destination = new
                departure = now
                flying = true
                Task {
                    try? await Task.sleep(for: .seconds(Self.flightTime + 0.1))
                    if Date.now.timeIntervalSince(departure) >= Self.flightTime { flying = false }
                }
            }
            .accessibilityHidden(true)
        }
    }

    private func flame(_ picture: NSImage, in place: CGRect, time: Double) -> some View {
        #if DEBUG
        FlameTrace.note(place)
        #endif
        return Flame(picture: picture, size: place.size, time: time)
            .offset(x: place.minX, y: place.minY)
    }

    /// Where the flame is at a moment of its flight. It rises quickly and drifts across more slowly,
    /// which bends the path into a shallow arc.
    private func place(at date: Date) -> CGRect {
        let end = destination ?? target
        guard let origin else { return end }
        let progress = min(1, max(0, date.timeIntervalSince(departure) / Self.flightTime))
        guard progress < 1 else { return end }
        let across = Self.ease(progress, 0.55, 0, 0.2, 1)
        let up = Self.ease(progress, 0.3, 0.7, 0.2, 1)
        func mix(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * t }
        let size = CGSize(width: mix(origin.width, end.width, across), height: mix(origin.height, end.height, across))
        // The flame's middle travels, so growing or shrinking doesn't pull it off its path.
        let middle = CGPoint(x: mix(origin.midX, end.midX, across), y: mix(origin.midY, end.midY, up))
        return CGRect(x: middle.x - size.width / 2, y: middle.y - size.height / 2, width: size.width, height: size.height)
    }

    /// A cubic Bézier timing curve, like CSS's `cubic-bezier`: how far along the move is at `time`.
    private static func ease(_ time: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        func bezier(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        // Find the curve's own parameter for this time by halving the range: 20 steps is past any pixel.
        var low = 0.0, high = 1.0
        for _ in 0..<20 {
            let middle = (low + high) / 2
            if bezier(middle, x1, x2) < time { low = middle } else { high = middle }
        }
        return bezier((low + high) / 2, y1, y2)
    }
}

private struct Flame: View {
    let picture: NSImage
    let size: CGSize
    let time: Double

    /// Where the rigid glass ends and the loose flame above it begins, as a share of the height.
    private static let split = 0.37
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
        ZStack {
            image.blur(radius: max(1.5, size.height * 0.04)).opacity(glow)
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
    }

    private var image: some View {
        Image(nsImage: picture)
            .interpolation(.high)
            .resizable()
            .frame(width: size.width, height: size.height)
    }
}

/// The two places the flame can be, and how it lines up there.
enum FlameSlot: Hashable {
    /// In the middle of Home.
    case home
    /// Beside the title on every other page.
    case docked

    var size: CGSize {
        switch self {
        case .home: return CGSize(width: 165, height: 260)
        case .docked: return CGSize(width: 29, height: 45)
        }
    }

    /// How far down the picture the glass ends, so its foot can stand on a line of text.
    static let foot = 0.92
}

/// Where each slot is in the window. `ForgeShell` keeps the newest and moves the flame to the one in use.
/// Measured frames kept in state, so the move between them animates like any other change.
struct FlamePlaces: PreferenceKey {
    /// The coordinate space the frames are measured in: the whole shell.
    static let space = "flame"
    static let defaultValue: [FlameSlot: CGRect] = [:]

    static func reduce(value: inout [FlameSlot: CGRect], nextValue: () -> [FlameSlot: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks this view's frame as a place the flame can be.
    func flamePlace(_ slot: FlameSlot) -> some View {
        background {
            GeometryReader { box in
                Color.clear.preference(key: FlamePlaces.self, value: [slot: box.frame(in: .named(FlamePlaces.space))])
            }
        }
    }
}

#if DEBUG
/// LOCALAI_FLAME_TRACE=/path.txt writes where the flame is each time it is drawn, to check its flight.
enum FlameTrace {
    private static let path = ProcessInfo.processInfo.environment["LOCALAI_FLAME_TRACE"]
    private static let start = Date()
    private nonisolated(unsafe) static var lines: [String] = []

    static func note(_ place: CGRect) {
        guard let path else { return }
        lines.append(String(format: "%.3f  x %.0f  y %.0f  w %.0f  h %.0f", Date().timeIntervalSince(start), place.midX, place.midY, place.width, place.height))
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}
#endif
