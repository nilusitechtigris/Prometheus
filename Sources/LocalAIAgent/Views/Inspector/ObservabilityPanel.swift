import SwiftUI

struct ObservabilityPanel: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GenerationSection()
                ContextSection()
                ModelMemorySection()
                SystemSection()
                ThermalSection()
                RangesLegend()
            }
            .padding(14)
        }
        .background(.background.secondary)
    }
}

// MARK: - Generation

private struct GenerationSection: View {
    @Environment(ChatController.self) private var chat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Generation", symbol: "bolt.horizontal.fill",
                          trailing: chat.live != nil ? AnyView(LevelPill(level: .good, text: "Live")) : nil)

            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let live = chat.live
                let m = chat.lastMetrics
                let ttft = live?.timeToFirstToken ?? (live == nil ? m?.timeToFirstToken : nil)
                let tps = live?.tokensPerSecond ?? (live == nil ? m?.tokensPerSecond : nil)

                HStack(spacing: 10) {
                    BigMetric(title: "Time to first token", value: Format.seconds(ttft), unit: "",
                              level: Thresholds.timeToFirstToken.level(ttft), threshold: Thresholds.timeToFirstToken, raw: ttft)
                    BigMetric(title: "Tokens / sec", value: Format.rate(tps), unit: "",
                              level: Thresholds.tokensPerSecond.level(tps), threshold: Thresholds.tokensPerSecond, raw: tps)
                }
            }

            if let load = chat.lastMetrics?.loadDuration, load > 0.5, chat.live == nil {
                Label("TTFT includes \(Format.seconds(load)) of model loading (cold start). Follow-up messages are much faster while the model stays in memory.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let m = chat.lastMetrics, chat.live == nil {
                Card(padding: 10) {
                    VStack(spacing: 6) {
                        row("Prompt processing", m.promptTokensPerSecond.map { "\(Format.rate($0)) tok/s" } ?? "—")
                        row("Tokens in / out", "\(m.promptTokens.map(String.init) ?? "—") / \(m.completionTokens.map(String.init) ?? "—")\(m.isEstimated ? " ≈" : "")")
                        if let load = m.loadDuration {
                            row("Model load", Format.seconds(load), note: load > 0.5 ? "cold start" : nil)
                        }
                        if let t = m.thinkingDuration { row("Thinking time", Format.seconds(t)) }
                        row("Total time", Format.seconds(m.totalDuration))
                    }
                }
            } else if chat.live == nil {
                Text("Send a message to see speed metrics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if chat.throughputHistory.count >= 2 {
                Card(padding: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Throughput per response (tok/s)").font(.caption).foregroundStyle(.secondary)
                        Sparkline(points: chat.throughputHistory, color: Palette.accent2,
                                  rules: [Thresholds.tokensPerSecond.critical, Thresholds.tokensPerSecond.warning])
                    }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String, note: String? = nil) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            if let note { Text(note).font(.caption2).foregroundStyle(.tertiary) }
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}

private struct BigMetric: View {
    let title: String
    let value: String
    let unit: String
    let level: HealthLevel
    let threshold: Threshold
    let raw: Double?

    var body: some View {
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    StatusDot(level: level, size: 7)
                }
                Text(value)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                RangeBar(value: raw, threshold: threshold, height: 5)
            }
        }
    }
}

// MARK: - Context

private struct ContextSection: View {
    @Environment(ChatController.self) private var chat
    @Environment(BackendController.self) private var backends

