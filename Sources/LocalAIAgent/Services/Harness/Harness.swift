import Foundation

/// The one harness. Where the versions before it worked every task the same way, this one sends each task down
/// one route (see `HarnessRouter`) and switches on only the parts that route needs. Three things hold on every
/// route:
///
/// - Where it can, it starts from the reply the plain model gives, asked for exactly as with the harness off. So
///   a task the harness has nothing for costs nothing and loses nothing.
/// - That reply is only replaced when code has a reason it can state: two programs that agree, an example from
///   the message that the reply's code fails, a rule the reply measurably breaks, a sentence on a page.
/// - A reply that already passes is never touched. Editing code or text that was right is where repair loops
///   lose what they gain.
///
/// The parts are the ones the earlier versions have. The steps that put them together are written out here, so a
/// change to this harness can't change what v1 to v6 do. `checks/traces` holds them to that.
extension TestLab {
    /// Works a task through the one harness. `answer` is how the caller gets a reply from the model, so chat can
    /// stream it. `earlier` is the chat so far. The result lands in `total.answer`.
    static func runOne(prompt: String, earlier: String = "", setup: TestSetup, policy: HarnessPolicy = .current,
                       total: inout Reply, answer: (AnswerPlan) async -> Reply) async {
        let task = HarnessTask(prompt: prompt, earlier: earlier)
        total.onStage?(.understand, 1)
        var routing = await HarnessRouter.route(task, policy: policy) { question in
            // One letter is wanted, so the room is small. A model that can't stop thinking uses it up and gets Direct.
            let reply = await stepReply(.understand, [ChatTurn(role: "user", content: question)], setup: setup, tokens: 16, log: false, total: &total)
            return reply.answer
        }
        if routing.route == .lookup, !WebConsent.shared.lookupsPossible {
            routing = HarnessRouting(route: .direct, kind: .other, reason: "web lookups are off, so the model answers from what it knows", calls: routing.calls)
        }
        total.route = routing.route
        total.toolLog.append(routing.step)
        if Task.isCancelled { return }

        switch routing.route {
        case .direct, .build:
            // Build is Dev's, where there's a project to build in. A task that reaches here is answered.
            await ownReply(to: task, total: &total, answer: answer)
        case .exact, .document:
            await runLoop(prompt: prompt, earlier: earlier, setup: setup, strict: true, total: &total, answer: answer)
        case .program:
            if routing.kind == .code {
                // Code shown in the message: the loop runs it and has the reply state what it printed.
                await runLoop(prompt: prompt, earlier: earlier, setup: setup, strict: true, total: &total, answer: answer)
            } else {
                await programRoute(task, setup: setup, total: &total, answer: answer)
            }
        case .code:
            await codeRoute(task, total: &total, answer: answer)
        case .rules:
            await rulesRoute(task, setup: setup, total: &total, answer: answer)
        case .lookup:
            await lookupRoute(task, prompt: prompt, earlier: earlier, setup: setup, total: &total, answer: answer)
        }
    }

    /// The reply the plain model gives, asked for exactly as with the harness off. It becomes the reply so far.
    @discardableResult
    private static func ownReply(to task: HarnessTask, total: inout Reply, answer: (AnswerPlan) async -> Reply) async -> Reply {
        total.onStage?(.answer, 1)
        var plan = AnswerPlan(task: task.prompt)
        plan.direct = true
        let reply = await answer(plan)
        absorb(reply, into: &total)
        total.answer = reply.answer
        total.error = reply.error
        return reply
    }

    // MARK: Program

