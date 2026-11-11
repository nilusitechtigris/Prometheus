import SwiftUI

/// The same model with the harness off and through each version of it: tools from trusted sites plus
/// prompt injection protection.
struct HarnessTestDashboard: View {
    enum Detail: Hashable { case howItWorks, versions, changes, repeats, tools, sites }

    @Environment(TestLab.self) private var lab
    @Environment(BackendController.self) private var backends
    @Environment(ChatController.self) private var chat
    @Environment(AppSettings.self) private var settings

    /// Off only for debug renders of the whole page.
    var scrollable = true
    @State var detail = Detail.howItWorks
    @State private var askAboutWeb = false

    var body: some View {
        let run = lab.harnessRun(for: testModel?.id)
        let baseline = run.flatMap { lab.baseline(of: $0) }
        TestPage(title: "Harness · \(lab.harnessSize.title)",
                 subtitle: subtitle,
                 caption: backends.kind.supportsTools ? setupCaption : "Harness tools need Ollama or MLX LM for now",
                 notice: notice(showing: run),
                 progress: lab.harnessProgress, onStop: { lab.cancelHarnessTest() }, scrollable: scrollable, shownRun: run?.id) {
            TestFrameworkPicker()
            TestModelPicker()
            HarnessSizePicker()
            if Edition.current.isLab { HarnessVersionPicker() }
            HarnessRepeatsPicker()
            HarnessOffToggle()
            RunTestButton(title: lab.harnessChoice == nil ? "Run all \(HarnessVersion.allCases.count)" : "Run test",
                          disabled: !canRun || !backends.kind.supportsTools) {
                // The test can't stop to ask about each lookup, so it asks once before it starts.
                if WebConsent.shared.testNeedsAsking {
                    askAboutWeb = true
                } else {
                    lab.runHarnessTest(backends: backends, settings: settings)
                }
            }
            .confirmationDialog("This test looks things up on the web", isPresented: $askAboutWeb) {
                Button("Run the Test") {
                    if canRun { lab.runHarnessTest(backends: backends, settings: settings) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("With the harness on, its knowledge tasks search \(WebConsent.destinations) and open pages from the trusted sites, without asking each time. This is for the test only, whatever Web lookups is set to in chat. The questions are fixed, so nothing of yours is sent.")
            }
        } content: {
            if let run {
                TestBlocks(title: run.displayName, symbol: "cube.fill", date: run.date, tiles: tiles(run, baseline)) {
                    hero(run, baseline)
                } left: {
                    topics(run, baseline)
                } right: {
                    let rows = lab.repeats(of: run)
                    if run.askedSet != nil, rows.isEmpty {
                        sources(run, baseline)
                    } else if !rows.isEmpty, !showsPages(run) {
                        TestPanel(title: "Repeat runs", symbol: "repeat", note: "the same setup, round by round") {
                            // The table can outgrow the panel when every version was run.
                            ScrollView { repeatTable(rows, shown: run) }.frame(maxHeight: .infinity)
                        }
                    } else {
                        injection(run)
                    }
                } runs: {
                    history(selected: run)
                }
            } else if lab.harnessProgress == nil {
                TestEmptyState(text: "Run the test to compare the chosen model with and without the harness: the same questions, then poisoned web pages that try to take it over.")
            }
            details(run, baseline)
        }
    }

    private var subtitle: String {
        switch lab.harnessSize {
        case .normal: "\(ModelTestSuite.quickIDs.count) quick tasks: Coding, Knowledge and Instructions."
        case .max: "The same \(ModelTestSuite.questionCount) questions \(Edition.current.isLab ? "with each version" : "with the harness off and on"), then \(InjectionSuite.cases.count) poisoned pages."
        case .heldOut: "\(HeldOut.size()) public questions the harness was never tuned on: maths, writing to rules, and code."
        case .practice: "\(HeldOut.size(HeldOut.practice)) more of the same kinds, for finding what fails. The harness may be tuned on these, so they prove nothing."
        }
    }

    private var testModel: LocalModel? { lab.testModel(in: backends) }
    private var canRun: Bool { !lab.isRunning && !chat.isGenerating && backends.status.isOnline && testModel != nil }

    /// The chosen model or version has no run of its own, so the page is showing another one.
    private func notice(showing run: ModelTestResult?) -> String? {
        guard let model = testModel, let run, lab.harnessProgress == nil else { return nil }
        if !run.isCurrentSuite { return "From an older version of the test, so its score won't compare with new runs." }
        if run.errorCount > 0 {
            return "\(run.errorCount) question\(run.errorCount == 1 ? "" : "s") got no reply because of an error, and count\(run.errorCount == 1 ? "s" : "") as wrong."
        }
        if run.size != lab.harnessSize { return "No \(lab.harnessSize.title) run yet. Showing \(run.size.title)." }
        if model.id != run.model { return "Not tested yet. Showing \(run.displayName) \(run.quant)." }
        if let choice = lab.harnessChoice, let shown = run.version, choice != shown {
            return Edition.current.isLab ? "\(choice.title) not tested on this model yet. Showing \(shown.title)."
                                         : "The harness isn't tested on this model yet. Showing a run of an earlier harness."
        }
        return nil
    }

    private var setupCaption: String {
        let context = testModel.map { Format.tokens(backends.estimatedContext(for: $0)) } ?? "—"
        let thinking = testModel?.catalog?.thinking == true && settings.thinkingEnabled && backends.kind.supportsThinkingControl
        let versions = lab.harnessChoice.map(\.testTimeWeight) ?? HarnessVersion.allCases.map(\.testTimeWeight).reduce(0, +)
        var time: String
        switch lab.harnessSize {
        case .normal: time = thinking ? "Thinking on, can take \(versions * 15)+ minutes" : "Takes up to \(versions * 10) minutes"
        case .max: time = thinking ? "Thinking on, can take \(versions * 2)+ hours" : "Takes up to \(versions == 1 ? "an hour" : "\(versions) hours")"
        // Nobody has timed these yet, so it says how much there is to ask instead of guessing.
        case .heldOut, .practice: time = "\(lab.harnessSize.questionSet.map { HeldOut.size($0) } ?? 0) questions\(Edition.current.isLab ? " for each version" : "")"
        }
        if lab.harnessRepeats > 1 { time += ", \(lab.harnessRepeats) times over" }
        let sameAsLoop = !thinking && lab.harnessChoice == .thinking ? " · Without thinking, \(HarnessVersion.thinking.short) runs like \(HarnessVersion.loop.short)" : ""
        return "\(backends.kind.displayName) · \(context) context · \(time)\(sameAsLoop)"
    }

    // MARK: Overview

    private func tiles(_ run: ModelTestResult, _ baseline: ModelTestResult?) -> (MetricTile, MetricTile, MetricTile, MetricTile) {
        let without = run.injectionWithout ?? [], with = run.injectionWith ?? []
        let toolLog = run.items.flatMap { $0.toolLog ?? [] }.filter(HarnessTools.isToolCall)
        let failedCalls = toolLog.filter { $0.hasSuffix(HarnessTools.failedMark) }.count
        let questionsWithTools = run.items.filter(usedTools).count
        return (MetricTile(title: "Injections stopped", value: with.isEmpty ? "—" : "\(with.filter(\.passed).count)/\(with.count)",
                           caption: with.isEmpty ? "Only in Max"
                               : without.isEmpty ? Self.notRunOff : "Was \(without.filter(\.passed).count)/\(without.count) without the harness",
                           symbol: "shield.lefthalf.filled",
                           level: with.isEmpty ? nil : with.allSatisfy(\.passed) ? .good : .warning),
                MetricTile(title: "Tool calls", value: "\(toolLog.count)",
                           caption: toolCaption(run, questions: questionsWithTools, failed: failedCalls),
                           symbol: "wrench.and.screwdriver", level: failedCalls > 0 ? .warning : nil),
                MetricTile(title: run.askedSet != nil ? "Right answers" : "Points", value: "\(run.points)", unit: "of \(run.maxPoints)",
                           caption: baseline.map { "Was \($0.points) without the harness" } ?? Self.notRunOff, symbol: "star"),
                MetricTile(title: "Test time", value: Format.seconds(run.duration),
                           caption: baseline.map { "Was \(Format.seconds($0.duration)) without the harness" } ?? Self.notRunOff,
                           symbol: "clock"))
    }

    private static let notRunOff = "Harness off wasn't run"

    private func toolCaption(_ run: ModelTestResult, questions: Int, failed: Int) -> String {
        let spread = failed > 0 ? "\(failed) failed, across \(questions) questions" : "Across \(questions) of \(run.items.count) questions"
        return run.modelToolCalls.map { "\($0) by the model itself. \(spread)" } ?? spread
    }

    private func hero(_ run: ModelTestResult, _ baseline: ModelTestResult?) -> some View {
        let on = TestFormat.score(run.score)
        let version = run.version?.runPhrase() ?? "the harness"
        let cantCallTools = "This model can't call tools itself, so only the harness used them."
        let publicSet = run.askedSet != nil
        let headline, note: String
        let aside: String?
        if let baseline {
            let off = TestFormat.score(baseline.score)
            if publicSet {
                // Every question counts the same here, so the gain is counted in questions. A rounded score
                // would call 90 against 91 right "no change".
                let more = run.passed - baseline.passed
                headline = more == 0 ? "No change with \(version)" : "\(abs(more)) \(more > 0 ? "more" : "fewer") right with \(version)"
                aside = "\(baseline.passed) → \(run.passed) of \(run.items.count)"
            } else {
                let delta = Int(run.score) - Int(baseline.score)
                headline = delta == 0 ? "No change with \(version)" : "\(delta > 0 ? "+" : "")\(delta) with \(version)"
                aside = "\(off) → \(on)"
            }
            note = run.toolsAvailable == false ? "\(off) off, \(on) on. \(cantCallTools)" : "\(off) with the harness off, \(on) with it on, on the same questions."
        } else {
            headline = publicSet ? "\(run.passed) of \(run.items.count) right with \(version)" : "\(on) with \(version)"
            aside = nil
            note = run.toolsAvailable == false ? cantCallTools : "Run with the harness on only, so there's no score to compare it with."
        }
        var single = note
        if run.size == .practice {
            single = "Practice questions. The harness may be tuned on these, so report Held-out numbers, not these."
        } else if publicSet, run.toolsAvailable != false {
            single = "The share of \(run.items.count) public questions answered right, in one run."
        }
        var card = TestHero(score: run.score, headline: headline, aside: aside,
                            detail: "\(run.quant) by \(run.quantProvider) · \(run.backend)", note: repeatNote(run) ?? single) {
            ModelRunChips(run: run)
        }
        if publicSet {
            // The app's own test is scaled to a frontier model. This one is just the share answered right.
            card.unit = "% right"
            card.scale = ["0", "25", "50", "75", "100"]
        }
        return card
    }

    /// For a run that is one round of several: which one it is, and the means.
    private func repeatNote(_ run: ModelTestResult) -> String? {
        let rows = lab.repeats(of: run)
        guard let index = run.repeatIndex, let mine = rows.first(where: { $0.version == run.version }), mine.scores.count > 1 else { return nil }
        let mean = String(format: "%.1f", mine.mean)
        let off = rows.first { $0.version == nil }.map { String(format: ", and %.1f with the harness off", $0.mean) } ?? ""
        return "Round \(index). Mean over \(mine.scores.count) rounds: \(mean)\(off)."
    }

    // MARK: Repeats and sources

    /// True when the panel beside By topic holds the poisoned pages, which only Max has.
    private func showsPages(_ run: ModelTestResult) -> Bool { !(run.injectionWith ?? []).isEmpty }

    /// Every score of every round, so a gain can be seen next to how much a score moves by itself.
    private func repeatTable(_ rows: [RepeatRow], shown run: ModelTestResult) -> some View {
        let rounds = Set(rows.flatMap(\.rounds)).sorted()
        let off = rows.first { $0.version == nil }
        let mine = rows.first { $0.version == run.version }
        func one(_ value: Double) -> String { String(format: "%.1f", value) }
        return VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("")
                    ForEach(rounds, id: \.self) { Text("Round \($0)").gridColumnAlignment(.trailing) }
                    Text("Mean").gridColumnAlignment(.trailing)
                    Text("Lowest to highest").gridColumnAlignment(.trailing)
                }
                .font(.uiCaption.weight(.semibold))
                .foregroundStyle(.secondary)
                ForEach(rows) { row in
                    let chosen = row.version == run.version
                    GridRow {
                        Text(row.title).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(rounds, id: \.self) { round in
                            Text(row.scores[round].map(one) ?? "—").monospacedDigit()
                        }
                        Text(one(row.mean)).monospacedDigit().fontWeight(.semibold)
                        Text("\(one(row.low)) to \(one(row.high))").monospacedDigit()
                    }
                    .font(.uiCallout)
                    .foregroundStyle(chosen ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(row.version == nil ? .primary : .secondary))
                }
            }
            Spacer(minLength: 0)
            if let off, let mine, mine.version != nil {
                panelFootnote((mine.verdict(against: off) ?? "Fewer than two rounds have both runs, so there's nothing to compare yet.")
                              + " The plain model is asked at temperature 0, so its rounds differ little. Whether a gap is more than luck is under What changed.")
            } else {
                panelFootnote("Run with the harness off too, to see a gain next to how much a score moves by itself.")
            }
        }
    }

    /// The questions that passed on one side only.
    private func flips(_ run: ModelTestResult, _ baseline: ModelTestResult) -> (gained: [ModelTestItemResult], lost: [ModelTestItemResult]) {
        let pairs = run.items.compactMap { item in baseline.items.first { $0.id == item.id }.map { (with: item, without: $0) } }
        return (pairs.filter { $0.with.passed && !$0.without.passed }.map(\.with), pairs.filter { !$0.with.passed && $0.without.passed }.map(\.with))
    }

    /// Shown where a held-out run would list its questions.
    private var closedNote: some View {
        panelFootnote("The held-out questions and replies aren't shown, so that nobody tunes the harness on them by accident. Practice asks questions of the same kinds and shows everything.")
    }

    /// Where the public questions come from, and how this run did on each.
    private func sources(_ run: ModelTestResult, _ baseline: ModelTestResult?) -> some View {
        func right(_ result: ModelTestResult?, _ prefix: String) -> String {
            guard let items = result?.items.filter({ $0.id.hasPrefix(prefix) }), !items.isEmpty else { return "—" }
            return "\(items.filter(\.passed).count)/\(items.count)"
        }
        let footnote: String
        if let baseline {
            let changed = flips(run, baseline)
            footnote = FlipTest.sentence(gained: changed.gained.count, lost: changed.lost.count)
        } else if run.size == .practice {
            footnote = "Public test questions kept apart from the held-out ones. The harness may be tuned on these, so a gain here is a lead to follow, not a result."
        } else {
            footnote = "Public test questions, picked by a fixed seed and never used to tune the harness. Code grades every one."
        }
        return TestPanel(title: "Where the questions come from", symbol: "books.vertical.fill", note: "right answers") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text("")
                    Text("Off").gridColumnAlignment(.trailing)
                    Text(run.version?.runShort() ?? "On").gridColumnAlignment(.trailing).foregroundStyle(Palette.accent)
                }
                .font(.uiCaption.weight(.semibold))
                .foregroundStyle(.secondary)
                ForEach(HeldOut.sources, id: \.prefix) { source in
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(source.name).font(.uiCallout)
                            Text(source.what).font(.uiCaption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(right(baseline, source.prefix)).monospacedDigit().foregroundStyle(.secondary)
                        Text(right(run, source.prefix)).monospacedDigit().fontWeight(.semibold).foregroundStyle(Palette.accent)
                    }
                    .font(.uiCallout)
                }
            }
            Spacer(minLength: 0)
            panelFootnote(footnote)
        }
    }

    /// A few lines under a panel. It asks for little width, so a long one wraps instead of pushing the two
    /// panels one above the other.
    private func panelFootnote(_ text: String) -> some View {
        Text(text)
            .font(.uiCaption).foregroundStyle(.secondary)
            .frame(minWidth: 0, idealWidth: 240, maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func usedTools(_ item: ModelTestItemResult) -> Bool {
        (item.toolLog ?? []).contains(where: HarnessTools.isToolCall)
    }

    // MARK: Details

    @ViewBuilder
    private func details(_ run: ModelTestResult?, _ baseline: ModelTestResult?) -> some View {
        let tabs = detailTabs(run, baseline)
        // A tab can go away when another run is shown. The first one stands in for it.
        let shown = tabs.contains { $0.id == detail } ? detail : .howItWorks
        TestDetails(tabs: tabs, selection: $detail) {
            switch (shown, run, baseline) {
            case (.versions, _, _): versions(run, baseline)
            case (.changes, let run?, let baseline?): changes(run, baseline)
            case (.repeats, let run?, _): repeatTable(lab.repeats(of: run), shown: run)
            case (.tools, let run?, _): toolActivity(run)
            case (.sites, _, _): TrustedSiteList()
            default: HarnessFlowDiagram()
            }
        }
    }

    private func detailTabs(_ run: ModelTestResult?, _ baseline: ModelTestResult?) -> [(id: Detail, title: String)] {
        var tabs: [(id: Detail, title: String)] = [(.howItWorks, "How it works")]
        // Comparing versions is the lab's.
        if Edition.current.isLab { tabs.append((.versions, "Versions")) }
        if run != nil, baseline != nil { tabs.append((.changes, "What changed")) }
        // Max keeps its poisoned pages in the panel, so its repeats go here.
        if let run, showsPages(run), !lab.repeats(of: run).isEmpty { tabs.append((.repeats, "Repeats")) }
        if run != nil { tabs.append((.tools, "Tool use")) }
        tabs.append((.sites, "Trusted sites"))
        return tabs
    }

    // MARK: Topics

    /// Every version beside the run with the harness off, so the results sit side by side.
    private func topics(_ run: ModelTestResult, _ baseline: ModelTestResult?) -> some View {
        let runs = lab.comparableRuns(to: run)
        // Outside the lab: the harness in use, and the shown run's own version when that's an earlier one.
        let columns = HarnessVersion.offered() + [run.version].compactMap { $0 }.filter { !HarnessVersion.offered().contains($0) }
        return TestPanel(title: "By topic", symbol: "square.grid.3x2.fill", note: "score, on this model and setup") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 16) {
                GridRow {
                    Text("")
                    Text("Off").gridColumnAlignment(.trailing)
                    ForEach(columns) { version in
                        Text(version.runShort())
                            .foregroundStyle(version == run.version ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.secondary))
                            .gridColumnAlignment(.trailing)
                    }
                }
                .font(.uiCaption.weight(.semibold))
                .foregroundStyle(.secondary)
                ForEach(ModelTestCategory.allCases.filter { category in run.items.contains { $0.category == category } }) { category in
                    GridRow {
                        HStack(spacing: 6) {
                            Image(systemName: category.symbol).font(.uiCaption).foregroundStyle(.secondary).frame(width: 16)
                            Text(category.name).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text(baseline?.score(for: category).map(Format.percent) ?? "—").monospacedDigit().foregroundStyle(.secondary)
                        ForEach(columns) { version in
                            topicCell(runs[version]?.score(for: category).map(Format.percent), chosen: version == run.version)
                        }
                    }
                    .font(.uiCallout)
                }
                GridRow {
                    Text("All topics").frame(maxWidth: .infinity, alignment: .leading)
                    Text(baseline.map { TestFormat.score($0.score) } ?? "—").monospacedDigit().foregroundStyle(.secondary)
                    ForEach(columns) { version in
                        topicCell(runs[version].map { TestFormat.score($0.score) }, chosen: version == run.version)
                    }
                }
                .font(.uiCallout.weight(.semibold))
            }
        }
    }

    private func topicCell(_ text: String?, chosen: Bool) -> some View {
        Text(text ?? "—")
            .monospacedDigit()
            .fontWeight(chosen ? .semibold : .regular)
            // A version that wasn't run steps back, so the eye goes to the numbers.
            .foregroundStyle(chosen ? AnyShapeStyle(Palette.accent) : text == nil ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.secondary))
    }

    // MARK: Versions

    /// What each version does, how it scored on this setup, and every question side by side.
    @ViewBuilder
    private func versions(_ run: ModelTestResult?, _ baseline: ModelTestResult?) -> some View {
        let runs = run.map { lab.comparableRuns(to: $0) } ?? [:]
        VStack(alignment: .leading, spacing: 12) {
            Text(run.map { "Scores for \($0.displayName) \($0.quant) at \(Format.tokens($0.contextLength)) context, thinking \($0.thinking ? "on" : "off"). Only runs on this same setup are compared." }
                 ?? "Run the test to score a version.")
                .font(.uiCaption).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(HarnessVersion.allCases) { version in
                    VersionCard(version: version, run: runs[version], baseline: baseline,
                                selected: version == run?.version) {
                        if let run = runs[version] { lab.show(harnessRun: run) }
                    }
                }
            }
            if let run {
                if run.size == .heldOut {
                    closedNote
                } else {
                    VersionQuestionGrid(run: run, baseline: baseline, runs: runs, weighted: run.askedSet == nil)
                }
            }
        }
    }

    // MARK: Injection

    private func injection(_ run: ModelTestResult) -> some View {
        let without = run.injectionWithout ?? [], with = run.injectionWith ?? []
        return TestPanel(title: "Prompt injection test", symbol: "exclamationmark.shield.fill", note: "not part of the score") {
            if with.isEmpty {
                Text("The \(InjectionSuite.cases.count) poisoned pages are part of Harness - Max.")
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
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
                Text("Stopped: the reply shows no sign of the attack and still sums up the page.")
                    .font(.uiCaption).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    // MARK: What changed

    @ViewBuilder
    private func changes(_ run: ModelTestResult, _ baseline: ModelTestResult) -> some View {
        let (gained, lost) = flips(run, baseline)
        VStack(alignment: .leading, spacing: 10) {
            Text(FlipTest.sentence(gained: gained.count, lost: lost.count))
                .font(.uiCallout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if run.size == .heldOut {
                ForEach(HeldOut.sources, id: \.prefix) { source in
                    let more = gained.filter { $0.id.hasPrefix(source.prefix) }.count, fewer = lost.filter { $0.id.hasPrefix(source.prefix) }.count
                    if more + fewer > 0 {
                        Text("\(source.name): \(more) to right, \(fewer) to wrong").font(.uiCallout).monospacedDigit()
                    }
                }
                closedNote
            } else {
                changeList("Solved only with the harness", gained)
                changeList("Solved only without the harness", lost)
            }
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
            if run.size == .heldOut {
                closedNote
            } else if !used.isEmpty {
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
                       tag: [run.version?.runTitle(), run.size.title, run.repeatIndex.map { "round \($0)" }, run.isCurrentSuite ? nil : "old test"]
                           .compactMap { $0 }.joined(separator: " · "),
                       result: "\(lab.baseline(of: run).map { TestFormat.score($0.score) } ?? "—") → \(TestFormat.score(run.score))",
                       selected: run.id == selected.id,
                       onSelect: { lab.show(harnessRun: run) },
                       onDelete: { lab.delete(modelRun: run.id) })
        }
    }
}

/// Normal, the quick test, or Max, everything.
private struct HarnessSizePicker: View {
    @Environment(TestLab.self) private var lab

    var body: some View {
        Picker("Test size", selection: Binding(get: { lab.harnessSize }, set: { lab.chooseHarnessSize($0) })) {
            ForEach(HarnessTestSize.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // As tall as the pills beside it.
        .controlSize(.large)
        .fixedSize()
        .disabled(lab.isRunning)
        .help("Normal: \(ModelTestSuite.quickIDs.count) tasks, to check a change quickly. Max: all \(ModelTestSuite.questionCount) questions and the poisoned pages. Held-out: \(HeldOut.size()) public questions the harness was never tuned on. Practice: \(HeldOut.size(HeldOut.practice)) more like them, for finding what fails. Scores from different sizes don't compare.")
    }
}

/// How many times the next test runs everything.
private struct HarnessRepeatsPicker: View {
    @Environment(TestLab.self) private var lab
    @State private var show = false

    private func title(_ count: Int) -> String { count == 1 ? "1 run" : "\(count) runs" }

    var body: some View {
        // The same pill and list as the version beside it, so the row reads as one set of controls.
        Button {
            show.toggle()
        } label: {
            PickerPill {
                Text(title(lab.harnessRepeats)).fontWeight(.medium).lineLimit(1)
            }
        }
        .buttonStyle(.soft)
        .foregroundStyle(.primary)
        .glassCapsule(interactive: true)
        .disabled(lab.isRunning)
        .help("How many times the test asks everything")
        .popover(isPresented: $show, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How many runs").font(.uiHeadline).padding(.horizontal, 8).padding(.bottom, 4)
                ForEach(TestLab.repeatOptions, id: \.self) { count in
                    PopoverRow(selected: lab.harnessRepeats == count) {
                        lab.harnessRepeats = count
                        show = false
                    } content: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title(count)).font(.uiCallout.weight(.semibold))
                            Text(count == 1 ? "Asks everything once."
                                 : "Asks everything \(count) times over, so you can see how much a score moves from one run to the next. With Harness off too, every round has its own harness-off run.")
                                .font(.uiCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(12)
            .frame(width: 340)
        }
    }
}

/// Whether a run also covers the harness off, or only the harness on.
private struct HarnessOffToggle: View {
    @Environment(TestLab.self) private var lab
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Toggle("Harness off too", isOn: $settings.harnessTestRunsOff)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.uiCaption)
            .fixedSize()
            .disabled(lab.isRunning)
            .help("On: runs the questions and poisoned pages with the harness off as well, or reuses a matching run. Off: runs them with the harness on only.")
    }
}

/// Chooses the version to test and show, or every version in turn.
private struct HarnessVersionPicker: View {
    @Environment(TestLab.self) private var lab
    @State private var show = false

    var body: some View {
        Button {
            show.toggle()
        } label: {
            PickerPill {
                Text(lab.harnessChoice?.title ?? "All versions").fontWeight(.medium).lineLimit(1)
            }
        }
        .buttonStyle(.soft)
        .foregroundStyle(.primary)
        .glassCapsule(interactive: true)
        .disabled(lab.isRunning)
        .help("Choose which version of the harness to test")
        .popover(isPresented: $show, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Version to test").font(.uiHeadline).padding(.horizontal, 8).padding(.bottom, 4)
                ForEach(HarnessVersion.allCases) { version in
                    PopoverRow(selected: lab.harnessChoice == version) {
                        lab.chooseHarness(version)
                        show = false
                    } content: {
                        HarnessVersionLabel(version: version)
                    }
                }
                Divider().padding(.vertical, 4)
                PopoverRow(selected: lab.harnessChoice == nil) {
                    lab.chooseHarness(nil)
                    show = false
                } content: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("All versions").font(.uiCallout.weight(.semibold))
                        Text("Runs each one in turn, so you can leave it and compare them after.")
                            .font(.uiCaption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .frame(width: 380)
        }
    }
}

/// One version: what it does, the steps it takes, and how it did. Choosing it shows that run above.
private struct VersionCard: View {
    let version: HarnessVersion
    let run: ModelTestResult?
    let baseline: ModelTestResult?
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(version.title).font(.uiHeadline)
                        if version == .recommended { Chip(text: "Recommended", tint: Palette.accent) }
                    }
                    Text(version.summary).font(.uiCaption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    FlowLayout(spacing: 4) {
                        ForEach(Array(version.route.enumerated()), id: \.offset) { index, step in
                            HStack(spacing: 4) {
                                if index > 0 {
                                    Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.accent.opacity(0.8))
                                }
                                Text(step)
                                    .font(.uiCaption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                        }
                        if version.isLoop {
                            Label("Fails? Back to Act", systemImage: "arrow.counterclockwise")
                                .font(.uiCaption2)
                                .foregroundStyle(Palette.accent)
                                .padding(.leading, 4)
                        }
                    }
                    if version == .council {
                        FlowLayout(spacing: 4) {
                            ForEach(CouncilAgent.all) { agent in
                                Text("\(agent.name) \(String(format: "%.1f", agent.temperature)) · \(agent.summary)")
                                    .font(.uiCaption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let run {
                    HStack(spacing: 18) {
                        stat("Score", TestFormat.score(run.score), lit: true)
                        // On a public set every question counts the same, so both are counted in questions.
                        stat(run.askedSet == nil ? "Points" : "Right", "\(run.points)/\(run.maxPoints)")
                        stat("Gain", baseline.map { signed(run.askedSet == nil ? Int(run.score) - Int($0.score) : run.passed - $0.passed) } ?? "—")
                        stat("Model called", run.modelToolCalls.map(String.init) ?? "—")
                        stat("Time", Format.seconds(run.duration))
                    }
                } else {
                    Text("Not run on this setup").font(.uiCaption).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(selected ? Palette.accent.opacity(0.10) : Color.primary.opacity(0.04), in: shape)
            .overlay(shape.strokeBorder(selected ? Palette.accent.opacity(0.45) : .clear, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.soft)
        .disabled(run == nil)
    }

    private func signed(_ value: Int) -> String { value == 0 ? "0" : String(format: "%+d", value) }

    private func stat(_ title: String, _ value: String, lit: Bool = false) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.uiDisplay(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(lit ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.primary))
            Text(title).font(.uiCaption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// Every question, passed or failed, with the harness off and in each version.
private struct VersionQuestionGrid: View {
    let run: ModelTestResult
    let baseline: ModelTestResult?
    let runs: [HarnessVersion: ModelTestResult]
    /// Off for a test where every question counts the same, which has no points to show.
    var weighted = true

    /// A long test shows only the questions the setups disagree on. The rest would be a wall of ticks.
    private var shown: [ModelTestItemResult] {
        guard run.items.count > 40 else { return run.items }
        let others = [baseline].compactMap { $0 } + runs.values
        return run.items.filter { item in
            let marks = Set(others.compactMap { other in other.items.first { $0.id == item.id }?.passed } + [item.passed])
            return marks.count > 1
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Question by question").font(.uiCallout.weight(.semibold))
            if shown.isEmpty {
                Text("The runs agree on all \(run.items.count) questions.").font(.uiCaption).foregroundStyle(.secondary)
            } else if shown.count < run.items.count {
                Text("Showing the \(shown.count) of \(run.items.count) questions where the runs differ.")
                    .font(.uiCaption).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    Text("Question")
                    Text(weighted ? "Points" : "").gridColumnAlignment(.trailing)
                    Text("Off").gridColumnAlignment(.center)
                    ForEach(HarnessVersion.allCases) { Text($0.short).gridColumnAlignment(.center) }
                }
                .font(.uiCaption.weight(.semibold))
                .foregroundStyle(.secondary)
                ForEach(shown) { item in
                    GridRow {
                        Text(item.title).font(.uiCallout).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(weighted ? "\(item.weight)" : "").font(.uiCaption.monospacedDigit()).foregroundStyle(.secondary)
                        mark(baseline?.items.first { $0.id == item.id })
                        ForEach(HarnessVersion.allCases) { version in
                            mark(runs[version]?.items.first { $0.id == item.id })
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mark(_ item: ModelTestItemResult?) -> some View {
        if let item {
            Image(systemName: item.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.uiCaption)
                .foregroundStyle(item.passed ? Palette.good : Palette.critical.opacity(0.75))
        } else {
            Text("—").font(.uiCaption).foregroundStyle(.tertiary)
        }
    }
}

/// One poisoned page: how it went without and with the harness, expanding to show both replies.
private struct InjectionRow: View {
    let with: InjectionResult
    let without: InjectionResult?
    @State private var expanded = false

    /// A dash when that side wasn't run, because a cross would say the attack got through.
    @ViewBuilder
    private func mark(_ result: InjectionResult?) -> some View {
        if let result {
            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.passed ? Palette.good : Palette.critical)
                .frame(width: 34)
        } else {
            Text("—").foregroundStyle(.tertiary).frame(width: 34)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.quick) { expanded.toggle() }
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
            .buttonStyle(.soft)
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
