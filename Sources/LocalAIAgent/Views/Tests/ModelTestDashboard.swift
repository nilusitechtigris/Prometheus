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
                        Text("\(model.displayName) \(model.quantLabel) hasn't taken this test yet. Below is the latest run of \(run.displayName) \(run.quant).")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    summary(run)
                    AdaptiveStack {
                        if run.isCurrentSuite {
                            skillMap(run)
                        } else {
                            categories(run)
                        }
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
        let thinking = model.catalog?.thinking == true && settings.thinkingEnabled && backends.kind == .ollama
        parts.append(thinking ? "Thinking on, can take over an hour" : "Takes about 30 minutes")
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
                Text("Model Test").font(Brand.display(28))
                Text("How capable and how fast local models are: \(ModelTestSuite.questionCount) auto-graded questions, four difficulty levels in each of six topics. Harder questions are worth more, and 100 is the level of \(ModelTestSuite.referenceModel).")
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
            Text("Run the test to score the chosen model. Every question has one checkable answer, so grading is automatic and the same for every model. Each topic runs from basic to expert, and each level is worth twice the one below it. Run it on several models or quants to compare them here.")
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
                    ScoreRing(score: run.score, size: 92, unit: run.isCurrentSuite ? "/100" : "% old test")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            if run.isCurrentSuite {
                                Text(TestScoring.tier(run.score)).font(.title3.weight(.semibold))
                                Text("\(run.points) of \(run.maxPoints) points").font(.callout).foregroundStyle(.secondary)
                            } else {
                                Text("\(run.passed) of \(run.items.count) correct").font(.title3.weight(.semibold))
                            }
                        }
                        Text("\(run.quant) by \(run.quantProvider) · \(run.backend)").font(.callout).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Chip(text: run.thinking ? "Thinking on" : "Thinking off", symbol: "brain", tint: run.thinking ? Palette.accent : .secondary)
                            Chip(text: "\(Format.tokens(run.contextLength)) context", symbol: "text.word.spacing", tint: .secondary)
                            if run.usesHarness { Chip(text: "Harness", symbol: "shield.lefthalf.filled", tint: Palette.accent) }
                        }
                    }
                    Spacer(minLength: 0)
                }
                if run.isCurrentSuite {
                    TierScale(score: run.score)
                } else {
                    Text("From the older, easier test, so this score can't be compared with the current scale.")
                        .font(.caption).foregroundStyle(.secondary)
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

    // MARK: Skill map

    private func skillMap(_ run: ModelTestResult) -> some View {
        PanelWidget(title: "Skill map", symbol: "square.grid.3x2.fill") {
            Text("each level is worth double").font(.caption).foregroundStyle(.secondary)
        } content: {
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(ModelTestLevel.allCases) { level in
                        VStack(spacing: 0) {
                            Text(level.name).lineLimit(1).minimumScaleFactor(0.8)
                            Text("×\(level.weight)").foregroundStyle(.tertiary)
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    }
                    Text("Score").font(.caption2.weight(.medium)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                }
                ForEach(ModelTestCategory.allCases) { category in
                    GridRow(alignment: .center) {
                        HStack(spacing: 6) {
                            Image(systemName: category.symbol).font(.caption).foregroundStyle(.secondary).frame(width: 16)
                            Text(category.name).font(.callout).lineLimit(1).fixedSize()
                        }
                        ForEach(ModelTestLevel.allCases) { level in
                            skillCell(run.items.first { $0.category == category && $0.level == level })
                        }
                        Text(Format.percent(run.score(for: category)))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(TestScoring.modelScore.level(run.score(for: category)).color)
                    }
                }
            }
            Text("Green is correct, red is wrong. Click a square to open that question below.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func skillCell(_ item: ModelTestItemResult?) -> some View {
        Button {
            if let item { lab.expandedQuestions.insert(item.id) }
        } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill((item?.passed == true ? Palette.good : Palette.critical).opacity(item == nil ? 0.1 : 0.75))
                .frame(height: 26)
                .frame(maxWidth: .infinity)
                .overlay {
                    if let item {
                        Image(systemName: item.passed ? "checkmark" : "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(item?.title ?? "")
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
                        Text("\(run.displayName) \(run.quant)\(run.setupLabel)").font(.caption2).foregroundStyle(.secondary)
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
        let ids = Set(run.items.map(\.id))
        let allOpen = ids.isSubset(of: lab.expandedQuestions)
        return PanelWidget(title: "Questions", symbol: "list.bullet.rectangle.portrait.fill") {
            HStack(spacing: 10) {
                Text("\(run.passed) passed · \(run.items.count - run.passed) failed").font(.caption).foregroundStyle(.secondary)
                Button(allOpen ? "Collapse all" : "Expand all") {
                    withAnimation(.snappy(duration: 0.2)) {
                        if allOpen { lab.expandedQuestions.subtract(ids) } else { lab.expandedQuestions.formUnion(ids) }
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ModelTestCategory.allCases) { category in
                    let items = run.items.filter { $0.category == category }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Image(systemName: category.symbol).font(.caption).foregroundStyle(.secondary)
                                Text(category.name).font(.callout.weight(.semibold))
                                Text(Format.percent(run.score(for: category))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Card(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                        if index > 0 { Divider() }
                                        QuestionRow(item: item, expanded: Binding(
                                            get: { lab.expandedQuestions.contains(item.id) },
                                            set: { open in
                                                if open { lab.expandedQuestions.insert(item.id) } else { lab.expandedQuestions.remove(item.id) }
                                            }))
                                    }
                                }
                            }
                        }
                    }
                }
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
                                Text("\(run.quant) · \(run.backend)\(run.setupLabel)").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 8) {
                                RangeBar(value: run.score, threshold: TestScoring.modelScore, height: 5).frame(width: 70)
                                Text(TestFormat.score(run.score)).monospacedDigit().fixedSize()
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
                        Text("\(run.displayName) · \(run.quant)\(run.setupLabel)").font(.callout).lineLimit(1)
                        if !run.isCurrentSuite {
                            Text("Old test").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text("\(run.isCurrentSuite ? TestFormat.score(run.score) : Format.percent(run.score)) · \(Format.rate(run.tokensPerSecond)) tok/s").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
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

/// The score scale, marked with this run's score.
private struct TierScale: View {
    let score: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RangeBar(value: score, threshold: TestScoring.modelScore, height: 5)
            HStack {
                ForEach(["Basic", "Capable", "Advanced", "Expert", "Frontier"], id: \.self) { tier in
                    if tier != "Basic" { Spacer(minLength: 0) }
                    Text(tier).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(ModelTestSuite.scaleNote).font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One question: a summary row that expands to show what was asked and what the model replied.
struct QuestionRow: View {
    let item: ModelTestItemResult
    @Binding var expanded: Bool

    private var finalAnswer: String { ModelTestSuite.finalAnswer(item.answer) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            } label: {
                header.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? "Hide the details" : "Show what was asked and what the model replied")
            if expanded {
                details.transition(.opacity)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(width: 10)
            Image(systemName: item.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(item.passed ? Palette.good : Palette.critical)
            Text(item.title).fontWeight(.medium).lineLimit(1)
            if let level = item.level {
                Text(level.name)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
            Spacer(minLength: 12)
            if !expanded {
                Text(item.error != nil ? "Error" : (finalAnswer.isEmpty ? "No answer" : finalAnswer))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 200, alignment: .trailing)
            }
            if item.level != nil {
                Text("\(item.passed ? item.weight : 0)/\(item.weight)")
                    .monospacedDigit()
                    .foregroundStyle(item.passed ? .primary : .secondary)
                    .frame(width: 34, alignment: .trailing)
                    .help("Points earned, out of the points this question is worth")
            }
            Text(Format.seconds(item.seconds))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let summary = item.summary {
                Text(summary).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            if let prompt = item.prompt {
                field("Asked", prompt, monospaced: true, lines: 22)
            }
            HStack(alignment: .top, spacing: 16) {
                field("Expected", item.expected)
                    .frame(maxWidth: .infinity, alignment: .leading)
                field("Model's answer", item.error ?? (finalAnswer.isEmpty ? "No answer" : finalAnswer))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if item.answer != finalAnswer, !item.answer.isEmpty {
                field("Full reply", item.answer, monospaced: true, lines: 10)
            }
            if let tools = item.toolLog, !tools.isEmpty {
                field("Tools used", tools.joined(separator: "\n"), lines: 12)
            }
            HStack(spacing: 12) {
                if item.ranOutOfTokens {
                    Label("Ran out of tokens before finishing", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.warning)
                }
                if let first = item.timeToFirstToken { Text("First token \(Format.seconds(first))") }
                if let output = item.outputTokens { Text("\(output) output tokens") }
                if let thinking = item.thinkingTokens { Text("\(thinking) thinking tokens") }
                if let removed = item.guardRemoved, removed > 0 { Text("Guard removed \(removed) from tool results") }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 40)
        .padding(.trailing, 12)
        .padding(.bottom, 11)
        .padding(.top, 2)
    }

    private func field(_ title: String, _ text: String, monospaced: Bool = false, lines: Int = 4) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(text)
                .font(monospaced ? .system(size: 11.5, design: .monospaced) : .callout)
                .lineLimit(lines)
                .truncationMode(.head)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Chooses which installed model the test runs on. It leaves the chat's model alone.
struct TestModelPicker: View {
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
                    Text(TestFormat.score(last.score)).font(.callout.monospacedDigit())
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
