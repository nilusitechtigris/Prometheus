import Charts
import SwiftUI

enum Format {
    static func bytes(_ b: Int64?) -> String {
        guard let b else { return "—" }
        return ByteCountFormatter.string(fromByteCount: b, countStyle: .memory)
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
            .background(level.color.opacity(0.18), in: Capsule())
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
                .clipShape(Capsule())

                if let value, value.isFinite {
                    let d = height + 6
                    Circle()
                        .fill(threshold.level(value).color)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .frame(width: d, height: d)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                        .offset(x: min(max(x(value) - d / 2, 0), w - d))
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
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
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
        .background(tint.opacity(0.12), in: Capsule())
        .foregroundStyle(tint == .secondary ? Color.secondary : tint)
    }
}

/// A flat fill with a hairline edge, for controls on the near-black.
private struct GlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content.background(Color.white.opacity(0.07), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
    }
}

extension View {
    /// Use only for floating controls.
    func glassCapsule(interactive: Bool = false) -> some View {
        modifier(GlassBackground(shape: Capsule()))
    }

    func glassPanel(cornerRadius: CGFloat) -> some View {
        modifier(GlassBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
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

/// The main action: the accent colour with a soft glow.
struct AccentButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 9 : 14, style: .continuous)
        configuration.label
            .font(compact ? .uiCaption.weight(.semibold) : .uiCallout.weight(.semibold))
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, compact ? 11 : 20)
            .padding(.vertical, compact ? 5 : 11)
            .background(Palette.gradient, in: shape)
            .shadow(color: Palette.accent.opacity(compact ? 0 : 0.35), radius: 12)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// A quieter action beside the main one.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        configuration.label
            .font(.uiCallout.weight(.medium))
            .foregroundStyle(Forge.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(configuration.isPressed ? 0.09 : 0.03), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.13), lineWidth: 1))
    }
}
