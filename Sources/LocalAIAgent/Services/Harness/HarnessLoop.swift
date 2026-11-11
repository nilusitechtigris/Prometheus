import Foundation

/// The harness's loop. After understanding a task it goes Act, Answer, Check, and back to Act with
/// what Check found, until the reply passes, a round changes nothing, or the budget of rounds and
/// seconds runs out. It keeps the best attempt so far, so another round can't make the result worse.
/// Check is code, not the model's opinion of itself, and it sees only the task, never an expected
/// answer, so it works the same on anything.
///
/// v3 keeps thinking off wherever it can, to save tokens. v4 is the same loop with the model thinking at
/// every step it takes part in, when Think is on. A failed check reaches the next round's thinking as
/// the problems it has to fix, so Check stays code, and a step that thinks itself out of room goes again
/// without thinking, so v4 can't end up with less than v3 would have had.
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
        /// Set on v5's turns, which stand alone instead of following the chat.
        var agent: AgentTurn?
        /// Set by the one harness when it wants the reply the plain model gives. The caller then sends exactly the
        /// request it sends with the harness off, and nothing else in this plan counts.
        var direct = false
    }

    /// Something Check found wrong with a reply.
    enum Problem: Equatable {
        case empty, cutOff, missingResult, unsupported
        case rule(String)

        var text: String {
            switch self {
            case .empty: return "The reply was empty."
            case .cutOff: return "The reply was cut off before it finished."
            case .missingResult: return "The reply left out the result."
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
        /// The person said no to a lookup for this reply, so later rounds don't try again.
        var webDeclined = false
        /// True in v6, where evidence has to meet stricter rules (see HarnessEvidence.swift).
        var strict = false
        /// The sentences the model was given to answer from, in v6.
        var quotes: [String] = []
        /// Sentences of every page opened, to look for what backs an answer.
        var pageSentences: [String] = []
        /// What the model answered before any page was read. Nil when it wasn't sure or wasn't asked.
        var memoryAnswer: String?
        /// True once the two answers' sentences have been put side by side, which happens once.
        var reconciled = false
        /// True when the result came from plain code, as opposed to a program the model wrote.
        var computedByCode = false
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

    struct Attempt {
        let text: String
        let problems: [Problem]

        /// Lower is better. Any reply beats no reply, however many problems it has.
        var rank: Int { text.isEmpty ? Int.max : problems.count }
    }

    /// Time a task gets per round. A round that has started always finishes.
    private static let secondsPerRound = 60.0
    /// The same with thinking at each step. A step can think for 80 seconds at 25 tokens a second, the
    /// slowest speed in the saved runs, and most rounds have two steps that call the model.
    private static let thinkingSecondsPerRound = 180.0
    /// Plenty for stating a result, and little enough that thinking can't use up a small context.
    static let tightTokens = 384
    private static let triesPerUnit = 6

    /// Tokens a step gets on top of its reply for thinking, since a model's limit counts both. Qwen3 1.7B
    /// used 350 to over 2,000 at a single step, and writing a program used the most. A quarter of the
    /// context still leaves room for the prompt and the reply.
    static func thinkingRoom(_ setup: TestSetup) -> Int { min(setup.context / 4, 2_048) }

    /// One step's request to the model, for a step that needs a short reply in `tokens` tokens. Its cost
    /// lands in `total`. In v4 the model thinks first, and if that leaves no reply the step goes again
    /// without thinking. `log` is whether this step gets its own line, since a rewrite logs for itself.
    static func stepReply(_ stage: HarnessStage, _ turns: [ChatTurn], setup: TestSetup, tokens: Int, log: Bool = true,
                          total: inout Reply) async -> Reply {
        if setup.thinksAtSteps {
            // Chat shows thinking as it comes, in the small batches it takes to keep up.
            let tell = total.onThought
            var unsent = (total.thinkingTokens > 0 ? "\n\n" : "") + "\(stage.title):\n", sent = Date.distantPast
            let reply = await converse(turns, setup: setup, maxTokens: tokens + thinkingRoom(setup), useTools: false, think: true) { thought in
                unsent += thought
                if Date().timeIntervalSince(sent) > 0.05 {
                    tell?(unsent)
                    unsent = ""
                    sent = Date()
                }
            }
            if reply.thinkingTokens > 0 { tell?(unsent) }
            absorb(reply, into: &total)
            if log { noteThinking(stage, reply, total: &total) }
            if hasReply(reply) { return reply }
            total.toolLog.append("\(stage.title): ran out of room thinking, so it went again without")
        }
        let reply = await converse(turns, setup: setup, maxTokens: tokens, useTools: false, think: setup.think == nil ? nil : false)
        absorb(reply, into: &total)
        return reply
    }

    /// False when thinking used up the tokens before any reply came. Being stopped or an error isn't that.
    private static func hasReply(_ reply: Reply) -> Bool {
        reply.error != nil || Task.isCancelled || !reply.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func noteThinking(_ stage: HarnessStage, _ reply: Reply, total: inout Reply) {
        if reply.thinkingTokens > 0 { total.toolLog.append("\(stage.title): thought for \(reply.thinkingTokens) tokens") }
    }

    /// Works a task through the loop. `answer` is how the caller gets a reply from the model, so chat can
    /// stream it. `earlier` is the chat so far. The result lands in `total.answer`.
    /// `thinkEachStep` is the difference between v3 and v4, and only counts with thinking on.
    /// `strict` is v6: the same loop with stricter evidence, and at most two rounds, which is where studies of
    /// repair loops on small models found nearly all of the gain.
    static func runLoop(prompt: String, earlier: String = "", setup: TestSetup, thinkEachStep: Bool = false, strict: Bool = false,
                        total: inout Reply, answer: (AnswerPlan) async -> Reply) async {
        let started = Date()
        let rounds = strict ? min(max(setup.maxRounds, 1), 2) : max(setup.maxRounds, 1)
        let thinks = thinkEachStep && setup.think == true
        let budget = Double(rounds) * (thinks ? thinkingSecondsPerRound : secondsPerRound)
        let task = HarnessTask(prompt: prompt, earlier: earlier)
        var setup = setup
        if thinks { setup.thinkingUntil = started.addingTimeInterval(budget) }

        total.onStage?(.understand, 1)
        let kind = strict ? await understandStrict(task, setup: setup, total: &total) : await understand(task, setup: setup, total: &total)
        total.toolLog.append("Understood: \(kind.rawValue) task")
        var state = LoopState(kind: kind, rules: kind == .writing ? task.rules : task.rules.onlyFinalLine)
        state.strict = strict
        // v6 doesn't cut a reply to a word count, so a one-sentence count is put where a rewrite can meet it.
        if strict { state.rules = state.rules.countingTheOnlyUnit }

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
            var attempt: Attempt
            if state.kind == .writing, round > 1, state.rules.unit != nil, !strict || state.rules.hasUnitRules {
                let draft = await repairUnits(of: best?.text ?? "", task: task, state: &state, setup: setup, total: &total)
                attempt = judge(draft, cut: false, task: task, state: state)
            } else {
                var answerPlan = plan(round: round, task: task, state: state, last: last, setup: setup)
                var reply = await answer(answerPlan)
                absorb(reply, into: &total)
                if answerPlan.think == true {
                    noteThinking(.answer, reply, total: &total)
                    if !hasReply(reply) {
                        total.toolLog.append("Answer: ran out of room thinking, so it went again without")
                        answerPlan.think = false
                        answerPlan.maxTokens = tightTokens
                        reply = await answer(answerPlan)
                        absorb(reply, into: &total)
                    }
                }
                if let error = reply.error {
                    total.error = error
                    break
                }
                attempt = judge(reply.answer, cut: reply.stats?.stopReason == "length", task: task, state: state)
            }
            if strict { attempt = reconciled(attempt, task: task, state: &state, total: &total, mayGoAgain: round < rounds) }

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

    static func finish(_ best: Attempt?, rounds: Int, task: HarnessTask, state: LoopState, total: inout Reply) {
        var text = best?.text ?? ""
        if let result = state.result, !HarnessText.mentions(result, in: text, label: state.rules.finalLabel) {
            text = HarnessText.adding(result, to: text, label: state.rules.finalLabel)
            total.toolLog.append("Wrote the result into the reply")
        } else if state.strict {
            // v6 ends its steps with what was checked instead, just below.
        } else if let problem = best?.problems.first {
            total.toolLog.append("Stopped after \(rounds) round\(rounds == 1 ? "" : "s"): \(problem.text)")
        } else if best != nil {
            total.toolLog.append("Passed the checks in round \(rounds)")
        }
        if state.strict { total.toolLog.append(checkedLine(best, state: state)) }
        if state.readTheWeb {
            let filtered = PromptGuard.filterReply(text)
            text = filtered.text
            if filtered.blocked > 0 {
                total.toolLog.append("Removed \(filtered.blocked) untrusted link\(filtered.blocked == 1 ? "" : "s") from the reply")
            }
        }
        total.answer = text
        total.result = state.result
        total.onDraft?(text)
    }

    // MARK: Answer

    /// Thinking is for working something out. Once a tool has the answer, or code will check the reply,
    /// it only uses up the tokens, which is how a small model ends up with no reply at all. So v4 gives
    /// it room for both, unless the last reply got cut off, when thinking is what there wasn't room for.
    private static func plan(round: Int, task: HarnessTask, state: LoopState, last: Attempt?, setup: TestSetup) -> AnswerPlan {
        var plan = AnswerPlan(task: task.ask)
        plan.addendum = state.strict && !state.quotes.isEmpty ? quotedNote(state.evidence) : evidenceNote(state.evidence)
        if let result = state.result {
            plan.addendum += "\n\nThe exact result is: \(result)"
            if let label = state.rules.finalLabel { plan.addendum += "\nEnd your reply with this line:\n\(label): \(result)" }
        }
        let needsWorking = state.kind == .document && task.needsCounting && state.result == nil
        let tight = round > 1 || (!needsWorking && (!state.evidence.isEmpty || state.rules.hasShape))
        if setup.thinksAtSteps, last?.problems.contains(.cutOff) != true {
            plan.think = true
            if tight { plan.maxTokens = tightTokens + thinkingRoom(setup) }
        } else if tight {
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
    static func repairUnits(of draft: String, task: HarnessTask, state: inout LoopState, setup: TestSetup,
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
        let topic = task.topic
        var words: [String] = []
        if let letter = rules.startLetter {
            let request = "Topic: \(topic)\n\nList 12 different words that start with the letter \(letter.uppercased()) and fit this topic. One word per line, nothing else."
            let reply = await stepReply(.answer, [ChatTurn(role: "user", content: request)], setup: varied, tokens: 80, log: false, total: &total)
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
                let reply = await stepReply(.answer, [ChatTurn(role: "user", content: request)], setup: varied, tokens: 80, log: false, total: &total)
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

    static func judge(_ raw: String, cut: Bool, task: HarnessTask, state: LoopState) -> Attempt {
        // v6 doesn't cut a reply down to a word count: that passes the rule and breaks the sentence.
        let text = state.rules.tidied(raw, cutting: !state.strict)
        guard !text.isEmpty else { return Attempt(text: "", problems: [.empty]) }
        var problems: [Problem] = []
        let finished = state.rules.finalLabel.map { raw.lowercased().contains($0.lowercased() + ":") } ?? false
        if cut, !finished { problems.append(.cutOff) }
        if let result = state.result, !HarnessText.mentions(result, in: text, label: state.rules.finalLabel) {
            problems.append(.missingResult)
        }
        if state.strict, state.kind == .fact {
            if state.result == nil, !state.quotes.isEmpty, !isBacked(text, by: state.quotes, task: task) { problems.append(.unsupported) }
        } else if state.kind == .fact || state.kind == .document, state.result == nil, !state.evidence.isEmpty,
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
        total.modelToolCalls += part.modelToolCalls
        if let stats = part.stats { total.stats = merge(total.stats, stats) }
    }
}
