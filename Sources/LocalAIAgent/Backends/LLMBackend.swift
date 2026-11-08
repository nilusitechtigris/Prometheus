import Foundation

enum BackendKind: String, CaseIterable, Identifiable, Codable {
    case ollama, lmStudio, llamaCpp, mlx

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .llamaCpp: return "llama.cpp"
        case .mlx: return "MLX LM"
        }
    }

    var tagline: String {
        switch self {
        case .ollama: return "Recommended · one-click model downloads"
        case .lmStudio: return "OpenAI-compatible server · GGUF & MLX"
        case .llamaCpp: return "llama-server · maximum control"
        case .mlx: return "Apple MLX · one-click model downloads"
        }
    }

    var symbol: String {
        switch self {
        case .ollama: return "shippingbox.fill"
        case .lmStudio: return "macwindow"
        case .llamaCpp: return "terminal.fill"
        case .mlx: return "cpu.fill"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .ollama: return "http://127.0.0.1:11434"
        case .lmStudio: return "http://127.0.0.1:1234"
        case .llamaCpp: return "http://127.0.0.1:8080"
        case .mlx: return "http://127.0.0.1:8081"
        }
    }

    var setupSteps: [String] {
        switch self {
        case .ollama:
            return ["brew install ollama", "brew services start ollama"]
        case .lmStudio:
            return ["Install LM Studio from lmstudio.ai", "Developer tab → Start Server (port 1234)", "Load a model in LM Studio"]
        case .llamaCpp:
            return ["brew install llama.cpp", "llama-server -hf ggml-org/gemma-3-4b-it-GGUF -c 8192 --port 8080"]
        case .mlx:
            return ["brew install mlx-lm", "mlx_lm.server --port 8081"]
        }
    }

    /// Whether the app can set the context window per request. LM Studio and llama.cpp fix it when the
    /// model is loaded. MLX LM has no window of its own, so the app's limit is the one that applies.
    var supportsPerRequestContext: Bool { self == .ollama || self == .mlx }
    /// Whether thinking can be turned on and off for each request.
    var supportsThinkingControl: Bool { self == .ollama || self == .mlx }
    /// Whether the harness can give models tools through this framework.
    var supportsTools: Bool { self == .ollama || self == .mlx }
    var supportsModelDownloads: Bool { self == .ollama || self == .mlx }
}

struct LocalModel: Identifiable, Hashable {
    let id: String
    var sizeBytes: Int64?
    var parameterSize: String?
    var quantization: String?
    var family: String?
    /// Who published the quantized weights, as reported by the framework (e.g. "lmstudio-community").
    var publisher: String?

    var catalog: CatalogModel? { ModelCatalog.entry(matchingID: id) }
    var variant: QuantVariant? { ModelCatalog.variant(forTag: id) }
    var isVerified: Bool { catalog != nil }
    var displayName: String { catalog?.displayName ?? id }

    /// Quantization label, always available when it can be determined.
    var quantLabel: String {
        variant?.quant ?? quantization.map(QuantParser.normalise) ?? QuantParser.quant(in: id) ?? "Unknown quant"
    }

    /// Who produced the quantized file.
    var quantProvider: String {
        variant?.quantizedBy ?? publisher ?? QuantParser.provider(in: id) ?? "Unknown"
    }
}

struct ModelDetails: Equatable {
    var maxContext: Int?
    var supportsThinking = false
    var capabilities: [String] = []
}

struct LoadedModel: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let sizeBytes: Int64
    let vramBytes: Int64
    let contextLength: Int?
    let expiresAt: Date?
}

struct ChatTurn: Encodable {
    let role: String
    let content: String
    /// Tool calls the assistant made in this turn, sent back so the model sees what it asked for.
    var toolCalls: [ToolCall] = []
    /// On a "tool" turn: which tool produced the content.
    var toolName: String?
}

/// A request from the model to run a tool. Arguments are kept as text.
struct ToolCall: Encodable, Equatable {
    let name: String
    let arguments: [String: String]
}

struct ToolDefinition {
    struct Parameter {
        let name: String
        let description: String
    }

    let name: String
    let description: String
    let parameters: [Parameter]

