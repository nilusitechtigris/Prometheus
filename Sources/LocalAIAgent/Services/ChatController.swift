import Foundation
import Observation

/// Live numbers for the response currently streaming.
struct LiveGeneration {
    enum Phase { case waiting, thinking, answering }
    var phase: Phase = .waiting
    var startedAt = Date()
    var firstTokenAt: Date?
    var tokens = 0
    var thinkingTokens = 0

    var timeToFirstToken: Double? { firstTokenAt.map { $0.timeIntervalSince(startedAt) } }

    var tokensPerSecond: Double? {
        guard let first = firstTokenAt, tokens > 1 else { return nil }
        let elapsed = Date().timeIntervalSince(first)
        return elapsed > 0.2 ? Double(tokens - 1) / elapsed : nil
    }
}

@MainActor
@Observable
final class ChatController {
    private(set) var conversations: [Conversation] = []
    var selectedID: UUID?
    private(set) var isGenerating = false
    private(set) var streamingMessageID: UUID?
    private(set) var live: LiveGeneration?
    /// Number of older messages left out of the last request because they didn't fit the context window.
    private(set) var trimmedMessageCount = 0

    private let settings: AppSettings
    private let backends: BackendController
    private let store = ConversationStore()
    private var generationTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    init(settings: AppSettings, backends: BackendController) {
        self.settings = settings
        self.backends = backends
        conversations = store.load().sorted { $0.updatedAt > $1.updatedAt }
        selectedID = conversations.first?.id
    }

    var selected: Conversation? {
        guard let id = selectedID else { return nil }
        return conversations.first { $0.id == id }
    }

    /// Metrics of the most recent finished response in the selected conversation.
    var lastMetrics: GenerationMetrics? {
        selected?.messages.last(where: { $0.role == .assistant && $0.metrics != nil })?.metrics
    }

    /// Average generation numbers for the selected chat, counting only replies from this exact
    /// model + quantization — so a new chat, model or quant starts from zero.
    func averages(for modelID: String?) -> GenerationAverages? {
        guard let modelID, let conversation = selected else { return nil }
        let metrics = conversation.messages.compactMap { m -> GenerationMetrics? in
            guard m.role == .assistant, m.modelName == modelID, m.errorText == nil else { return nil }
            return m.metrics
        }
        return GenerationAverages(metrics)
    }

    // MARK: Conversations

    @discardableResult
    func newConversation() -> UUID {
        if let current = selected, current.messages.isEmpty { return current.id }
        let conv = Conversation()
        conversations.insert(conv, at: 0)
        selectedID = conv.id
        scheduleSave()
        return conv.id
    }

    func delete(_ id: UUID) {
        if streamingConversationID == id { stop() }
        conversations.removeAll { $0.id == id }
        if selectedID == id { selectedID = conversations.first?.id }
        scheduleSave()
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = index(of: id) else { return }
        conversations[i].title = trimmed
        scheduleSave()
    }

    func clearAll() {
        stop()
        conversations.removeAll()
        selectedID = nil
        scheduleSave()
    }

    private func index(of id: UUID) -> Int? { conversations.firstIndex { $0.id == id } }

    private var streamingConversationID: UUID? {
        guard let mid = streamingMessageID else { return nil }
        return conversations.first { $0.messages.contains { $0.id == mid } }?.id
    }

    // MARK: Generation

    var canSend: Bool { !isGenerating && backends.status.isOnline && backends.selectedModel != nil && backends.activeTest == nil }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, canSend else { return }
        let convID = selectedID.flatMap(index(of:)) != nil ? selectedID! : newConversation()
        guard let i = index(of: convID) else { return }

