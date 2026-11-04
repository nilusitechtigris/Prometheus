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
        Rectangle()
            .fill(level.color)
            .frame(width: size, height: size)
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
            .background(level.color.opacity(0.18), in: PixelRect.pill)
            .foregroundStyle(level == .warning ? Color.primary.opacity(0.85) : (level == .unknown ? .secondary : level.color))
    }
}

/// A track split into green / yellow / red zones with a marker at the current value.
struct RangeBar: View {
    let value: Double?
    let threshold: Threshold
    var height: CGFloat = 7

    var body: some View {
        let zones = zones()
        let lo = threshold.displayMin, span = max(threshold.displayMax - lo, 0.0001)
        let shown = value.flatMap { $0.isFinite ? min(max($0, lo), threshold.displayMax) : nil }
        let litColor = threshold.level(value).color
        Canvas { context, size in
            let pitch = max((height / 2).rounded() * 2, 4)
            let count = Int(size.width / pitch)
            let top = (size.height - height) / 2
            for index in 0..<count {
                let at = lo + (Double(index) + 0.5) / Double(count) * span
                let zone = zones.first { at < $0.end } ?? zones[zones.count - 1]
                let lit = shown.map { at <= $0 } ?? false
                context.fill(Path(CGRect(x: CGFloat(index) * pitch, y: top, width: pitch - 1, height: height)),
                             with: .color(lit ? litColor : zone.level.color.opacity(0.28)))
            }
            if let shown {
                let x = min(CGFloat((shown - lo) / span) * size.width, size.width - 4)
                context.fill(Path(CGRect(x: x, y: 0, width: 4, height: size.height)), with: .color(.white))
            }
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

/// Recent values as a skyline of pixel columns.
struct Sparkline: View {
    let points: [SamplePoint]
    var color: Color = Palette.accent
    var domain: ClosedRange<Double>?
    var height: CGFloat = 38

    var body: some View {
        let top = domain?.upperBound ?? max((points.map(\.value).max() ?? 1) * 1.2, 1)
        let bottom = domain?.lowerBound ?? 0
        Canvas { context, size in
            guard points.count > 1 else { return }
            let cell = Pixel.unit
            let columns = Int(size.width / cell)
            for column in 0..<columns {
                let point = points[column * points.count / columns]
                let share = min(max((point.value - bottom) / max(top - bottom, 0.0001), 0), 1)
                let bar = max((CGFloat(share) * size.height / cell).rounded() * cell, cell)
                let x = CGFloat(column) * cell
                context.fill(Path(CGRect(x: x, y: size.height - bar, width: cell, height: bar)), with: .color(color.opacity(0.24)))
                context.fill(Path(CGRect(x: x, y: size.height - bar, width: cell, height: cell)), with: .color(color))
            }
        }
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
            .background(.background.opacity(0.65), in: PixelRect(radius: 12))
            .overlay(PixelRect(radius: 12).strokeBorder(.separator.opacity(0.6), lineWidth: Pixel.line))
    }
}

struct SectionHeader: View {
    let title: String
    var symbol: String?
    var trailing: AnyView?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { PixelIcon(symbol).foregroundStyle(.secondary).font(.uiCaption) }
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
            if let symbol { PixelIcon(symbol).imageScale(.small) }
            Text(text)
        }
        .font(.uiCaption.monospacedDigit())
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: PixelRect.pill)
        .foregroundStyle(tint == .secondary ? Color.secondary : tint)
    }
}

/// A flat fill with a hairline edge, for controls on the near-black.
private struct GlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content.background(Color.white.opacity(0.07), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: Pixel.line))
    }
}

extension View {
    /// Use only for floating controls.
    func glassCapsule(interactive: Bool = false) -> some View {
        modifier(GlassBackground(shape: PixelRect.pill))
    }

    func glassPanel(cornerRadius: CGFloat) -> some View {
        modifier(GlassBackground(shape: PixelRect(radius: cornerRadius)))
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

/// The theme's glow rising from the foot of the window in ordered dither, like a hearth. Drawn once and
/// deliberately not animated, so it never adds GPU load to the numbers the app is measuring.
struct AmbientBackground: View {
    private static let cell: CGFloat = 4
    private static let bayer: [[Double]] = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

    var body: some View {
        let glow = [Palette.accent2.opacity(0.06), Palette.accent.opacity(0.1), Palette.accent.opacity(0.15)]
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Forge.black))
            let rows = Int(size.height * 0.26 / Self.cell), columns = Int(size.width / Self.cell) + 1
            var bands = [Path](repeating: Path(), count: glow.count)
            for row in 0..<rows {
                let rise = Double(row) / Double(max(rows - 1, 1))
                for column in 0..<columns {
                    let across = Double(column) / Double(columns)
                    let strength = pow(1 - rise, 2.2) * (0.72 + 0.28 * sin(across * .pi)) * Double(glow.count)
                    let level = Int((strength + Self.bayer[row % 4][column % 4] / 16 - 1).rounded(.down))
                    guard level >= 0 else { continue }
                    bands[min(level, glow.count - 1)].addRect(CGRect(x: CGFloat(column) * Self.cell,
                                                                     y: size.height - CGFloat(row + 1) * Self.cell,
                                                                     width: Self.cell, height: Self.cell))
                }
            }
            for (band, color) in zip(bands, glow) { context.fill(band, with: .color(color)) }
        }
        .ignoresSafeArea()
    }
}
