import SwiftUI

/// The same model, with and without the harness: tools from trusted sites plus prompt injection protection.
struct HarnessTestDashboard: View {
    enum Detail: Hashable { case howItWorks, changes, tools, sites }

    @Environment(TestLab.self) private var lab
    @Environment(BackendController.self) private var backends
    @Environment(ChatController.self) private var chat
    @Environment(AppSettings.self) private var settings

    /// Off only for debug renders of the whole page.
    var scrollable = true
    @State var detail = Detail.howItWorks

    var body: some View {
        let run = lab.harnessRun(for: testModel?.id)
        let pair = run.flatMap { run in lab.baseline(of: run).map { (run: run, baseline: $0) } }
        TestPage(title: "Harness Test", symbol: "shield.lefthalf.filled",
                 subtitle: "What tools and protection add: the same \(ModelTestSuite.questionCount) questions with the harness off and on, then \(InjectionSuite.cases.count) poisoned pages both ways.",
                 caption: backends.kind.supportsTools ? setupCaption : "Harness tools need Ollama for now",
                 notice: notice(showing: run),
                 progress: lab.harnessProgress, onStop: { lab.cancelHarnessTest() }, scrollable: scrollable) {
            TestModelPicker()
            RunTestButton(title: "Run test", disabled: !canRun || !backends.kind.supportsTools) {
                lab.runHarnessTest(backends: backends, settings: settings)
            }
        } content: {
            if let (run, baseline) = pair {
                TestBlocks(title: run.displayName, symbol: "cube.fill", date: run.date, tiles: tiles(run, baseline)) {
                    hero(run, baseline)
                } left: {
                    topics(run, baseline)
                } right: {
                    injection(run)
                } runs: {
                    history(selected: run)
                }
            } else if lab.harnessProgress == nil {
                TestEmptyState(text: "Run the test to compare the chosen model with and without the harness: the same questions, then poisoned web pages that try to take it over.")
            }
            details(pair)
        }
    }

    private var testModel: LocalModel? { lab.testModel(in: backends) }
    private var canRun: Bool { !lab.isRunning && !chat.isGenerating && backends.status.isOnline && testModel != nil }

    /// The chosen model has no run of its own, so the page is showing another model's.
    private func notice(showing run: ModelTestResult?) -> String? {
        guard let model = testModel, let run, model.id != run.model, lab.harnessProgress == nil else { return nil }
        return "Not tested yet. Showing \(run.displayName) \(run.quant)."
    }

    private var setupCaption: String {
        let context = testModel.map { Format.tokens(backends.estimatedContext(for: $0)) } ?? "—"
        let thinking = testModel?.catalog?.thinking == true && settings.thinkingEnabled && backends.kind == .ollama
        return "\(backends.kind.displayName) · \(context) context · " + (thinking ? "Thinking on, can take 2+ hours" : "Takes up to an hour")
    }

    // MARK: Overview

    private func tiles(_ run: ModelTestResult, _ baseline: ModelTestResult) -> (MetricTile, MetricTile, MetricTile, MetricTile) {
        let without = run.injectionWithout ?? [], with = run.injectionWith ?? []
        let toolLog = run.items.flatMap { $0.toolLog ?? [] }.filter(HarnessTools.isToolCall)
        let failedCalls = toolLog.filter { $0.hasSuffix(HarnessTools.failedMark) }.count
        let questionsWithTools = run.items.filter(usedTools).count
        return (MetricTile(title: "Injections stopped", value: "\(with.filter(\.passed).count)/\(with.count)",
                           caption: "Was \(without.filter(\.passed).count)/\(without.count) without the harness", symbol: "shield.lefthalf.filled",
                           level: with.allSatisfy(\.passed) ? .good : .warning),
                MetricTile(title: "Tool calls", value: "\(toolLog.count)",
                           caption: failedCalls > 0 ? "\(failedCalls) failed, across \(questionsWithTools) questions" : "Across \(questionsWithTools) of \(run.items.count) questions",
                           symbol: "wrench.and.screwdriver", level: failedCalls > 0 ? .warning : nil),
                MetricTile(title: "Points", value: "\(run.points)", unit: "of \(run.maxPoints)",
                           caption: "Was \(baseline.points) without the harness", symbol: "star"),
                MetricTile(title: "Test time", value: Format.seconds(run.duration),
                           caption: "Was \(Format.seconds(baseline.duration)) without the harness", symbol: "clock"))
    }

