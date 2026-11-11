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
    /// True for Harness - Normal, which asks only some of the questions. Its scores don't compare with a
    /// full run's. A plain flag rather than a name, so a later build's new size can't fail the whole file.
    var quick: Bool?
    /// The name of the question set for a run on public questions, such as "heldout-v1". Nil for the app's own tests.
    var questionSet: String?
    /// Runs made together as repeats of one setup share this, and `repeatIndex` counts them from 1. Nil for a single run.
    var repeatGroup: UUID?
    var repeatIndex: Int?
    /// The Python that graded the code questions, for a run on a public set. Nil when none was run.
    var pythonVersion: String?
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
    /// The public question set this run asked, if any. An older build saves runs back without `questionSet`,
    /// so the suite version stands in for it.
    var askedSet: String? { questionSet ?? HeldOut.set(forSuiteVersion: suiteVersion) }
    var isCurrentSuite: Bool {
        guard let askedSet else { return suiteVersion == ModelTestSuite.version }
        return suiteVersion == HeldOut.suiteVersion(askedSet)
    }
    /// Questions that got no reply because the framework failed. They count as wrong, so a run with any is no
    /// fair score to compare against.
    var errorCount: Int { items.filter { $0.error != nil }.count }

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
    var isQuick: Bool { quick == true }
    /// Which of the Harness Test's question sets this run asked. Scores only compare within one.
    var size: HarnessTestSize { askedSet == HeldOut.practice ? .practice : askedSet != nil ? .heldOut : isQuick ? .normal : .max }

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
    var setupLabel: String {
        (thinking ? " · thinking" : "") + (version.map { " · " + (Edition.current.isLab ? "harness \($0.short)" : $0.runTitle().lowercased()) } ?? "")
    }
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
    /// The end of what the model thought, which is where it decides. Nil in runs from before this was kept.
    var thinking: String?

    var weight: Int { level?.weight ?? 1 }
    /// The model hit the test's token limit before it finished.
    var ranOutOfTokens: Bool { ["length", "max_tokens"].contains(stopReason) }
}

/// One line of a set of repeat runs: the scores one setup got, by round. A set can be stopped part way or
/// lose a run later, so a score keeps the number of the round it came from.
struct RepeatRow: Identifiable, Equatable {
    /// Nil for the runs with the harness off.
    let version: HarnessVersion?
    let scores: [Int: Double]

    var id: String { version?.rawValue ?? "off" }
    var title: String { version?.runTitle() ?? "Harness off" }
    var rounds: [Int] { scores.keys.sorted() }
    var mean: Double { scores.values.reduce(0, +) / Double(max(scores.count, 1)) }
    var low: Double { scores.values.min() ?? 0 }
    var high: Double { scores.values.max() ?? 0 }

    /// What the rounds say about this version against the plain model, over the rounds both have. Nil with
    /// fewer than two. It only says which way the rounds went: whether a gap is more than luck is `FlipTest`'s job.
    func verdict(against off: RepeatRow) -> String? {
        let gaps = rounds.compactMap { round in off.scores[round].map { (scores[round] ?? 0) - $0 } }
        guard gaps.count >= 2 else { return nil }
        let size = String(format: "%.1f", abs(gaps.reduce(0, +) / Double(gaps.count)))
        let higher = gaps.filter { $0 > 0 }.count, lower = gaps.filter { $0 < 0 }.count
        if higher == gaps.count { return "\(title) scored higher than the plain model in all \(gaps.count) rounds, by \(size) points on average." }
        if lower == gaps.count { return "\(title) scored lower than the plain model in all \(gaps.count) rounds, by \(size) points on average." }
        if higher == 0, lower == 0 { return "\(title) scored the same as the plain model in all \(gaps.count) rounds." }
        return "\(title) was higher than the plain model in \(higher) of \(gaps.count) rounds and lower in \(lower), so the rounds don't agree."
    }
}

/// Whether a gap between two runs on the same questions is more than luck. It looks only at the questions that
/// flipped: from wrong to right with the harness, or from right to wrong. If the harness changed nothing, a flip
/// would go either way as often as a coin lands heads. This is the exact sign test, also known as McNemar's.
enum FlipTest {
    /// How often chance alone splits this many flips at least this unevenly. Nil when nothing flipped.
    static func chance(gained: Int, lost: Int) -> Double? {
        let flips = gained + lost
        guard flips > 0 else { return nil }
        var term = pow(0.5, Double(flips)), sum = term
        for index in 0..<min(gained, lost) {
            term *= Double(flips - index) / Double(index + 1)
            sum += term
        }
        return min(1, 2 * sum)
    }

    static func sentence(gained: Int, lost: Int) -> String {
        guard let chance = chance(gained: gained, lost: lost) else { return "No question changed between the two runs." }
        func questions(_ count: Int) -> String { "\(count) question\(count == 1 ? "" : "s")" }
        let flips = "\(questions(gained)) went from wrong to right and \(questions(lost)) from right to wrong."
        if chance < 0.001 { return "\(flips) Chance alone would split them this unevenly less than 1 time in 1,000." }
        if chance < 0.05 { return "\(flips) Chance alone would split them this unevenly about 1 time in \(Int((1 / chance).rounded()))." }
        return "\(flips) Chance alone splits them like that about \(max(Int((chance * 100).rounded()), 5)) times in 100, so this run doesn't show a difference by itself."
    }
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
