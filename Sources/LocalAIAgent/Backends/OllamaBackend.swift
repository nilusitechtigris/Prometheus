import Foundation

struct OllamaBackend: LLMBackend {
    let kind = BackendKind.ollama
    let baseURL: URL

    private func url(_ path: String) -> URL { baseURL.appendingPathComponent(path) }

    func ping() async throws -> String {
        let obj = try await HTTP.json(HTTP.request(url("api/version"), timeout: 2))
        return obj["version"] as? String ?? "online"
    }

    func listModels() async throws -> [LocalModel] {
        let obj = try await HTTP.json(HTTP.request(url("api/tags"), timeout: 5))
        let models = obj["models"] as? [[String: Any]] ?? []
        return models.compactMap { m in
            guard let name = m["name"] as? String else { return nil }
            let details = m["details"] as? [String: Any] ?? [:]
            return LocalModel(
                id: name,
                sizeBytes: m.int64("size"),
                parameterSize: details["parameter_size"] as? String,
                quantization: details["quantization_level"] as? String,
                family: details["family"] as? String,
                // Official library models are quantized by Ollama; `user/model` and `hf.co/user/repo` by their owner.
                publisher: QuantParser.provider(in: name) ?? "Ollama"
            )
        }
        .sorted { $0.id < $1.id }
    }

    func details(for model: String) async throws -> ModelDetails {
        let obj = try await HTTP.json(HTTP.request(url("api/show"), method: "POST", json: ["model": model], timeout: 10))
        var details = ModelDetails()
        details.capabilities = obj["capabilities"] as? [String] ?? []
        details.supportsThinking = details.capabilities.contains("thinking")
        if let info = obj["model_info"] as? [String: Any] {
            for (key, value) in info where key.hasSuffix(".context_length") {
                details.maxContext = (value as? NSNumber)?.intValue
            }
        }
        return details
    }

    func loadedModels() async throws -> [LoadedModel] {
        let obj = try await HTTP.json(HTTP.request(url("api/ps"), timeout: 3))
        let models = obj["models"] as? [[String: Any]] ?? []
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return models.compactMap { m in
            guard let name = m["name"] as? String else { return nil }
            return LoadedModel(
                name: name,
                sizeBytes: m.int64("size") ?? 0,
                vramBytes: m.int64("size_vram") ?? 0,
                contextLength: m.int("context_length"),
                expiresAt: (m["expires_at"] as? String).flatMap { iso.date(from: $0) }
            )
        }
    }

    func chat(_ request: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var options: [String: Any] = [
                        "temperature": request.temperature,
                        "num_ctx": request.contextLength,
                    ]
                    if let max = request.maxTokens { options["num_predict"] = max }
                    var body: [String: Any] = [
                        "model": request.model,
                        "messages": request.messages.map(Self.encode),
                        "stream": true,
                        "options": options,
                        "keep_alive": "10m",
                    ]
                    if let think = request.think { body["think"] = think }
                    if !request.tools.isEmpty { body["tools"] = request.tools.map(\.json) }

                    let lines = try await HTTP.lines(HTTP.request(url("api/chat"), method: "POST", json: body))
                    for try await line in lines {
                        try Task.checkCancellation()
                        guard let data = line.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let error = obj["error"] as? String { throw BackendError.http(500, error) }
                        if let message = obj["message"] as? [String: Any] {
                            if let t = message["thinking"] as? String, !t.isEmpty { continuation.yield(.thinking(t)) }
                            if let c = message["content"] as? String, !c.isEmpty { continuation.yield(.content(c)) }
                            for call in message["tool_calls"] as? [[String: Any]] ?? [] {
                                guard let function = call["function"] as? [String: Any],
                                      let name = function["name"] as? String else { continue }
                                let arguments = (function["arguments"] as? [String: Any] ?? [:]).mapValues { "\($0)" }
                                continuation.yield(.toolCall(ToolCall(name: name, arguments: arguments)))
                            }
                        }
                        if obj["done"] as? Bool == true {
                            let ns = 1_000_000_000.0
                            var stats = BackendStats()
                            stats.promptTokens = obj.int("prompt_eval_count")
                            stats.completionTokens = obj.int("eval_count")
                            stats.promptEvalSeconds = obj.double("prompt_eval_duration").map { $0 / ns }
                            stats.evalSeconds = obj.double("eval_duration").map { $0 / ns }
                            stats.loadSeconds = obj.double("load_duration").map { $0 / ns }
                            stats.totalSeconds = obj.double("total_duration").map { $0 / ns }
                            stats.stopReason = obj["done_reason"] as? String
                            if let n = stats.completionTokens, let s = stats.evalSeconds, s > 0 { stats.tokensPerSecond = Double(n) / s }
                            if let n = stats.promptTokens, let s = stats.promptEvalSeconds, s > 0 { stats.promptTokensPerSecond = Double(n) / s }
                            continuation.yield(.finished(stats))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func encode(_ turn: ChatTurn) -> [String: Any] {
        var message: [String: Any] = ["role": turn.role, "content": turn.content]
        if !turn.toolCalls.isEmpty {
            message["tool_calls"] = turn.toolCalls.map { ["function": ["name": $0.name, "arguments": $0.arguments]] }
        }
        if let name = turn.toolName { message["tool_name"] = name }
        return message
    }

    // MARK: Ollama-only management

    struct PullUpdate {
        var status: String
        var completed: Int64
        var total: Int64
        var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    }

    func pull(_ model: String) -> AsyncThrowingStream<PullUpdate, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = try HTTP.request(url("api/pull"), method: "POST", json: ["model": model, "stream": true])
                    req.timeoutInterval = 120
                    let lines = try await HTTP.lines(req)
                    var totals: [String: Int64] = [:]
                    var completed: [String: Int64] = [:]
                    for try await line in lines {
                        try Task.checkCancellation()
                        guard let data = line.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let error = obj["error"] as? String { throw BackendError.http(500, error) }
                        let status = obj["status"] as? String ?? ""
                        if let digest = obj["digest"] as? String {
                            if let t = obj.int64("total") { totals[digest] = t }
                            if let c = obj.int64("completed") { completed[digest] = c }
                        }
                        let total = totals.values.reduce(0, +)
                        let done = completed.values.reduce(0, +)
                        continuation.yield(PullUpdate(status: status, completed: done, total: total))
                        if status == "success" { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func delete(_ model: String) async throws {
        _ = try await HTTP.data(HTTP.request(url("api/delete"), method: "DELETE", json: ["model": model], timeout: 30))
    }

    /// Frees the model's memory immediately.
    func unload(_ model: String) async throws {
        _ = try await HTTP.data(HTTP.request(url("api/generate"), method: "POST", json: ["model": model, "keep_alive": 0], timeout: 30))
    }
}
