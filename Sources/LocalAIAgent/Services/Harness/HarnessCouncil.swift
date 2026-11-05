import Foundation

/// v5. Code prepares a shared notes file the way v3 prepares its evidence, then three agents take turns on it:
/// round 1 each on their own, later rounds answering each other. Code compares their answers after each
/// round and stops as soon as they agree, or when more talk won't change anything. Then one of them writes
/// the reply, and v3's checks test it. The agents take turns on one loaded model, because they have to read
/// each other anyway, and at the same time they'd need the memory three times over.
extension TestLab {
    /// One turn, which stands alone: no chat history, and the agent's own temperature.
    struct AgentTurn {
        let name: String
        let temperature: Double
        let system: String
        /// True while the agents write for each other, false for the reply the user reads.
        let isNote: Bool
    }

    /// Time a task gets per round. A round that has started always finishes, so all three get their say.
    private static let secondsPerDiscussion = 90.0
    /// Most of a turn goes on thinking, and a small model that runs out of tokens there writes nothing.
    private static let turnTokens = 1_536
    /// Tokens the system rules and an agent's brief take up.
    private static let briefTokens = 400
    /// How much of its thinking an agent gets back when it ran out of tokens, in characters.
    private static let thinkingKept = 1_000

    /// The same for every agent, and the agent's own brief comes last, after the file. So the model can reuse
    /// what it already read, instead of starting over each time the speaker changes.
    private static let councilRules = """
    You are one of three agents working on a task together through a shared notes file. The harness keeps the file: \
    you read it in the message, and what you reply goes into it under your name. \(PromptGuard.systemRules)
    """

    private struct Council {
        let task: HarnessTask
        let setup: TestSetup
        let rounds: Int
        var state: LoopState
        var notes: SharedNotes

        var label: String { state.rules.finalLabel ?? "Answer" }
        /// True when a draft can itself be the reply, because code can tell a good one.
        var isDrafting: Bool { state.kind == .writing && state.rules.hasShape }
        var replyTokens: Int { min(setup.context / 2, turnTokens) }
        /// What's left of the context for the file, at about 3.5 characters a token.
        var readingRoom: Int { (setup.context - replyTokens - briefTokens) * 35 / 10 }
    }

    /// Works a task through v5. `answer` is how the caller gets a reply from the model, so chat can stream
    /// it. `earlier` is the chat so far. The result lands in `total.answer`.
    static func runCouncil(prompt: String, earlier: String = "", setup: TestSetup, maxTokens: Int, total: inout Reply,
                           answer: (AnswerPlan) async -> Reply) async {
        let started = Date()
        let rounds = max(setup.maxRounds, 1)
        let budget = Double(rounds) * secondsPerDiscussion
        let task = HarnessTask(prompt: prompt, earlier: earlier)

        // Preparing the file.
        total.onStage?(.understand, 1)
        let kind = await understand(task, setup: setup, total: &total)
        total.toolLog.append("Understood: \(kind.rawValue) task")
        var state = LoopState(kind: kind, rules: kind == .writing ? task.rules : task.rules.onlyFinalLine)
        total.onStage?(.act, 1)
        await act(task, state: &state, round: 1, mayConfirm: rounds > 1, setup: setup, total: &total)
        var council = Council(task: task, setup: setup, rounds: rounds, state: state,
                              notes: SharedNotes(model: setup.model.id, task: task.ask, earlier: earlier, evidence: state.evidence))
        publish(council.notes, total: total)
        total.toolLog.append("Prepared the shared notes")
        if setup.think == nil { total.toolLog.append("This model can't think first, so the agents went without") }

        // The discussion.
        var best: Attempt?
        var standing = SharedNotes.Standing()
        var lastKeys: [String?] = []
        var roundsRun = 0
        for round in 1...rounds {
            if Task.isCancelled { break }
            roundsRun = round
            total.onStage?(.answer, round)
            council.notes.rounds.append([])
            // Last round's standing would be out of date as soon as anyone here writes.
            council.notes.standing = nil
            for agent in CouncilAgent.all where !Task.isCancelled {
                let brief = brief(for: agent, round: round, council: council)
                let reply = await askAgent(agentPlan(agent, brief: brief, round: round, isNote: true, council: council), total: &total, answer: answer)
                if let error = reply.error {
                    total.error = error
                    return
                }
                guard let entry = entry(for: agent, from: reply, council: council, total: &total) else {
                    total.toolLog.append("\(agent.name) wrote nothing" + HarnessTools.failedMark)
                    continue
                }
                council.notes.rounds[round - 1].append(entry)
                total.toolLog.append(logLine(for: entry, isDraft: council.isDrafting))
                publish(council.notes, total: total)
                if council.isDrafting {
                    let attempt = Attempt(text: entry.note, problems: entry.problems.map(Problem.rule))
                    if attempt.rank < best?.rank ?? Int.max { best = attempt }
                }
            }

            total.onStage?(.check, round)
            let entries = council.notes.rounds[round - 1]
            standing = SharedNotes.standing(of: entries)
            council.notes.standing = standingText(of: entries, standing)
            publish(council.notes, total: total)
            if let summary = standing.summary { total.toolLog.append(summary) }

            let keys = entries.map { $0.answer.flatMap(SharedNotes.key(of:)) }
            if standing.isUnanimous || (best?.problems.isEmpty ?? false) { break }
            if round < rounds, keys == lastKeys, !keys.contains(where: { $0 == nil }) {
                total.toolLog.append("Nobody changed their answer, so the talk ended here")
                break
            }
            if round < rounds, Date().timeIntervalSince(started) > budget {
                total.toolLog.append("Out of time after round \(round)")
                break
            }
            lastKeys = keys
        }
        if Task.isCancelled { return }

        // The reply. A word or number the group settled on now counts like a tool's result, so it has to be in
        // the reply. A longer conclusion may need rewording into the form the task asks for, so that's left
        // to the writer.
        if council.state.result == nil, let settled = standing.answer, !settled.contains(" ") { council.state.result = settled }
        // The agents have had their say on what the tools found, and nothing new is coming. So a page that
        // doesn't mention their answer is no reason to ask again, as it is in v3.
        council.state.evidence = []
        total.onStage?(.answer, roundsRun)
        await writeReply(council: &council, standing: standing, rounds: roundsRun, maxTokens: maxTokens, best: &best, total: &total, answer: answer)
        if Task.isCancelled { return }

        total.onStage?(.check, roundsRun)
        finish(best, rounds: roundsRun, task: task, state: council.state, total: &total)
        council.notes.reply = total.answer
        publish(council.notes, total: total)
    }

