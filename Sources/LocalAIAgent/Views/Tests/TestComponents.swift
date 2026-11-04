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

/// The title block at the top of a page.
struct PageHeader<Controls: View>: View {
    let title: String
    let symbol: String
    let subtitle: String
    var caption: String?
    /// A second line under the controls, for what the page is showing instead.
    var notice: String?
    @ViewBuilder var controls: Controls

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Palette.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Brand.display(28))
                // Always two lines' worth, so the blocks below start at the same height on every page.
                Text(subtitle)
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) { controls }
                if let caption {
                    Text(caption).font(.uiCaption).foregroundStyle(.secondary)
                }
                if let notice {
                    Text(notice).font(.uiCaption).foregroundStyle(Palette.accent)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// The page all three tests share: header, live progress, then the blocks.
struct TestPage<Controls: View, Content: View>: View {
    let title: String
    let symbol: String
    let subtitle: String
    var caption: String?
    var notice: String?
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
            ScrollView { page }
        } else {
            page
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: title, symbol: symbol, subtitle: subtitle, caption: caption, notice: notice) { controls }
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
}

/// Block sizes every test page uses, so each block has the same size and place on all of them.
enum TestLayout {
    static let overviewHeight: CGFloat = 236
    static let panelHeight: CGFloat = 330
    static let runsHeight: CGFloat = 200
    static let tileSpacing: CGFloat = 12
    /// Below this the two columns stack.
    static let twoColumnWidth: CGFloat = 860
}

/// Two equal columns of a fixed height, or one above the other in a narrow window.
struct TestColumns<Left: View, Right: View>: View {
    let height: CGFloat
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                left.frame(maxWidth: .infinity, maxHeight: .infinity)
                right.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: TestLayout.twoColumnWidth)
            .frame(height: height)
            VStack(spacing: 16) {
                left.frame(height: height)
                right.frame(height: height)
            }
        }
    }
}

/// The blocks of every test page, in order: main card and four tiles, two panels, then all runs.
/// The details panel follows them because it's the only block whose height changes.
struct TestBlocks<Hero: View, Left: View, Right: View, Runs: View>: View {
    let title: String
    let symbol: String
    let date: Date
    let tiles: (MetricTile, MetricTile, MetricTile, MetricTile)
    @ViewBuilder var hero: Hero
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right
    @ViewBuilder var runs: Runs

    var body: some View {
        TestColumns(height: TestLayout.overviewHeight) {
            PanelWidget(title: title, symbol: symbol, fill: true) {
                Text(TestFormat.relative(date)).font(.uiCaption).foregroundStyle(.secondary)
            } content: {
                hero
            }
        } right: {
            VStack(spacing: TestLayout.tileSpacing) {
                HStack(spacing: TestLayout.tileSpacing) {
                    tiles.0
                    tiles.1
                }
                HStack(spacing: TestLayout.tileSpacing) {
                    tiles.2
                    tiles.3
                }
            }
        }
        TestColumns(height: TestLayout.panelHeight) { left } right: { right }
        runs
    }
}

/// What the main card holds on every test page: a score ring with three lines beside it, then its scale.
struct TestHero<Chips: View>: View {
    let score: Double?
    var unit = "/100"
    var bands = TestScoring.modelScore
    let headline: String
    var aside: String?
    let detail: String
    var scale = ["Basic", "Capable", "Advanced", "Expert", "Frontier"]
    let note: String
    @ViewBuilder var chips: Chips

    var body: some View {
        HStack(spacing: 16) {
            ScoreRing(score: score, size: 92, unit: unit, bands: bands)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(headline).font(.uiTitle3.weight(.semibold)).lineLimit(1)
                    if let aside {
                        Text(aside).font(.uiCallout).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Text(detail).font(.uiCallout).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) { chips }
            }
            Spacer(minLength: 0)
        }
        Spacer(minLength: 0)
        VStack(alignment: .leading, spacing: 4) {
            RangeBar(value: score, threshold: bands, height: 5)
            HStack {
                ForEach(Array(scale.enumerated()), id: \.element) { index, label in
                    if index > 0 { Spacer(minLength: 0) }
                    Text(label).font(.uiCaption2).foregroundStyle(.secondary)
                }
            }
            Text(note).font(.uiCaption2).foregroundStyle(.tertiary).lineLimit(1).minimumScaleFactor(0.85)
        }
    }
}

/// How a model run was set up, for the main card.
struct ModelRunChips: View {
    let run: ModelTestResult

    var body: some View {
        Chip(text: run.thinking ? "Thinking on" : "Thinking off", symbol: "brain", tint: run.thinking ? Palette.accent : .secondary)
        Chip(text: "\(Format.tokens(run.contextLength)) context", symbol: "text.word.spacing", tint: .secondary)
        if run.usesHarness {
            Chip(text: run.harnessRounds.map { "Harness · \($0) rounds" } ?? "Harness", symbol: "shield.lefthalf.filled", tint: Palette.accent)
        }
    }
}

/// One of the two panels in the middle of a test page.
struct TestPanel<Content: View>: View {
    let title: String
    let symbol: String
    let note: String
    @ViewBuilder var content: Content

    var body: some View {
        PanelWidget(title: title, symbol: symbol, fill: true) {
            Text(note).font(.uiCaption).foregroundStyle(.secondary).lineLimit(1)
        } content: {
            content
        }
    }
}

/// The last block of a test page: one panel, with tabs for what each test has to show.
struct TestDetails<Tab: Hashable, Content: View>: View {
    let tabs: [(id: Tab, title: String)]
    @Binding var selection: Tab
    @ViewBuilder var content: Content

    var body: some View {
        PanelWidget(title: "Details", symbol: "list.bullet.rectangle.portrait.fill") {
            HStack(spacing: 4) {
                ForEach(tabs, id: \.id) { tab in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selection = tab.id }
                    } label: {
                        Text(tab.title)
                            .font(.uiCaption.weight(.medium))
                            .foregroundStyle(selection == tab.id ? .white : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(selection == tab.id ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Color.primary.opacity(0.06)), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        } content: {
            content
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

/// Every run of a test, in a block of a fixed height.
struct TestRunList<Run: Identifiable, Row: View>: View {
    let runs: [Run]
    @ViewBuilder var row: (Run) -> Row

    var body: some View {
        PanelWidget(title: "All runs", symbol: "clock.arrow.circlepath", fill: true) {
            Text("\(runs.count)").font(.uiCaption).foregroundStyle(.secondary)
        } content: {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(runs) { row($0) }
                }
            }
        }
        .frame(height: TestLayout.runsHeight)
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
