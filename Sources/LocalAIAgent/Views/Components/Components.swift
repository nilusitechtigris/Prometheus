import Charts
import SwiftUI

enum Format {
    /// A size in the largest unit that keeps it readable: "738 MB", "2.5 GB". Written with a point whatever the
    /// Mac's region, like every other number in the app. The system's own formatter follows the region, which
    /// put "2,5 GB" beside "16.0 GB". `binary` counts in 1024s, as memory is; files count in 1000s, as Finder does.
    static func bytes(_ b: Int64?, binary: Bool = true) -> String {
        guard let b else { return "—" }
        let step = binary ? 1_024.0 : 1_000.0
        var value = Double(b), unit = 0
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        while abs(value) >= step, unit < units.count - 1 {
            value /= step
            unit += 1
        }
        let text = unit < 2 || abs(value) >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(text) \(units[unit])"
    }

    static func gigabytes(_ b: Int64) -> String {
        String(format: "%.1f GB", Double(b) / 1_073_741_824)
    }

    /// Always seconds with two decimals (0.20 s, never "200 ms") so values compare at a glance.
    static func seconds(_ s: Double?) -> String {
        guard let s else { return "—" }
        if s < 60 { return String(format: "%.2f s", s) }
        return String(format: "%dm %02ds", Int(s) / 60, Int(s) % 60)
    }

    static func rate(_ r: Double?) -> String {
        guard let r else { return "—" }
        return r >= 100 ? String(format: "%.0f", r) : String(format: "%.1f", r)
    }

    static func percent(_ p: Double?) -> String {
        guard let p else { return "—" }
        return String(format: "%.0f%%", p)
    }

    static func temp(_ t: Double?) -> String {
        guard let t else { return "—" }
        return String(format: "%.0f°C", t)
    }

    /// Sampling temperature with up to two decimals: 0.7, 0.75, 1.
    static func samplingTemperature(_ t: Double) -> String {
        var text = String(format: "%.2f", t)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text += "0" }
        return text
    }

    static func tokens(_ n: Int) -> String {
        n >= 1024 && n % 1024 == 0 ? "\(n / 1024)K" : (n >= 1000 ? String(format: "%.1fK", Double(n) / 1000) : "\(n)")
    }
}

/// Small coloured dot + optional label.
struct StatusDot: View {
    let level: HealthLevel
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(level.color)
            .frame(width: size, height: size)
            .shadow(color: level.color.opacity(level == .unknown ? 0 : 0.6), radius: 2)
    }
}

struct LevelPill: View {
    let level: HealthLevel
    var text: String?

    var body: some View {
        Text(text ?? level.label)
            .font(.uiCaption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(level.color.opacity(0.18), in: Capsule(style: .circular))
            .foregroundStyle(level == .warning ? Color.primary.opacity(0.85) : (level == .unknown ? .secondary : level.color))
    }
}

/// A track split into green / yellow / red zones with a marker at the current value.
struct RangeBar: View {
    let value: Double?
    let threshold: Threshold
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let lo = threshold.displayMin, hi = threshold.displayMax
            let span = max(hi - lo, 0.0001)
            let x: (Double) -> CGFloat = { CGFloat((min(max($0, lo), hi) - lo) / span) * w }
            let zones = zones()
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    ForEach(zones.indices, id: \.self) { i in
                        let z = zones[i]
                        Rectangle()
                            .fill(z.level.color.opacity(0.28))
                            .frame(width: max(x(z.end) - x(z.start) - 1.5, 0), height: height)
                            .offset(x: x(z.start))
                    }
                    if let value, value.isFinite {
                        Rectangle()
                            .fill(threshold.level(value).color.opacity(0.85))
                            .frame(width: max(x(value), 2), height: height)
                    }
                }
                .frame(width: w, height: height, alignment: .leading)
                .clipShape(Capsule(style: .circular))