    private static func publish(_ notes: SharedNotes, total: Reply) {
        if let name = total.notesName { notes.save(as: name) }
        total.onNotes?(notes.markdown)
    }

    // MARK: Turns

    private static func brief(for agent: CouncilAgent, round: Int, council: Council) -> String {
        let form = "Answer what the task asks, in the form it asks for, using full names rather than symbols unless it wants a symbol. Reply in exactly this form:\n\(SharedNotes.form(label: council.label))"
        let job: String
        switch (round, council.isDrafting) {
        case (1, true):
            job = "Round 1. Write your own draft of the reply, and nothing else. The others can't see it until all three have written."
        case (_, true):
            job = "Round \(round) of \(council.rounds). Read the drafts and what code found wrong with them, then write a better draft, and nothing else."
        case (1, false):
            job = "Round 1. Work on the task on your own: the others can't see this until all three have written. \(form)"
        default:
            job = "Round \(round) of \(council.rounds). Read what the others wrote and say what is right or wrong in it. Keep your answer unless you found a mistake in it: a change without a reason doesn't count. \(form)"
        }
        return "You are the \(agent.name). \(agent.personality)\n\n\(job)"
    }

    private static func agentPlan(_ agent: CouncilAgent, brief: String, round: Int, isNote: Bool, council: Council) -> AnswerPlan {
        let reading = council.notes.reading(for: agent, round: round, characters: council.readingRoom)
        var plan = AnswerPlan(task: "\(reading)\n\n---\n\(brief)")
        plan.think = council.setup.think == nil ? nil : true
        plan.maxTokens = council.replyTokens
        plan.agent = AgentTurn(name: agent.name, temperature: agent.temperature, system: councilRules, isNote: isNote)
        return plan
    }

    /// Gets a reply out of an agent. If thinking used up its tokens and left nothing, it goes again without,
    /// picking up where its thinking stopped. Starting over would lose the reasoning, and the short retry
    /// isn't enough for a small model to redo it.
    private static func askAgent(_ plan: AnswerPlan, total: inout Reply, answer: (AnswerPlan) async -> Reply) async -> Reply {
        let reply = await answer(plan)
        absorb(reply, into: &total)
        let isBlank = reply.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard isBlank, reply.error == nil, !Task.isCancelled, plan.think == true else { return reply }
        total.toolLog.append("\(plan.agent?.name ?? "An agent") used up its tokens thinking, so it finished from there")
        var again = plan
        again.task += "\n\nYou ran out of room while thinking. Your thinking ended with:\n…\(reply.thinking.suffix(thinkingKept))\n\nStop thinking and reply now."
        again.think = false
        again.maxTokens = tightTokens
        let second = await answer(again)
        absorb(second, into: &total)
        return second
    }

    /// Turns a reply into what goes in the file, with what code can say about it. Once the web is in play an
    /// agent's note is treated like a page, so one that picked something up can't pass it on to the others.
    private static func entry(for agent: CouncilAgent, from reply: Reply, council: Council, total: inout Reply) -> SharedNotes.Entry? {
        var text = reply.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if council.state.readTheWeb {
            let clean = PromptGuard.sanitize(text)
            total.guardRemoved += clean.removed
            text = PromptGuard.filterReply(clean.text).text
        }
        if council.isDrafting {
            let attempt = judge(text, cut: reply.stats?.stopReason == "length", task: council.task, state: council.state)
            return SharedNotes.Entry(agent: agent, note: attempt.text, problems: attempt.problems.map(\.text))
        }
        let parsed = SharedNotes.parse(text, label: council.label)
        // Cut off before its answer, the last line is only where the tokens ran out.
        let unfinished = reply.stats?.stopReason == "length" && text.range(of: council.label + ":", options: .caseInsensitive) == nil
        let earlier = council.notes.rounds.dropLast().last?.first { $0.agent == agent }
        var entry = SharedNotes.holdingFirm(SharedNotes.Entry(agent: agent, note: parsed.note, answer: unfinished ? nil : parsed.answer), after: earlier)
        if let result = council.state.result, !HarnessText.mentions(result, in: parsed.answer ?? text, label: nil) {
            entry.problems.append("The tools got \(result).")
        }
        return entry
    }