    private func hero(_ run: ModelTestResult, _ baseline: ModelTestResult) -> some View {
        let off = TestFormat.score(baseline.score), on = TestFormat.score(run.score)
        let delta = Int(run.score) - Int(baseline.score)
        return TestHero(score: run.score,
                        headline: delta == 0 ? "No change" : "\(delta > 0 ? "+" : "")\(delta) with the harness",
                        aside: "\(off) → \(on)",
                        detail: "\(run.quant) by \(run.quantProvider) · \(run.backend)",
                        note: run.toolsAvailable == false
                            ? "\(off) off, \(on) on. This model can't call tools itself, so only the harness used them."
                            : "\(off) with the harness off, \(on) with it on, on the same questions.") {
            ModelRunChips(run: run)
        }
    }

    private func usedTools(_ item: ModelTestItemResult) -> Bool {
        (item.toolLog ?? []).contains(where: HarnessTools.isToolCall)
    }

    // MARK: Details

    @ViewBuilder
    private func details(_ pair: (run: ModelTestResult, baseline: ModelTestResult)?) -> some View {
        let tabs: [(id: Detail, title: String)] = pair == nil
            ? [(.howItWorks, "How it works"), (.sites, "Trusted sites")]
            : [(.howItWorks, "How it works"), (.changes, "What changed"), (.tools, "Tool use"), (.sites, "Trusted sites")]
        TestDetails(tabs: tabs, selection: $detail) {
            switch (detail, pair) {
            case (.changes, let pair?): changes(pair.run, pair.baseline)
            case (.tools, let pair?): toolActivity(pair.run)
            case (.sites, _): TrustedSiteList()
            default: HarnessFlowDiagram()
            }
        }
    }

    // MARK: Topics

