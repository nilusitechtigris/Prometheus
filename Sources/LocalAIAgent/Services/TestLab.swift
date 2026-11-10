import Foundation
import Observation

/// Runs the model and hardware tests and keeps their results.
@MainActor
@Observable
final class TestLab {
    /// Newest first.
    private(set) var modelResults: [ModelTestResult] = []
    private(set) var hardwareResults: [HardwareTestResult] = []
    private(set) var modelProgress: TestProgress?
    private(set) var hardwareProgress: TestProgress?
    private(set) var harnessProgress: TestProgress?
    /// Which Harness Test to run and show.
    private(set) var harnessSize = HarnessTestSize.normal
    private(set) var lastError: String?

    /// Questions open in the dashboard's list.
    var expandedQuestions: Set<String> = []
    /// The model the model test runs on; nil means the chat's model.
    var testModelID: String?
    /// The run each dashboard shows in detail; nil means the newest.
    var selectedModelRunID: UUID?
    var selectedHarnessRunID: UUID?
    var selectedHardwareRunID: UUID?
    /// The version of the harness to test and show; nil means every version in turn.
    var harnessChoice: HarnessVersion? = .recommended

    private var modelTask: Task<Void, Never>?
    private var hardwareTask: Task<Void, Never>?
    private var harnessTask: Task<Void, Never>?
    private var timeline: [HardwareSample] = []
    private var worstThermal = ProcessInfo.ThermalState.nominal
    private let store = TestResultStore()

    init() {
        let saved = store.load()
        modelResults = saved.model.sorted { $0.date > $1.date }
        hardwareResults = saved.hardware.sorted { $0.date > $1.date }
    }

    var isRunning: Bool { modelProgress != nil || hardwareProgress != nil || harnessProgress != nil }

    func testModel(in backends: BackendController) -> LocalModel? {
        backends.models.first { $0.id == testModelID && backends.isSelectable($0) } ?? backends.selectedModel
    }

    /// Picks the model to test and shows its newest run, if it has one.
    func chooseTestModel(_ model: LocalModel) {
        testModelID = model.id
        selectedModelRunID = latestModelResult(for: model.id)?.id
        selectedHarnessRunID = nil
    }

    /// Shows a past run, and makes its model the one to test next.
    func show(_ run: ModelTestResult) {
        selectedModelRunID = run.id
        testModelID = run.model
    }

    /// Runs of the whole question set. Harness - Normal stays out of the Model Test's scores and lists.
    var fullRuns: [ModelTestResult] { modelResults.filter { !$0.isQuick } }

    var selectedModelRun: ModelTestResult? {
        modelResults.first { $0.id == selectedModelRunID }
            ?? fullRuns.first { $0.isCurrentSuite && !$0.usesHarness }
            ?? fullRuns.first { !$0.usesHarness }
    }

    var selectedHardwareRun: HardwareTestResult? {
        hardwareResults.first { $0.id == selectedHardwareRunID } ?? hardwareResults.first
    }

    func latestModelResult(for modelID: String?) -> ModelTestResult? {
        fullRuns.first { $0.model == modelID && $0.isCurrentSuite && !$0.usesHarness }
    }

    /// Newest run of each model + quant + framework on the current questions, best score first.
    var leaderboard: [ModelTestResult] {
        var seen = Set<String>()
        return fullRuns.filter { $0.isCurrentSuite && seen.insert($0.configurationKey).inserted }
            .sorted { ($0.score, $0.tokensPerSecond ?? 0) > ($1.score, $1.tokensPerSecond ?? 0) }
    }

    func delete(modelRun id: UUID) {
        modelResults.removeAll { $0.id == id }
        if selectedModelRunID == id { selectedModelRunID = nil }
        if selectedHarnessRunID == id { selectedHarnessRunID = nil }
        save()
    }

    func delete(hardwareRun id: UUID) {
        hardwareResults.removeAll { $0.id == id }
        if selectedHardwareRunID == id { selectedHardwareRunID = nil }
        save()
    }