    /// A word problem. The model's own answer comes first. A program is then written and run, and three things
    /// can happen. The program agrees with the reply: done, and checked. It disagrees: a second program, written
    /// another way, decides. If the two programs agree, their result goes into a reworded reply. If the second
    /// sides with the model, the reply stands. With no two of the three agreeing, the reply stands and the steps
    /// say it wasn't checked: a program is a second opinion, and a small model's program is wrong often enough
    /// that one alone shouldn't overrule its answer.
    private static func programRoute(_ task: HarnessTask, setup: TestSetup, total: inout Reply, answer: (AnswerPlan) async -> Reply) async {
        let own = await ownReply(to: task, total: &total, answer: answer)
        if own.error != nil || Task.isCancelled { return }

        total.onStage?(.act, 1)
        var state = LoopState(kind: .calculation, rules: task.rules.onlyFinalLine)
        state.strict = true
        await act(task, state: &state, round: 1, mayConfirm: false, setup: setup, total: &total)
        if Task.isCancelled { return }
        let label = state.rules.finalLabel
        guard let first = state.result else {
            total.toolLog.append("Not checked: no program ran to the end, so this is the model's own working")
            return
        }
        total.onStage?(.check, 1)
        if states(first, in: own.answer, label: label) {
            total.result = first
            total.toolLog.append(state.computedByCode ? "Checked: code worked this out, and the reply agrees" : "Checked: a program was run for this, and the reply agrees with what it printed")
            return
        }
        if state.computedByCode {
            // Plain code, not a program the model wrote: there's nothing to doubt, so its result goes in.
            total.toolLog.append("The reply said otherwise, so it's worded again around the result")
            await reword(task, around: first, why: "Code worked this out.", state: state, own: own, setup: setup, total: &total, answer: answer)
            return
        }

        total.onStage?(.act, 2)
        let note = "An earlier program printed \(first.prefix(70)). Solve the task again a different way, to check that."
        let second = await writeProgram(task, note: note, state: &state, setup: setup, total: &total).flatMap(HarnessText.keyResult(of:))
        if Task.isCancelled { return }
        total.onStage?(.check, 2)
        if let second, second == first {
            total.toolLog.append("A second program agreed, and the reply said otherwise, so it's worded again around the result")
            await reword(task, around: first, why: "Two programs worked this out and agree.", state: state, own: own, setup: setup, total: &total, answer: answer)
        } else if let second, states(second, in: own.answer, label: label) {
            total.result = second
            total.toolLog.append("Checked: a second program agrees with the reply, and the first didn't")
        } else {
            total.toolLog.append("Not checked: the reply and the program\(second == nil ? "" : "s") disagree and nothing settled it, so this is the model's own working")
        }
    }

    /// Whether a reply states a result. A number has to be there as a number: "180" isn't stated by a reply that
    /// says 1800, which reading it as a run of characters would allow.
    static func states(_ result: String, in reply: String, label: String?) -> Bool {
        guard let value = Double(result) else { return HarnessText.mentions(result, in: reply, label: label) }
        let scope = label == nil ? reply : ModelTestSuite.finalAnswer(reply)
        return ModelTestSuite.numbers(in: scope).contains(value)
    }

    /// Has the model state a result code is sure of, and writes it in if the reply still leaves it out.
    private static func reword(_ task: HarnessTask, around result: String, why: String, state: LoopState, own: Reply, setup: TestSetup,
                               total: inout Reply, answer: (AnswerPlan) async -> Reply) async {
        var state = state
        state.result = result
        total.onStage?(.answer, 2)
        var plan = AnswerPlan(task: task.ask)
        plan.addendum = "\n\n\(why) The exact result is: \(result)"
        if let label = state.rules.finalLabel { plan.addendum += "\nEnd your reply with this line:\n\(label): \(result)" }
        plan.addendum += "\n\nGive your final reply now, in a few lines."
        plan.think = setup.think == nil ? nil : false
        plan.maxTokens = tightTokens
        let reply = await answer(plan)
        absorb(reply, into: &total)
        // With no usable second reply, the result is written into the first.
        let text = reply.error == nil && !reply.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? reply.answer : own.answer
        let attempt = judge(text, cut: reply.stats?.stopReason == "length", task: task, state: state)
        finish(attempt, rounds: 2, task: task, state: state, total: &total)
    }

    // MARK: Code

    /// A request for code. The model answers as it would with the harness off. The sandbox then runs the reply's
    /// code on the examples the message itself gives, or only checks that it's valid when there are none. Code
    /// that fails goes back with what went wrong, twice at most, and the first version that passes stays. A
    /// version that passes is never asked for again. Tests the model writes for itself are not used as a judge.
    private static func codeRoute(_ task: HarnessTask, total: inout Reply, answer: (AnswerPlan) async -> Reply) async {
        let own = await ownReply(to: task, total: &total, answer: answer)
        if own.error != nil || Task.isCancelled { return }
        guard let firstCode = CodeCheck.python(in: own.answer) else {
            total.toolLog.append("Nothing here for code to check: the reply holds no Python")
            return
        }
        let examples = CodeCheck.examples(in: task.prompt)
        total.onStage?(.check, 1)
        var best = (text: own.answer, code: firstCode, outcome: await CodeCheck.run(firstCode, examples: examples))
        total.toolLog.append(best.outcome.line)

        var fixes = 0
        while !best.outcome.passed, fixes < 2, !Task.isCancelled {
            fixes += 1
            total.toolLog.append("Round \(fixes + 1): \(best.outcome.problem.prefix(160))")
            total.onStage?(.answer, fixes + 1)
            var plan = AnswerPlan(task: task.prompt)
            plan.addendum = "\n\nYour code was run and it failed. \(best.outcome.problem)\n\nYour code was:\n```python\n\(best.code.prefix(6_000))\n```\n\n"
                + "Fix it, and reply with the whole corrected code in one code block."
            let reply = await answer(plan)
            absorb(reply, into: &total)
            guard reply.error == nil, let fixed = CodeCheck.python(in: reply.answer) else {
                total.toolLog.append("The fix held no code" + HarnessTools.failedMark)
                break
            }
            total.onStage?(.check, fixes + 1)
            let outcome = await CodeCheck.run(fixed, examples: examples)
            total.toolLog.append(outcome.line)
            // Only a version that does better takes the place of the one before it.
            if outcome.score > best.outcome.score { best = (reply.answer, fixed, outcome) }
        }
        total.answer = best.text
        total.onDraft?(best.text)
        total.toolLog.append(best.outcome.verdict)
    }