    var body: some View {
        let ctx = backends.effectiveContext
        let used = chat.lastMetrics?.contextUsed
        let pct = used.map { Double($0) / Double(max(ctx, 1)) * 100 }

        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Context window", symbol: "text.word.spacing")
            Card(padding: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(used.map { Format.tokens($0) } ?? "0")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("of \(Format.tokens(ctx)) tokens")
                            .foregroundStyle(.secondary)
                        Spacer()
                        LevelPill(level: Thresholds.contextUsage.level(pct ?? 0), text: Format.percent(pct ?? 0))
                    }
                    RangeBar(value: pct ?? 0, threshold: Thresholds.contextUsage, height: 6)
                    if chat.trimmedMessageCount > 0 {
                        Label("\(chat.trimmedMessageCount) older messages trimmed to fit", systemImage: "scissors")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let max = backends.maxContext {
                        Text("Model supports up to \(Format.tokens(max)) tokens\(backends.kind.supportsPerRequestContext ? "" : " · set in \(backends.kind.displayName)")")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

// MARK: - Model memory

private struct ModelMemorySection: View {
    @Environment(BackendController.self) private var backends
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Model in memory", symbol: "memorychip")
            if backends.kind != .ollama {
                Card(padding: 10) {
                    Text("Loaded-model memory is reported by Ollama. \(backends.kind.displayName) shows it in its own window.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if backends.loaded.isEmpty {
                Card(padding: 10) {
                    HStack {
                        Image(systemName: "moon.zzz").foregroundStyle(.secondary)
                        Text("No model loaded. It loads on your next message and unloads after 10 idle minutes.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(backends.loaded) { m in
                    LoadedModelCard(model: m, budget: monitor.gpuBudgetBytes)
                }
            }
        }
    }
}

private struct LoadedModelCard: View {
    @Environment(BackendController.self) private var backends
    let model: LoadedModel
    let budget: Int64

    var body: some View {
        let gpuShare = model.sizeBytes > 0 ? Double(model.vramBytes) / Double(model.sizeBytes) * 100 : 0
        let budgetPct = Double(model.sizeBytes) / Double(max(budget, 1)) * 100
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(ModelCatalog.entry(matchingID: model.name)?.displayName ?? model.name)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Button("Unload") { Task { await backends.unload(model.name) } }
                        .controlSize(.small)
                        .help("Free this model's memory now")
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.gigabytes(model.sizeBytes))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("of \(Format.gigabytes(budget)) GPU budget").foregroundStyle(.secondary)
                    Spacer()
                }
                RangeBar(value: budgetPct, threshold: Threshold(warning: 70, critical: 95, displayMax: 100), height: 6)
                HStack(spacing: 6) {
                    Chip(text: gpuShare >= 99.5 ? "100% GPU" : String(format: "%.0f%% GPU / %.0f%% CPU", gpuShare, 100 - gpuShare),
                         symbol: "cpu", tint: gpuShare >= 99.5 ? Palette.good : Palette.warning)
                    if let ctx = model.contextLength { Chip(text: "\(Format.tokens(ctx)) ctx", symbol: "text.word.spacing") }
                    if let exp = model.expiresAt, exp > Date() {
                        Chip(text: "unloads \(exp.formatted(.relative(presentation: .numeric)))", symbol: "timer")
                    }
                }
            }
        }
    }
}

// MARK: - System

private struct SystemSection: View {
    @Environment(SystemMonitor.self) private var monitor
    @Environment(ChatController.self) private var chat

    var body: some View {
        let s = monitor.snapshot
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "System", symbol: "cpu")

            MetricCard(title: "CPU", symbol: "cpu", value: Format.percent(s.cpuUsage),
                       detail: "\(s.perCoreUsage.count) cores", threshold: Thresholds.cpuUsage,
                       raw: s.cpuUsage, series: monitor.cpu.points, domain: 0...100) {
                CoreBars(values: s.perCoreUsage)
            }

            MetricCard(title: "GPU", symbol: "square.stack.3d.up.fill", value: Format.percent(s.gpuUsage),
                       detail: monitor.gpuCoreCount.map { "\($0)-core GPU" } ?? "", threshold: Thresholds.gpuUsage,
                       raw: s.gpuUsage, series: monitor.gpu.points, domain: 0...100) {
                HStack {
                    Text("GPU memory in use").foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.bytes(s.gpuMemoryInUse)).monospacedDigit()
                }
                .font(.caption)
                if chat.isGenerating, (s.gpuUsage ?? 0) >= Thresholds.gpuUsage.warning {
                    Label("High GPU load is expected while generating.", systemImage: "info.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            MetricCard(title: "Memory", symbol: "memorychip.fill",
                       value: Format.percent(s.memoryPercent),
                       detail: "\(Format.gigabytes(s.memoryUsed)) of \(Format.gigabytes(s.memoryTotal))",
                       threshold: Thresholds.memoryUsage, raw: s.memoryPercent, series: monitor.memory.points,
                       domain: 0...100, levelOverride: s.memoryLevel) {
                VStack(spacing: 3) {
                    breakdown("Pressure", pressureText(s.memoryPressure), level: pressureLevel(s.memoryPressure))
                    breakdown("App", Format.gigabytes(s.memoryApp))
                    breakdown("Wired", Format.gigabytes(s.memoryWired))
                    breakdown("Compressed", Format.gigabytes(s.memoryCompressed))
                    breakdown("Swap used", Format.gigabytes(s.swapUsed), level: s.swapUsed > 2_147_483_648 ? .warning : nil)
                }
            }
        }
    }

    private func breakdown(_ label: String, _ value: String, level: HealthLevel? = nil) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            if let level { StatusDot(level: level, size: 6) }
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }

    private func pressureText(_ p: Int) -> String { p >= 4 ? "Critical" : p >= 2 ? "Warning" : "Normal" }
    private func pressureLevel(_ p: Int) -> HealthLevel { p >= 4 ? .critical : p >= 2 ? .warning : .good }
}

private struct MetricCard<Extra: View>: View {
    let title: String
    let symbol: String
    let value: String
    let detail: String
    let threshold: Threshold
    let raw: Double?
    let series: [SamplePoint]
    var domain: ClosedRange<Double>?
    var levelOverride: HealthLevel?
    @ViewBuilder var extra: Extra

    var body: some View {
        let level = levelOverride ?? threshold.level(raw)
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: symbol).foregroundStyle(.secondary).font(.caption)
                    Text(title).font(.callout.weight(.semibold))
                    Spacer()
                    LevelPill(level: level)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(value)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                RangeBar(value: raw, threshold: threshold, height: 5)
                Sparkline(points: series, color: level == .unknown ? Palette.accent : level.color, domain: domain,
                          rules: [threshold.warning, threshold.critical], height: 34)
                extra
            }
        }
    }
}

