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
    private(set) var lastError: String?

    /// The model the model test runs on; nil means the chat's model.
    var testModelID: String?
    /// The run each dashboard shows in detail; nil means the newest.
    var selectedModelRunID: UUID?
    var selectedHardwareRunID: UUID?

    private var modelTask: Task<Void, Never>?
    private var hardwareTask: Task<Void, Never>?
    private var timeline: [HardwareSample] = []
    private var worstThermal = ProcessInfo.ThermalState.nominal
    private let store = TestResultStore()

    init() {
        let saved = store.load()
        modelResults = saved.model.sorted { $0.date > $1.date }
        hardwareResults = saved.hardware.sorted { $0.date > $1.date }
    }

    var isRunning: Bool { modelProgress != nil || hardwareProgress != nil }

    func testModel(in backends: BackendController) -> LocalModel? {
        backends.models.first { $0.id == testModelID && backends.isSelectable($0) } ?? backends.selectedModel
    }

    /// Picks the model to test and shows its newest run, if it has one.
    func chooseTestModel(_ model: LocalModel) {
        testModelID = model.id
        selectedModelRunID = latestModelResult(for: model.id)?.id
    }

    /// Shows a past run, and makes its model the one to test next.
    func show(_ run: ModelTestResult) {
        selectedModelRunID = run.id
        testModelID = run.model
    }

    var selectedModelRun: ModelTestResult? {
        modelResults.first { $0.id == selectedModelRunID } ?? modelResults.first
    }

    var selectedHardwareRun: HardwareTestResult? {
        hardwareResults.first { $0.id == selectedHardwareRunID } ?? hardwareResults.first
    }

    func latestModelResult(for modelID: String?) -> ModelTestResult? {
        modelResults.first { $0.model == modelID }
    }

    /// Newest run of each model + quant + framework, best score first.
    var leaderboard: [ModelTestResult] {
        var seen = Set<String>()
        return modelResults.filter { seen.insert($0.configurationKey).inserted }
            .sorted { ($0.score, $0.tokensPerSecond ?? 0) > ($1.score, $1.tokensPerSecond ?? 0) }
    }

    func delete(modelRun id: UUID) {
        modelResults.removeAll { $0.id == id }
        if selectedModelRunID == id { selectedModelRunID = nil }
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

    func runModelTest(backends: BackendController, settings: AppSettings) {
        guard !isRunning, backends.activeTest == nil, let model = testModel(in: backends) else { return }
        let backend = backends.backend
        let start = Date()
        lastError = nil
        modelProgress = TestProgress(step: "Loading \(model.displayName)…", startedAt: start)
        backends.activeTest = "Model test"

        modelTask = Task { [weak self] in
            let (context, supportsThinking) = await backends.capabilities(of: model)
            let think: Bool? = backend.kind == .ollama && supportsThinking ? settings.thinkingEnabled : nil
            let questions = ModelTestSuite.questions(contextLength: context)

            // Two models at once would compete for memory and skew the numbers.
            if settings.unloadOnSwitch {
                for other in (try? await backend.loadedModels()) ?? [] where other.name != model.id {
                    await backends.unload(other.name)
                }
            }

            var result = ModelTestResult(model: model.id, displayName: model.displayName, quant: model.quantLabel,
                                         quantProvider: model.quantProvider, backend: backend.kind.displayName,
                                         thinking: think ?? false, contextLength: context)
            var generated = 0, generationSeconds = 0.0
            var firstTokens: [Double] = []
            for (i, question) in questions.enumerated() {
                if Task.isCancelled { break }
                if i > 0 {
                    self?.modelProgress = TestProgress(step: question.category.name,
                                                       detail: "Question \(i + 1) of \(questions.count) · \(question.title)",
                                                       fraction: Double(i) / Double(questions.count), startedAt: start)
                }
                let (item, stats) = await Self.ask(question, backend: backend, model: model.id, context: context, think: think)
                if Task.isCancelled { break }
                result.items.append(item)
                if i == 0 { result.loadSeconds = stats?.loadSeconds }
                if let tokens = stats?.completionTokens, let seconds = stats?.evalSeconds, seconds > 0 {
                    generated += tokens
                    generationSeconds += seconds
                }
                // Warm, short prompts only: the first question includes loading, the long one reading 3K tokens.
                if i > 0, question.category != .longContext, let ttft = item.timeToFirstToken { firstTokens.append(ttft) }
                if question.category == .longContext { result.promptTokensPerSecond = stats?.promptTokensPerSecond }
                if i == 0, item.error != nil, let error = item.error {
                    self?.lastError = error
                    break
                }
            }

            guard let self else { return }
            let complete = result.items.count == questions.count
            if complete {
                result.duration = Date().timeIntervalSince(start)
                result.tokensPerSecond = generationSeconds > 0 ? Double(generated) / generationSeconds : nil
                result.timeToFirstToken = firstTokens.sorted().dropFirst(firstTokens.count / 2).first
                modelResults.insert(result, at: 0)
                selectedModelRunID = nil
                save()
            }
            if settings.unloadOnSwitch, model.id != backends.selectedModel?.id {
                // A new task, so this still runs after Stop cancelled the current one.
                Task { await backends.unload(model.id) }
            }
            modelProgress = nil
            modelTask = nil
            backends.activeTest = nil
        }
    }

    func cancelModelTest() { modelTask?.cancel() }

    private static func ask(_ question: ModelTestQuestion, backend: LLMBackend, model: String, context: Int,
                            think: Bool?) async -> (ModelTestItemResult, BackendStats?) {
        let request = ChatRequest(
            model: model,
            messages: [ChatTurn(role: "system", content: ModelTestSuite.systemPrompt), ChatTurn(role: "user", content: question.prompt)],
            temperature: 0,
            contextLength: context,
            maxTokens: think == true ? 2_048 : 400,
            think: think
        )
        let start = Date()
        var firstToken: Date?
        var answer = "", thinkingTokens = 0
        var parser = ThinkTagParser()
        var stats: BackendStats?
        var errorText: String?
        do {
            for try await event in backend.chat(request) {
                if Task.isCancelled { break }
                switch event {
                case .thinking:
                    if firstToken == nil { firstToken = Date() }
                    thinkingTokens += 1
                case .content(let chunk):
                    if firstToken == nil { firstToken = Date() }
                    let parts = parser.feed(chunk)
                    answer += parts.answer
                    if !parts.thinking.isEmpty { thinkingTokens += 1 }
                case .finished(let s):
                    stats = s
                }
            }
            answer += parser.flush().answer
        } catch {
            errorText = error.localizedDescription
        }
        let completion = stats?.completionTokens
        let item = ModelTestItemResult(
            id: question.id, category: question.category, title: question.title, expected: question.expected,
            answer: answer.trimmingCharacters(in: .whitespacesAndNewlines),
            passed: errorText == nil && question.grade(answer),
            seconds: Date().timeIntervalSince(start) - (stats?.loadSeconds ?? 0),
            timeToFirstToken: firstToken.map { $0.timeIntervalSince(start) - (stats?.loadSeconds ?? 0) },
            outputTokens: completion.map { max($0 - thinkingTokens, 0) },
            thinkingTokens: thinkingTokens > 0 ? thinkingTokens : nil,
            promptTokens: stats?.promptTokens,
            error: errorText
        )
        return (item, stats)
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
        return (try? decoder.decode(Payload.self, from: data)) ?? Payload()
    }

    func save(_ payload: Payload) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
