import SwiftUI

/// Circular score gauge, coloured by the score's health band.
struct ScoreRing: View {
    let score: Double?
    var size: CGFloat = 64
    var unit = "/100"
    var bands = TestScoring.modelScore

    var body: some View {
        let level = bands.level(score)
        let width = size * 0.11
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: width)
            Circle()
                .trim(from: 0, to: (score ?? 0) / 100)
                .stroke(level.color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(score.map(TestFormat.score) ?? "—")
                    .font(.uiDisplay(size: size * 0.32, weight: .bold))
                    .monospacedDigit()
                Text(unit).font(.uiDisplay(size: size * 0.13, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .padding(width / 2)
    }
}

/// The page all three test dashboards share, so each reads the same way from top to bottom:
/// header, live progress, overview, two panels, details, then every run.
struct TestPage<Controls: View, Content: View>: View {
    let title: String
    let symbol: String
    let subtitle: String
    var caption: String?
    var progress: TestProgress?
    var progressNote: String?
    let onStop: () -> Void
    /// Off only for debug renders of the whole page.
    var scrollable = true
    @ViewBuilder var controls: Controls
    @ViewBuilder var content: Content

    @Environment(TestLab.self) private var lab

    var body: some View {
        if scrollable {
            ScrollView { page }.background(AmbientBackground())
        } else {
            page
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let progress {
                PanelWidget(title: "Running", symbol: "hourglass") { EmptyView() } content: {
                    TestProgressView(progress: progress, onStop: onStop)
                    if let progressNote {
                        Text(progressNote).font(.uiCaption).foregroundStyle(.secondary)
                    }
                }
            }
            if let error = lab.lastError { ErrorBanner(text: error) { lab.dismissError() } }
            content
        }
        .padding(24)
        .frame(maxWidth: 1180)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Palette.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Brand.display(28))
                Text(subtitle)
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) { controls }
                if let caption {
                    Text(caption).font(.uiCaption).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// The first row of every test page: one main card, then four tiles.
struct TestOverview<Hero: View>: View {
    let title: String
    let symbol: String
    let date: Date
    let tiles: (MetricTile, MetricTile, MetricTile, MetricTile)
    @ViewBuilder var hero: Hero

    var body: some View {
        AdaptiveStack(minWidth: 940) {
            PanelWidget(title: title, symbol: symbol) {
                Text(TestFormat.relative(date)).font(.uiCaption).foregroundStyle(.secondary)
            } content: {
                hero
            }
            .frame(minWidth: 380, maxWidth: .infinity)

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    tiles.0
                    tiles.1
                }
                GridRow {
                    tiles.2
                    tiles.3
                }
            }
        }
    }
}

/// What a test page shows before its first run.
struct TestEmptyState: View {
    let text: String

    var body: some View {
        PanelWidget(title: "No results yet", symbol: "sparkles") { EmptyView() } content: {
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The last panel of every test page.
struct TestRunList<Run: Identifiable, Row: View>: View {
    let runs: [Run]
    @ViewBuilder var row: (Run) -> Row

    var body: some View {
        PanelWidget(title: "All runs", symbol: "clock.arrow.circlepath") {
            Text("\(runs.count)").font(.uiCaption).foregroundStyle(.secondary)
        } content: {
            VStack(spacing: 6) {
                ForEach(runs) { row($0) }
            }
        }
    }
}

struct TestRunRow: View {
    let level: HealthLevel
    let date: Date
    let title: String
    var tag: String?
    let result: String
    let selected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(level: level, size: 8)
            Text(date.formatted(date: .abbreviated, time: .shortened)).font(.uiCallout.monospacedDigit()).frame(width: 170, alignment: .leading)
            Text(title).font(.uiCallout).lineLimit(1)
            if let tag {
                Text(tag).font(.uiCaption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Text(result).font(.uiCallout.monospacedDigit()).foregroundStyle(.secondary)
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete this run")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(selected ? Palette.accent.opacity(0.10) : Color.primary.opacity(0.03),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
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
                    if let symbol { Image(systemName: symbol).font(.uiCaption).foregroundStyle(Palette.accent) }
                    Text(title).font(.uiCaption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    if let level { StatusDot(level: level, size: 7) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.uiDisplay(size: 26, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let unit { Text(unit).font(.uiCallout).foregroundStyle(.secondary).lineLimit(1) }
                }
                if let caption {
                    Text(caption).font(.uiCaption).foregroundStyle(.secondary).lineLimit(2)
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
                    Text(progress.step).font(.uiCallout.weight(.semibold))
                    if !progress.detail.isEmpty {
                        Text(progress.detail).font(.uiCaption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(String(format: "%.0f s", context.date.timeIntervalSince(progress.startedAt)))
                        .font(.uiCaption.monospacedDigit())
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
                .font(.uiCallout.weight(.semibold))
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
