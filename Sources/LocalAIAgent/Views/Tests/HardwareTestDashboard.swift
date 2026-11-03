import Charts
import SwiftUI

/// Full results of the hardware test, and what they mean for running models on this Mac.
struct HardwareTestDashboard: View {
    @Environment(TestLab.self) private var lab
    @Environment(BackendController.self) private var backends
    @Environment(ChatController.self) private var chat
    @Environment(SystemMonitor.self) private var monitor
    @Environment(AppSettings.self) private var settings

    /// Off only for debug renders of the whole page.
    var scrollable = true

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
                if let progress = lab.hardwareProgress {
                    PanelWidget(title: "Running", symbol: "hourglass") { EmptyView() } content: {
                        TestProgressView(progress: progress) { lab.cancelHardwareTest() }
                        Text("Keep other heavy apps closed for steady numbers. The last step holds the GPU at full load to check for throttling.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error = lab.lastError { ErrorBanner(text: error) { lab.dismissError() } }

                if let run = lab.selectedHardwareRun {
                    machine(run)
                    metrics(run)
                    thermals(run)
                    meaning(run)
                    history(selected: run)
                } else if lab.hardwareProgress == nil {
                    PanelWidget(title: "No results yet", symbol: "sparkles") { EmptyView() } content: {
                        Text("Run the test to measure what drives local AI on this Mac: GPU math for reading prompts, memory bandwidth for generating tokens, and disk speed for loading models.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Palette.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Hardware Test").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("CPU, GPU, memory and disk: the parts that set how fast models load, read and write on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            RunTestButton(title: "Run hardware test", disabled: lab.isRunning || chat.isGenerating) {
                lab.runHardwareTest(monitor: monitor, backends: backends)
            }
        }
    }

    // MARK: Machine and metrics

    private func machine(_ run: HardwareTestResult) -> some View {
        PanelWidget(title: run.chip, symbol: "laptopcomputer") {
            Text(TestFormat.relative(run.date)).font(.caption).foregroundStyle(.secondary)
        } content: {
            FlowLayout(spacing: 8) {
                Chip(text: "\(run.cpuCores) CPU cores", symbol: "cpu", tint: .secondary)
                if let gpu = run.gpuCores { Chip(text: "\(gpu) GPU cores", symbol: "square.stack.3d.up", tint: .secondary) }
                Chip(text: "\(Format.gigabytes(run.memoryBytes)) memory", symbol: "memorychip", tint: .secondary)
                Chip(text: "≈ \(Format.gigabytes(run.gpuBudgetBytes)) usable by the GPU", symbol: "square.stack.3d.up.fill", tint: .secondary)
                Chip(text: "Test took \(Format.seconds(run.duration))", symbol: "clock", tint: .secondary)
                if let state = run.worstThermalState {
                    Chip(text: "Thermal: \(state)", symbol: "thermometer.medium", tint: state == "Nominal" ? Palette.good : Palette.warning)
                }
            }
        }
    }

    private func metrics(_ run: HardwareTestResult) -> some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                MetricTile(title: "GPU compute", value: TestFormat.number(run.gpuTFLOPS, decimals: 2), unit: "TFLOPS",
                           caption: "FP16 matrix math · sets prompt reading speed", symbol: "square.stack.3d.up.fill")
                MetricTile(title: "GPU memory bandwidth", value: TestFormat.gbPerSecond(run.gpuBandwidth), unit: "GB/s",
                           caption: "Sets token generation speed", symbol: "arrow.left.arrow.right")
                MetricTile(title: "CPU memory bandwidth", value: TestFormat.gbPerSecond(run.cpuBandwidth), unit: "GB/s",
                           caption: "All cores copying at once", symbol: "memorychip")
                MetricTile(title: "Sustained GPU", value: Format.percent(run.sustainedPercent),
                           caption: "Of peak after 15 s at full load", symbol: "flame",
                           level: TestScoring.sustained.level(run.sustainedPercent))
            }
            GridRow {
                MetricTile(title: "CPU · one core", value: TestFormat.number(run.cpuSingle, decimals: 0), unit: "M it/s",
                           caption: "Mandelbrot iterations per second", symbol: "cpu")
                MetricTile(title: "CPU · all cores", value: TestFormat.number(run.cpuMulti, decimals: 0), unit: "M it/s",
                           caption: run.cpuSingle.flatMap { s in run.cpuMulti.map { String(format: "%.1f× one core", $0 / max(s, 0.001)) } },
                           symbol: "cpu.fill")
                MetricTile(title: "Disk read", value: TestFormat.gbPerSecond(run.diskRead), unit: "GB/s",
                           caption: run.diskRead.map { "Reads a 5 GB model in ≈ \(Format.seconds(5 / max($0, 0.01)))" }, symbol: "internaldrive")
                MetricTile(title: "Disk write", value: TestFormat.gbPerSecond(run.diskWrite), unit: "GB/s",
                           caption: "Sets how fast downloads are saved", symbol: "square.and.arrow.down")
            }
        }
    }

