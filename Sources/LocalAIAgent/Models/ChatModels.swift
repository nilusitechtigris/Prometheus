import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case system, user, assistant }

    var id = UUID()
    var role: Role
    var content: String
    var thinking: String?
    var createdAt = Date()
    var modelName: String?
    var metrics: GenerationMetrics?
    var errorText: String?
    /// What the harness did for this reply, one line per step. Nil when it was off.
    var harnessSteps: [String]?
    /// The version of the harness that worked on this reply. Nil when it was off.
    var harnessVersion: SavedHarnessVersion?
    /// The file v5's agents shared for this reply, as Markdown. Nil in every other version.
    var sharedNotes: String?
}

struct GenerationMetrics: Codable, Equatable {
    var backend: String
    /// Seconds from sending the request to the first streamed token (thinking or answer).
    var timeToFirstToken: Double?
    var tokensPerSecond: Double?
    var promptTokens: Int?
    var completionTokens: Int?
    var promptTokensPerSecond: Double?
    /// Seconds the backend spent loading the model into memory for this request.
    var loadDuration: Double?
    var totalDuration: Double?
    var thinkingDuration: Double?
    var contextLength: Int?
    var stopReason: String?
    var isEstimated = false
    /// Tokens spent reasoning; the rest of `completionTokens` is the visible answer.
    var thinkingTokens: Int?
    /// Prompt processing + all token generation (model loading excluded).
    var taskDuration: Double?
    var promptDuration: Double?
    var generationDuration: Double?
    /// Sampling temperature the reply was generated with.
    var temperature: Double?

    var contextUsed: Int? {
        guard let p = promptTokens else { return nil }
        return p + (completionTokens ?? 0)
    }

    var outputTokens: Int? {
        completionTokens.map { max($0 - (thinkingTokens ?? 0), 0) }
    }

    /// Falls back to total minus load for replies saved before task time was recorded.
    var taskTime: Double? {
        taskDuration ?? totalDuration.map { max($0 - (loadDuration ?? 0), 0) }
    }

    /// Thinking + answer generation, after the prompt has been read.
    var generationTime: Double? { generationDuration ?? taskTime }

    /// Part of `generationTime` spent reasoning.
    var thinkingTime: Double? {
        guard let t = thinkingDuration, (thinkingTokens ?? 0) > 0 else { return nil }
        return min(t, generationTime ?? t)
    }

    /// Part of `generationTime` spent writing the visible answer.
    var outputTime: Double? {
        generationTime.map { max($0 - (thinkingTime ?? 0), 0) }
    }
}

/// Mean generation metrics over a set of responses.
struct GenerationAverages {
    let responses: Int
    /// Mean time to first token over warm responses (model already in memory).
    let timeToFirstToken: Double?
    /// Responses whose first token waited for the model to load; excluded from the TTFT mean.
    let coldStarts: Int
    let averageLoad: Double?
    let tokensPerSecond: Double?
    let promptTokensPerSecond: Double?
    let completionTokens: Double?
    let totalDuration: Double?

    init?(_ metrics: [GenerationMetrics]) {
        guard !metrics.isEmpty else { return nil }
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }

        let cold = metrics.filter { ($0.loadDuration ?? 0) > 0.5 }
        let warm = metrics.filter { ($0.loadDuration ?? 0) <= 0.5 }
        responses = metrics.count
        coldStarts = cold.count
        // If every response was a cold start, fall back to TTFT minus the load time.
        timeToFirstToken = mean(warm.compactMap(\.timeToFirstToken))
            ?? mean(cold.compactMap { m in m.timeToFirstToken.map { max($0 - (m.loadDuration ?? 0), 0) } })
        averageLoad = mean(cold.compactMap(\.loadDuration))
        tokensPerSecond = mean(metrics.compactMap(\.tokensPerSecond))
        promptTokensPerSecond = mean(metrics.compactMap(\.promptTokensPerSecond))
        completionTokens = mean(metrics.compactMap { $0.outputTokens.map(Double.init) })
        totalDuration = mean(metrics.compactMap(\.generationTime))
    }
}

struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String = "New Chat"
    var createdAt = Date()
    var updatedAt = Date()
    var messages: [ChatMessage] = []

    /// Plain-text snippet of the latest message for the chat list (Markdown symbols stripped).
    var preview: String {
        guard let text = messages.last(where: { $0.role != .system && !$0.content.isEmpty })?.content else { return "" }
        let lines = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("```") && !$0.hasPrefix("|-") }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#>*-|/ ")) }
        return lines.joined(separator: " ")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
    }
}