private struct CoreBars: View {
    let values: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                let level = Thresholds.cpuUsage.level(v)
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2).fill(.quaternary.opacity(0.6))
                    RoundedRectangle(cornerRadius: 2).fill(level.color.opacity(0.85))
                        .frame(height: max(2, CGFloat(v / 100) * 22))
                }
                .frame(height: 22)
            }
        }
        .help("Per-core utilisation")
    }
}

// MARK: - Thermals

private struct ThermalSection: View {
    @Environment(SystemMonitor.self) private var monitor

    var body: some View {
        let s = monitor.snapshot
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Temperature", symbol: "thermometer.medium",
                          trailing: AnyView(LevelPill(level: thermalLevel(s.thermalState), text: "macOS: \(thermalText(s.thermalState))")))

            Card(padding: 10) {
                VStack(spacing: 12) {
                    ThermalRow(title: "CPU", symbol: "cpu", value: s.cpuTemp, max: s.cpuTempMax,
                               threshold: Thresholds.cpuTemp, series: monitor.cpuTemp.points)
                    Divider()
                    ThermalRow(title: "GPU", symbol: "square.stack.3d.up.fill", value: s.gpuTemp, max: s.gpuTempMax,
                               threshold: Thresholds.gpuTemp, series: monitor.gpuTemp.points)
                    Divider()
                    ThermalRow(title: "Memory", symbol: "memorychip.fill", value: s.memoryTemp, max: nil,
                               threshold: Thresholds.memoryTemp, series: monitor.memoryTemp.points)
                }
            }
            if s.cpuTemp == nil && s.gpuTemp == nil {
                Text("Temperature sensors aren't readable on this Mac; macOS thermal state is shown instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

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

private struct ThermalRow: View {
    let title: String
    let symbol: String
    let value: Double?
    let max: Double?
    let threshold: Threshold
    let series: [SamplePoint]

    var body: some View {
        let level = threshold.level(value)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Gauge(value: Swift.min(Swift.max(value ?? threshold.displayMin, threshold.displayMin), threshold.displayMax),
                      in: threshold.displayMin...threshold.displayMax) {
                    EmptyView()
                } currentValueLabel: {
                    Text(value.map { String(format: "%.0f", $0) } ?? "—")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Gradient(stops: gradientStops))
                .scaleEffect(0.78)
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.callout.weight(.semibold))
                        LevelPill(level: level)
                    }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Sparkline(points: series, color: level == .unknown ? Palette.accent : level.color,
                          domain: threshold.displayMin...threshold.displayMax,
                          rules: [threshold.warning, threshold.critical], height: 30)
                    .frame(width: 90)
            }
            RangeBar(value: value, threshold: threshold, height: 5)
        }
    }

    private var subtitle: String {
        guard let value else { return "Sensor unavailable" }
        var s = String(format: "Avg %.1f°C", value)
        if let max { s += String(format: " · Hottest %.0f°C", max) }
        return s
    }

    private var gradientStops: [Gradient.Stop] {
        let span = threshold.displayMax - threshold.displayMin
        let w = (threshold.warning - threshold.displayMin) / span
        let c = (threshold.critical - threshold.displayMin) / span
        return [
            .init(color: Palette.good, location: 0),
            .init(color: Palette.good, location: w - 0.02),
            .init(color: Palette.warning, location: w + 0.02),
            .init(color: Palette.warning, location: c - 0.02),
            .init(color: Palette.critical, location: c + 0.02),
            .init(color: Palette.critical, location: 1),
        ]
    }
}

// MARK: - Legend

private struct RangesLegend: View {
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                legend("CPU / GPU load", Thresholds.describe(Thresholds.cpuUsage, unit: "%"))
                legend("Memory used", Thresholds.describe(Thresholds.memoryUsage, unit: "%") + " (or macOS memory pressure)")
                legend("CPU / GPU temperature", Thresholds.describe(Thresholds.cpuTemp, unit: "°C"))
                legend("Memory temperature", Thresholds.describe(Thresholds.memoryTemp, unit: "°C"))
                legend("Time to first token", Thresholds.describe(Thresholds.timeToFirstToken, unit: " s", decimals: 1))
                legend("Tokens / sec", Thresholds.describe(Thresholds.tokensPerSecond, unit: ""))
                legend("Context used", Thresholds.describe(Thresholds.contextUsage, unit: "%"))
                Text("Apple Silicon runs hot by design and throttles near 100 °C. Temperatures come from the SMC and SoC sensors; no admin rights needed.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                StatusDot(level: .good, size: 6)
                StatusDot(level: .warning, size: 6)
                StatusDot(level: .critical, size: 6)
                Text("How ranges are defined").font(.caption.weight(.medium))
            }
        }
        .padding(.horizontal, 2)
    }

    private func legend(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption.weight(.semibold))
            Text(text).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
