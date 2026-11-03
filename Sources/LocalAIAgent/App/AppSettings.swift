import Foundation
import Observation

/// User preferences, persisted to UserDefaults.
@MainActor
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    static let defaultSystemPrompt = "You are a helpful, accurate and concise assistant running locally on the user's Mac. Use Markdown for structure and code blocks for code."
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
    var showInspector: Bool { didSet { defaults.set(showInspector, forKey: "showInspector") } }
    /// Unload the previous model when switching, so two models don't compete for unified memory.
    var unloadOnSwitch: Bool { didSet { defaults.set(unloadOnSwitch, forKey: "unloadOnSwitch") } }

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
        showInspector = defaults.object(forKey: "showInspector") as? Bool ?? true
        unloadOnSwitch = defaults.object(forKey: "unloadOnSwitch") as? Bool ?? true
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
