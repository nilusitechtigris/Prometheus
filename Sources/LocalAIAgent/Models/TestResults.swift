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

/// One run of the model test: a fixed set of auto-graded questions, plus the speed numbers
/// measured while answering them.
struct ModelTestResult: Codable, Identifiable, Equatable {
    var id = UUID()
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
    var score: Double { items.isEmpty ? 0 : Double(passed) / Double(items.count) * 100 }

    func score(for category: ModelTestCategory) -> Double? {
        let inCategory = items.filter { $0.category == category }
        guard !inCategory.isEmpty else { return nil }
        return Double(inCategory.filter(\.passed).count) / Double(inCategory.count) * 100
    }

    /// Identifies the exact model + quant + framework + thinking setup, for the leaderboard.
    var configurationKey: String { "\(backend)|\(model)|\(thinking)" }
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
}

/// Live progress of a running test.
struct TestProgress: Equatable {
    var step: String
    var detail: String = ""
    var fraction: Double = 0
    var startedAt = Date()
}

enum TestScoring {
    /// Overall model score bands: ≥ 80 % good, 50–80 % fair, below that weak.
    static let modelScore = Threshold(warning: 80, critical: 50, higherIsWorse: false, displayMax: 100)
    /// Sustained GPU throughput: below 90 % of the best burst means the chip is throttling.
    static let sustained = Threshold(warning: 90, critical: 75, higherIsWorse: false, displayMax: 100)
}