    private func topics(_ run: ModelTestResult, _ baseline: ModelTestResult) -> some View {
        TestPanel(title: "By topic", symbol: "square.grid.3x2.fill", note: "score within each topic") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 18) {
                GridRow {
                    Text("")
                    Text("Off").gridColumnAlignment(.trailing)
                    Text("On").gridColumnAlignment(.trailing)
                    Text("Change").gridColumnAlignment(.trailing)
                }
                .font(.uiCaption.weight(.semibold))
                .foregroundStyle(.secondary)
                ForEach(ModelTestCategory.allCases) { category in
                    let off = baseline.score(for: category) ?? 0, on = run.score(for: category) ?? 0
                    GridRow {
                        HStack(spacing: 6) {
                            Image(systemName: category.symbol).font(.uiCaption).foregroundStyle(.secondary).frame(width: 16)
                            Text(category.name).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text(Format.percent(off)).monospacedDigit().foregroundStyle(.secondary)
                        Text(Format.percent(on)).monospacedDigit().fontWeight(.medium)
                        Text(on == off ? "—" : String(format: "%+.0f", on - off))
                            .monospacedDigit()
                            .foregroundStyle(on > off ? Palette.good : (on < off ? Palette.critical : .secondary))
                    }
                    .font(.uiCallout)
                }
            }
        }
    }

    // MARK: Injection

    private func injection(_ run: ModelTestResult) -> some View {
        let without = run.injectionWithout ?? [], with = run.injectionWith ?? []
        return TestPanel(title: "Prompt injection test", symbol: "exclamationmark.shield.fill", note: "not part of the score") {
            HStack {
                Text("Poisoned page")
                Spacer()
                Text("Off").frame(width: 34)
                Text("On").frame(width: 34)
            }
            .font(.uiCaption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            // A row can open to show both replies, so the panel scrolls rather than grows.
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(with) { result in
                        Divider()
                        InjectionRow(with: result, without: without.first { $0.id == result.id })
                    }
                }
            }
            .frame(maxHeight: .infinity)
            Text("A page counts as stopped when the reply shows no sign of the attack and still summarizes the page.")
                .font(.uiCaption).foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    // MARK: What changed

    @ViewBuilder
    private func changes(_ run: ModelTestResult, _ baseline: ModelTestResult) -> some View {
        let pairs = run.items.compactMap { item in baseline.items.first { $0.id == item.id }.map { (with: item, without: $0) } }
        let gained = pairs.filter { $0.with.passed && !$0.without.passed }.map(\.with)
        let lost = pairs.filter { !$0.with.passed && $0.without.passed }.map(\.with)
        VStack(alignment: .leading, spacing: 10) {
            Text("\(gained.count) gained · \(lost.count) lost").font(.uiCaption).foregroundStyle(.secondary)
            if gained.isEmpty && lost.isEmpty {
                Text("The same questions passed with and without the harness.").font(.uiCallout).foregroundStyle(.secondary)
            }
            changeList("Solved only with the harness", gained)
            changeList("Solved only without the harness", lost)
        }
    }

    @ViewBuilder
    private func changeList(_ title: String, _ items: [ModelTestItemResult]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.uiCallout.weight(.semibold))
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider() }
                            QuestionRow(item: item, expanded: expansion(item.id))
                        }
                    }
                }
            }
        }
    }

    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(get: { lab.expandedQuestions.contains(id) },
                set: { open in
                    if open { lab.expandedQuestions.insert(id) } else { lab.expandedQuestions.remove(id) }
                })
    }

    @ViewBuilder
    private func toolActivity(_ run: ModelTestResult) -> some View {
        let used = run.items.filter(usedTools)
        VStack(alignment: .leading, spacing: 10) {
            Text("\(used.count) question\(used.count == 1 ? "" : "s") used tools.").font(.uiCaption).foregroundStyle(.secondary)
            if !used.isEmpty {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(used.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider() }
                            QuestionRow(item: item, expanded: expansion(item.id))
                        }
                    }
                }
            }
        }
    }

    // MARK: History

    private func history(selected: ModelTestResult) -> some View {
        TestRunList(runs: lab.harnessRuns) { run in
            TestRunRow(level: TestScoring.modelScore.level(run.score), date: run.date,
                       title: "\(run.displayName) · \(run.quant)\(run.thinking ? " · thinking" : "")",
                       result: "\(lab.baseline(of: run).map { TestFormat.score($0.score) } ?? "—") → \(TestFormat.score(run.score))",
                       selected: run.id == selected.id,
                       onSelect: {
                           lab.selectedHarnessRunID = run.id
                           lab.testModelID = run.model
                       },
                       onDelete: { lab.delete(modelRun: run.id) })
        }
    }
}

/// One poisoned page: how it went without and with the harness, expanding to show both replies.
private struct InjectionRow: View {
    let with: InjectionResult
    let without: InjectionResult?
    @State private var expanded = false

    private func mark(_ result: InjectionResult?) -> some View {
        Image(systemName: result?.passed == true ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(result?.passed == true ? Palette.good : Palette.critical)
            .frame(width: 34)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 10)
                    Text(with.title).font(.uiCallout)
                    Spacer()
                    mark(without)
                    mark(with)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(with.summary).font(.uiCallout).fixedSize(horizontal: false, vertical: true)
                    if let without { reply("Reply with the harness off", without.reply) }
                    reply("Reply with the harness on", with.reply)
                    if with.guardRemoved > 0 || with.replyBlocked > 0 {
                        Text("The guard removed \(with.guardRemoved) from the page and \(with.replyBlocked) from the reply.")
                            .font(.uiCaption).foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 28)
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
            }
        }
    }

    private func reply(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.uiCaption.weight(.semibold)).foregroundStyle(.secondary)
            Text(text.isEmpty ? "(empty)" : text)
                .font(.system(size: 11.5, design: .monospaced))
                .lineLimit(6)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
