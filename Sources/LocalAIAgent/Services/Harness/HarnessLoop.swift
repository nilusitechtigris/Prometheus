import Foundation

/// The harness's loop. After understanding a task it goes Act, Answer, Check, and back to Act with
/// what Check found, until the reply passes, a round changes nothing, or the budget of rounds and
/// seconds runs out. It keeps the best attempt so far, so another round can't make the result worse.
/// Check is code, not the model's opinion of itself, and it sees only the task, never an expected
/// answer, so it works the same on anything.
extension TestLab {
    enum TaskKind: String {
        case calculation, code, fact, document, writing, other
    }

    /// What one Answer step sends to the model.
    struct AnswerPlan {
        var task: String
        /// Evidence and feedback, read after the task.
        var addendum = ""
        /// Nil keeps the model's usual setting.
        var think: Bool?
        var maxTokens: Int?
    }

    /// Something Check found wrong with a reply.
    enum Problem: Equatable {
        case empty, cutOff, missingResult, unsupported
        case rule(String)

        var text: String {
            switch self {
            case .empty: return "The reply was empty."
            case .cutOff: return "The reply was cut off before it finished."
            case .missingResult: return "The reply left out the tool's result."
            case .unsupported: return "The reply's answer isn't in what the tools found."
            case .rule(let text): return text
            }
        }
    }

    /// Everything the loop has learned about a task so far.
    struct LoopState {
        var kind: TaskKind
        var rules: TextRules
        var evidence: [String] = []
        /// The exact value a tool produced, which the reply has to contain.
        var result: String?
        var readTheWeb = false
        /// True while the next Act should look for more.
        var wantsEvidence = true
        var failedProgram: (problem: String, code: String)?
        var triedShownCode = false
        var queries: [String] = []
        var hits: [SearchHit] = []
        var opened: Set<String> = []
        /// First words already tried when rewriting a sentence or line.
        var usedWords: Set<String> = []
    }

    private struct Attempt {
        let text: String
        let problems: [Problem]

        /// Lower is better. Any reply beats no reply, however many problems it has.
        var rank: Int { text.isEmpty ? Int.max : problems.count }
    }

    /// Time a task gets per round. A round that has started always finishes.
    private static let secondsPerRound = 60.0
    /// Plenty for stating a result, and little enough that thinking can't use up a small context.
    private static let tightTokens = 384
    private static let triesPerUnit = 6

    static func pipelineReply(prompt: String, setup: TestSetup, maxTokens: Int, useTools: Bool) async -> Reply {
        var total = Reply()
        await runLoop(prompt: prompt, setup: setup, total: &total) { plan in
            let tools = useTools && plan.addendum.isEmpty
            let system = ModelTestSuite.systemPrompt + "\n\n" + PromptGuard.systemRules + (tools ? "\n\n" + HarnessTools.systemRules : "")
            let think: Bool?? = plan.think == nil ? .none : .some(plan.think)
            return await converse([ChatTurn(role: "system", content: system), ChatTurn(role: "user", content: plan.task + plan.addendum)],
                                  setup: setup, maxTokens: plan.maxTokens ?? maxTokens, useTools: tools, think: think)
        }
        return total
    }

