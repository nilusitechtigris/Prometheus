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
    /// The harness step under way, when the harness is on.
    var stage: HarnessStage?
    /// Which round of the harness's loop this is.
    var round = 1
    /// The agent taking its turn, in v5.
    var speaker: String?
    /// What that agent has written so far. It only joins the shared notes once it's whole.
    var note: String?
    /// True while the plain model answers first, in a side by side reply.
    var plainSide = false

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

    func delete(_ id: UUID) { delete([id]) }

    func delete(_ ids: Set<UUID>) {
        if let streaming = streamingConversationID, ids.contains(streaming) { stop() }
        discardNotes(of: conversations.filter { ids.contains($0.id) }.flatMap(\.messages))
        conversations.removeAll { ids.contains($0.id) }
        if let selectedID, ids.contains(selectedID) { self.selectedID = conversations.first?.id }
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
        discardNotes(of: conversations.flatMap(\.messages))
        conversations.removeAll()
        selectedID = nil
        scheduleSave()
    }

    private func discardNotes(of messages: [ChatMessage]) {
        SharedNotes.discard(messages.filter { $0.sharedNotes != nil }.map(\.id.uuidString))
    }

    private func index(of id: UUID) -> Int? { conversations.firstIndex { $0.id == id } }

    private var streamingConversationID: UUID? {
        guard let mid = streamingMessageID else { return nil }
        return conversations.first { $0.messages.contains { $0.id == mid } }?.id
    }

    // MARK: Generation

    var canSend: Bool { !isGenerating && backends.status.isOnline && backends.selectedModel != nil && backends.activeTest == nil }

    /// Whether a message can be answered twice, by the plain model and by the harness, to compare them.
    var canCompare: Bool { canSend && backends.kind.supportsTools }

    /// `sideBySide` answers with the plain model first and then the harness, whatever the Harness button says.
    func send(_ text: String, sideBySide: Bool = false) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, canSend else { return }
        let convID = selectedID.flatMap(index(of:)) != nil ? selectedID! : newConversation()
        guard let i = index(of: convID) else { return }

        conversations[i].messages.append(ChatMessage(role: .user, content: text))
        if conversations[i].title == "New Chat" {
            let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
            conversations[i].title = firstLine.count > 48 ? String(firstLine.prefix(47)) + "…" : firstLine
        }
        generate(in: convID, sideBySide: sideBySide)
    }

    /// Questions the harness settles with code alone: two sums for its calculator and a program it runs as
    /// written. None needs the web or a program the model has to write, so the demo shows the same thing on any
    /// model, and the line under each reply has something code checked. They're short on purpose: a plain model
    /// asked for a power remainder wrote for over a minute, which is true to life but too long for a first look.
    static let demoQuestions = ["What is 48271 × 9377?",
                                "What is 3847 × 2961 + 58213?",
                                "What does this Python program print?\n\nfs = [lambda: i * i for i in range(4)]\nprint(sum(f() for f in fs))"]
    /// True while the demo is asking its questions.
    private(set) var demoRunning = false
    private var demoStopped = false

    /// Asks each demo question side by side in a chat of its own, so a newcomer sees the harness at work on
    /// this Mac's model before they've thought of a question.
    func runDemo() {
        guard canCompare, !demoRunning else { return }
        let convID = newConversation()
        if let i = index(of: convID) { conversations[i].title = "Harness demo" }
        demoRunning = true
        demoStopped = false
        Task { [weak self] in
            for question in Self.demoQuestions {
                guard let self, !demoStopped, selectedID == convID, canCompare else { break }
                send(question, sideBySide: true)
                while isGenerating { try? await Task.sleep(for: .milliseconds(150)) }
            }
            self?.demoRunning = false
        }
    }

    /// Adds the plain model's reply beside a harness reply that's already there, from the same messages.
    func addPlainReply(to messageID: UUID) {
        guard canSend, let model = backends.selectedModel,
              let ci = conversations.firstIndex(where: { $0.messages.contains { $0.id == messageID } }),
              let mi = conversations[ci].messages.firstIndex(where: { $0.id == messageID }),
              conversations[ci].messages[mi].role == .assistant, conversations[ci].messages[mi].plain == nil else { return }
        let convID = conversations[ci].id
        let backend = backends.backend
        let context = backends.effectiveContext
        let (turns, _, estimatedPrompt) = buildTurns(Array(conversations[ci].messages[..<mi]), context: context)
        let request = ChatRequest(model: model.id, messages: turns, temperature: settings.temperature, contextLength: context,
                                  maxTokens: settings.maxResponseTokens > 0 ? settings.maxResponseTokens : nil,
                                  think: backend.kind.supportsThinkingControl && backends.supportsThinking ? settings.thinkingEnabled : nil)
        conversations[ci].messages[mi].plain = PlainReply()
        streamingMessageID = messageID
        isGenerating = true
        var fresh = LiveGeneration()
        fresh.plainSide = true
        live = fresh
        generationTask = Task { [weak self] in
            guard let self else { return }
            await stream(request, backend: backend, messageID: messageID, convID: convID, estimatedPrompt: estimatedPrompt,
                         keepIfStopped: true, asPlain: true)
            // Stopped before a word came: there's nothing to put beside the reply.
            update(messageID, in: convID) { if $0.plain?.content.isEmpty == true, $0.plain?.errorText == nil { $0.plain = nil } }
            isGenerating = false
            streamingMessageID = nil
            live = nil
            generationTask = nil
            scheduleSave()
        }
    }

    func regenerate() {
        guard canSend, let id = selectedID, let i = index(of: id) else { return }
        var wasSideBySide = false
        while let last = conversations[i].messages.last, last.role == .assistant {
            if last.plain != nil { wasSideBySide = true }
            discardNotes(of: [last])
            conversations[i].messages.removeLast()
        }
        guard conversations[i].messages.last?.role == .user else { return }
        generate(in: id, sideBySide: wasSideBySide)
    }

    func stop() {
        demoStopped = true
        generationTask?.cancel()
    }

    private func generate(in convID: UUID, sideBySide: Bool = false) {
        guard let model = backends.selectedModel, let ci = index(of: convID) else { return }
        let backend = backends.backend
        let context = backends.effectiveContext
        // Side by side always has a harness reply to compare with, whatever the Harness button says.
        let compare = sideBySide && backend.kind.supportsTools
        let harness = (settings.harnessEnabled || compare) && backend.kind.supportsTools ? settings.harnessVersion : nil

        let messages = conversations[ci].messages
        let (turns, trimmed, estimatedPrompt) = buildTurns(messages, context: context)
        trimmedMessageCount = trimmed
        let request = ChatRequest(
            model: model.id,
            messages: turns,
            temperature: settings.temperature,
            contextLength: context,
            maxTokens: settings.maxResponseTokens > 0 ? settings.maxResponseTokens : nil,
            think: backend.kind.supportsThinkingControl && backends.supportsThinking ? settings.thinkingEnabled : nil
        )

        var assistant = ChatMessage(role: .assistant, content: "", modelName: model.id)
        assistant.harnessVersion = harness.map(SavedHarnessVersion.init)
        if compare { assistant.plain = PlainReply() }
        conversations[ci].messages.append(assistant)
        conversations[ci].updatedAt = Date()
        moveToTop(convID)

        streamingMessageID = assistant.id
        isGenerating = true
        var fresh = LiveGeneration()
        fresh.plainSide = compare
        live = fresh

        generationTask = Task { [weak self] in
            guard let self else { return }
            if compare {
                // The plain model goes first, as the harness-off side does in Dev mode's Compare.
                await stream(request, backend: backend, messageID: assistant.id, convID: convID, estimatedPrompt: estimatedPrompt,
                             asPlain: true)
                live = LiveGeneration()
            }
            if Task.isCancelled || message(assistant.id, in: convID) == nil {
                // Stopped during the plain reply: what there is of it stays, and the harness doesn't start.
            } else if let harness {
                let began = Date()
                WebConsent.shared.beginReply()
                await runHarness(harness, request, messages: messages, model: model, messageID: assistant.id, convID: convID)
                WebConsent.shared.endReply()
                if compare { update(assistant.id, in: convID) { $0.harnessSeconds = Date().timeIntervalSince(began) } }
            } else {
                await stream(request, backend: backend, messageID: assistant.id, convID: convID, estimatedPrompt: estimatedPrompt)
            }
            isGenerating = false
            streamingMessageID = nil
            live = nil
            generationTask = nil
            scheduleSave()
        }
    }

    // MARK: Harness

    /// Runs a reply through a version of the harness, streaming each attempt into the message. From v2 on
    /// only the harness uses tools, so a page the model reads can't steer one with this chat in view. In v1
    /// the model holds them, and the gate is what stops a page steering them.
    private func runHarness(_ version: HarnessVersion, _ request: ChatRequest, messages: [ChatMessage], model: LocalModel,
                            messageID: UUID, convID: UUID) async {
        let canCall = version == .tools ? await backends.capabilities(of: model).supportsTools : false
        let setup = TestLab.TestSetup(model: model, backend: backends.backend, context: request.contextLength, think: request.think,
                                      supportsTools: canCall, temperature: request.temperature, maxRounds: settings.harnessMaxRounds)
        var reply = TestLab.Reply()
        reply.onStage = { [weak self] stage, round in
            self?.live?.stage = stage
            self?.live?.round = round
        }
        reply.onLog = { [weak self] steps in
            self?.update(messageID, in: convID) { $0.harnessSteps = steps }
        }
        reply.onDraft = { [weak self] text in
            self?.update(messageID, in: convID) { $0.content = text }
        }
        reply.notesName = messageID.uuidString
        reply.onNotes = { [weak self] notes in
            self?.update(messageID, in: convID) { $0.sharedNotes = notes }
        }
        reply.onThought = { [weak self] thought in
            self?.live?.phase = .thinking
            self?.update(messageID, in: convID) { $0.thinking = ($0.thinking ?? "") + thought }
        }
        let earlier = messages.dropLast().filter { !$0.content.isEmpty }.suffix(2)
            .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content.prefix(600))" }
            .joined(separator: "\n")
        await TestLab.work(version, prompt: messages.last?.content ?? "", earlier: earlier, setup: setup,
                           maxTokens: request.maxTokens ?? 2_048, total: &reply) { [weak self] plan in
            guard let self else { return TestLab.Reply() }
            if let agent = plan.agent {
                return await streamAgent(plan, agent, base: request, messageID: messageID, convID: convID)
            }
            if version == .tools {
                return await streamWithTools(plan, canCall: canCall, base: request, messages: messages, messageID: messageID, convID: convID)
            }
            return await streamAttempt(plan, keepThoughts: version == .thinking, base: request, messages: messages, messageID: messageID, convID: convID)
        }
        update(messageID, in: convID) { $0.harnessResult = reply.result }
    }

    /// One attempt at the reply. It streams like any reply, and hands back what the loop needs to check it.
    /// `keepThoughts` adds its thinking to what earlier steps thought, rather than replacing it.
    private func streamAttempt(_ plan: TestLab.AnswerPlan, keepThoughts: Bool, base: ChatRequest, messages: [ChatMessage],
                               messageID: UUID, convID: UUID) async -> TestLab.Reply {
        // What the tools found takes room from the chat history, so the turns are rebuilt each time.
        let evidence = String(plan.addendum.prefix(base.contextLength * 7 / 6))
        let built = buildTurns(messages, context: base.contextLength, harness: (HarnessTools.chatRules, plan.task, evidence))
        var request = base
        request.messages = built.turns
        if let think = plan.think { request.think = think }
        if let limit = plan.maxTokens { request.maxTokens = limit }
        trimmedMessageCount = built.trimmed

        let firstAttempt = (live?.round ?? 1) == 1
        var fresh = LiveGeneration()
        fresh.stage = live?.stage
        fresh.round = live?.round ?? 1
        live = fresh
        await stream(request, backend: backends.backend, messageID: messageID, convID: convID, estimatedPrompt: built.estimated,
                     keepIfStopped: !firstAttempt, earlierThoughts: keepThoughts ? message(messageID, in: convID)?.thinking ?? "" : "")
        return replySoFar(in: messageID, convID: convID)
    }

    /// One agent's turn in v5, which stands alone on the agent's own temperature. Notes stream beside the
    /// shared notes, so the only text that reaches the message is the final reply.
    private func streamAgent(_ plan: TestLab.AnswerPlan, _ agent: TestLab.AgentTurn, base: ChatRequest,
                             messageID: UUID, convID: UUID) async -> TestLab.Reply {
        let system = [settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines), HarnessTools.chatRules, agent.system]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        var request = base
        request.messages = [ChatTurn(role: "system", content: system), ChatTurn(role: "user", content: plan.task)]
        request.temperature = agent.temperature
        if let think = plan.think { request.think = think }
        if let limit = plan.maxTokens { request.maxTokens = limit }

        var fresh = LiveGeneration()
        fresh.stage = live?.stage
        fresh.round = live?.round ?? 1
        fresh.speaker = agent.name
        live = fresh
        await stream(request, backend: backends.backend, messageID: messageID, convID: convID,
                     estimatedPrompt: (system.count + plan.task.count) * 10 / 35, keepIfStopped: true, asNote: agent.isNote)
        var reply = replySoFar(in: messageID, convID: convID)
        if agent.isNote { reply.answer = live?.note ?? "" }
        return reply
    }

    /// v1: the model holds the tools, so it can go back and forth with them before it replies. Its last round
    /// comes without them, so it has to answer with what it has.
    private func streamWithTools(_ plan: TestLab.AnswerPlan, canCall: Bool, base: ChatRequest, messages: [ChatMessage],
                                 messageID: UUID, convID: UUID) async -> TestLab.Reply {
        let built = buildTurns(messages, context: base.contextLength, harness: (HarnessTools.chatToolRules, plan.task, ""))
        trimmedMessageCount = built.trimmed
        var request = base
        request.messages = built.turns
        var log = TestLab.Reply()
        log.onLog = { [weak self] steps in
            self?.update(messageID, in: convID) { $0.harnessSteps = steps }
        }
        var gate = ToolGate()
        for round in 0...TestLab.maxToolRounds {
            request.tools = canCall && round < TestLab.maxToolRounds ? HarnessTools.definitions : []
            live = LiveGeneration()
            let calls = await stream(request, backend: backends.backend, messageID: messageID, convID: convID,
                                     estimatedPrompt: built.estimated, keepIfStopped: round > 0)
            if calls.isEmpty || Task.isCancelled { break }
            request.messages.append(ChatTurn(role: "assistant", content: replySoFar(in: messageID, convID: convID).answer, toolCalls: calls))
            request.messages += await TestLab.runTools(calls, gate: &gate, reply: &log)
        }
        var reply = replySoFar(in: messageID, convID: convID)
        reply.toolLog = log.toolLog
        reply.guardRemoved = log.guardRemoved
        reply.modelToolCalls = log.modelToolCalls
        return reply
    }

    /// What a message holds right now, in the form the harness reads a reply.
    private func replySoFar(in messageID: UUID, convID: UUID) -> TestLab.Reply {
        var reply = TestLab.Reply()
        guard let message = message(messageID, in: convID) else { return reply }
        reply.answer = message.content
        reply.thinking = message.thinking ?? ""
        reply.error = message.errorText
        reply.thinkingTokens = message.metrics?.thinkingTokens ?? 0
        var stats = BackendStats()
        stats.stopReason = message.metrics?.stopReason
        reply.stats = stats
        return reply
    }

    /// The message a reply answers: the nearest one from the user above it.
    func question(for messageID: UUID) -> String? {
        for conversation in conversations {
            guard let mi = conversation.messages.firstIndex(where: { $0.id == messageID }) else { continue }
            return conversation.messages[..<mi].last { $0.role == .user }?.content
        }
        return nil
    }

    private func message(_ messageID: UUID, in convID: UUID) -> ChatMessage? {
        index(of: convID).flatMap { ci in conversations[ci].messages.first { $0.id == messageID } }
    }

    /// `keepIfStopped` leaves the message in place when Stop comes before any text, for a retry whose
    /// earlier attempt is worth keeping. `earlierThoughts` stays above what this reply thinks. `asNote` keeps
    /// the text out of the message, in `live.note`. `asPlain` writes the reply beside the message, as the plain
    /// model's side of a comparison. Returns any tools the model asked for.
    @discardableResult
    private func stream(_ request: ChatRequest, backend: LLMBackend, messageID: UUID, convID: UUID, estimatedPrompt: Int,
                        keepIfStopped: Bool = false, earlierThoughts: String = "", asNote: Bool = false,
                        asPlain: Bool = false) async -> [ToolCall] {
        let start = Date()
        var content = "", thinking = ""
        var parser = ThinkTagParser()
        var thinkingEndedAt: Date?
        var stats: BackendStats?
        var lastFlush = Date.distantPast
        var errorText: String?
        var cancelled = false
        var calls: [ToolCall] = []

        func shownThoughts() -> String? {
            if earlierThoughts.isEmpty { return thinking.isEmpty ? nil : thinking }
            return thinking.isEmpty ? earlierThoughts : "\(earlierThoughts)\n\n\(HarnessStage.answer.title):\n\(thinking)"
        }

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
            try Task.checkCancellation()
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
                case .toolCall(let call):
                    calls.append(call)
                case .finished(let s):
                    stats = s
                }
                if Date().timeIntervalSince(lastFlush) > 0.05 {
                    if asNote { live?.note = content }
                    update(messageID, in: convID) {
                        if asPlain {
                            $0.plain = PlainReply(content: content, thinking: thinking.isEmpty ? nil : thinking)
                            return
                        }
                        if !asNote { $0.content = content }
                        $0.thinking = shownThoughts()
                    }
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
        if asNote { live?.note = content }
        update(messageID, in: convID) {
            if asPlain {
                $0.plain = PlainReply(content: content, thinking: thinking.isEmpty ? nil : thinking, metrics: gotOutput ? m : nil, errorText: errorText)
                return
            }
            if !asNote { $0.content = content }
            $0.thinking = shownThoughts()
            $0.metrics = gotOutput ? m : nil
            $0.errorText = errorText
        }
        if cancelled, !gotOutput, !keepIfStopped { removeMessage(messageID, in: convID) }
        return calls
    }

    /// Picks the newest messages that fit ~75% of the context window, leaving room for the answer.
    private func buildTurns(_ messages: [ChatMessage], context: Int, harness: (rules: String, task: String, evidence: String)? = nil)
        -> (turns: [ChatTurn], trimmed: Int, estimated: Int) {
        func estimate(_ s: String) -> Int { s.count * 10 / 35 + 4 }
        let system = [settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines), harness?.rules ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let budget = Int(Double(context) * 0.75)
        var used = (system.isEmpty ? 0 : estimate(system)) + estimate(harness?.evidence ?? "")
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
        if let harness, let last = kept.last {
            kept[kept.count - 1] = ChatTurn(role: last.role, content: harness.task + harness.evidence)
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
