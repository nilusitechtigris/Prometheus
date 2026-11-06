import Foundation

/// LM Studio, llama.cpp's `llama-server` and `mlx_lm.server` all speak the OpenAI chat-completions protocol.
struct OpenAICompatibleBackend: LLMBackend {
    let kind: BackendKind
    let baseURL: URL

    private func url(_ path: String) -> URL { baseURL.appendingPathComponent(path) }

    func ping() async throws -> String {
        // MLX LM's model list scans the whole Hugging Face cache, which is too much to do every few seconds.
        _ = try await HTTP.data(HTTP.request(url(kind == .mlx ? "health" : "v1/models"), timeout: 2))
        return "online"
    }

    func listModels() async throws -> [LocalModel] {
        let obj = try await HTTP.json(HTTP.request(url("v1/models"), timeout: 5))
        let data = obj["data"] as? [[String: Any]] ?? []

        // LM Studio's REST API also reports who published each file and its quantization.
        var lmStudioInfo: [String: [String: Any]] = [:]
        if kind == .lmStudio,
           let rich = try? await HTTP.json(HTTP.request(url("api/v0/models"), timeout: 3)),
           let list = rich["data"] as? [[String: Any]] {
            for m in list { if let id = m["id"] as? String { lmStudioInfo[id] = m } }
        }

        return data.compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            // Skip embedding-only models that LM Studio also lists.
            if id.lowercased().contains("embed") { return nil }
            let info = lmStudioInfo[id]
            if (info?["type"] as? String) == "embeddings" { return nil }
            return LocalModel(
                id: id,
                quantization: info?["quantization"] as? String,
                publisher: (info?["publisher"] as? String) ?? (kind == .mlx ? QuantParser.provider(in: id) : nil)
            )
        }
        .sorted { $0.id < $1.id }
    }

    func details(for model: String) async throws -> ModelDetails {
        var details = ModelDetails()
        switch kind {
        case .lmStudio:
            // LM Studio's richer REST API exposes the loaded/max context per model.
            if let obj = try? await HTTP.json(HTTP.request(url("api/v0/models"), timeout: 3)),
               let list = obj["data"] as? [[String: Any]],
               let m = list.first(where: { ($0["id"] as? String) == model }) {
                details.maxContext = m.int("loaded_context_length") ?? m.int("max_context_length")
            }
        case .llamaCpp:
            if let obj = try? await HTTP.json(HTTP.request(url("props"), timeout: 3)),
               let settings = obj["default_generation_settings"] as? [String: Any] {
                details.maxContext = settings.int("n_ctx")
            }
        case .mlx:
            // It only knows a model's abilities once it's loaded, and one without tools just ignores them.
            details.capabilities = ["tools"]
        default:
            break
        }
        details.supportsThinking = ModelCatalog.entry(matchingID: model)?.thinking ?? false
        return details
    }

    func chat(_ request: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var body: [String: Any] = [
                        "model": request.model,
                        "messages": request.messages.map(Self.encode),
                        "stream": true,
                        "temperature": request.temperature,
                        "stream_options": ["include_usage": true],
                    ]
                    // MLX LM stops at 512 tokens unless it's told otherwise.
                    if let max = request.maxTokens ?? (kind == .mlx ? request.contextLength : nil) { body["max_tokens"] = max }
                    if kind == .mlx, let think = request.think { body["chat_template_kwargs"] = ["enable_thinking": think] }
                    if !request.tools.isEmpty { body["tools"] = request.tools.map(\.json) }

                    let started = Date()
                    let lines = try await HTTP.lines(HTTP.request(url("v1/chat/completions"), method: "POST", json: body))
                    var stats = BackendStats()
                    var chunkCount = 0
                    var firstToken: Date?, lastToken: Date?
                    // A call can arrive in pieces, so they're put together by position and sent at the end.
                    var calls: [Int: (name: String, arguments: String)] = [:]
                    for try await line in lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let err = obj["error"] {
                            let message = (err as? [String: Any])?["message"] as? String ?? "\(err)"
                            throw BackendError.http(500, message)
                        }
                        if let choices = obj["choices"] as? [[String: Any]], let choice = choices.first {
                            if let delta = choice["delta"] as? [String: Any] {
                                let reasoning = (delta["reasoning_content"] as? String) ?? (delta["reasoning"] as? String)
                                if let r = reasoning, !r.isEmpty { continuation.yield(.thinking(r)); chunkCount += 1 }
                                if let c = delta["content"] as? String, !c.isEmpty { continuation.yield(.content(c)); chunkCount += 1 }
                                if reasoning?.isEmpty == false || (delta["content"] as? String)?.isEmpty == false {
                                    lastToken = Date()
                                    if firstToken == nil { firstToken = lastToken }
                                }
                                for call in delta["tool_calls"] as? [[String: Any]] ?? [] {
                                    let index = call.int("index") ?? calls.count
                                    let function = call["function"] as? [String: Any]
                                    var pieces = calls[index] ?? (name: "", arguments: "")
                                    pieces.name += function?["name"] as? String ?? ""
                                    pieces.arguments += function?["arguments"] as? String ?? ""
                                    calls[index] = pieces
                                }
                            }
                            if let reason = choice["finish_reason"] as? String { stats.stopReason = reason }
                        }
                        if let usage = obj["usage"] as? [String: Any] {
                            stats.promptTokens = usage.int("prompt_tokens")
                            stats.completionTokens = usage.int("completion_tokens")
                        }
                        // llama.cpp reports precise server-side timings.
                        if let timings = obj["timings"] as? [String: Any] {
                            stats.promptTokens = timings.int("prompt_n") ?? stats.promptTokens
                            stats.completionTokens = timings.int("predicted_n") ?? stats.completionTokens
                            stats.promptTokensPerSecond = timings.double("prompt_per_second")
                            stats.tokensPerSecond = timings.double("predicted_per_second")
                            stats.promptEvalSeconds = timings.double("prompt_ms").map { $0 / 1000 }
                            stats.evalSeconds = timings.double("predicted_ms").map { $0 / 1000 }
                        }
                    }
                    if stats.completionTokens == nil { stats.completionTokens = chunkCount }
                    Self.measure(&stats, started: started, firstToken: firstToken, lastToken: lastToken)
                    for index in calls.keys.sorted() {
                        guard let call = calls[index], !call.name.isEmpty else { continue }
                        continuation.yield(.toolCall(ToolCall(name: call.name, arguments: Self.decode(call.arguments))))
                    }
                    continuation.yield(.finished(stats))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Only llama.cpp reports its own speed, so for the others it's timed from here.
    private static func measure(_ stats: inout BackendStats, started: Date, firstToken: Date?, lastToken: Date?) {
        guard let firstToken, let lastToken else { return }
        let reading = stats.promptEvalSeconds ?? firstToken.timeIntervalSince(started)
        let generating = stats.evalSeconds ?? lastToken.timeIntervalSince(firstToken)
        stats.promptEvalSeconds = reading
        stats.evalSeconds = generating
        if stats.promptTokensPerSecond == nil, reading > 0, let tokens = stats.promptTokens {
            stats.promptTokensPerSecond = Double(tokens) / reading
        }
        if stats.tokensPerSecond == nil, generating > 0, let tokens = stats.completionTokens {
            stats.tokensPerSecond = Double(tokens) / generating
        }
    }

    private static func encode(_ turn: ChatTurn) -> [String: Any] {
        var message: [String: Any] = ["role": turn.role, "content": turn.content]
        if !turn.toolCalls.isEmpty {
            message["tool_calls"] = turn.toolCalls.enumerated().map { index, call in
                ["id": "call_\(index)", "type": "function", "function": ["name": call.name, "arguments": encode(call.arguments)]]
            }
        }
        if let name = turn.toolName { message["name"] = name }
        return message
    }

    /// Arguments travel as JSON text in this protocol.
    private static func encode(_ arguments: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decode(_ arguments: String) -> [String: String] {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object.mapValues { "\($0)" }
    }
}