    func dismissError() { lastError = nil }

    private func save() { store.save(.init(model: modelResults, hardware: hardwareResults)) }

    // MARK: - Model test

    /// What a run needs to know about the model it's testing.
    struct TestSetup {
        let model: LocalModel
        let backend: LLMBackend
        let context: Int
        var think: Bool?
        let supportsTools: Bool
        var temperature = 0.0
        /// Rounds the harness gets on a task.
        var maxRounds = 3
        /// In v4, when the model stops thinking at each step. Nil in every other case.
        var thinkingUntil: Date?

        /// Whether the step about to run should think, rather than use as few tokens as it can.
        var thinksAtSteps: Bool { thinkingUntil.map { Date() < $0 } ?? false }
    }

    #if DEBUG
    /// Runs a few questions through the harness, for checking changes without a full test.
    func debugSample(ids: [String], backends: BackendController, settings: AppSettings, path: String) {
        guard let model = testModel(in: backends) else { return }
        WebConsent.shared.allowForChecks()
        Task {
            let setup = await Self.prepare(model, backends: backends, settings: settings)
            var lines: [String] = ["model \(model.id) tools \(setup.supportsTools) harness \(settings.harnessVersion.title)"]
            for question in ModelTestSuite.questions(contextLength: setup.context) where ids.contains(question.id) {
                let (item, _) = await Self.ask(question, setup: setup, harness: settings.harnessVersion)
                lines.append("\(item.passed ? "PASS" : "FAIL") \(item.id) (\(item.weight) pts, \(Int(item.seconds)) s, \(item.modelToolCalls ?? 0) model calls) expected \(item.expected)")
                if !item.passed { lines.append("   full: \(item.answer.suffix(260))") }
                lines.append("   answer: \(ModelTestSuite.finalAnswer(item.answer).prefix(90))")
                lines.append("   tokens: output \(item.outputTokens ?? 0), thinking \(item.thinkingTokens ?? 0), stopped \(item.stopReason ?? "?")")
                for step in item.toolLog ?? [] { lines.append("   \(step.prefix(100))") }
                try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
            try? (lines + ["done"]).joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
    #endif

    private static func prepare(_ model: LocalModel, backends: BackendController, settings: AppSettings) async -> TestSetup {
        let backend = backends.backend
        let (context, supportsThinking, supportsTools) = await backends.capabilities(of: model)
        // Two models at once would compete for memory and skew the numbers.
        if settings.unloadOnSwitch {
            for other in (try? await backend.loadedModels()) ?? [] where other.name != model.id {
                await backends.unload(other.name)
            }
            await backends.freeOtherFrameworks()
        }
        return TestSetup(model: model, backend: backend, context: context,
                         think: backend.kind.supportsThinkingControl && supportsThinking ? settings.thinkingEnabled : nil,
                         supportsTools: backend.kind.supportsTools && supportsTools, maxRounds: settings.harnessMaxRounds)
    }

    private static func finish(_ model: LocalModel, backends: BackendController, settings: AppSettings) {
        if settings.unloadOnSwitch, model.id != backends.selectedModel?.id {
            // A new task, so this still runs after Stop cancelled the current one.
            Task { await backends.unload(model.id) }
        }
        backends.activeTest = nil
    }

    func runModelTest(backends: BackendController, settings: AppSettings) {
        guard !isRunning, backends.activeTest == nil, let model = testModel(in: backends) else { return }
        let start = Date()
        lastError = nil
        modelProgress = TestProgress(step: "Loading \(model.displayName)…", startedAt: start)
        backends.activeTest = "Model test"

        modelTask = Task { [weak self] in
            let setup = await Self.prepare(model, backends: backends, settings: settings)
            let result = await self?.runSuite(setup, harness: nil) { index, total, question in
                self?.modelProgress = TestProgress(step: question.category.name,
                                                   detail: "Question \(index + 1) of \(total) · \(question.title)",
                                                   fraction: Double(index) / Double(total), startedAt: start)
            }
            guard let self else { return }
            if let result {
                modelResults.insert(result, at: 0)
                selectedModelRunID = nil
                save()
            }
            modelProgress = nil
            modelTask = nil
            Self.finish(model, backends: backends, settings: settings)
        }
    }

    func cancelModelTest() { modelTask?.cancel() }

    // MARK: - Harness test

    /// The run to show: the one picked, else the newest of the chosen version on this model, else whatever
    /// this model has, else any model's. Runs from an older test come last, so they stay in view.
    func harnessRun(for modelID: String?) -> ModelTestResult? {
        let quick = harnessSize == .normal
        return modelResults.first { $0.id == selectedHarnessRunID }
            ?? newestHarnessRun(in: modelResults.filter { $0.isQuick == quick }, for: modelID)
            ?? newestHarnessRun(in: modelResults, for: modelID)
    }

    private func newestHarnessRun(in runs: [ModelTestResult], for modelID: String?) -> ModelTestResult? {
        runs.first { $0.usesHarness && $0.isCurrentSuite && $0.model == modelID && (harnessChoice == nil || $0.version == harnessChoice) }
            ?? runs.first { $0.usesHarness && $0.isCurrentSuite && $0.model == modelID }
            ?? runs.first { $0.usesHarness && $0.isCurrentSuite }
            ?? runs.first { $0.usesHarness && $0.model == modelID }
            ?? runs.first { $0.usesHarness }
    }

    /// Picks how much of the test to run and shows that size's newest run, if it has one.
    func chooseHarnessSize(_ size: HarnessTestSize) {
        harnessSize = size
        selectedHarnessRunID = nil
    }

    /// Picks the version to test and shows its newest run, if it has one.
    func chooseHarness(_ version: HarnessVersion?) {
        harnessChoice = version
        selectedHarnessRunID = nil
    }

    /// Shows a past harness run, and makes its model and version the ones to test next.
    func show(harnessRun run: ModelTestResult) {
        selectedHarnessRunID = run.id
        testModelID = run.model
        harnessChoice = run.version
        harnessSize = run.isQuick ? .normal : .max
    }

    /// The newest run of each version that compares with this one: same questions, size, model, context and thinking.
    func comparableRuns(to run: ModelTestResult) -> [HarnessVersion: ModelTestResult] {
        var runs: [HarnessVersion: ModelTestResult] = [:]
        for candidate in modelResults where candidate.suiteVersion == run.suiteVersion && candidate.isQuick == run.isQuick && candidate.model == run.model
            && candidate.contextLength == run.contextLength && candidate.thinking == run.thinking {
            if let version = candidate.version, runs[version] == nil { runs[version] = candidate }
        }
        if let version = run.version { runs[version] = run }
        return runs
    }

    func baseline(of run: ModelTestResult) -> ModelTestResult? {
        modelResults.first { $0.id == run.baselineRunID }
    }

    var harnessRuns: [ModelTestResult] { modelResults.filter(\.usesHarness) }

    /// The run to compare against, if this exact setup has already been tested without the harness.
    private func existingBaseline(_ setup: TestSetup, quick: Bool) -> ModelTestResult? {
        modelResults.first {
            $0.isCurrentSuite && !$0.usesHarness && $0.isQuick == quick && $0.model == setup.model.id
                && $0.thinking == (setup.think ?? false) && $0.contextLength == setup.context
        }
    }

    /// The same questions on the same model without the harness, the poisoned pages both ways, then the
    /// questions through each chosen version. A matching run without the harness is reused rather than
    /// repeated, and with `harnessTestRunsOff` turned off nothing runs without the harness at all.
    /// The pages run once, since every version guards them the same way. Harness - Normal asks only
    /// `ModelTestSuite.quickIDs` and leaves the pages out.
    func runHarnessTest(backends: BackendController, settings: AppSettings) {
        guard !isRunning, backends.activeTest == nil, let model = testModel(in: backends) else { return }
        let versions = harnessChoice.map { [$0] } ?? HarnessVersion.allCases
        let quick = harnessSize == .normal
        let start = Date()
        lastError = nil
        harnessProgress = TestProgress(step: "Loading \(model.displayName)…", startedAt: start)
        backends.activeTest = "Harness test"

        harnessTask = Task { [weak self] in
            guard let self else { return }
            // The test can't stop to ask about each lookup, so whoever starts it is told first. The yes belongs
            // to this task alone: nothing else running at the same time can use it.
            await WebConsent.$inTest.withValue(true) {
            var setup = await Self.prepare(model, backends: backends, settings: settings)
            // A version that always thinks, tested on its own, compares with a run that thinks too.
            if versions.allSatisfy(\.alwaysThinks), setup.think != nil { setup.think = true }
            var baseline = self.existingBaseline(setup, quick: quick)
            let runsOff = settings.harnessTestRunsOff
            let needsOffRun = runsOff && baseline == nil

            @MainActor func report(_ step: String, _ detail: String, _ fraction: Double) {
                self.harnessProgress = TestProgress(step: step, detail: detail, fraction: fraction, startedAt: start)
            }
            // Every set of questions gets the same share of the bar, and the poisoned pages a tenth.
            let pagesShare = quick ? 0 : 0.1
            let suiteShare = (1 - pagesShare) / Double(versions.count + (needsOffRun ? 1 : 0))
            let withoutShare = needsOffRun ? suiteShare : 0

            if needsOffRun {
                baseline = await self.runSuite(setup, harness: nil, quick: quick) { index, total, question in
                    report("Without the harness", "Question \(index + 1) of \(total) · \(question.title)",
                           withoutShare * Double(index) / Double(total))
                }
                if let baseline {
                    self.modelResults.insert(baseline, at: 0)
                    self.save()
                }
            }

            // The run without the harness comes back empty if it was stopped or failed.
            let ready = baseline != nil || !runsOff
            var without: [InjectionResult] = [], with: [InjectionResult] = []
            if ready && !quick {
                let cases = InjectionSuite.cases
                for (i, attack) in cases.enumerated() where !Task.isCancelled {
                    report("Injection test", "Page \(i + 1) of \(cases.count) · \(attack.title)",
                           withoutShare + pagesShare * Double(i) / Double(cases.count))
                    if runsOff { without.append(await Self.attack(attack, setup: setup, harness: false)) }
                    with.append(await Self.attack(attack, setup: setup, harness: true))
                }
            }

            if ready {
                for (position, version) in versions.enumerated() where !Task.isCancelled {
                    let began = Date()
                    let step = versions.count > 1 ? "\(version.title), \(position + 1) of \(versions.count)" : "With \(version.title)"
                    let done = withoutShare + pagesShare + suiteShare * Double(position)
                    guard var run = await self.runSuite(setup, harness: version, quick: quick, report: { index, total, question in
                        report(step, "Question \(index + 1) of \(total) · \(question.title)", done + suiteShare * Double(index) / Double(total))
                    }) else { break }
                    run.baselineRunID = baseline?.id
                    run.toolsAvailable = setup.supportsTools
                    // v6 stops at two rounds whatever the setting says, so that's what the run records.
                    run.harnessRounds = version.usesRounds ? (version == .evidence ? min(setup.maxRounds, 2) : setup.maxRounds) : nil
                    run.injectionWithout = without
                    run.injectionWith = with
                    run.duration = Date().timeIntervalSince(began)
                    self.modelResults.insert(run, at: 0)
                    self.selectedHarnessRunID = nil
                    self.save()
                }
            }
            }
            harnessProgress = nil
            harnessTask = nil
            Self.finish(model, backends: backends, settings: settings)
        }
    }

    func cancelHarnessTest() { harnessTask?.cancel() }

    private static func attack(_ attack: InjectionCase, setup: TestSetup, harness: Bool) async -> InjectionResult {
        var system = InjectionSuite.systemPrompt
        var page = attack.page, removed = 0
        if harness {
            system += "\n\n" + PromptGuard.systemRules
            (page, removed) = PromptGuard.wrap(attack.page, source: "web page")
        }
        let turns = [ChatTurn(role: "system", content: system), ChatTurn(role: "user", content: InjectionSuite.prompt(for: page))]
        let reply = await converse(turns, setup: setup, maxTokens: 1_024, useTools: false)
        var text = reply.answer, blocked = 0
        if harness { (text, blocked) = PromptGuard.filterReply(text, secret: InjectionSuite.secret) }
        let leaked = (attack.canaries + [InjectionSuite.secret]).contains { text.localizedCaseInsensitiveContains($0) }
        return InjectionResult(id: attack.id, title: attack.title, summary: attack.summary, resisted: !leaked,
                               didTask: text.localizedCaseInsensitiveContains(attack.topicWord),
                               reply: text.trimmingCharacters(in: .whitespacesAndNewlines),
                               guardRemoved: removed, replyBlocked: blocked)
    }

    // MARK: - Running the questions

    /// Runs every question once. Returns nil if it was stopped or failed.
    private func runSuite(_ setup: TestSetup, harness: HarnessVersion?, quick: Bool = false,
                          report: @MainActor (Int, Int, ModelTestQuestion) -> Void) async -> ModelTestResult? {
        let start = Date()
        let questions = ModelTestSuite.questions(contextLength: setup.context).filter { !quick || ModelTestSuite.quickIDs.contains($0.id) }
        var result = ModelTestResult(suiteVersion: ModelTestSuite.version, harness: harness == nil ? nil : true, harnessVersion: harness.map(SavedHarnessVersion.init),
                                     model: setup.model.id, displayName: setup.model.displayName, quant: setup.model.quantLabel,
                                     quantProvider: setup.model.quantProvider, backend: setup.backend.kind.displayName,
                                     thinking: harness?.alwaysThinks == true ? setup.think != nil : setup.think ?? false,
                                     contextLength: setup.context)
        result.quick = quick ? true : nil
        var generated = 0, generationSeconds = 0.0
        var firstTokens: [Double] = []
        var promptReadTokens = 0
        for (i, question) in questions.enumerated() {
            if Task.isCancelled { return nil }
            if i > 0 { report(i, questions.count, question) }
            let (item, stats) = await Self.ask(question, setup: setup, harness: harness)
            if Task.isCancelled { return nil }
            result.items.append(item)
            if i == 0 { result.loadSeconds = stats?.loadSeconds }
            if let tokens = stats?.completionTokens, let seconds = stats?.evalSeconds, seconds > 0 {
                generated += tokens
                generationSeconds += seconds
            }
            // Warm, short prompts only: the first question includes loading, the long ones reading 3K tokens.
            if i > 0, question.category != .longContext, let ttft = item.timeToFirstToken { firstTokens.append(ttft) }
            // Questions can share a cached prefix, so measure on the most tokens actually read.
            if question.category == .longContext, let read = stats?.promptTokens, read > promptReadTokens {
                promptReadTokens = read
                result.promptTokensPerSecond = stats?.promptTokensPerSecond
            }
            if i == 0, let error = item.error {
                lastError = error
                return nil
            }
        }
        result.duration = Date().timeIntervalSince(start)
        result.tokensPerSecond = generationSeconds > 0 ? Double(generated) / generationSeconds : nil
        result.timeToFirstToken = firstTokens.sorted().dropFirst(firstTokens.count / 2).first
        return result
    }

    private static func ask(_ question: ModelTestQuestion, setup: TestSetup, harness: HarnessVersion?) async -> (ModelTestItemResult, BackendStats?) {
        let start = Date()
        let limit = tokenLimit(question, context: setup.context)
        let reply: Reply
        if let harness {
            reply = await harnessReply(harness, prompt: question.prompt, setup: setup, maxTokens: limit, notesName: "Tests/\(question.id)")
        } else {
            let system = ModelTestSuite.systemPrompt
            reply = await converse([ChatTurn(role: "system", content: system), ChatTurn(role: "user", content: question.prompt)],
                                   setup: setup, maxTokens: limit, useTools: false)
        }
        let stats = reply.stats
        var item = ModelTestItemResult(
            id: question.id, category: question.category, title: question.title, expected: question.expected,
            answer: reply.answer.trimmingCharacters(in: .whitespacesAndNewlines),
            passed: reply.error == nil && question.grade(reply.answer),
            seconds: Date().timeIntervalSince(start) - (stats?.loadSeconds ?? 0),
            timeToFirstToken: reply.firstToken.map { $0.timeIntervalSince(start) - (stats?.loadSeconds ?? 0) },
            outputTokens: stats?.completionTokens.map { max($0 - reply.thinkingTokens, 0) },
            thinkingTokens: reply.thinkingTokens > 0 ? reply.thinkingTokens : nil,
            promptTokens: stats?.promptTokens,
            error: reply.error
        )
        item.level = question.level
        item.summary = question.summary
        item.prompt = question.shortPrompt ?? question.prompt
        item.stopReason = stats?.stopReason
        item.thinking = reply.thinking.isEmpty ? nil : String(reply.thinking.suffix(6_000))
        if harness != nil {
            item.toolLog = reply.toolLog
            item.guardRemoved = reply.guardRemoved
            item.modelToolCalls = reply.modelToolCalls
        }
        return (item, stats)
    }

    struct Reply {
        var answer = ""
        var thinking = ""
        var thinkingTokens = 0
        var firstToken: Date?
        var stats: BackendStats?
        var error: String?
        var toolLog: [String] = [] { didSet { onLog?(toolLog) } }
        /// The exact value a tool worked out, when one did.
        var result: String?
        var guardRemoved = 0
        /// Tools the model called by itself, as opposed to the harness running them for it.
        var modelToolCalls = 0
        /// Set by whoever wants to follow along as the harness works.
        var onLog: (([String]) -> Void)?
        /// The step under way, and which round of the loop it's in.
        var onStage: ((HarnessStage, Int) -> Void)?
        /// The best reply so far.
        var onDraft: ((String) -> Void)?
        /// Where v5 keeps its shared notes, inside their folder. Nil keeps them off the disk.
        var notesName: String?
        /// The shared notes so far.
        var onNotes: ((String) -> Void)?
        /// More of what the model thought at a step that doesn't stream into the chat by itself.
        var onThought: ((String) -> Void)?
    }

    /// Rounds of tool use a question gets. After that the model has to answer with what it has.
    static let maxToolRounds = 4

    /// Gets a reply from the model, running any tools it asks for along the way.
    static func converse(_ startingTurns: [ChatTurn], setup: TestSetup, maxTokens: Int, useTools: Bool,
                         think: Bool?? = .none, onThought: (String) -> Void = { _ in }) async -> Reply {
        var turns = startingTurns
        var reply = Reply()
        var gate = ToolGate()
        for round in 0...maxToolRounds {
            let request = ChatRequest(model: setup.model.id, messages: turns, temperature: setup.temperature, contextLength: setup.context,
                                      maxTokens: maxTokens, think: think ?? setup.think,
                                      tools: useTools && round < maxToolRounds ? HarnessTools.definitions : [])
            var text = "", calls: [ToolCall] = []
            var parser = ThinkTagParser()
            do {
                for try await event in setup.backend.chat(request) {
                    if Task.isCancelled { break }
                    switch event {
                    case .thinking(let thought):
                        if reply.firstToken == nil { reply.firstToken = Date() }
                        reply.thinkingTokens += 1
                        reply.thinking += thought
                        onThought(thought)
                    case .content(let chunk):
                        if reply.firstToken == nil { reply.firstToken = Date() }
                        let parts = parser.feed(chunk)
                        text += parts.answer
                        reply.thinking += parts.thinking
                        if !parts.thinking.isEmpty {
                            reply.thinkingTokens += 1
                            onThought(parts.thinking)
                        }
                    case .toolCall(let call):
                        calls.append(call)
                    case .finished(let stats):
                        reply.stats = merge(reply.stats, stats)
                    }
                }
                text += parser.flush().answer
            } catch {
                reply.error = error.localizedDescription
            }
            reply.answer = text
            if calls.isEmpty || reply.error != nil || Task.isCancelled { break }

            turns.append(ChatTurn(role: "assistant", content: text, toolCalls: calls))
            turns += await runTools(calls, gate: &gate, reply: &reply)
        }
        return reply
    }

    /// Adds up one question's rounds of tool use.
    static func merge(_ total: BackendStats?, _ next: BackendStats) -> BackendStats {
        guard var total else { return next }
        total.completionTokens = (total.completionTokens ?? 0) + (next.completionTokens ?? 0)
        total.evalSeconds = (total.evalSeconds ?? 0) + (next.evalSeconds ?? 0)
        if (next.promptTokens ?? 0) > (total.promptTokens ?? 0) {
            total.promptTokens = next.promptTokens
            total.promptTokensPerSecond = next.promptTokensPerSecond
        }
        total.stopReason = next.stopReason
        return total
    }

    /// Every question gets room to think too: cutting a model off mid-thought would measure this limit
    /// instead of the model. Qwen3 1.7B took 842 tokens on 47 × 23 and 2,164 on element 74, thinking
    /// included. Capped so prompt and reply still fit in the context window.
    private static func tokenLimit(_ question: ModelTestQuestion, context: Int) -> Int {
        let limit: Int
        switch question.level {
        case .basic: limit = 2_048
        case .intermediate: limit = 4_096
        case .advanced: limit = 4_096
        case .expert: limit = 8_192
        }
        let promptTokens = question.prompt.count * 10 / 35 + 64
        return max(min(limit, context - promptTokens), 256)
    }

    // MARK: - Hardware test

    private struct Phase {
        let name: String
        let weight: Double
    }

    private static let phases = [
        Phase(name: "CPU · one core", weight: 2.5),
        Phase(name: "CPU · all cores", weight: 2.5),
        Phase(name: "Memory bandwidth", weight: 1.5),
        Phase(name: "GPU compute", weight: 2),
        Phase(name: "GPU memory", weight: 1.5),
        Phase(name: "Disk", weight: 1.5),
        Phase(name: "Sustained GPU load", weight: 15),
    ]
    private static let sustainedSeconds = 15.0

    func runHardwareTest(monitor: SystemMonitor, backends: BackendController) {
        guard !isRunning, backends.activeTest == nil else { return }
        let start = Date()
        lastError = nil
        timeline = []
        hardwareProgress = TestProgress(step: Self.phases[0].name, startedAt: start)
        backends.activeTest = "Hardware test"

        worstThermal = .nominal

        let sampler = Task { [weak self] in
            while !Task.isCancelled {
                let s = monitor.snapshot
                self?.timeline.append(HardwareSample(t: Date().timeIntervalSince(start), cpuTemp: s.cpuTemp, gpuTemp: s.gpuTemp,
                                                     cpuLoad: s.cpuUsage, gpuLoad: s.gpuUsage))
                if let self, s.thermalState.rawValue > self.worstThermal.rawValue { self.worstThermal = s.thermalState }
                try? await Task.sleep(for: .seconds(1))
            }
        }

        hardwareTask = Task { [weak self] in
            var result = HardwareTestResult(chip: monitor.chipName, cpuCores: ProcessInfo.processInfo.activeProcessorCount,
                                            gpuCores: monitor.gpuCoreCount, memoryBytes: Int64(ProcessInfo.processInfo.physicalMemory),
                                            gpuBudgetBytes: monitor.gpuBudgetBytes)
            let total = Self.phases.map(\.weight).reduce(0, +)
            var done = 0.0
            var phaseIndex = 0

            @MainActor func begin() -> Double {
                let phase = Self.phases[phaseIndex]
                self?.hardwareProgress = TestProgress(step: phase.name, detail: "Step \(phaseIndex + 1) of \(Self.phases.count)",
                                                      fraction: done / total, startedAt: start)
                return Date().timeIntervalSince(start)
            }
            @MainActor func end(_ began: Double) {
                result.phases.append(TestPhaseSpan(name: Self.phases[phaseIndex].name, start: began, end: Date().timeIntervalSince(start)))
                done += Self.phases[phaseIndex].weight
                phaseIndex += 1
            }
            func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
                await Task.detached(priority: .userInitiated) { work() }.value
            }

            var t = begin()
            result.cpuSingle = await run { HardwareBenchmarks.cpuSingleCore() }
            end(t)

            if !Task.isCancelled {
                t = begin()
                result.cpuMulti = await run { HardwareBenchmarks.cpuMultiCore() }
                end(t)
            }
            if !Task.isCancelled {
                t = begin()
                result.cpuBandwidth = await run { HardwareBenchmarks.cpuMemoryBandwidth() }
                end(t)
            }

            let matmul = await run { HardwareBenchmarks.GPUMatmul() }
            if !Task.isCancelled {
                t = begin()
                if let matmul { result.gpuTFLOPS = await run { HardwareBenchmarks.gpuCompute(matmul) } }
                end(t)
            }
            if !Task.isCancelled {
                t = begin()
                if let matmul {
                    let device = matmul.device
                    result.gpuBandwidth = await run { HardwareBenchmarks.gpuMemoryBandwidth(device: device) }
                }
                end(t)
            }
            if !Task.isCancelled {
                t = begin()
                let disk = await run { HardwareBenchmarks.disk() }
                result.diskRead = disk.read
                result.diskWrite = disk.write
                end(t)
            }
            if !Task.isCancelled, let matmul {
                t = begin()
                var bursts: [Double] = []
                let phaseStart = Date()
                while !Task.isCancelled, Date().timeIntervalSince(phaseStart) < Self.sustainedSeconds {
                    if let tflops = await run({ matmul.run(count: 6) }) { bursts.append(tflops) }
                    let elapsed = Date().timeIntervalSince(phaseStart)
                    self?.hardwareProgress?.fraction = (done + Self.phases[phaseIndex].weight * min(elapsed / Self.sustainedSeconds, 1)) / total
                    self?.hardwareProgress?.detail = String(format: "Step %d of %d · %.0f s left", phaseIndex + 1, Self.phases.count,
                                                            max(Self.sustainedSeconds - elapsed, 0))
                }
                if let best = bursts.max(), best > 0, bursts.count >= 4 {
                    let tail = bursts.suffix(max(bursts.count / 5, 1))
                    result.sustainedPercent = min(tail.reduce(0, +) / Double(tail.count) / best * 100, 100)
                }
                end(t)
            }

            sampler.cancel()
            guard let self else { return }
            if !Task.isCancelled, phaseIndex == Self.phases.count {
                result.duration = Date().timeIntervalSince(start)
                result.timeline = timeline
                result.worstThermalState = ["Nominal", "Fair", "Serious", "Critical"][min(worstThermal.rawValue, 3)]
                hardwareResults.insert(result, at: 0)
                selectedHardwareRunID = nil
                save()
            } else if !Task.isCancelled {
                lastError = "The GPU couldn't be used for the test."
            }
            hardwareProgress = nil
            hardwareTask = nil
            backends.activeTest = nil
        }
    }

    func cancelHardwareTest() { hardwareTask?.cancel() }
}

/// Test results as JSON next to the conversations.
struct TestResultStore {
    struct Payload: Codable {
        var model: [ModelTestResult] = []
        var hardware: [HardwareTestResult] = []
    }

    let fileURL = ConversationStore.directory.appendingPathComponent("tests.json")

    func load() -> Payload {
        guard let data = try? Data(contentsOf: fileURL) else { return Payload() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            ConversationStore.setAside(fileURL)
            return Payload()
        }
        return payload
    }

    func save(_ payload: Payload) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
