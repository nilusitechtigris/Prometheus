import Charts
import SwiftUI

/// Full results of the hardware test, and what they mean for running models on this Mac.
struct HardwareTestDashboard: View {
    enum Detail: Hashable { case localAI, phases }

    @Environment(TestLab.self) private var lab
    @Environment(BackendController.self) private var backends
    @Environment(ChatController.self) private var chat
    @Environment(SystemMonitor.self) private var monitor
    @Environment(AppSettings.self) private var settings

    /// Off only for debug renders of the whole page.
    var scrollable = true
    @State var detail = Detail.localAI

    var body: some View {
        TestPage(title: "Hardware Test",
                 subtitle: "How fast this Mac computes, moves memory and reads its disk: the parts that set how quickly models load, read and write.",
                 caption: "\(ProcessInfo.processInfo.activeProcessorCount) CPU cores · Takes about 30 seconds",
                 progress: lab.hardwareProgress,
                 progressNote: "Keep other heavy apps closed for steady numbers. The last step holds the GPU at full load to check for throttling.",
                 onStop: { lab.cancelHardwareTest() }, scrollable: scrollable, shownRun: lab.selectedHardwareRun?.id) {
            Text(monitor.chipName)
                .font(.uiCallout.weight(.medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.08), in: Capsule(style: .circular))
                .overlay(Capsule(style: .circular).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            RunTestButton(title: "Run test", disabled: lab.isRunning || chat.isGenerating) {
                lab.runHardwareTest(monitor: monitor, backends: backends)
            }
        } content: {
            if let run = lab.selectedHardwareRun {
                TestBlocks(title: run.chip, symbol: "laptopcomputer", date: run.date, tiles: tiles(run)) {
                    hero(run)
                } left: {
                    measurements(run)
                } right: {
                    thermals(run)
                } runs: {
                    history(selected: run)
                }
                TestDetails(tabs: [(.localAI, "Local AI speed"), (.phases, "Test steps")], selection: $detail) {
                    switch detail {
                    case .localAI: meaning(run)
                    case .phases: phases(run)
                    }
                }
            } else if lab.hardwareProgress == nil {
                TestEmptyState(text: "Run the test to measure what drives local AI on this Mac: GPU math for reading prompts, memory bandwidth for generating tokens, and disk speed for loading models.")
            }
        }
    }

    /// The hottest macOS said the Mac got during a run, in plain words. Runs save macOS's own word for it.
    static func heatCaption(_ worst: String?) -> String {
        switch worst?.lowercased() {
        case "nominal": "The Mac stayed cool throughout"
        case "fair": "The Mac got warm, at full speed"
        case "serious", "throttling": "The Mac got hot and was slowed down"
        case "critical": "The Mac got too hot"
        default: "Heat wasn't recorded"
        }
    }

    // MARK: Overview

    private func tiles(_ run: HardwareTestResult) -> (MetricTile, MetricTile, MetricTile, MetricTile) {
        (MetricTile(title: "GPU compute", value: TestFormat.number(run.gpuTFLOPS, decimals: 2), unit: "TFLOPS",
                    caption: "Sets prompt reading speed", symbol: "square.stack.3d.up.fill"),
         MetricTile(title: "Memory bandwidth", value: TestFormat.gbPerSecond(run.gpuBandwidth), unit: "GB/s",
                    caption: "Sets token generation speed", symbol: "arrow.left.arrow.right"),
         MetricTile(title: "Disk read", value: TestFormat.gbPerSecond(run.diskRead), unit: "GB/s",
                    caption: run.diskRead.map { "Reads a 5 GB model in ≈ \(Format.seconds(5 / max($0, 0.01)))" }, symbol: "internaldrive"),
         MetricTile(title: "Test time", value: Format.seconds(run.duration),
                    caption: Self.heatCaption(run.worstThermalState), symbol: "clock"))
    }

    private func hero(_ run: HardwareTestResult) -> some View {
        TestHero(score: run.sustainedPercent, unit: "%", bands: TestScoring.sustained,
                 headline: TestScoring.sustained.level(run.sustainedPercent) == .good ? "No throttling" : "Throttling under load",
                 aside: "sustained speed",
                 detail: "GPU speed after 15 s at full load, against its best burst.",
                 scale: ["Throttling", "Steady"],
                 note: "≈ \(Format.gigabytes(run.gpuBudgetBytes)) of memory is usable by the GPU, which limits the largest model.") {
            Chip(text: "\(run.cpuCores) CPU", symbol: "cpu", tint: .secondary)
            if let gpu = run.gpuCores { Chip(text: "\(gpu) GPU", symbol: "square.stack.3d.up", tint: .secondary) }
            Chip(text: Format.gigabytes(run.memoryBytes), symbol: "memorychip", tint: .secondary)
        }
    }

    // MARK: Measurements

    private func measurements(_ run: HardwareTestResult) -> some View {
        let rows: [(String, String, String)] = [
            ("CPU · one core", "\(TestFormat.number(run.cpuSingle, decimals: 0)) M it/s", "Mandelbrot iterations"),
            ("CPU · all cores", "\(TestFormat.number(run.cpuMulti, decimals: 0)) M it/s",
             run.cpuSingle.flatMap { s in run.cpuMulti.map { String(format: "%.1f× one core", $0 / max(s, 0.001)) } } ?? ""),
            ("GPU compute", "\(TestFormat.number(run.gpuTFLOPS, decimals: 2)) TFLOPS", "FP16 matrix math"),
            ("GPU memory", "\(TestFormat.gbPerSecond(run.gpuBandwidth)) GB/s", "Copy bandwidth"),
            ("CPU memory", "\(TestFormat.gbPerSecond(run.cpuBandwidth)) GB/s", "All cores copying"),
            ("Disk read", "\(TestFormat.gbPerSecond(run.diskRead)) GB/s", "Sets model load time"),
            ("Disk write", "\(TestFormat.gbPerSecond(run.diskWrite)) GB/s", "Sets download saving"),
        ]
        return TestPanel(title: "All measurements", symbol: "square.grid.3x2.fill", note: "\(rows.count) tests") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 18) {
                ForEach(rows, id: \.0) { row in
                    GridRow {
                        Text(row.0).frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.1).monospacedDigit().fontWeight(.medium).gridColumnAlignment(.trailing)
                        Text(row.2).foregroundStyle(.secondary).font(.uiCaption).gridColumnAlignment(.trailing)
                    }
                    .font(.uiCallout)
                }
            }
        }
    }

    // MARK: Thermals

    private static let shortPhaseNames = [
        "CPU · one core": "1 core", "CPU · all cores": "All cores", "Memory bandwidth": "Memory",
        "GPU compute": "GPU", "GPU memory": "GPU mem", "Disk": "Disk", "Sustained GPU load": "Sustained GPU load",
    ]

    private func thermals(_ run: HardwareTestResult) -> some View {
        TestPanel(title: "Thermals during the test", symbol: "thermometer.medium",
                  note: "peak CPU \(Format.temp(run.peakCPUTemp)) · GPU \(Format.temp(run.peakGPUTemp))") {
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
                            .foregroundStyle(Palette.warning)
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
            .padding(.top, 14)
            .frame(maxHeight: .infinity)
            HStack(spacing: 14) {
                legend("CPU temperature °C", Palette.warning)
                legend("GPU temperature °C", Palette.accent)
                legend("GPU load %", Palette.glow.opacity(0.5))
                Spacer()
            }
        }
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.uiCaption2).foregroundStyle(.secondary)
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
        return VStack(alignment: .leading, spacing: 10) {
            Text("Generation speed each model can reach on this Mac.").font(.uiCaption).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        HStack(spacing: 5) {
                            Text(row.name).lineLimit(1)
                            Text(row.quant).foregroundStyle(.tertiary)
                        }
                        .font(.uiCaption)
                        .frame(width: 210, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule(style: .circular).fill(Color.primary.opacity(0.05))
                                Capsule(style: .circular).fill(row.fit.level.color.opacity(0.8).gradient)
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
                        .font(.uiCaption.monospacedDigit())
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
                .font(.uiCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Test steps

    private func phases(_ run: HardwareTestResult) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
            GridRow {
                Text("Step")
                Text("Started").gridColumnAlignment(.trailing)
                Text("Took").gridColumnAlignment(.trailing)
            }
            .font(.uiCaption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(run.phases) { phase in
                GridRow {
                    Text(phase.name).frame(maxWidth: .infinity, alignment: .leading)
                    Text(Format.seconds(phase.start)).monospacedDigit().foregroundStyle(.secondary)
                    Text(Format.seconds(phase.end - phase.start)).monospacedDigit().fontWeight(.medium)
                }
                .font(.uiCallout)
            }
        }
    }

    // MARK: History

    private func history(selected: HardwareTestResult) -> some View {
        TestRunList(runs: lab.hardwareResults) { run in
            TestRunRow(level: TestScoring.sustained.level(run.sustainedPercent), date: run.date, title: run.chip,
                       result: "\(TestFormat.number(run.gpuTFLOPS, decimals: 2)) TFLOPS · \(TestFormat.gbPerSecond(run.gpuBandwidth)) GB/s",
                       selected: run.id == selected.id, onSelect: { lab.selectedHardwareRunID = run.id },
                       onDelete: { lab.delete(hardwareRun: run.id) })
        }
    }
}
