import Foundation

/// LM Studio, llama.cpp's `llama-server` and `mlx_lm.server` all speak the OpenAI chat-completions protocol.
struct OpenAICompatibleBackend: LLMBackend {
    let kind: BackendKind
    let baseURL: URL

    private func url(_ path: String) -> URL { baseURL.appendingPathComponent(path) }

    func ping() async throws -> String {
        _ = try await HTTP.data(HTTP.request(url("v1/models"), timeout: 2))
        return "online"
    }

    func listModels() async throws -> [LocalModel] {
        let obj = try await HTTP.json(HTTP.request(url("v1/models"), timeout: 5))
        let data = obj["data"] as? [[String: Any]] ?? []
        return data.compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            // Skip embedding-only models that LM Studio also lists.
            if id.lowercased().contains("embed") { return nil }
            return LocalModel(id: id)
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
                        "messages": request.messages.map { ["role": $0.role, "content": $0.content] },
                        "stream": true,
                        "temperature": request.temperature,
                        "stream_options": ["include_usage": true],
                    ]
                    if let max = request.maxTokens { body["max_tokens"] = max }

                    let lines = try await HTTP.lines(HTTP.request(url("v1/chat/completions"), method: "POST", json: body))
                    var stats = BackendStats()
                    var chunkCount = 0
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
                    continuation.yield(.finished(stats))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
