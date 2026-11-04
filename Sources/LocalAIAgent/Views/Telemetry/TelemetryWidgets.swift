import SwiftUI

// The two telemetry widgets, each shown in its own floating window (FloatingWidgets.swift):
// Generation (this chat's averages + context) and Hardware, ordered along the data path of a
// reply — GPU (does the work) → memory (holds the model) → CPU.

/// A titled panel with its own tinted background, so each group reads as a separate widget.
struct PanelWidget<Trailing: View, Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Palette.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(title).font(.uiHeadline)
                Spacer()
                trailing
            }
            content
        }
        .padding(12)
        .background {
            shape.fill(Color.primary.opacity(0.045))
            shape.fill(LinearGradient(colors: [Palette.accent.opacity(0.10), .clear], startPoint: .top, endPoint: .center))
        }
        .overlay(shape.strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5))
    }
}

// MARK: - Generation

struct GenerationWidget: View {
    @Environment(ChatController.self) private var chat
    @Environment(BackendController.self) private var backends

    var body: some View {
        // Scoped to this chat + this exact model and quant: a new chat, model or quant starts at zero.
        let avg = chat.averages(for: backends.selectedModel?.id)
        let replies = avg?.responses ?? 0

        PanelWidget(title: "Generation", symbol: "bolt.fill") {
            Text("\(replies) repl\(replies == 1 ? "y" : "ies") · avg")
                .font(.uiCaption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } content: {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    AvgTile(title: "First token", value: Format.seconds(avg?.timeToFirstToken),
                            threshold: Thresholds.timeToFirstToken, raw: avg?.timeToFirstToken,
                            help: "Average time to the first token. Replies that waited for the model to load are left out\(avg.map { $0.coldStarts > 0 ? " (\($0.coldStarts) here)" : "" } ?? "").")
                    AvgTile(title: "Speed", value: Format.rate(avg?.tokensPerSecond), unit: "tok/s",
                            threshold: Thresholds.tokensPerSecond, raw: avg?.tokensPerSecond,
                            help: "Average generation speed")
                }
                GridRow {
                    AvgTile(title: "Prompt speed", value: Format.rate(avg?.promptTokensPerSecond), unit: "tok/s",
                            help: "Average speed of reading the prompt")
                    AvgTile(title: "Reply", value: avg?.completionTokens.map { "\(Int($0.rounded()))" } ?? "—",
                            unit: avg?.totalDuration.map { "tok · \(Format.seconds($0))" } ?? "tok",
                            help: "Average reply length and total time")
                }
            }
            ContextStrip()
        }
    }
}

private struct AvgTile: View {
    let title: String
    let value: String
    var unit: String?
    var threshold: Threshold?
    var raw: Double?
    var help: String

    var body: some View {
        let level = threshold?.level(raw) ?? .unknown
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(title).font(.uiCaption2).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    if threshold != nil { StatusDot(level: level, size: 6) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.uiDisplay(size: 19, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if let unit { Text(unit).font(.uiCaption2).foregroundStyle(.secondary).lineLimit(1) }
                }
                if let threshold {
                    RangeBar(value: raw, threshold: threshold, height: 4)
                }
            }
        }
        .help(help)
    }
}

// MARK: - Context

private struct ContextStrip: View {
    @Environment(ChatController.self) private var chat
    @Environment(BackendController.self) private var backends

