import Foundation
import Observation
import SwiftUI

/// User preferences, persisted to UserDefaults.
@MainActor
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    /// Kept short (~350 tokens) because every token here is prompt processing before the first reply.
    static let defaultSystemPrompt = """
        You are a knowledgeable, thoughtful assistant running entirely on the user's Mac. You have no internet access \
        and no tools: you can't browse, look things up or run code. Nothing the user shares leaves this device.

        How to answer
        - Lead with the answer: the direct answer or recommendation first, then the reasoning or details that support it.
        - Be concise by default. Match the length to the question: a sentence or two for simple questions, more depth \
        and structure only when the task needs it. No filler, no restating the question, no generic closing offers.
        - If a request is ambiguous, make a sensible assumption and state it in one line. Ask a clarifying question \
        only when the answer would change completely.
        - For math, logic, debugging or multi-step problems, work through the key steps carefully, check your result, \
        then state the final answer clearly.
        - When there are trade-offs, compare the options briefly and give a clear recommendation.

        Accuracy
        - Accuracy beats confidence. If you're unsure, say so and say what would settle it.
        - Never invent facts, quotes, sources, links, statistics, or function and API names.
        - Your knowledge has a training cutoff. For recent events, prices, versions or anything that changes over time, \
        say your information may be out of date.
        - If the user's premise is wrong, point it out politely and explain why.

        Formatting
        - Use Markdown when it helps: short paragraphs, numbered lists for steps, bullets for options, tables for \
        comparisons, **bold** for key terms. No headings in short answers.
        - Put code, commands and file contents in fenced code blocks with a language tag. Write complete, working code \
        that follows the language's conventions, and explain only the non-obvious parts.
        - Write math in plain text or Unicode (x², √, ≤, π) when possible; use a $$ … $$ block for complex equations.

        Style
        - Be warm, direct and clear, like an expert explaining to a smart colleague.
        - Reply in the language the user writes in.
        - The user's own instructions about format, length, tone or role always take priority over these defaults.
        """
    static let contextOptions = [2_048, 4_096, 8_192, 16_384, 32_768, 65_536, 131_072]

    var backendKind: BackendKind { didSet { defaults.set(backendKind.rawValue, forKey: "backendKind") } }
    var baseURLs: [String: String] { didSet { defaults.set(baseURLs, forKey: "baseURLs") } }
    var selectedModels: [String: String] { didSet { defaults.set(selectedModels, forKey: "selectedModels") } }
    var contextLength: Int { didSet { defaults.set(contextLength, forKey: "contextLength") } }
    var temperature: Double { didSet { defaults.set(temperature, forKey: "temperature") } }
    var systemPrompt: String { didSet { defaults.set(systemPrompt, forKey: "systemPrompt") } }
    var thinkingEnabled: Bool { didSet { defaults.set(thinkingEnabled, forKey: "thinkingEnabled") } }
    var allowUnverifiedModels: Bool { didSet { defaults.set(allowUnverifiedModels, forKey: "allowUnverifiedModels") } }
    var maxResponseTokens: Int { didSet { defaults.set(maxResponseTokens, forKey: "maxResponseTokens") } }
    /// Unload the previous model when switching, so two models don't compete for unified memory.
    var unloadOnSwitch: Bool { didSet { defaults.set(unloadOnSwitch, forKey: "unloadOnSwitch") } }
    /// Whether the stats card under each reply is expanded (applies to every reply).
    var replyStatsExpanded: Bool { didSet { defaults.set(replyStatsExpanded, forKey: "replyStatsExpanded") } }
    /// Runs chat replies through the harness. Off by default because its web searches leave this Mac.
    var harnessEnabled: Bool { didSet { defaults.set(harnessEnabled, forKey: "harnessEnabled") } }
    /// The draft Forge layout, with its near-black look and Geist type.
    var draftLayout: Bool {
        didSet {
            defaults.set(draftLayout, forKey: "draftLayout")
            applyDraftLook()
        }
    }

    init() {
        backendKind = BackendKind(rawValue: defaults.string(forKey: "backendKind") ?? "") ?? .ollama
        baseURLs = defaults.dictionary(forKey: "baseURLs") as? [String: String] ?? [:]
        selectedModels = defaults.dictionary(forKey: "selectedModels") as? [String: String] ?? [:]
        let ctx = defaults.integer(forKey: "contextLength")
        contextLength = ctx > 0 ? ctx : 8_192
        temperature = defaults.object(forKey: "temperature") as? Double ?? 0.7
        systemPrompt = defaults.string(forKey: "systemPrompt") ?? Self.defaultSystemPrompt
        thinkingEnabled = defaults.object(forKey: "thinkingEnabled") as? Bool ?? true
        allowUnverifiedModels = defaults.bool(forKey: "allowUnverifiedModels")
        maxResponseTokens = defaults.integer(forKey: "maxResponseTokens")
        unloadOnSwitch = defaults.object(forKey: "unloadOnSwitch") as? Bool ?? true
        replyStatsExpanded = defaults.object(forKey: "replyStatsExpanded") as? Bool ?? true
        harnessEnabled = defaults.bool(forKey: "harnessEnabled")
        draftLayout = defaults.bool(forKey: "draftLayout")
        applyDraftLook()
    }

    private func applyDraftLook() {
        ThemeStore.shared.preview = draftLayout ? .forge : nil
        Font.usesGeist = draftLayout
    }

    func baseURL(for kind: BackendKind) -> String {
        let value = baseURLs[kind.rawValue]?.trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? kind.defaultBaseURL : value
    }

    func setBaseURL(_ url: String, for kind: BackendKind) {
        baseURLs[kind.rawValue] = url
    }

    var selectedModel: String? {
        get { selectedModels[backendKind.rawValue] }
        set { selectedModels[backendKind.rawValue] = newValue }
    }
}
