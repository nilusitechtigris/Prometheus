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
    static let harnessRoundOptions = [1, 2, 3, 5]

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
    /// Runs chat replies through the harness. On for a new install, since its math, code and rule checks stay
    /// on this Mac and it asks before it looks anything up (see `WebConsent`). A copy that was already in use
    /// keeps what it had.
    var harnessEnabled: Bool { didSet { defaults.set(harnessEnabled, forKey: "harnessEnabled") } }
    /// The version picked for chat, which only the lab can change. `activeHarness` is the one that runs.
    var harnessVersion: HarnessVersion { didSet { defaults.set(harnessVersion.rawValue, forKey: "harnessVersion") } }
    /// Whether the Tests page shows the Model Test, the Harness Test and Publish beside the Hardware Test.
    var showLab: Bool { didSet { defaults.set(showLab, forKey: "showLab") } }
    /// Times the harness's loop may go round on a task, in chat and in the Harness Test.
    var harnessMaxRounds: Int { didSet { defaults.set(harnessMaxRounds, forKey: "harnessMaxRounds") } }
    /// The rounds a copy outside the lab gets, where there's no control for them.
    static let usualHarnessRounds = 3
    /// The version chat runs with the harness on. Outside the lab that's the recommended one, whatever is stored.
    var activeHarness: HarnessVersion { HarnessVersion.allowed(harnessVersion) }
    /// The rounds the loop gets, in chat and in the Harness Test.
    var activeRounds: Int { Edition.current.isLab ? harnessMaxRounds : Self.usualHarnessRounds }
    /// Whether the Harness Test also covers the harness off, or only the harness on.
    var harnessTestRunsOff: Bool { didSet { defaults.set(harnessTestRunsOff, forKey: "harnessTestRunsOff") } }
    /// Whether the telemetry panel is open along the bottom of the window, and how tall it is.
    var telemetryOpen: Bool { didSet { defaults.set(telemetryOpen, forKey: "telemetryOpen") } }
    var telemetryHeight: Double { didSet { defaults.set(telemetryHeight, forKey: "telemetryHeight") } }
    static let telemetryHeights = 150.0...420.0
    /// Whether the chats show beside the conversation on the Chat page.
    var chatsOpen: Bool { didSet { defaults.set(chatsOpen, forKey: "chatsOpen") } }

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
        // Every copy that has run before has chosen a theme, so this tells a new install from an update.
        let usedBefore = defaults.object(forKey: "movedToPrometheusTheme") != nil || defaults.object(forKey: "backendKind") != nil
            || FileManager.default.fileExists(atPath: ConversationStore.directory.appendingPathComponent("conversations.json").path)
        harnessEnabled = defaults.object(forKey: "harnessEnabled") as? Bool ?? !usedBefore
        harnessVersion = HarnessVersion(rawValue: defaults.string(forKey: "harnessVersion") ?? "") ?? .recommended
        showLab = defaults.object(forKey: "showLab") as? Bool ?? usedBefore
        let rounds = defaults.integer(forKey: "harnessMaxRounds")
        harnessMaxRounds = rounds > 0 ? rounds : Self.usualHarnessRounds
        harnessTestRunsOff = defaults.object(forKey: "harnessTestRunsOff") as? Bool ?? true
        telemetryOpen = defaults.object(forKey: "telemetryOpen") as? Bool ?? true
        let panelHeight = defaults.double(forKey: "telemetryHeight")
        telemetryHeight = panelHeight > 0 ? min(max(panelHeight, Self.telemetryHeights.lowerBound), Self.telemetryHeights.upperBound) : 216
        chatsOpen = defaults.object(forKey: "chatsOpen") as? Bool ?? true
        // Written down once, so the choice made at the first launch doesn't change at the second.
        if defaults.object(forKey: "harnessEnabled") == nil { defaults.set(harnessEnabled, forKey: "harnessEnabled") }
        if defaults.object(forKey: "showLab") == nil { defaults.set(showLab, forKey: "showLab") }
    }

    /// The part of the default prompt that is only true with the harness off.
    static let offlineClaim = " You have no internet access and no tools: you can't browse, look things up or run code. Nothing the user shares leaves this device."

    /// The prompt for a reply. With the harness on, the default prompt's line about having no tools is left
    /// out: the harness does run code and look things up, and a model told it can't tends to say so anyway.
    func systemPrompt(harnessOn: Bool) -> String { Self.systemPrompt(systemPrompt, harnessOn: harnessOn) }

    static func systemPrompt(_ saved: String, harnessOn: Bool) -> String {
        let prompt = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        return harnessOn ? prompt.replacingOccurrences(of: offlineClaim, with: "") : prompt
    }

    func baseURL(for kind: BackendKind) -> String {
        #if DEBUG
        // For looking at the first-run pages on a Mac that already has everything.
        if kind == .ollama, let url = ProcessInfo.processInfo.environment["LOCALAI_OLLAMA_URL"] { return url }
        #endif
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