    // MARK: Rules

    /// Writing with rules code can measure. The model answers as it would with the harness off, with nothing
    /// capped and nothing cut. A reply that keeps every rule is left exactly as written. One that breaks a rule is
    /// first tidied by code (a lead-in line, stray emphasis), and if that isn't enough it goes back: a sentence or
    /// line at a time where the rules are about those, else as a whole with the broken rules named. Twice at
    /// most, and the attempt that breaks the fewest rules is the reply.
    private static func rulesRoute(_ task: HarnessTask, setup: TestSetup, total: inout Reply, answer: (AnswerPlan) async -> Reply) async {
        let own = await ownReply(to: task, total: &total, answer: answer)
        if own.error != nil || Task.isCancelled { return }
        var state = LoopState(kind: .writing, rules: task.rules.countingTheOnlyUnit)
        state.strict = true
        let rules = state.rules
        let cut = own.stats?.stopReason == "length"

        total.onStage?(.check, 1)
        let written = own.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !written.isEmpty, !cut, rules.violations(of: written).isEmpty {
            total.toolLog.append("Checked: the rules in the message, by code. The reply is as the model wrote it")
            return
        }
        var best = judge(own.answer, cut: cut, task: task, state: state)
        if best.problems.isEmpty {
            total.toolLog.append("Tidied the reply so it keeps the rules")
        }
        var last = best
        var round = 1
        while !best.problems.isEmpty, round < 3, !Task.isCancelled {
            round += 1
            if let problem = last.problems.first { total.toolLog.append("Round \(round): \(problem.text)") }
            total.onStage?(.answer, round)
            let attempt: Attempt
            if rules.unit != nil, rules.hasUnitRules, !best.text.isEmpty {
                let draft = await repairUnits(of: best.text, task: task, state: &state, setup: setup, total: &total)
                attempt = judge(draft, cut: false, task: task, state: state)
            } else {
                var plan = AnswerPlan(task: task.ask)
                plan.addendum = "\n\nYour last reply had these problems:\n" + last.problems.map { "- \($0.text)" }.joined(separator: "\n")
                plan.addendum += last.text.isEmpty ? "\n\nReply again." : "\n\nYour last reply:\n\(last.text)\n\nReply again with only the corrected text."
                let reply = await answer(plan)
                absorb(reply, into: &total)
                if let error = reply.error {
                    total.error = error
                    break
                }
                attempt = judge(reply.answer, cut: reply.stats?.stopReason == "length", task: task, state: state)
            }
            total.onStage?(.check, round)
            let stuck = attempt.problems == last.problems && attempt.text == last.text
            last = attempt
            if attempt.rank < best.rank { best = attempt }
            if stuck { break }
        }
        total.answer = best.text
        total.onDraft?(best.text)
        total.toolLog.append(best.problems.first.map { "Not checked: \($0.text)" } ?? "Checked: the rules in the message, by code")
    }

    // MARK: Look up

    /// Words that ask for what is true now, which a model's memory can't know.
    private static let fresh = #"\b(current(ly)?|latest|newest|today|tonight|now|this (year|month|week)|recent(ly)?|still|so far|20[2-9]\d)\b"#

