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

    var contextUsed: Int? {
        guard let p = promptTokens else { return nil }
        return p + (completionTokens ?? 0)
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
        completionTokens = mean(metrics.compactMap { $0.completionTokens.map(Double.init) })
        totalDuration = mean(metrics.compactMap(\.totalDuration))
    }
}

struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String = "New Chat"
    var createdAt = Date()
    var updatedAt = Date()
    var messages: [ChatMessage] = []

    /// Plain-text snippet of the latest message for the sidebar (Markdown symbols stripped).
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