    /// Works a task through the loop. `answer` is how the caller gets a reply from the model, so chat can
    /// stream it. `earlier` is the chat so far. The result lands in `total.answer`.
    static func runLoop(prompt: String, earlier: String = "", setup: TestSetup, total: inout Reply,
                        answer: (AnswerPlan) async -> Reply) async {
        let started = Date()
        let rounds = max(setup.maxRounds, 1)
        let budget = Double(rounds) * secondsPerRound
        let task = HarnessTask(prompt: prompt, earlier: earlier)

        total.onStage?(.understand, 1)
        let kind = await understand(task, setup: setup, total: &total)
        total.toolLog.append("Understood: \(kind.rawValue) task")
        var state = LoopState(kind: kind, rules: kind == .writing ? task.rules : task.rules.onlyFinalLine)

        var best: Attempt?, last: Attempt?
        var roundsRun = 0
        for round in 1...rounds {
            if Task.isCancelled { break }
            roundsRun = round
            if round > 1, let problem = last?.problems.first { total.toolLog.append("Round \(round): \(problem.text)") }
            let evidenceBefore = state.evidence

            total.onStage?(.act, round)
            let hasTime = rounds > 1 && Date().timeIntervalSince(started) < budget / 2
            await act(task, state: &state, round: round, mayConfirm: hasTime, setup: setup, total: &total)

            total.onStage?(.answer, round)
            let attempt: Attempt
            if state.kind == .writing, round > 1, state.rules.unit != nil {
                let draft = await repairUnits(of: best?.text ?? "", task: task, state: &state, setup: setup, total: &total)
                attempt = judge(draft, cut: false, task: task, state: state)
            } else {
                let reply = await answer(plan(round: round, task: task, state: state, last: last, setup: setup))
                absorb(reply, into: &total)
                if let error = reply.error {
                    total.error = error
                    break
                }
                attempt = judge(reply.answer, cut: reply.stats?.stopReason == "length", task: task, state: state)
            }

            total.onStage?(.check, round)
            if attempt.rank < best?.rank ?? Int.max || best == nil {
                best = attempt
                total.onDraft?(attempt.text)
            }
            if attempt.problems.isEmpty { break }
            state.wantsEvidence = attempt.problems.contains(.unsupported) || state.evidence.isEmpty
            let stuck = last.map {
                $0.problems == attempt.problems && ($0.text == attempt.text || (state.kind != .writing && state.evidence == evidenceBefore))
            } ?? false
            last = attempt
            if stuck || Date().timeIntervalSince(started) > budget { break }
        }
        finish(best, rounds: roundsRun, task: task, state: state, total: &total)
    }

    private static func finish(_ best: Attempt?, rounds: Int, task: HarnessTask, state: LoopState, total: inout Reply) {
        var text = best?.text ?? ""
        if let result = state.result, !HarnessText.mentions(result, in: text, label: state.rules.finalLabel) {
            text = HarnessText.adding(result, to: text, label: state.rules.finalLabel)
            total.toolLog.append("Wrote the tool's result into the reply")
        } else if let problem = best?.problems.first {
            total.toolLog.append("Stopped after \(rounds) round\(rounds == 1 ? "" : "s"): \(problem.text)")
        } else if best != nil {
            total.toolLog.append("Passed the checks in round \(rounds)")
        }
        if state.readTheWeb {
            let filtered = PromptGuard.filterReply(text)
            text = filtered.text
            if filtered.blocked > 0 {
                total.toolLog.append("Removed \(filtered.blocked) untrusted link\(filtered.blocked == 1 ? "" : "s") from the reply")
            }
        }
        total.answer = text
        total.onDraft?(text)
    }

    // MARK: Answer

    /// Thinking is for working something out. Once a tool has the answer, or code will check the reply,
    /// it only uses up the tokens, which is how a small model ends up with no reply at all.
    private static func plan(round: Int, task: HarnessTask, state: LoopState, last: Attempt?, setup: TestSetup) -> AnswerPlan {
        var plan = AnswerPlan(task: task.ask)
        plan.addendum = evidenceNote(state.evidence)
        if let result = state.result {
            plan.addendum += "\n\nThe exact result is: \(result)"
            if let label = state.rules.finalLabel { plan.addendum += "\nEnd your reply with this line:\n\(label): \(result)" }
        }
        let needsWorking = state.kind == .document && task.needsCounting && state.result == nil
        if round > 1 || (!needsWorking && (!state.evidence.isEmpty || state.rules.hasShape)) {
            plan.think = setup.think == nil ? nil : false
            plan.maxTokens = tightTokens
        }
        if round > 1, let last {
            plan.addendum += "\n\nYour last reply had these problems:\n" + last.problems.map { "- \($0.text)" }.joined(separator: "\n")
            if !last.text.isEmpty, state.rules.hasShape {
                plan.addendum += "\n\nYour last reply:\n\(last.text)\n\nReply again with only the corrected text."
            } else {
                plan.addendum += "\n\nGive your final reply now, in a few lines."
            }
        }
        return plan
    }

