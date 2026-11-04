import SwiftUI

/// Circular score gauge, coloured by the score's health band.
struct ScoreRing: View {
    let score: Double?
    var size: CGFloat = 64
    var unit = "/100"

    var body: some View {
        let level = TestScoring.modelScore.level(score)
        let width = size * 0.11
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: width)
            Circle()
                .trim(from: 0, to: (score ?? 0) / 100)
                .stroke(level.color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(score.map(TestFormat.score) ?? "—")
                    .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(unit).font(.system(size: size * 0.13, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .padding(width / 2)
    }
}

/// Large value tile for the dashboards.
struct MetricTile: View {
    let title: String
    let value: String
    var unit: String?
    var caption: String?
    var symbol: String?
    var level: HealthLevel?

    var body: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let symbol { Image(systemName: symbol).font(.caption).foregroundStyle(Palette.accent) }
                    Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    if let level { StatusDot(level: level, size: 7) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let unit { Text(unit).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                }
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Fills the grid row, so tiles side by side share one height.
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Side by side when there's room, stacked otherwise.
struct AdaptiveStack<Content: View>: View {
    var minWidth: CGFloat = 900
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) { content }.frame(minWidth: minWidth)
            VStack(alignment: .leading, spacing: 16) { content }
        }
    }
}

/// Thin progress bar in the theme gradient.
struct ProgressStrip: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Palette.gradient).frame(width: max(geo.size.width * min(max(fraction, 0), 1), 6))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

/// Live status of a running test: step, detail, bar, elapsed time and a Stop button.
struct TestProgressView: View {
    let progress: TestProgress
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text(progress.step).font(.callout.weight(.semibold))
                    if !progress.detail.isEmpty {
                        Text(progress.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(String(format: "%.0f s", context.date.timeIntervalSince(progress.startedAt)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button("Stop", action: onStop).controlSize(.small)
            }
            ProgressStrip(fraction: progress.fraction)
        }
    }
}

/// Gradient capsule button used to start a test.
struct RunTestButton: View {
    let title: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "play.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Palette.gradient, in: Capsule())
                .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

enum TestFormat {
    static func gbPerSecond(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    /// A model test score out of 100. Rounded down, so only a perfect run shows 100.
    static func score(_ v: Double) -> String { "\(Int(v))" }

    static func number(_ v: Double?, decimals: Int = 1) -> String {
        guard let v else { return "—" }
        return String(format: "%.\(decimals)f", v)
    }

    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }
}
