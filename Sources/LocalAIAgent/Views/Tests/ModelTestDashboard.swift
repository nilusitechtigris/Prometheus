import Charts
import SwiftUI

/// Full results of the model test: the selected run in detail, then every model compared.
struct ModelTestDashboard: View {
    @Environment(TestLab.self) private var lab
    @Environment(BackendController.self) private var backends
    @Environment(ChatController.self) private var chat
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
                if let progress = lab.modelProgress {
                    PanelWidget(title: "Running", symbol: "hourglass") { EmptyView() } content: {
                        TestProgressView(progress: progress) { lab.cancelModelTest() }
                    }
                }
                if let error = lab.lastError { ErrorBanner(text: error) { lab.dismissError() } }

                if let run = lab.selectedModelRun {
                    if let model = testModel, lab.modelProgress == nil, lab.latestModelResult(for: model.id) == nil {
                        Text("\(model.displayName) \(model.quantLabel) hasn't been tested yet. Below is the latest run of \(run.displayName) \(run.quant).")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    summary(run)
                    AdaptiveStack {
                        categories(run)
                        qualityVsSpeed(selected: run)
                    }
                    questions(run)
                    leaderboard(selected: run)
                    history(selected: run)
                } else if lab.modelProgress == nil {
                    emptyState
                }
            }
            .padding(24)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
    }

    private var testModel: LocalModel? { lab.testModel(in: backends) }

    private var canRun: Bool { !lab.isRunning && !chat.isGenerating && backends.status.isOnline && testModel != nil }

    private var setupCaption: String? {
        guard let model = testModel else { return nil }
        var parts = [backends.kind.displayName, "\(Format.tokens(backends.estimatedContext(for: model))) context"]
        if model.catalog?.thinking == true, settings.thinkingEnabled, backends.kind == .ollama {
            parts.append("Thinking on, so this takes longer")
        }
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Palette.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Model Test").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("How well and how fast local models answer: 20 auto-graded questions on math, reasoning, knowledge, instructions, code and long context.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    TestModelPicker()
                    RunTestButton(title: "Run test", disabled: !canRun) {
                        lab.runModelTest(backends: backends, settings: settings)
                    }
                }
                if let setupCaption {
                    Text(setupCaption).font(.caption).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var emptyState: some View {
        PanelWidget(title: "No results yet", symbol: "sparkles") { EmptyView() } content: {
            Text("Run the test to score the chosen model. Every question has one checkable answer, so grading is automatic and the same for every model. Run it on several models or quants to compare them here.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Summary

    private func summary(_ run: ModelTestResult) -> some View {
        AdaptiveStack(minWidth: 940) {
            PanelWidget(title: run.displayName, symbol: "cube.fill") {
                Text(TestFormat.relative(run.date)).font(.caption).foregroundStyle(.secondary)
            } content: {
                HStack(spacing: 16) {
                    ScoreRing(score: run.score, size: 92)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(run.passed) of \(run.items.count) correct").font(.title3.weight(.semibold))
                        Text("\(run.quant) by \(run.quantProvider) · \(run.backend)").font(.callout).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Chip(text: run.thinking ? "Thinking on" : "Thinking off", symbol: "brain", tint: run.thinking ? Palette.accent : .secondary)
                            Chip(text: "\(Format.tokens(run.contextLength)) context", symbol: "text.word.spacing", tint: .secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity)

            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    MetricTile(title: "Speed", value: Format.rate(run.tokensPerSecond), unit: "tok/s",
                               caption: "Generation, all questions", symbol: "speedometer",
                               level: Thresholds.tokensPerSecond.level(run.tokensPerSecond))
                    MetricTile(title: "First token", value: Format.seconds(run.timeToFirstToken),
                               caption: "Median, model already loaded", symbol: "timer",
                               level: Thresholds.timeToFirstToken.level(run.timeToFirstToken))
                }
                GridRow {
                    MetricTile(title: "Prompt reading", value: Format.rate(run.promptTokensPerSecond), unit: "tok/s",
                               caption: "On the long-context question", symbol: "text.magnifyingglass")
                    MetricTile(title: "Test time", value: Format.seconds(run.duration),
                               caption: run.loadSeconds.map { $0 > 0.5 ? "Incl. \(Format.seconds($0)) model load" : "Model was already loaded" },
                               symbol: "clock")
                }
            }
        }
    }

    // MARK: Categories

    private func categories(_ run: ModelTestResult) -> some View {
        PanelWidget(title: "By category", symbol: "square.grid.3x2.fill") { EmptyView() } content: {
            Chart(ModelTestCategory.allCases) { category in
                let score = run.score(for: category) ?? 0
                BarMark(x: .value("Score", score), y: .value("Category", category.name))
                    .foregroundStyle(TestScoring.modelScore.level(score).color.gradient)
                    .cornerRadius(5)
                    .annotation(position: .trailing) {
                        Text(Format.percent(score)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
            }
            .chartXScale(domain: 0...112)
            .chartXAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                }
            }
            .frame(height: 220)
        }
        .frame(maxWidth: .infinity)
    }

    private func qualityVsSpeed(selected: ModelTestResult) -> some View {
        let runs = lab.leaderboard.filter { $0.tokensPerSecond != nil }
        return PanelWidget(title: "Quality vs speed", symbol: "chart.dots.scatter") {
            Text("newest run per model").font(.caption).foregroundStyle(.secondary)
        } content: {
            Chart(Array(runs.enumerated()), id: \.element.id) { index, run in
                PointMark(x: .value("Speed", run.tokensPerSecond ?? 0), y: .value("Score", run.score))
                    .symbolSize(run.configurationKey == selected.configurationKey ? 220 : 110)
                    .foregroundStyle(run.configurationKey == selected.configurationKey ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Color.secondary.opacity(0.6)))
                    // Alternate above / below so neighbouring labels don't collide.
                    .annotation(position: index.isMultiple(of: 2) ? .top : .bottom, spacing: 4) {
                        Text("\(run.displayName) \(run.quant)\(run.thinking ? " · thinking" : "")").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartYScale(domain: 0...110)
            .chartXAxisLabel("tok/s")
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                }
            }
            .frame(height: 220)
            Text(runs.count < 2 ? "Test more models or quants to compare them here. Up and to the right is better." : "Up and to the right is better: higher score, faster replies.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Questions

    private func questions(_ run: ModelTestResult) -> some View {
        PanelWidget(title: "Questions", symbol: "list.bullet.rectangle.portrait.fill") {
            Text("\(run.passed) passed · \(run.items.count - run.passed) failed").font(.caption).foregroundStyle(.secondary)
        } content: {
            Card(padding: 0) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
                    GridRow {
                        Text("")
                        Text("Question")
                        Text("Expected")
                        Text("Model's answer")
                        Text("Time").gridColumnAlignment(.trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    ForEach(run.items) { item in
                        Divider().gridCellUnsizedAxes(.horizontal)
                        GridRow(alignment: .top) {
                            Image(systemName: item.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(item.passed ? Palette.good : Palette.critical)
                            HStack(spacing: 6) {
                                Image(systemName: item.category.symbol).font(.caption).foregroundStyle(.secondary).frame(width: 16)
                                Text(item.title).fontWeight(.medium)
                            }
                            Text(item.expected).foregroundStyle(.secondary).lineLimit(1)
                            Text(item.error ?? (item.answer.isEmpty ? "(no answer)" : item.answer))
                                .foregroundStyle(item.error != nil ? Palette.critical : .primary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .help(item.answer)
                            Text(Format.seconds(item.seconds)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .padding(.vertical, 7)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    // MARK: Leaderboard and history

    private func leaderboard(selected: ModelTestResult) -> some View {
        PanelWidget(title: "Leaderboard on this Mac", symbol: "trophy.fill") {
            Text("newest run per model + quant").font(.caption).foregroundStyle(.secondary)
        } content: {
            Card(padding: 0) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
                    GridRow {
                        Text("#")
                        Text("Model")
                        Text("Score")
                        Text("Speed").gridColumnAlignment(.trailing)
                        Text("First token").gridColumnAlignment(.trailing)
                        Text("Prompt").gridColumnAlignment(.trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    ForEach(Array(lab.leaderboard.enumerated()), id: \.element.id) { index, run in
                        Divider().gridCellUnsizedAxes(.horizontal)
                        GridRow {
                            Text("\(index + 1)")
                                .fontWeight(run.id == selected.id ? .bold : .regular)
                                .foregroundStyle(run.id == selected.id ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.secondary))
                                .monospacedDigit()
                            VStack(alignment: .leading, spacing: 1) {
                                Text(run.displayName).fontWeight(.medium)
                                Text("\(run.quant) · \(run.backend)\(run.thinking ? " · thinking" : "")").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 8) {
                                RangeBar(value: run.score, threshold: TestScoring.modelScore, height: 5).frame(width: 70)
                                Text(Format.percent(run.score)).monospacedDigit().fixedSize()
                            }
                            Text("\(Format.rate(run.tokensPerSecond)) tok/s").monospacedDigit()
                            Text(Format.seconds(run.timeToFirstToken)).monospacedDigit()
                            Text("\(Format.rate(run.promptTokensPerSecond)) tok/s").monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .onTapGesture { lab.show(run) }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private func history(selected: ModelTestResult) -> some View {
        PanelWidget(title: "All runs", symbol: "clock.arrow.circlepath") {
            Text("\(lab.modelResults.count)").font(.caption).foregroundStyle(.secondary)
        } content: {
            VStack(spacing: 6) {
                ForEach(lab.modelResults) { run in
                    HStack(spacing: 10) {
                        StatusDot(level: TestScoring.modelScore.level(run.score), size: 8)
                        Text(run.date.formatted(date: .abbreviated, time: .shortened)).font(.callout.monospacedDigit()).frame(width: 170, alignment: .leading)
                        Text("\(run.displayName) · \(run.quant)").font(.callout).lineLimit(1)
                        Spacer()
                        Text("\(Format.percent(run.score)) · \(Format.rate(run.tokensPerSecond)) tok/s").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        Button { lab.delete(modelRun: run.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help("Delete this run")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(run.id == selected.id ? Palette.accent.opacity(0.10) : Color.primary.opacity(0.03),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { lab.show(run) }
                }
            }
        }
    }
}

/// Chooses which installed model the test runs on. It leaves the chat's model alone.
private struct TestModelPicker: View {
    @Environment(TestLab.self) private var lab
    @Environment(BackendController.self) private var backends
    @Environment(UIState.self) private var ui

    var body: some View {
        @Bindable var ui = ui
        Button {
            ui.showTestModelPicker.toggle()
        } label: {
            PickerPill {
                if let model = lab.testModel(in: backends) {
                    Text(model.displayName).fontWeight(.medium).lineLimit(1)
                    QuantBadge(text: model.quantLabel)
                } else {
                    Text("Choose a model")
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(Color.primary.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .opacity(lab.isRunning ? 0.5 : 1)
        .disabled(lab.isRunning)
        .help("Choose the model to test")
        .popover(isPresented: $ui.showTestModelPicker, arrowEdge: .bottom) {
            TestModelList { ui.showTestModelPicker = false }
        }
    }
}

private struct TestModelList: View {
    let onDone: () -> Void
    @Environment(TestLab.self) private var lab
    @Environment(BackendController.self) private var backends
    @Environment(SystemMonitor.self) private var monitor
    @Environment(UIState.self) private var ui

    var body: some View {
        let models = backends.models.filter(backends.isSelectable)
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Model to test").font(.headline)
                Text("Installed in \(backends.kind.displayName). This doesn't change the model you chat with.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if models.isEmpty {
                Text("No models installed yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(models) { row($0) }
                    }
                }
                .frame(height: min(CGFloat(models.count) * 56, 360))
            }
            if backends.kind.supportsModelDownloads {
                Divider()
                Button {
                    onDone()
                    ui.showLibrary = true
                } label: {
                    Label("Get more models…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .frame(width: 390)
    }

    private func row(_ model: LocalModel) -> some View {
        let fit = backends.memoryEstimate(for: model, context: backends.estimatedContext(for: model))
            .map { MemoryFit.verdict(requiredBytes: $0, budget: monitor.gpuBudgetBytes) }
        let last = lab.latestModelResult(for: model.id)
        return PopoverRow(selected: lab.testModel(in: backends)?.id == model.id, action: {
            lab.chooseTestModel(model)
            onDone()
        }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.displayName).font(.callout.weight(.medium)).lineLimit(1)
                    if model.id == backends.selectedModel?.id {
                        Text("In chat").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    QuantBadge(text: model.quantLabel)
                    Text(Format.bytes(model.sizeBytes)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    if let fit, fit != .great {
                        Text(fit.label).font(.caption).foregroundStyle(fit.level.color)
                    }
                }
            }
            Spacer(minLength: 8)
            if let last {
                HStack(spacing: 5) {
                    StatusDot(level: TestScoring.modelScore.level(last.score), size: 7)
                    Text(Format.percent(last.score)).font(.callout.monospacedDigit())
                }
            } else {
                Text("Not tested").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}

struct ErrorBanner: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
            Text(text).font(.callout).lineLimit(3)
            Spacer()
            Button("Dismiss", action: onDismiss).controlSize(.small)
        }
        .padding(12)
        .background(Palette.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
