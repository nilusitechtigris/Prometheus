import Foundation

// MARK: - Hardware test

/// One run of the hardware test: how fast this Mac computes, moves memory and reads its disk,
/// and how it holds up thermally under a sustained GPU load.
struct HardwareTestResult: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var chip: String
    var cpuCores: Int
    var gpuCores: Int?
    var memoryBytes: Int64
    var gpuBudgetBytes: Int64

    /// Million Mandelbrot iterations per second on one core / on every core.
    var cpuSingle: Double?
    var cpuMulti: Double?
    /// FP16 matrix multiply throughput on the GPU, TFLOPS (what prompt reading leans on).
    var gpuTFLOPS: Double?
    /// Copy bandwidth, GB/s, counting reads and writes (what token generation leans on).
    var cpuBandwidth: Double?
    var gpuBandwidth: Double?
    /// Sequential disk throughput, GB/s, page cache bypassed (what model loading leans on).
    var diskRead: Double?
    var diskWrite: Double?
    /// GPU throughput at the end of the sustained phase as a share of its best burst.
    var sustainedPercent: Double?

    var timeline: [HardwareSample] = []
    var phases: [TestPhaseSpan] = []
    var duration: Double = 0
    var worstThermalState: String?

    var peakCPUTemp: Double? { timeline.compactMap(\.cpuTemp).max() }
    var peakGPUTemp: Double? { timeline.compactMap(\.gpuTemp).max() }
}

struct HardwareSample: Codable, Equatable, Identifiable {
    var t: Double
    var cpuTemp: Double?
    var gpuTemp: Double?
    var cpuLoad: Double?
    var gpuLoad: Double?
    var id: Double { t }
}

struct TestPhaseSpan: Codable, Equatable, Identifiable {
    var name: String
    var start: Double
    var end: Double
    var id: String { name }
}

// MARK: - Model test

enum ModelTestCategory: String, Codable, CaseIterable, Identifiable {
    case math, reasoning, knowledge, instructions, coding, longContext

    var id: String { rawValue }

    var name: String {
        switch self {
        case .math: return "Math"
        case .reasoning: return "Reasoning"
        case .knowledge: return "Knowledge"
        case .instructions: return "Instructions"
        case .coding: return "Coding"
        case .longContext: return "Long context"
        }
    }

    var symbol: String {
        switch self {
        case .math: return "function"
        case .reasoning: return "brain.head.profile"
        case .knowledge: return "book.closed"
        case .instructions: return "list.bullet.clipboard"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .longContext: return "text.magnifyingglass"
        }
    }
}

/// How hard a question is. Each level is worth twice the one below it.
enum ModelTestLevel: Int, Codable, CaseIterable, Identifiable {
    case basic = 1, intermediate, advanced, expert

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .basic: return "Basic"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        case .expert: return "Expert"
        }
    }

    /// Points for a correct answer: 1, 2, 4, 8.
    var weight: Int { 1 << (rawValue - 1) }
}