    /// A fact. A page talks a small model out of what it knew more often than it tells it something new, so the
    /// web is only asked when the model isn't sure. It answers from memory three times, in one short line, twice
    /// with some chance in the wording. The same answer each time is knowledge, and then it replies as it would
    /// with the harness off and nothing is searched. Anything else, or a question about what is true now, goes
    /// to the lookup: the page that covers what the question names, a few sentences from it, and a reply that
    /// only counts as backed when one sentence holds it.
    private static func lookupRoute(_ task: HarnessTask, prompt: String, earlier: String, setup: TestSetup,
                                    total: inout Reply, answer: (AnswerPlan) async -> Reply) async {
        let asksForNow = task.body.range(of: fresh, options: [.regularExpression, .caseInsensitive]) != nil
        if !asksForNow {
            total.onStage?(.act, 1)
            var varied = setup
            varied.temperature = max(setup.temperature, 0.8)
            var said: [String] = []
            for attempt in 0..<3 where !Task.isCancelled {
                guard let line = await fromMemory(task, setup: attempt == 0 ? setup : varied, total: &total) else { break }
                if let before = said.last, !sameAnswer(before, line, task: task) { break }
                said.append(line)
            }
            if Task.isCancelled { return }
            if said.count == 3 {
                total.toolLog.append("The same answer from memory three times, so nothing was looked up")
                await ownReply(to: task, total: &total, answer: answer)
                total.toolLog.append("Not checked: answered from memory, with no lookup")
                return
            }
            total.toolLog.append(said.isEmpty ? "Not sure from memory, so it's looked up" : "Memory gave different answers, so it's looked up")
        }
        await runLoop(prompt: prompt, earlier: earlier, setup: setup, strict: true, total: &total, answer: answer)
    }

    /// Whether two short answers name the same thing: the same names and numbers, or one holding all of the
    /// other's. "Gerd Faltings, in 1983" and "Faltings" agree. "1983" and "1986" don't.
    static func sameAnswer(_ first: String, _ second: String, task: HarnessTask) -> Bool {
        let one = Set(distinctive(first, beyond: task.body, leading: true).map { $0.lowercased() })
        let two = Set(distinctive(second, beyond: task.body, leading: true).map { $0.lowercased() })
        if !one.isEmpty, !two.isEmpty { return one.isSubset(of: two) || two.isSubset(of: one) }
        // With no name or number to go by in one of them, they have to read the same.
        func plain(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
        return plain(first) == plain(second)
    }
}

/// Runs the Python a reply holds, in the sandbox, against the examples its message gave. Only examples the
/// person wrote count: a line of the message that starts with `assert`. With none, the code is only checked for
/// being valid Python, because running a program that waits for input or a file would call working code broken.
enum CodeCheck {
    struct Outcome {
        /// Examples that held, or -1 when Python couldn't read the code at all.
        let score: Int
        let examples: Int
        let passed: Bool
        /// What went wrong, in words for the model. Empty when it passed.
        let problem: String

        /// One line for the reply's steps.
        var line: String {
            if examples == 0 { return passed ? "Ran a check: the code is valid Python" : "Ran a check: Python can't read the code" + HarnessTools.failedMark }
            return "Ran the code on the \(examples) example\(examples == 1 ? "" : "s") in the message: \(max(score, 0)) held" + (passed ? "" : HarnessTools.failedMark)
        }

        /// The last line of the steps: what was checked, said plainly.
        var verdict: String {
            if passed {
                return examples == 0 ? "Checked: the code is valid Python. The message gave no examples to run it on"
                                     : "Checked: the code passes the \(examples) example\(examples == 1 ? "" : "s") in the message"
            }
            return examples == 0 ? "Not checked: Python still can't read the code" : "Not checked: the code still fails \(examples - max(score, 0)) of the \(examples) examples in the message"
        }
    }

