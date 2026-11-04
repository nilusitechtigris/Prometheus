import SwiftUI

/// The same model, with and without the harness: tools from trusted sites plus prompt injection protection.
struct HarnessTestDashboard: View {
    @Environment(TestLab.self) private var lab
    @Environment(BackendController.self) private var backends
    @Environment(ChatController.self) private var chat
    @Environment(AppSettings.self) private var settings

    /// Off only for debug renders of the whole page.
    var scrollable = true

    var body: some View {
        TestPage(title: "Harness Test", symbol: "shield.lefthalf.filled",
                 subtitle: "What tools and protection add: the same \(ModelTestSuite.questionCount) questions with the harness off and on, then \(InjectionSuite.cases.count) poisoned pages both ways.",
                 caption: backends.kind.supportsTools ? setupCaption : "Harness tools need Ollama for now",
                 progress: lab.harnessProgress, onStop: { lab.cancelHarnessTest() }, scrollable: scrollable) {
            TestModelPicker()
            RunTestButton(title: "Run test", disabled: !canRun || !backends.kind.supportsTools) {
                lab.runHarnessTest(backends: backends, settings: settings)
            }
        } content: {
            if let run = lab.harnessRun(for: testModel?.id), let baseline = lab.baseline(of: run) {
                if let model = testModel, model.id != run.model, lab.harnessProgress == nil {
                    Text("\(model.displayName) \(model.quantLabel) hasn't taken this test yet. Below is the latest run of \(run.displayName) \(run.quant).")
                        .font(.uiCallout).foregroundStyle(.secondary)
                }
                comparison(run, baseline)
                if run.toolsAvailable == false {
                    Text("This model can't call tools, so only the injection protection was on.")
                        .font(.uiCallout).foregroundStyle(.secondary)
                }
                AdaptiveStack {
                    topics(run, baseline)
                    injection(run)
                }
                changes(run, baseline)
                toolActivity(run)
                history(selected: run)
            } else if lab.harnessProgress == nil {
                TestEmptyState(text: "Run the test to compare the chosen model with and without the harness: the same questions, then poisoned web pages that try to take it over.")
            }
            HarnessFeatures()
        }
    }

    private var testModel: LocalModel? { lab.testModel(in: backends) }
    private var canRun: Bool { !lab.isRunning && !chat.isGenerating && backends.status.isOnline && testModel != nil }

    private var setupCaption: String {
        let context = testModel.map { Format.tokens(backends.estimatedContext(for: $0)) } ?? "—"
        let thinking = testModel?.catalog?.thinking == true && settings.thinkingEnabled && backends.kind == .ollama
        return "\(backends.kind.displayName) · \(context) context · " + (thinking ? "Thinking on, can take 2+ hours" : "Takes up to an hour")
    }

    // MARK: Comparison