    /// As Ollama and OpenAI-style servers want it.
    var json: [String: Any] {
        let properties = Dictionary(uniqueKeysWithValues: parameters.map {
            ($0.name, ["type": "string", "description": $0.description])
        })
        return ["type": "function",
                "function": ["name": name, "description": description,
                             "parameters": ["type": "object", "properties": properties,
                                            "required": parameters.map(\.name)]]]
    }
}

struct ChatRequest {
    var model: String
    var messages: [ChatTurn]
    var temperature: Double
    var contextLength: Int
    var maxTokens: Int?
    var think: Bool?
    var tools: [ToolDefinition] = []
}

struct BackendStats {
    var promptTokens: Int?
    var completionTokens: Int?
    var promptEvalSeconds: Double?
    var evalSeconds: Double?
    var loadSeconds: Double?
    var totalSeconds: Double?
    var promptTokensPerSecond: Double?
    var tokensPerSecond: Double?
    var stopReason: String?
}

enum StreamEvent {
    case thinking(String)
    case content(String)
    case toolCall(ToolCall)
    case finished(BackendStats)
}

enum BackendError: LocalizedError {
    case http(Int, String)
    case badResponse
    case notSupported(String)
    /// MLX LM's generation stopped after an error, with the reason from its log when there is one.
    case serverStopped(String?)
    /// MLX LM answers 404 when it can't load or run a model, whatever the reason.
    case couldNotRun(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            let detail = body.isEmpty ? "" : " — \(body.prefix(300))"
            return "Server returned HTTP \(code)\(detail)"
        case .badResponse: return "Unexpected response from the server."
        case .notSupported(let what): return "\(what) isn't supported by this framework."
        case .serverStopped(let reason):
            return "MLX LM's server stopped generating after an error" + (reason.map { " (\($0))" } ?? "")
                + ". Prometheus restarts it, so the next request starts fresh."
        case .couldNotRun(let reason): return "MLX LM couldn't run the model: \(reason.prefix(300))"
        }
    }
}

protocol LLMBackend: Sendable {
    var kind: BackendKind { get }
    var baseURL: URL { get }
    func ping() async throws -> String
    func listModels() async throws -> [LocalModel]
    func details(for model: String) async throws -> ModelDetails
    func loadedModels() async throws -> [LoadedModel]
    func chat(_ request: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error>
}

extension LLMBackend {
    func details(for model: String) async throws -> ModelDetails { ModelDetails() }
    func loadedModels() async throws -> [LoadedModel] { [] }
}

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300      // idle time between bytes (covers slow model loads)
        config.timeoutIntervalForResource = 60 * 60 * 6
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func request(_ url: URL, method: String = "GET", json: Any? = nil, timeout: TimeInterval? = nil) throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let timeout { req.timeoutInterval = timeout }
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        return req
    }

    static func data(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw BackendError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    static func json(_ req: URLRequest) async throws -> [String: Any] {
        let data = try await data(req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BackendError.badResponse }
        return obj
    }

    /// Streams newline-delimited lines, surfacing HTTP errors with their body.
    static func lines(_ req: URLRequest) async throws -> AsyncLineSequence<URLSession.AsyncBytes> {
        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw BackendError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            var body = ""
            for try await line in bytes.lines { body += line; if body.count > 2000 { break } }
            throw BackendError.http(http.statusCode, extractError(body))
        }
        return bytes.lines
    }

    static func extractError(_ body: String) -> String {
        if let data = body.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let e = obj["error"] as? String { return e }
            if let e = obj["error"] as? [String: Any], let m = e["message"] as? String { return m }
        }
        return body
    }
}

extension Dictionary where Key == String, Value == Any {
    func int(_ key: String) -> Int? {
        if let v = self[key] as? Int { return v }
        if let v = self[key] as? Double { return Int(v) }
        if let v = self[key] as? NSNumber { return v.intValue }
        return nil
    }
    func int64(_ key: String) -> Int64? {
        if let v = self[key] as? NSNumber { return v.int64Value }
        return nil
    }
    func double(_ key: String) -> Double? {
        if let v = self[key] as? NSNumber { return v.doubleValue }
        return nil
    }
}