        conversations[i].messages.append(ChatMessage(role: .user, content: text))
        if conversations[i].title == "New Chat" {
            let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
            conversations[i].title = firstLine.count > 48 ? String(firstLine.prefix(47)) + "…" : firstLine
        }
        generate(in: convID)
    }

    func regenerate() {
        guard canSend, let id = selectedID, let i = index(of: id) else { return }
        while let last = conversations[i].messages.last, last.role == .assistant {
            conversations[i].messages.removeLast()
        }
        guard conversations[i].messages.last?.role == .user else { return }
        generate(in: id)
    }

    func stop() {
        generationTask?.cancel()
    }

    private func generate(in convID: UUID) {
        guard let model = backends.selectedModel, let ci = index(of: convID) else { return }
        let backend = backends.backend
        let context = backends.effectiveContext

        let (turns, trimmed, estimatedPrompt) = buildTurns(conversations[ci].messages, context: context)
        trimmedMessageCount = trimmed
        let request = ChatRequest(
            model: model.id,
            messages: turns,
            temperature: settings.temperature,
            contextLength: context,
            maxTokens: settings.maxResponseTokens > 0 ? settings.maxResponseTokens : nil,
            think: backend.kind == .ollama && backends.supportsThinking ? settings.thinkingEnabled : nil
        )

        let assistant = ChatMessage(role: .assistant, content: "", modelName: model.id)
        conversations[ci].messages.append(assistant)
        conversations[ci].updatedAt = Date()
        moveToTop(convID)

        streamingMessageID = assistant.id
        isGenerating = true
        live = LiveGeneration()

        generationTask = Task { [weak self] in
            await self?.stream(request, backend: backend, messageID: assistant.id, convID: convID, estimatedPrompt: estimatedPrompt)
        }
    }

    private func stream(_ request: ChatRequest, backend: LLMBackend, messageID: UUID, convID: UUID, estimatedPrompt: Int) async {
        let start = Date()
        var content = "", thinking = ""
        var parser = ThinkTagParser()
        var thinkingEndedAt: Date?
        var stats: BackendStats?
        var lastFlush = Date.distantPast
        var errorText: String?
        var cancelled = false

        func noteToken(isThinking: Bool) {
            guard var l = live else { return }
            if l.firstTokenAt == nil { l.firstTokenAt = Date() }
            l.tokens += 1
            if isThinking { l.thinkingTokens += 1 }
            if !isThinking, l.phase != .answering {
                l.phase = .answering
                if !thinking.isEmpty, thinkingEndedAt == nil { thinkingEndedAt = Date() }
            } else if isThinking {
                l.phase = .thinking
            }
            live = l
        }

        do {
            for try await event in backend.chat(request) {
                switch event {
                case .thinking(let t):
                    thinking += t
                    noteToken(isThinking: true)
                case .content(let c):
                    let parts = parser.feed(c)
                    thinking += parts.thinking
                    content += parts.answer
                    // A chunk inside <think>…</think> (or the tags themselves) is a thinking token.
                    noteToken(isThinking: parts.answer.isEmpty && (!parts.thinking.isEmpty || parser.isThinking))
                case .toolCall:
                    break   // Chat doesn't offer tools.
                case .finished(let s):
                    stats = s
                }
                if Date().timeIntervalSince(lastFlush) > 0.05 {
                    update(messageID, in: convID) { $0.content = content; $0.thinking = thinking.isEmpty ? nil : thinking }
                    lastFlush = Date()
                }
            }
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                cancelled = true
            } else {
                errorText = Self.friendly(error)
            }
        }

        let tail = parser.flush()
        thinking += tail.thinking
        content += tail.answer
        let end = Date()

        var m = GenerationMetrics(backend: backend.kind.displayName)
        let firstToken = live?.firstTokenAt
        m.timeToFirstToken = firstToken.map { $0.timeIntervalSince(start) }
        m.promptTokens = stats?.promptTokens
        // Frameworks report one count for thinking + answer; split it using the streamed chunks
        // (Ollama streams one token per chunk).
        let completion = stats?.completionTokens ?? live?.tokens ?? 0
        m.completionTokens = completion
        if let thinkingCount = live?.thinkingTokens, thinkingCount > 0 {
            m.thinkingTokens = min(thinkingCount, completion)
        }
        if let tps = stats?.tokensPerSecond {
            m.tokensPerSecond = tps
        } else if let first = firstToken, let n = live?.tokens, n > 1 {
            m.tokensPerSecond = Double(n - 1) / max(end.timeIntervalSince(first), 0.001)
            m.isEstimated = true
        }
        if m.promptTokens == nil {
            m.promptTokens = estimatedPrompt
            m.isEstimated = true
        }
        m.promptTokensPerSecond = stats?.promptTokensPerSecond
        m.loadDuration = stats?.loadSeconds
        m.totalDuration = stats?.totalSeconds ?? end.timeIntervalSince(start)
        if let generation = stats?.evalSeconds {
            m.promptDuration = stats?.promptEvalSeconds
            m.generationDuration = generation
            m.taskDuration = (stats?.promptEvalSeconds ?? 0) + generation
        } else {
            // No server timings (LM Studio, MLX): wall-clock from request to last token.
            m.taskDuration = max(end.timeIntervalSince(start) - (stats?.loadSeconds ?? 0), 0)
            m.generationDuration = firstToken.map { end.timeIntervalSince($0) }
        }
        if !thinking.isEmpty, let first = firstToken {
            m.thinkingDuration = (thinkingEndedAt ?? end).timeIntervalSince(first)
        }
        m.contextLength = request.contextLength
        m.stopReason = cancelled ? "stopped" : stats?.stopReason
        m.temperature = request.temperature

        let gotOutput = !content.isEmpty || !thinking.isEmpty
        update(messageID, in: convID) {
            $0.content = content
            $0.thinking = thinking.isEmpty ? nil : thinking
            $0.metrics = gotOutput ? m : nil
            $0.errorText = errorText
        }
        if cancelled, !gotOutput { removeMessage(messageID, in: convID) }

        isGenerating = false
        streamingMessageID = nil
        live = nil
        generationTask = nil
        scheduleSave()
    }

    /// Picks the newest messages that fit ~75% of the context window, leaving room for the answer.
    private func buildTurns(_ messages: [ChatMessage], context: Int) -> ([ChatTurn], Int, Int) {
        func estimate(_ s: String) -> Int { s.count * 10 / 35 + 4 }
        let system = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let budget = Int(Double(context) * 0.75)
        var used = system.isEmpty ? 0 : estimate(system)
        let history = messages.filter { ($0.role == .user || $0.role == .assistant) && !$0.content.isEmpty }
        var kept: [ChatTurn] = []
        var trimmed = 0
        for (offset, msg) in history.reversed().enumerated() {
            let cost = estimate(msg.content)
            if used + cost > budget, !kept.isEmpty {
                trimmed = history.count - offset
                break
            }
            kept.insert(ChatTurn(role: msg.role.rawValue, content: msg.content), at: 0)
            used += cost
        }
        if !system.isEmpty { kept.insert(ChatTurn(role: "system", content: system), at: 0) }
        return (kept, trimmed, used)
    }

    private func update(_ messageID: UUID, in convID: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let ci = index(of: convID),
              let mi = conversations[ci].messages.firstIndex(where: { $0.id == messageID }) else { return }
        change(&conversations[ci].messages[mi])
    }

    private func removeMessage(_ messageID: UUID, in convID: UUID) {
        guard let ci = index(of: convID) else { return }
        conversations[ci].messages.removeAll { $0.id == messageID }
    }

    private func moveToTop(_ id: UUID) {
        guard let i = index(of: id), i != 0 else { return }
        let conv = conversations.remove(at: i)
        conversations.insert(conv, at: 0)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = conversations
        let store = self.store
        saveTask = Task.detached(priority: .background) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            store.save(snapshot)
        }
    }

    func saveNow() { store.save(conversations) }

    static func friendly(_ error: Error) -> String {
        if let url = error as? URLError {
            switch url.code {
            case .cannotConnectToHost, .networkConnectionLost, .cannotFindHost:
                return "Couldn't reach the framework. Is it still running?"
            case .timedOut:
                return "The request timed out. Large models can take a while to load — try again."
            default: break
            }
        }
        return error.localizedDescription
    }
}