                // A plain mark. A ringed knob made a read-only bar look like a slider to drag.
                if let value, value.isFinite {
                    let markWidth: CGFloat = 3
                    Capsule(style: .circular)
                        .fill(Color.white.opacity(0.92))
                        .frame(width: markWidth, height: height + 6)
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                        .offset(x: min(max(x(value) - markWidth / 2, 0), w - markWidth))
                }
            }
            .frame(width: w, height: geo.size.height, alignment: .leading)
        }
        .frame(height: height + 8)
        .accessibilityElement()
        .accessibilityLabel("Range")
        .accessibilityValue(value.map { String(format: "%.0f", $0) } ?? "unknown")
    }

    private struct Zone { let start: Double; let end: Double; let level: HealthLevel }

    private func zones() -> [Zone] {
        let lo = threshold.displayMin, hi = threshold.displayMax
        if threshold.higherIsWorse {
            return [Zone(start: lo, end: threshold.warning, level: .good),
                    Zone(start: threshold.warning, end: threshold.critical, level: .warning),
                    Zone(start: threshold.critical, end: hi, level: .critical)]
        }
        return [Zone(start: lo, end: threshold.critical, level: .critical),
                Zone(start: threshold.critical, end: threshold.warning, level: .warning),
                Zone(start: threshold.warning, end: hi, level: .good)]
    }
}

struct Sparkline: View {
    let points: [SamplePoint]
    var color: Color = Palette.accent
    var domain: ClosedRange<Double>?
    var rules: [Double] = []
    var height: CGFloat = 38

    var body: some View {
        let top = domain?.upperBound ?? max((points.map(\.value).max() ?? 1) * 1.2, 1)
        let bottom = domain?.lowerBound ?? 0
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Time", p.id), yStart: .value("Base", bottom), yEnd: .value("Value", p.value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.id), y: .value("Value", p.value))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            ForEach(rules, id: \.self) { r in
                RuleMark(y: .value("Threshold", r))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        // From the first sample to the last. Left to itself the chart rounds the range outwards, which left
        // a blank strip before the line began.
        .chartXScale(domain: (points.first?.id ?? 0)...max(points.last?.id ?? 1, (points.first?.id ?? 0) + 1))
        .chartYScale(domain: bottom...top)
        .chartLegend(.hidden)
        .frame(height: height)
        .overlay {
            if points.count < 2 {
                Text("Collecting…").font(.uiCaption2).foregroundStyle(.tertiary)
            }
        }
    }
}

/// Lays children out left to right, wrapping onto new lines when the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Lines first, so each thing can sit at the middle of its line's height. Placed by their tops, a
        // switch and a taller button on one line looked like a mistake.
        var lines: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                lines.append([])
                x = 0
            }
            lines[lines.count - 1].append((index, size))
            x += size.width + spacing
        }
        var y = bounds.minY
        for line in lines where !line.isEmpty {
            let lineHeight = line.map(\.size.height).max() ?? 0
            var lineX = bounds.minX
            for item in line {
                subviews[item.index].place(at: CGPoint(x: lineX, y: y + (lineHeight - item.size.height) / 2),
                                           proposal: ProposedViewSize(item.size))
                lineX += item.size.width + spacing
            }
            y += lineHeight + lineSpacing
        }
    }
}

/// Rounded card container used across the inspector and library.
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Forge.line, lineWidth: 1))
    }
}

struct SectionHeader: View {
    let title: String
    var symbol: String?
    var trailing: AnyView?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).foregroundStyle(.secondary).font(.uiCaption) }
            Text(title.uppercased())
                .font(.uiCaption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            Spacer()
            trailing
        }
        .padding(.horizontal, 2)
    }
}

struct Chip: View {
    let text: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.uiCaption.monospacedDigit())
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule(style: .circular))
        .foregroundStyle(tint == .secondary ? Color.secondary : tint)
    }
}