    private static func logLine(for entry: SharedNotes.Entry, isDraft: Bool) -> String {
        let count = entry.problems.count
        if isDraft { return "\(entry.agent.name) wrote a draft" + (count == 0 ? " that passed" : " with \(count) problem\(count == 1 ? "" : "s")") }
        guard let answer = entry.answer else { return "\(entry.agent.name) gave no answer" }
        return "\(entry.agent.name) answered: \(answer.prefix(70))" + (entry.problems.isEmpty ? "" : " (\(entry.problems[0]))")
    }

    private static func standingText(of entries: [SharedNotes.Entry], _ standing: SharedNotes.Standing) -> String? {
        guard entries.contains(where: { $0.answer != nil }) else { return nil }
        let answers = entries.map { "\($0.agent.name): \($0.answer.map { String($0.prefix(60)) } ?? "no answer")" }.joined(separator: " · ")
        return [answers, standing.summary].compactMap { $0 }.joined(separator: "\n\n")
    }

    // MARK: The reply

    /// A draft that passes the checks is the reply already. Otherwise rules on a text's lines or sentences go
    /// to v3's repair, and anything else gets written up from the notes, with one more go if a check fails.
    private static func writeReply(council: inout Council, standing: SharedNotes.Standing, rounds: Int, maxTokens: Int, best: inout Attempt?,
                                   total: inout Reply, answer: (AnswerPlan) async -> Reply) async {
        if let draft = best, !draft.problems.isEmpty, council.state.rules.unit != nil {
            let text = await repairUnits(of: draft.text, task: council.task, state: &council.state, setup: council.setup, total: &total)
            let repaired = judge(text, cut: false, task: council.task, state: council.state)
            if repaired.rank < draft.rank { best = repaired }
        }

        let writer = standing.backers.first ?? CouncilAgent.all[0]
        var tries = 0
        while best?.problems.isEmpty != true, tries < 2, !Task.isCancelled {
            tries += 1
            var plan = agentPlan(writer, brief: closingBrief(for: writer, standing: standing, council: council),
                                 round: rounds + 1, isNote: false, council: council)
            if let last = best {
                plan.task += "\n\nYour last reply had these problems:\n" + last.problems.map { "- \($0.text)" }.joined(separator: "\n")
                if !last.text.isEmpty { plan.task += "\n\nYour last reply:\n\(last.text)\n\nReply again with only the corrected text." }
                plan.think = council.setup.think == nil ? nil : false
                plan.maxTokens = tightTokens
            } else {
                plan.maxTokens = min(maxTokens, council.replyTokens)
            }
            let reply = await askAgent(plan, total: &total, answer: answer)
            if let error = reply.error {
                total.error = error
                return
            }
            let attempt = judge(reply.answer, cut: reply.stats?.stopReason == "length", task: council.task, state: council.state)
            if best == nil || attempt.rank < best?.rank ?? Int.max {
                best = attempt
                total.onDraft?(attempt.text)
            }
            total.toolLog.append("\(writer.name) wrote the reply")
        }

        // An empty reply is worse than an agent's note.
        if best?.text.isEmpty != false, !Task.isCancelled, let last = council.notes.rounds.last(where: { !$0.isEmpty })?.first {
            best = judge(last.note + (last.answer.map { "\n\n\(council.label): \($0)" } ?? ""), cut: false, task: council.task, state: council.state)
            total.toolLog.append("Used \(last.agent.name)'s note as the reply")
        }
    }

    /// A tool's result outranks whatever the agents settled on, as it does in v3.
    private static func closingBrief(for writer: CouncilAgent, standing: SharedNotes.Standing, council: Council) -> String {
        let outcome: String
        if let result = council.state.result {
            outcome = "The answer to give is \(result)."
        } else if let conclusion = standing.answer {
            outcome = "The group concluded: \(conclusion). Give that conclusion in the form the task asks for."
        } else if council.notes.rounds.contains(where: { $0.contains { $0.answer.flatMap(SharedNotes.key(of:)) != nil } }) {
            outcome = "The agents did not agree, so decide which answer the notes support best."
        } else {
            outcome = "Bring together the best of what the agents wrote."
        }
        // It comes last, because a small model follows what it read most recently, and that's now the notes.
        return """
        You are the \(writer.name). The discussion is over, so write the final reply to the user. \(outcome)

        Don't mention the agents, the notes, the tools or the discussion. Follow this exactly:

        \(council.task.ask.prefix(600))
        """
    }
}