    /// The examples a message gives: its lines that start with `assert`, one to a line.
    static func examples(in message: String) -> [String] {
        message.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "`")) }
            .filter { $0.hasPrefix("assert ") }
    }

    /// The Python in a reply: its fenced blocks that are tagged as Python, or untagged and reading like it. Blocks
    /// that define something come before ones that only use it. Nil when there is none. A reply that is nothing
    /// but code, with no fence, counts too.
    static func python(in reply: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"```([a-zA-Z0-9+#-]*)[^\n]*\n(.*?)(?:```|\z)"#, options: .dotMatchesLineSeparators) else { return nil }
        func readsLikePython(_ code: String) -> Bool {
            code.range(of: #"(?m)^\s*(def |class |import |from \w+ import |print\(|for .+ in .+:|while .+:|if .+:|[A-Za-z_]\w* *=[^=])"#, options: .regularExpression) != nil
        }
        var blocks: [String] = []
        for match in regex.matches(in: reply, range: NSRange(reply.startIndex..., in: reply)) {
            guard let tag = Range(match.range(at: 1), in: reply), let body = Range(match.range(at: 2), in: reply) else { continue }
            let name = reply[tag].lowercased(), code = String(reply[body])
            if ["python", "py", "python3"].contains(name) || (name.isEmpty && readsLikePython(code)) { blocks.append(code) }
        }
        if blocks.isEmpty {
            let bare = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reply.contains("```"), bare.range(of: #"^(def |class |import |from \w+ import )"#, options: .regularExpression) != nil else { return nil }
            return bare + "\n"
        }
        let defining = blocks.filter { $0.range(of: #"(?m)^\s*(def |class )"#, options: .regularExpression) != nil }
        let code = (defining.isEmpty ? blocks : defining).joined(separator: "\n\n")
        return code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : code
    }

    /// Loads the code and tries each example on it, in the sandbox: no internet, no files of yours, ten seconds.
    /// What the code prints, and anything it tries to read from the keyboard, is kept away from the count.
    static func run(_ code: String, examples: [String]) async -> Outcome {
        let mark = "check-\(UUID().uuidString.prefix(8))"
        let script = """
        import ast, io, sys, traceback
        MARK = "\(mark)"
        src = open("reply.py").read()
        examples = [line for line in open("examples.txt").read().split("\\n") if line.strip()]
        def said(error):
            return " ".join("".join(traceback.format_exception_only(type(error), error)).split())[:300]
        try:
            compiled = compile(src, "reply.py", "exec")
        except SyntaxError as error:
            print(MARK, "SYNTAX", "line", error.lineno, error.msg)
            raise SystemExit(0)
        out = sys.stdout
        sys.stdout = io.StringIO()
        sys.stdin = io.StringIO("")
        env = {"__name__": "reply"}
        loaded = None
        try:
            exec(compiled, env)
        except BaseException as error:
            loaded = said(error)
        def explain(line):
            try:
                test = ast.parse(line).body[0].test
                if isinstance(test, ast.Compare) and len(test.ops) == 1 and isinstance(test.ops[0], ast.Eq):
                    got = eval(compile(ast.Expression(test.left), "example", "eval"), env)
                    want = eval(compile(ast.Expression(test.comparators[0]), "example", "eval"), env)
                    return "it gave " + repr(got)[:200] + " and the example expects " + repr(want)[:200]
            except BaseException as error:
                return said(error)
            return "the example isn't true"
        passed, first = 0, None
        for line in examples:
            try:
                exec(line, env)
                passed += 1
            except BaseException as error:
                if first is None:
                    first = line[:300] + " :: " + (explain(line) if isinstance(error, AssertionError) else said(error))
        sys.stdout = out
        print(MARK, "RESULT", passed, len(examples))
        if loaded: print(MARK, "LOAD", loaded)
        if first: print(MARK, "FIRST", first)
        """
        let outcome = await CodeRunner.run(script, language: .python, files: ["reply.py": code, "examples.txt": examples.joined(separator: "\n")])
        func marked(_ kind: String) -> String? {
            outcome.output.split(whereSeparator: \.isNewline).last { $0.hasPrefix("\(mark) \(kind) ") }.map { String($0.dropFirst(mark.count + kind.count + 2)) }
        }
        if let syntax = marked("SYNTAX") {
            return Outcome(score: -1, examples: examples.count, passed: false, problem: "Python can't read it: \(syntax).")
        }
        guard let result = marked("RESULT") else {
            // No count came back: the code never finished, or took the whole run down with it.
            let limit = outcome.succeeded ? "It stopped the run before the examples were tried." : "It didn't finish in the ten seconds it gets, so it may loop for ever or wait for input."
            return Outcome(score: 0, examples: examples.count, passed: false, problem: limit)
        }
        let score = Int(result.split(separator: " ").first ?? "") ?? 0
        if examples.isEmpty { return Outcome(score: 0, examples: 0, passed: true, problem: "") }
        if score == examples.count { return Outcome(score: score, examples: examples.count, passed: true, problem: "") }
        var problem = "\(examples.count - score) of the \(examples.count) example\(examples.count == 1 ? "" : "s") in the message failed."
        if let first = marked("FIRST") {
            let parts = first.components(separatedBy: " :: ")
            problem += " The first: `\(parts[0])`: \(parts.dropFirst().joined(separator: " :: "))."
        }
        if let loaded = marked("LOAD") { problem += " While the code was loading it raised: \(loaded)." }
        return Outcome(score: score, examples: examples.count, passed: false, problem: problem)
    }
}