/// A flat fill with a hairline edge, for controls on the near-black. An interactive one is the shape of a
/// button: it lights up under the pointer along with the label inside, and fades when the button is off.
private struct GlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    var interactive = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func body(content: Content) -> some View {
        let lit = interactive && isEnabled && hovering
        let fade = interactive && !isEnabled ? 0.5 : 1
        content.background(Color.white.opacity((lit ? 0.12 : 0.07) * fade), in: shape)
            .overlay(shape.outline(Color.white.opacity((lit ? 0.22 : 0.12) * fade), lineWidth: 0.5))
            .animation(Motion.press, value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    /// Use only for floating controls.
    func glassCapsule(interactive: Bool = false) -> some View {
        modifier(GlassBackground(shape: Capsule(style: .circular), interactive: interactive))
    }

    func glassPanel(cornerRadius: CGFloat) -> some View {
        modifier(GlassBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }
}

// Every capsule in the app is `Capsule(style: .circular)`: plain half-circle ends. SwiftUI's default for a
// capsule is the "continuous" corner, which needs more room than half a pill's height. Squeezed into a pill, its
// outline crossed itself and drew a short stray line just outside each end. Filled, nobody could see it;
// outlined, every pill had two.
extension InsettableShape {
    /// An outline drawn just inside the shape.
    func outline<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1) -> some View {
        strokeBorder(content, lineWidth: lineWidth)
    }
}

/// A faint fill that shows under the pointer, for rows and tiles that have no shape of their own until then.
private struct HoverFill<S: Shape>: ViewModifier {
    let shape: S
    let active: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(active && isEnabled && hovering ? 0.055 : 0), in: shape)
            .animation(Motion.press, value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverFill<S: Shape>(_ shape: S, when active: Bool = true) -> some View {
        modifier(HoverFill(shape: shape, active: active))
    }
}

/// A row of neighbouring controls.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: spacing) { content }
    }
}

/// For a control that draws its own shape: a pill, a card, a row, an icon. It leaves the label as it is and
/// adds what the plain style lacks. The control lights up a little under the pointer and dims while it is
/// pressed, so everything that can be clicked answers before the click lands. Nothing moves or changes size,
/// which keeps it right for a small icon and for a row as wide as the window.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Feedback(configuration: configuration) }

    private struct Feedback: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .brightness(!isEnabled ? 0 : configuration.isPressed ? -0.05 : hovering ? 0.07 : 0)
                .opacity(!isEnabled ? 0.5 : configuration.isPressed ? 0.8 : 1)
                .animation(Motion.press, value: configuration.isPressed)
                .animation(Motion.press, value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

extension ButtonStyle where Self == SoftButtonStyle {
    static var soft: SoftButtonStyle { SoftButtonStyle() }
}

/// The main action: the accent colour with a soft glow. It brightens under the pointer, dims while pressed,
/// and loses its glow when it can't be used, so a disabled one never looks ready.
struct AccentButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View { Feedback(configuration: configuration, compact: compact) }

    private struct Feedback: View {
        let configuration: ButtonStyleConfiguration
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: compact ? 9 : 14, style: .continuous)
            configuration.label
                .font(compact ? .uiCaption.weight(.semibold) : .uiCallout.weight(.semibold))
                .foregroundStyle(Palette.onAccent)
                .padding(.horizontal, compact ? 11 : 20)
                .padding(.vertical, compact ? 5 : 11)
                .background(Palette.gradient, in: shape)
                .brightness(!isEnabled ? 0 : configuration.isPressed ? -0.06 : hovering ? 0.05 : 0)
                .shadow(color: Palette.accent.opacity(compact || !isEnabled ? 0 : hovering ? 0.5 : 0.35), radius: 12)
                .saturation(isEnabled ? 1 : 0.5)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(Motion.press, value: configuration.isPressed)
                .animation(Motion.press, value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// A quieter action beside the main one. The compact one is the same size as the compact accent button, so
/// the two sit on one line.
struct OutlineButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View { Feedback(configuration: configuration, compact: compact) }

    private struct Feedback: View {
        let configuration: ButtonStyleConfiguration
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: compact ? 9 : 14, style: .continuous)
            let lit = configuration.isPressed ? 0.11 : hovering && isEnabled ? 0.07 : 0.03
            configuration.label
                .font(compact ? .uiCaption.weight(.semibold) : .uiCallout.weight(.medium))
                .foregroundStyle(Forge.ink)
                .padding(.horizontal, compact ? 11 : 16)
                .padding(.vertical, compact ? 5 : 10)
                .background(Color.white.opacity(lit), in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(hovering && isEnabled ? 0.22 : 0.13), lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.45)
                .animation(Motion.press, value: configuration.isPressed)
                .animation(Motion.press, value: hovering)
                .onHover { hovering = $0 }
        }
    }
}