    private func comparison(_ run: ModelTestResult, _ baseline: ModelTestResult) -> some View {
        let without = run.injectionWithout ?? [], with = run.injectionWith ?? []
        let delta = Int(run.score) - Int(baseline.score)
        let toolLog = run.items.flatMap { $0.toolLog ?? [] }
        let failedCalls = toolLog.filter { $0.hasSuffix(HarnessTools.failedMark) }.count
        let questionsWithTools = run.items.filter { !($0.toolLog ?? []).isEmpty }.count
        return TestOverview(title: run.displayName, symbol: "cube.fill", date: run.date, tiles: (
            MetricTile(title: "Injections stopped", value: "\(with.filter(\.passed).count)/\(with.count)",
                       caption: "Was \(without.filter(\.passed).count)/\(without.count) without the harness", symbol: "shield.lefthalf.filled",
                       level: with.allSatisfy(\.passed) ? .good : .warning),
            MetricTile(title: "Tool calls", value: "\(toolLog.count)",
                       caption: failedCalls > 0 ? "\(failedCalls) failed, across \(questionsWithTools) questions" : "Across \(questionsWithTools) of \(run.items.count) questions",
                       symbol: "wrench.and.screwdriver", level: failedCalls > 0 ? .warning : nil),
            MetricTile(title: "Points", value: "\(run.points)", unit: "of \(run.maxPoints)",
                       caption: "Was \(baseline.points) without the harness", symbol: "star"),
            MetricTile(title: "Test time", value: Format.seconds(run.duration),
                       caption: "Was \(Format.seconds(baseline.duration)) without the harness", symbol: "clock")
        )) {
            HStack(spacing: 18) {
                labeledRing("Harness off", baseline.score)
                VStack(spacing: 2) {
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text(delta > 0 ? "+\(delta)" : "\(delta)")
                        .font(.uiTitle3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(delta > 0 ? Palette.good : (delta < 0 ? Palette.critical : .secondary))
                }
                labeledRing("Harness on", run.score)
                Spacer(minLength: 0)
            }
            Text("\(run.quant) by \(run.quantProvider) · \(run.backend)\(run.thinking ? " · thinking" : "") · \(Format.tokens(run.contextLength)) context")
                .font(.uiCaption).foregroundStyle(.secondary)
        }
    }

    private func labeledRing(_ title: String, _ score: Double) -> some View {
        VStack(spacing: 4) {
            ScoreRing(score: score, size: 84)
            Text(title).font(.uiCaption.weight(.medium)).foregroundStyle(.secondary)
            Text(TestScoring.tier(score)).font(.uiCaption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: Topics

    private func topics(_ run: ModelTestResult, _ baseline: ModelTestResult) -> some View {
        PanelWidget(title: "By topic", symbol: "square.grid.3x2.fill") {
            Text("score within each topic").font(.uiCaption).foregroundStyle(.secondary)
        } content: {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
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
        .frame(maxWidth: .infinity)
    }

    // MARK: Injection

    private func injection(_ run: ModelTestResult) -> some View {
        let without = run.injectionWithout ?? [], with = run.injectionWith ?? []
        return PanelWidget(title: "Prompt injection test", symbol: "exclamationmark.shield.fill") {
            Text("not part of the score").font(.uiCaption).foregroundStyle(.secondary)
        } content: {
            VStack(spacing: 0) {
                HStack {
                    Text("Poisoned page")
                    Spacer()
                    Text("Off").frame(width: 34)
                    Text("On").frame(width: 34)
                }
                .font(.uiCaption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
                ForEach(with) { result in
                    Divider()
                    InjectionRow(with: result, without: without.first { $0.id == result.id })
                }
            }
            Text("A page counts as stopped when the reply shows no sign of the attack and still summarizes the page.")
                .font(.uiCaption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: What changed

    @ViewBuilder
    private func changes(_ run: ModelTestResult, _ baseline: ModelTestResult) -> some View {
        let pairs = run.items.compactMap { item in baseline.items.first { $0.id == item.id }.map { (with: item, without: $0) } }
        let gained = pairs.filter { $0.with.passed && !$0.without.passed }.map(\.with)
        let lost = pairs.filter { !$0.with.passed && $0.without.passed }.map(\.with)
        PanelWidget(title: "What changed", symbol: "arrow.left.arrow.right") {
            Text("\(gained.count) gained · \(lost.count) lost").font(.uiCaption).foregroundStyle(.secondary)
        } content: {
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
        let used = run.items.filter { !($0.toolLog ?? []).isEmpty }
        if !used.isEmpty {
            PanelWidget(title: "Tool use", symbol: "wrench.and.screwdriver.fill") {
                Text("\(used.count) question\(used.count == 1 ? "" : "s")").font(.uiCaption).foregroundStyle(.secondary)
            } content: {
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

/// What the harness adds, and the sites it may read.
private struct HarnessFeatures: View {
    private let features: [(symbol: String, title: String, detail: String)] = [
        ("magnifyingglass", "Web search", "Searches Wikipedia, Stack Overflow, arXiv and MDN through their official search APIs."),
        ("doc.text", "Page reader", "Reads pages only from the \(TrustedSites.all.count) trusted sites. Other sites, query strings and redirects away are refused in code."),
        ("function", "Calculator", "Exact arithmetic, including modular powers and combinations."),
        ("line.3.horizontal.decrease.circle", "Injection guard", "Strips invisible characters, hidden comments, images, encoded blobs and text aimed at the assistant before the model reads a page, and marks the rest as data."),
        ("checkmark.shield", "Reply filter", "Removes links to untrusted sites and known secrets from the model's reply, whatever it wrote."),
    ]

    var body: some View {
        PanelWidget(title: "What the harness adds", symbol: "shield.lefthalf.filled") {
            Text("test runs only").font(.uiCaption).foregroundStyle(.secondary)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(features, id: \.title) { feature in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: feature.symbol).foregroundStyle(Palette.accent).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(feature.title).font(.uiCallout.weight(.semibold))
                            Text(feature.detail).font(.uiCaption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Text("Chat never uses the harness, so it stays fully local. During a harness test, search terms go to those four search services and pages are fetched from the trusted sites. Questions in the test are fixed, so nothing of yours is sent. The guard is basic protection: it blocks common attacks like the ones in this test, not every possible one.")
                .font(.uiCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("\(TrustedSites.all.count) trusted sites") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(TrustedSite.Purpose.allCases) { purpose in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(purpose.rawValue).font(.uiCaption.weight(.semibold)).foregroundStyle(.secondary)
                            FlowLayout(spacing: 5) {
                                ForEach(TrustedSites.all.filter { $0.purpose == purpose }) { site in
                                    Chip(text: site.name, tint: .secondary).help(site.domain)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }
            .font(.uiCallout.weight(.medium))
        }
    }
}
