import Foundation

/// The harness as it was built, one version at a time. All of them stay runnable, in chat and in the
/// Harness Test, so their results can be compared on the same model.
enum HarnessVersion: String, Codable, CaseIterable, Identifiable {
    case tools, pipeline, loop, thinking, council

    static let latest = HarnessVersion.council

    var id: String { rawValue }

    /// For tight places.
    var short: String {
        switch self {
        case .tools: return "v1"
        case .pipeline: return "v2"
        case .loop: return "v3"
        case .thinking: return "v4"
        case .council: return "v5"
        }
    }

    var name: String {
        switch self {
        case .tools: return "Model tools"
        case .pipeline: return "Pipeline"
        case .loop: return "Loop"
        case .thinking: return "Thinking loop"
        case .council: return "Council"
        }
    }

    var title: String { "\(short) \(name)" }

    var summary: String {
        switch self {
        case .tools: return "The model gets the tools and decides when to call them."
        case .pipeline: return "The harness runs the right tool once, then the model answers from what it found."
        case .loop: return "The pipeline, plus code that checks each reply and goes round again until it passes."
        case .thinking: return "The loop, with the model thinking through every step it takes part in. Needs Think on: with it off, this is v3."
        case .council: return "Code prepares a shared notes file, then three agents with their own personality and temperature discuss the task in it, thinking on."
        }
    }

    /// The steps a task goes through, for drawing them.
    var route: [String] {
        switch self {
        case .tools: return ["Task", "Model calls tools if it wants", "Reply"]
        case .pipeline: return ["Task", "Understand", "Run one tool", "Answer", "Reply"]
        case .loop: return ["Task", "Understand", "Act", "Answer", "Code checks it", "Reply"]
        case .thinking: return ["Task", "Think, understand", "Think, act", "Think, answer", "Code checks it", "Reply"]
        case .council: return ["Task", "Code prepares the notes", "Three agents discuss", "One writes the reply", "Code checks it", "Reply"]
        }
    }

    /// Whether it's the loop, which goes round again after a failed check.
    var isLoop: Bool { self == .loop || self == .thinking }

    /// Whether the rounds setting applies, which in v5 limits the discussion.
    var usesRounds: Bool { isLoop || self == .council }

    /// True when it thinks whatever the Think button says.
    var alwaysThinks: Bool { self == .council }

    /// How long a test takes, compared with one model reply a question.
    var testTimeWeight: Int { self == .council ? 2 : 1 }
}

/// A version as it's saved in a file. It keeps a name this build doesn't know, from a build with versions
/// this one lacks, so reading the file works and saving it again changes nothing. With the plain enum, one
/// unknown name would fail the whole file: the app would show nothing and its next save would erase it all.
struct SavedHarnessVersion: Codable, Equatable {
    let name: String

    /// Nil for a name this build doesn't know.
    var version: HarnessVersion? { HarnessVersion(rawValue: name) }

    init(_ version: HarnessVersion) { name = version.rawValue }

    init(from decoder: Decoder) throws { name = try decoder.singleValueContainer().decode(String.self) }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

extension TestLab {
    /// Works a task through a version of the harness. `answer` is how the caller gets a reply from the
    /// model, so chat can stream it. `earlier` is the chat so far. The result lands in `total.answer`.
    static func work(_ version: HarnessVersion, prompt: String, earlier: String = "", setup: TestSetup, maxTokens: Int,
                     total: inout Reply, answer: (AnswerPlan) async -> Reply) async {
        switch version {
        case .tools:
            await modelTools(prompt: prompt, setup: setup, total: &total, answer: answer)
        case .pipeline:
            await PipelineHarness.run(prompt: prompt, earlier: earlier, setup: setup, maxTokens: maxTokens, total: &total, answer: answer)
        case .loop, .thinking:
            await runLoop(prompt: prompt, earlier: earlier, setup: setup, thinkEachStep: version == .thinking, total: &total, answer: answer)
        case .council:
            await runCouncil(prompt: prompt, earlier: earlier, setup: setup, maxTokens: maxTokens, total: &total, answer: answer)
        }
    }

    /// v1: the model holds the tools, and the harness only guards what comes back. What `answer` does with
    /// them is up to the caller, since chat streams each round.
    private static func modelTools(prompt: String, setup: TestSetup, total: inout Reply, answer: (AnswerPlan) async -> Reply) async {
        let reply = await answer(AnswerPlan(task: prompt))
        absorb(reply, into: &total)
        total.answer = reply.answer
        total.error = reply.error
        if !setup.supportsTools {
            total.toolLog.append("This model can't call tools, so it answered without them")
        } else if total.toolLog.isEmpty {
            total.toolLog.append("The model called no tools")
        }
        if total.toolLog.contains(where: { $0.hasPrefix("Searched") || $0.hasPrefix("Opened") }) {
            let filtered = PromptGuard.filterReply(total.answer)
            total.answer = filtered.text
            if filtered.blocked > 0 {
                total.toolLog.append("Removed \(filtered.blocked) untrusted link\(filtered.blocked == 1 ? "" : "s") from the reply")
            }
        }
        total.onDraft?(total.answer)
    }

    /// One task in a test: the harness's work, with the model replying straight away rather than streaming.
    static func harnessReply(_ version: HarnessVersion, prompt: String, setup: TestSetup, maxTokens: Int, notesName: String? = nil) async -> Reply {
        var total = Reply()
        total.notesName = notesName
        await work(version, prompt: prompt, setup: setup, maxTokens: maxTokens, total: &total) { plan in
            let think: Bool?? = plan.think == nil ? .none : .some(plan.think)
            if let agent = plan.agent {
                var own = setup
                own.temperature = agent.temperature
                return await converse([ChatTurn(role: "system", content: ModelTestSuite.systemPrompt + "\n\n" + agent.system),
                                       ChatTurn(role: "user", content: plan.task)],
                                      setup: own, maxTokens: plan.maxTokens ?? maxTokens, useTools: false, think: think)
            }
            let tools = setup.supportsTools && plan.addendum.isEmpty
            let system = ModelTestSuite.systemPrompt + "\n\n" + PromptGuard.systemRules + (tools ? "\n\n" + HarnessTools.systemRules : "")
            return await converse([ChatTurn(role: "system", content: system), ChatTurn(role: "user", content: plan.task + plan.addendum)],
                                  setup: setup, maxTokens: plan.maxTokens ?? maxTokens, useTools: tools, think: think)
        }
        return total
    }

    /// Runs the tools a model asked for, and returns the turns that tell it what happened.
    static func runTools(_ calls: [ToolCall], gate: inout ToolGate, reply: inout Reply) async -> [ChatTurn] {
        var turns: [ChatTurn] = []
        for call in calls {
            reply.modelToolCalls += 1
            if let refusal = gate.refusal(of: call) {
                reply.toolLog.append(HarnessTools.describe(call) + HarnessTools.refusedMark)
                turns.append(ChatTurn(role: "tool", content: refusal, toolName: call.name))
                continue
            }
            let (result, removed, failed) = await HarnessTools.run(call)
            if !failed { gate.note(call, result: result) }
            reply.toolLog.append(HarnessTools.describe(call) + (failed ? HarnessTools.failedMark : ""))
            reply.guardRemoved += removed
            turns.append(ChatTurn(role: "tool", content: result, toolName: call.name))
        }
        return turns
    }
}