    // MARK: Thermals

    private static let shortPhaseNames = [
        "CPU · one core": "1 core", "CPU · all cores": "All cores", "Memory bandwidth": "Memory",
        "GPU compute": "GPU", "GPU memory": "GPU mem", "Disk": "Disk", "Sustained GPU load": "Sustained GPU load",
    ]

    private func thermals(_ run: HardwareTestResult) -> some View {
        PanelWidget(title: "Thermals during the test", symbol: "thermometer.medium") {
            Text("peak CPU \(Format.temp(run.peakCPUTemp)) · GPU \(Format.temp(run.peakGPUTemp))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        } content: {
            Chart {
                ForEach(Array(run.phases.enumerated()), id: \.element.id) { index, phase in
                    RectangleMark(xStart: .value("Start", phase.start), xEnd: .value("End", phase.end))
                        .foregroundStyle(Color.primary.opacity(index.isMultiple(of: 2) ? 0.06 : 0.02))
                        .annotation(position: .top, alignment: .leading, spacing: 2) {
                            // Only label bands wide enough to hold their name.
                            if phase.end - phase.start >= run.duration * 0.08 {
                                Text(Self.shortPhaseNames[phase.name] ?? phase.name)
                                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                            }
                        }
                }
                ForEach(run.timeline) { s in
                    if let load = s.gpuLoad {
                        AreaMark(x: .value("Time", s.t), y: .value("GPU load", load), series: .value("Series", "GPU load"))
                            .foregroundStyle(Palette.glow.opacity(0.22))
                            .interpolationMethod(.monotone)
                    }
                }
                ForEach(run.timeline) { s in
                    if let t = s.cpuTemp {
                        LineMark(x: .value("Time", s.t), y: .value("°C", t), series: .value("Series", "CPU"))
                            .foregroundStyle(Palette.accent2)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.monotone)
                    }
                }
                ForEach(run.timeline) { s in
                    if let t = s.gpuTemp {
                        LineMark(x: .value("Time", s.t), y: .value("°C", t), series: .value("Series", "GPU"))
                            .foregroundStyle(Palette.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            .chartYScale(domain: 0...105)
            .chartXScale(domain: 0...max(run.duration, 1))
            .chartXAxisLabel("seconds")
            .frame(height: 220)
            HStack(spacing: 14) {
                legend("CPU temperature °C", Palette.accent2)
                legend("GPU temperature °C", Palette.accent)
                legend("GPU load %", Palette.glow.opacity(0.5))
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: What it means

    private struct Estimate: Identifiable {
        let name: String
        let quant: String
        let tokensPerSecond: Double
        let measured: Double?
        let fit: MemoryFit.Verdict
        var id: String { name + quant }
    }

    private func estimates(_ run: HardwareTestResult) -> [Estimate] {
        guard let bandwidth = run.gpuBandwidth else { return [] }
        let measured = Dictionary(lab.leaderboard.map { ($0.model, $0.tokensPerSecond) }, uniquingKeysWith: { first, _ in first })
        return ModelCatalog.all.map { catalog in
            let variant = catalog.defaultVariant
            let tested = backends.models.first { variant.matches($0.id) }.flatMap { measured[$0.id] ?? nil }
                ?? measured[variant.tag] ?? nil
            let fit = MemoryFit.verdict(requiredBytes: backends.memoryEstimate(for: catalog, variant: variant), budget: run.gpuBudgetBytes)
            return Estimate(name: catalog.displayName, quant: variant.quant,
                            tokensPerSecond: SpeedEstimate.tokensPerSecond(modelBytes: variant.bytes, bandwidthGBs: bandwidth),
                            measured: tested, fit: fit)
        }
        .sorted { $0.tokensPerSecond > $1.tokensPerSecond }
    }

    private func meaning(_ run: HardwareTestResult) -> some View {
        let rows = estimates(run)
        let top = max(rows.map { max($0.tokensPerSecond, $0.measured ?? 0) }.max() ?? 1, 1)
        return PanelWidget(title: "What this means for local AI", symbol: "sparkles") {
            Text("generation speed per model").font(.caption).foregroundStyle(.secondary)
        } content: {
            VStack(spacing: 6) {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        HStack(spacing: 5) {
                            Text(row.name).lineLimit(1)
                            Text(row.quant).foregroundStyle(.tertiary)
                        }
                        .font(.caption)
                        .frame(width: 210, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.05))
                                Capsule().fill(row.fit.level.color.opacity(0.8).gradient)
                                    .frame(width: max(geo.size.width * row.tokensPerSecond / top, 4))
                                if let measured = row.measured {
                                    Circle().fill(.white)
                                        .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1))
                                        .frame(width: 10, height: 10)
                                        .offset(x: min(geo.size.width * measured / top, geo.size.width) - 5)
                                }
                            }
                        }
                        .frame(height: 8)
                        Group {
                            if let measured = row.measured {
                                Text("\(Format.rate(measured)) measured").fontWeight(.semibold)
                            } else if row.fit == .tooLarge {
                                Text("won't fit").foregroundStyle(Palette.critical)
                            } else {
                                Text("≈ \(Int(row.tokensPerSecond.rounded())) tok/s").foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption.monospacedDigit())
                        .frame(width: 104, alignment: .trailing)
                    }
                    .help(row.measured.map { "Measured \(Format.rate($0)) tok/s in the model test; estimate ≈ \(Format.rate(row.tokensPerSecond))" }
                          ?? "\(row.fit.label) · estimate ≈ \(Format.rate(row.tokensPerSecond)) tok/s")
                }
            }
            HStack(spacing: 14) {
                legend("Runs great", Palette.good)
                legend("Tight fit", Palette.warning)
                legend("Too large", Palette.critical)
                legend("Measured in the model test", .white)
                Spacer()
            }
            Text("Each new token reads the whole model from memory once, so speed ≈ memory bandwidth ÷ model size. Bars use your measured GPU bandwidth; colours show whether the model fits in GPU memory at \(Format.tokens(settings.contextLength)) context.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: History

    private func history(selected: HardwareTestResult) -> some View {
        PanelWidget(title: "All runs", symbol: "clock.arrow.circlepath") {
            Text("\(lab.hardwareResults.count)").font(.caption).foregroundStyle(.secondary)
        } content: {
            VStack(spacing: 6) {
                ForEach(lab.hardwareResults) { run in
                    HStack(spacing: 10) {
                        StatusDot(level: TestScoring.sustained.level(run.sustainedPercent), size: 8)
                        Text(run.date.formatted(date: .abbreviated, time: .shortened)).font(.callout.monospacedDigit()).frame(width: 170, alignment: .leading)
                        Text(run.chip).font(.callout).lineLimit(1)
                        Spacer()
                        Text("\(TestFormat.number(run.gpuTFLOPS, decimals: 2)) TFLOPS · \(TestFormat.gbPerSecond(run.gpuBandwidth)) GB/s · \(TestFormat.number(run.cpuMulti, decimals: 0)) M it/s")
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        Button { lab.delete(hardwareRun: run.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help("Delete this run")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(run.id == selected.id ? Palette.accent.opacity(0.10) : Color.primary.opacity(0.03),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { lab.selectedHardwareRunID = run.id }
                }
            }
        }
    }
}