    var body: some View {
        let ctx = backends.effectiveContext
        let used = chat.lastMetrics?.contextUsed ?? 0
        let pct = Double(used) / Double(max(ctx, 1)) * 100
        let level = Thresholds.contextUsage.level(pct)

        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "text.word.spacing").font(.uiCaption).foregroundStyle(.secondary)
                    Text("Context").font(.uiCallout.weight(.semibold))
                    Spacer()
                    Text("\(Format.tokens(used)) / \(Format.tokens(ctx))")
                        .font(.uiCallout.monospacedDigit())
                    LevelPill(level: level, text: Format.percent(pct))
                }
                RangeBar(value: pct, threshold: Thresholds.contextUsage, height: 4)
                if chat.trimmedMessageCount > 0 {
                    Text("\(chat.trimmedMessageCount) older messages trimmed to fit")
                        .font(.uiCaption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Hardware

struct HardwareWidget: View {
    @Environment(SystemMonitor.self) private var monitor
    @Environment(ChatController.self) private var chat

    var body: some View {
        let s = monitor.snapshot
        PanelWidget(title: "Hardware", symbol: "cpu.fill") {
            LevelPill(level: thermalLevel(s.thermalState), text: "Thermal: \(thermalText(s.thermalState))")
        } content: {

            // GPU — runs the model.
            ComponentCard(title: "GPU", symbol: "square.stack.3d.up.fill",
                          subtitle: monitor.gpuCoreCount.map { "\($0)-core" }) {
                MiniStat(label: "Load", value: Format.percent(s.gpuUsage), threshold: Thresholds.gpuUsage,
                         raw: s.gpuUsage, series: monitor.gpu.points, domain: 0...100)
                MiniStat(label: "Temp", value: Format.temp(s.gpuTemp), detail: s.gpuTempMax.map { "max \(Int($0))°" },
                         threshold: Thresholds.gpuTemp, raw: s.gpuTemp, series: monitor.gpuTemp.points, domain: 20...110)
            } footer: {
                FooterRow(items: [("GPU memory", Format.bytes(s.gpuMemoryInUse), nil)])
                if chat.isGenerating, (s.gpuUsage ?? 0) >= Thresholds.gpuUsage.warning {
                    Text("High GPU load is expected while generating.")
                        .font(.uiCaption2).foregroundStyle(.tertiary)
                }
            }

            // Memory — holds the model weights and context.
            ComponentCard(title: "Memory", symbol: "memorychip.fill",
                          subtitle: "\(Format.gigabytes(s.memoryUsed)) / \(Format.gigabytes(s.memoryTotal))") {
                MiniStat(label: "Used", value: Format.percent(s.memoryPercent), threshold: Thresholds.memoryUsage,
                         raw: s.memoryPercent, series: monitor.memory.points, domain: 0...100, levelOverride: s.memoryLevel)
                MiniStat(label: "Temp", value: Format.temp(s.memoryTemp), threshold: Thresholds.memoryTemp,
                         raw: s.memoryTemp, series: monitor.memoryTemp.points, domain: 20...100)
            } footer: {
                FooterRow(items: [
                    ("Pressure", pressureText(s.memoryPressure), pressureLevel(s.memoryPressure)),
                    ("Swap", Format.gigabytes(s.swapUsed), s.swapUsed > 2_147_483_648 ? .warning : nil),
                ])
            }

            // CPU — tokenisation, sampling and everything else.
            ComponentCard(title: "CPU", symbol: "cpu", subtitle: "\(s.perCoreUsage.count) cores") {
                MiniStat(label: "Load", value: Format.percent(s.cpuUsage), threshold: Thresholds.cpuUsage,
                         raw: s.cpuUsage, series: monitor.cpu.points, domain: 0...100)
                MiniStat(label: "Temp", value: Format.temp(s.cpuTemp), detail: s.cpuTempMax.map { "max \(Int($0))°" },
                         threshold: Thresholds.cpuTemp, raw: s.cpuTemp, series: monitor.cpuTemp.points, domain: 20...110)
            } footer: {
                CoreBars(values: s.perCoreUsage)
            }
        }
    }

    private func pressureText(_ p: Int) -> String { p >= 4 ? "Critical" : p >= 2 ? "Warning" : "Normal" }
    private func pressureLevel(_ p: Int) -> HealthLevel { p >= 4 ? .critical : p >= 2 ? .warning : .good }

    private func thermalText(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Throttling"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    private func thermalLevel(_ s: ProcessInfo.ThermalState) -> HealthLevel {
        switch s {
        case .nominal: return .good
        case .fair: return .warning
        case .serious, .critical: return .critical
        @unknown default: return .unknown
        }
    }
}

/// A hardware component with its load and temperature side by side.
private struct ComponentCard<Stats: View, Footer: View>: View {
    let title: String
    let symbol: String
    var subtitle: String?
    @ViewBuilder var stats: Stats
    @ViewBuilder var footer: Footer

    var body: some View {
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: symbol).font(.uiCaption).foregroundStyle(Palette.accent)
                    Text(title).font(.uiCallout.weight(.semibold))
                    if let subtitle { Text(subtitle).font(.uiCaption).foregroundStyle(.secondary).monospacedDigit() }
                    Spacer()
                }
                HStack(alignment: .top, spacing: 10) {
                    stats
                }
                footer
            }
        }
    }
}

private struct MiniStat: View {
    let label: String
    let value: String
    var detail: String?
    let threshold: Threshold
    let raw: Double?
    let series: [SamplePoint]
    var domain: ClosedRange<Double>?
    var levelOverride: HealthLevel?

    var body: some View {
        let level = levelOverride ?? threshold.level(raw)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                StatusDot(level: level, size: 6)
                Text(label).font(.uiCaption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let detail { Text(detail).font(.uiCaption2.monospacedDigit()).foregroundStyle(.tertiary) }
            }
            HStack(alignment: .bottom, spacing: 6) {
                Text(value)
                    .font(.uiDisplay(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .fixedSize()
                Sparkline(points: series, color: level == .unknown ? Palette.accent : level.color,
                          domain: domain, height: 20)
            }
            RangeBar(value: raw, threshold: threshold, height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("\(label): \(value) — \(level.label)")
    }
}

private struct FooterRow: View {
    let items: [(String, String, HealthLevel?)]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 4) {
                    if let level = items[i].2 { StatusDot(level: level, size: 5) }
                    Text(items[i].0).foregroundStyle(.secondary)
                    Text(items[i].1).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .font(.uiCaption2)
        .lineLimit(1)
    }
}

private struct CoreBars: View {
    let values: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                let level = Thresholds.cpuUsage.level(v)
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1.5).fill(.quaternary.opacity(0.6))
                    RoundedRectangle(cornerRadius: 1.5).fill(level.color.opacity(0.85))
                        .frame(height: max(1.5, CGFloat(v / 100) * 14))
                }
                .frame(height: 14)
            }
        }
        .help("Per-core utilisation")
    }
}
