import SwiftUI

// The live hardware readout in the telemetry panel (TelemetryPanel.swift), ordered along the data path
// of a reply: GPU (does the work) → memory (holds the model) → CPU.

/// A titled panel with its own tinted background, so each group reads as a separate widget.
struct PanelWidget<Trailing: View, Content: View>: View {
    let title: String
    let symbol: String
    /// Fills the space it's given, for blocks of a fixed size.
    var fill = false
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.accent)
                Text(title).font(.uiHeadline)
                Spacer()
                trailing
            }
            content
        }
        .padding(16)
        .frame(maxWidth: fill ? .infinity : nil, maxHeight: fill ? .infinity : nil, alignment: .topLeading)
        .background(Forge.card, in: shape)
        .overlay(shape.strokeBorder(Forge.line, lineWidth: 1))
    }
}

// MARK: - Hardware

struct HardwareWidget: View {
    @Environment(SystemMonitor.self) private var monitor
    @Environment(ChatController.self) private var chat

    var body: some View {
        let s = monitor.snapshot
        PanelWidget(title: "Hardware", symbol: "cpu.fill") {
            LevelPill(level: thermalLevel(s.thermalState), text: "Heat: \(thermalText(s.thermalState))")
                .help(thermalHelp(s.thermalState))
            TelemetryPanelToggle()
        } content: {
            HStack(alignment: .top, spacing: 8) {
            // GPU — runs the model.
            ComponentCard(title: "GPU", symbol: "square.stack.3d.up.fill",
                          subtitle: monitor.gpuCoreCount.map { "\($0) cores" }) {
                MiniStat(label: "Load", value: Format.percent(s.gpuUsage), threshold: Thresholds.gpuUsage,
                         raw: s.gpuUsage, series: monitor.gpu.points, domain: 0...100)
                MiniStat(label: "Temp", value: Format.temp(s.gpuTemp), detail: s.gpuTempMax.map { "hottest \(Format.temp($0))" },
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
                MiniStat(label: "Temp", value: Format.temp(s.cpuTemp), detail: s.cpuTempMax.map { "hottest \(Format.temp($0))" },
                         threshold: Thresholds.cpuTemp, raw: s.cpuTemp, series: monitor.cpuTemp.points, domain: 20...110)
            } footer: {
                CoreBars(values: s.perCoreUsage)
            }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pressureText(_ p: Int) -> String { p >= 4 ? "Critical" : p >= 2 ? "Warning" : "Normal" }
    private func pressureLevel(_ p: Int) -> HealthLevel { p >= 4 ? .critical : p >= 2 ? .warning : .good }

    private func thermalText(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: return "normal"
        case .fair: return "warm"
        case .serious: return "slowing down"
        case .critical: return "too hot"
        @unknown default: return "unknown"
        }
    }

    /// What macOS's own heat reading means for the person waiting on a reply.
    private func thermalHelp(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: return "This is what macOS reports. The Mac is cool enough to run at full speed."
        case .fair: return "This is what macOS reports. The Mac is warm, and still running at full speed."
        case .serious: return "This is what macOS reports. The Mac is hot, so macOS is slowing the chips down and replies take longer."
        case .critical: return "This is what macOS reports. The Mac is too hot. Stop the model and let it cool."
        @unknown default: return "macOS didn't report how hot the Mac is."
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
                    if let subtitle { Text(subtitle).font(.uiCaption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8) }
                    Spacer()
                }
                HStack(alignment: .top, spacing: 10) {
                    stats
                }
                footer
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
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
                if let detail { Text(detail).font(.uiCaption2.monospacedDigit()).foregroundStyle(.tertiary).lineLimit(1).fixedSize() }
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
        .help("\(label): \(value), \(level.label.lowercased()). \(threshold.scaleNote(unit: value.hasSuffix("%") ? "%" : "°C"))")
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
