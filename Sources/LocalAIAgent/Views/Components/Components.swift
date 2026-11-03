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

    static func seconds(_ s: Double?) -> String {
        guard let s else { return "—" }
        if s < 1 { return String(format: "%.0f ms", s * 1000) }
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
            .font(.caption2.weight(.semibold))
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
                Text("Collecting…").font(.caption2).foregroundStyle(.tertiary)
            }
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
            .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
    }
}

struct SectionHeader: View {
    let title: String
    var symbol: String?
    var trailing: AnyView?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).foregroundStyle(.secondary).font(.caption) }
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
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
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
        .foregroundStyle(tint == .secondary ? Color.secondary : tint)
    }
}

/// App-wide brand mark.
struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [Palette.accent, Palette.accent2], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
            .shadow(color: Palette.accent.opacity(0.35), radius: size * 0.12, y: size * 0.05)
    }
}

extension View {
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
        }
    }
}