    /// Rewrites each sentence or line that breaks a rule, one at a time, and lets code pick a version that
    /// passes. A small model ignores "start with S" but follows "its first word must be Storm", and it
    /// hits an exact word count about one try in two, so a few short tries do what one long one can't.
    private static func repairUnits(of draft: String, task: HarnessTask, state: inout LoopState, setup: TestSetup,
                                    total: inout Reply) async -> String {
        let rules = state.rules
        guard let unit = rules.unit else { return draft }
        var units = rules.units(of: draft)
        let needed = rules.count ?? units.count
        while units.count < needed { units.append("") }
        let broken = (0..<needed).filter { units[$0].isEmpty || !rules.violations(ofUnit: units[$0], at: $0).isEmpty }
        guard !broken.isEmpty else { return rules.joined(units) }

        // The same prompt at temperature 0 would bring back the same text.
        var varied = setup
        varied.temperature = max(setup.temperature, 0.7)
        let think: Bool?? = setup.think == nil ? .none : .some(false)
        let topic = task.topic
        var words: [String] = []
        if let letter = rules.startLetter {
            let request = "Topic: \(topic)\n\nList 12 different words that start with the letter \(letter.uppercased()) and fit this topic. One word per line, nothing else."
            let reply = await converse([ChatTurn(role: "user", content: request)], setup: varied, maxTokens: 80, useTools: false, think: think)
            absorb(reply, into: &total)
            words = rules.firstWords(in: reply.answer).filter { !state.usedWords.contains($0) }
        }

        for index in broken {
            var bestProblems = units[index].isEmpty ? Int.max : rules.violations(ofUnit: units[index], at: index).count
            var tries = 0
            while tries < triesPerUnit, bestProblems > 0, !Task.isCancelled {
                tries += 1
                let word = words.isEmpty ? nil : words.removeFirst()
                if let word { state.usedWords.insert(word) }
                let request = "Topic: \(topic)\n\n\(rules.request(at: index, firstWord: word))"
                let reply = await converse([ChatTurn(role: "user", content: request)], setup: varied, maxTokens: 80, useTools: false, think: think)
                absorb(reply, into: &total)
                guard let option = rules.firstUnit(in: reply.answer) else { continue }
                let problems = rules.violations(ofUnit: option, at: index).count
                if problems < bestProblems {
                    units[index] = option
                    bestProblems = problems
                }
            }
            total.toolLog.append("Rewrote \(unit.rawValue) \(index + 1) in \(tries) tr\(tries == 1 ? "y" : "ies")" + (bestProblems == 0 ? "" : ", still not right"))
        }
        return rules.joined(units.filter { !$0.isEmpty })
    }

    // MARK: Check

    private static func judge(_ raw: String, cut: Bool, task: HarnessTask, state: LoopState) -> Attempt {
        let text = state.rules.tidied(raw)
        guard !text.isEmpty else { return Attempt(text: "", problems: [.empty]) }
        var problems: [Problem] = []
        let finished = state.rules.finalLabel.map { raw.lowercased().contains($0.lowercased() + ":") } ?? false
        if cut, !finished { problems.append(.cutOff) }
        if let result = state.result, !HarnessText.mentions(result, in: text, label: state.rules.finalLabel) {
            problems.append(.missingResult)
        }
        if state.kind == .fact || state.kind == .document, state.result == nil, !state.evidence.isEmpty,
           !isSupported(text, by: state.evidence, task: task) {
            problems.append(.unsupported)
        }
        return Attempt(text: text, problems: problems + state.rules.violations(of: text).map(Problem.rule))
    }

    /// Whether what the reply adds to the question can be found in the evidence.
    private static func isSupported(_ text: String, by evidence: [String], task: HarnessTask) -> Bool {
        let asked = Set(PassageFinder.keywords(in: task.body))
        let added = PassageFinder.keywords(in: ModelTestSuite.finalAnswer(text)).filter { !asked.contains($0) }
        let source = Set(PassageFinder.keywords(in: evidence.joined(separator: " ")))
        return added.isEmpty || added.contains(where: source.contains)
    }

    /// Adds a model reply's cost and log to the total.
    static func absorb(_ part: Reply, into total: inout Reply) {
        total.thinkingTokens += part.thinkingTokens
        if total.firstToken == nil { total.firstToken = part.firstToken }
        total.toolLog += part.toolLog
        total.guardRemoved += part.guardRemoved
        if let stats = part.stats { total.stats = merge(total.stats, stats) }
    }
}