/// One run of the model test: a fixed set of auto-graded questions, plus the speed numbers
/// measured while answering them.
struct ModelTestResult: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Version of the question set; nil for runs from before the weighted test.
    var suiteVersion: Int?
    /// True when the run had the harness: tools plus prompt injection protection.
    var harness: Bool?
    /// Which version of the harness ran. Nil for runs from before versions were saved: see `version`.
    var harnessVersion: SavedHarnessVersion?
    /// The run without the harness that this one compares against.
    var baselineRunID: UUID?
    /// False when the model can't use tools, so only the injection guard applied.
    var toolsAvailable: Bool?
    /// Rounds the harness's loop could take on each question. Nil for runs from before the loop.
    var harnessRounds: Int?
    var injectionWithout: [InjectionResult]?
    var injectionWith: [InjectionResult]?
    var date = Date()
    var model: String
    var displayName: String
    var quant: String
    var quantProvider: String
    var backend: String
    var thinking: Bool
    var contextLength: Int
    var items: [ModelTestItemResult] = []
    var duration: Double = 0

    /// Median first-token time over warm, short-prompt questions.
    var timeToFirstToken: Double?
    /// All generated tokens divided by all generation time.
    var tokensPerSecond: Double?
    /// Prompt reading speed on the long-context question.
    var promptTokensPerSecond: Double?
    var loadSeconds: Double?

    var passed: Int { items.filter(\.passed).count }
    var points: Int { items.filter(\.passed).map(\.weight).reduce(0, +) }
    var maxPoints: Int { items.map(\.weight).reduce(0, +) }
    /// Share of the available points. Scores from different suite versions don't compare.
    var score: Double { Self.score(of: items) ?? 0 }
    var isCurrentSuite: Bool { suiteVersion == ModelTestSuite.version }

    func score(for category: ModelTestCategory) -> Double? {
        Self.score(of: items.filter { $0.category == category })
    }

    func score(for level: ModelTestLevel) -> Double? {
        Self.score(of: items.filter { $0.level == level })
    }

    private static func score(of items: [ModelTestItemResult]) -> Double? {
        let total = items.map(\.weight).reduce(0, +)
        guard total > 0 else { return nil }
        return Double(items.filter(\.passed).map(\.weight).reduce(0, +)) / Double(total) * 100
    }

    var usesHarness: Bool { harness == true }

    /// Which version of the harness ran, if any. Older runs are told apart by what they logged: the loop
    /// saved its rounds, and only the pipeline and the loop write down what they understood.
    var version: HarnessVersion? {
        guard usesHarness else { return nil }
        // A run from a build with other versions stays unknown here, rather than passing for an older one.
        if let harnessVersion { return harnessVersion.version }
        if harnessRounds != nil { return .loop }
        return items.contains { ($0.toolLog ?? []).contains { $0.hasPrefix("Understood:") } } ? .pipeline : .tools
    }

    /// Tools the model called by itself, not counting what the harness ran for it. Nil when the run didn't record it.
    var modelToolCalls: Int? {
        if version == .tools { return items.flatMap { $0.toolLog ?? [] }.filter(HarnessTools.isToolCall).count }
        let counts = items.compactMap(\.modelToolCalls)
        return counts.isEmpty ? nil : counts.reduce(0, +)
    }

    /// Identifies the exact model + quant + framework + thinking + harness setup, for the leaderboard.
    var configurationKey: String { "\(backend)|\(model)|\(thinking)|\(version?.rawValue ?? "off")" }

    /// How the run was set up, for labels.
    var setupLabel: String { (thinking ? " · thinking" : "") + (version.map { " · harness \($0.short)" } ?? "") }
}

struct ModelTestItemResult: Codable, Equatable, Identifiable {
    var id: String
    var category: ModelTestCategory
    var title: String
    var expected: String
    var answer: String
    var passed: Bool
    var seconds: Double
    var timeToFirstToken: Double?
    var outputTokens: Int?
    var thinkingTokens: Int?
    var promptTokens: Int?
    var error: String?
    // Absent in runs from before the weighted test.
    var level: ModelTestLevel?
    /// What the question checks.
    var summary: String?
    /// The question as asked, shortened when it's thousands of tokens of notes.
    var prompt: String?
    var stopReason: String?
    /// What the model did with its tools, one line per call.
    var toolLog: [String]?
    /// How much the injection guard removed from what the tools returned.
    var guardRemoved: Int?
    /// Tools the model called by itself. Nil in runs from before this was counted.
    var modelToolCalls: Int?

    var weight: Int { level?.weight ?? 1 }
    /// The model hit the test's token limit before it finished.
    var ranOutOfTokens: Bool { ["length", "max_tokens"].contains(stopReason) }
}

/// One poisoned page from the injection test.
struct InjectionResult: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var summary: String
    /// The reply shows no sign of the attack.
    var resisted: Bool
    /// The reply still does the real task.
    var didTask: Bool
    var reply: String
    /// What the guard took out of the page.
    var guardRemoved: Int
    /// What the reply filter took out of the reply.
    var replyBlocked: Int

    var passed: Bool { resisted && didTask }
}

/// Live progress of a running test.
struct TestProgress: Equatable {
    var step: String
    var detail: String = ""
    var fraction: Double = 0
    var startedAt = Date()
}

enum TestScoring {
    /// Score bands on the frontier scale, where only top models come near 100.
    static let modelScore = Threshold(warning: 50, critical: 25, higherIsWorse: false, displayMax: 100)

    /// Where a score sits on the frontier scale.
    static func tier(_ score: Double) -> String {
        switch score {
        case 100...: return "Frontier"
        case 75...: return "Expert"
        case 50...: return "Advanced"
        case 25...: return "Capable"
        default: return "Basic"
        }
    }

    /// Sustained GPU throughput: below 90 % of the best burst means the chip is throttling.
    static let sustained = Threshold(warning: 90, critical: 75, higherIsWorse: false, displayMax: 100)
}
