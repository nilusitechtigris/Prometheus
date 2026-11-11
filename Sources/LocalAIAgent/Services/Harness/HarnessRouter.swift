import Foundation

/// What the one harness does with a task. A route is a fixed recipe of the harness's parts, and every task gets
/// exactly one. Direct is the route that does nothing: the model answers as it would with the harness off.
enum HarnessRoute: String, Codable, CaseIterable, Identifiable {
    case direct, exact, program, code, lookup, document, rules, build

    var id: String { rawValue }

    /// For the first line of a reply's steps.
    var title: String {
        switch self {
        case .direct: return "Direct"
        case .exact: return "Exact"
        case .program: return "Program"
        case .code: return "Code"
        case .lookup: return "Look up"
        case .document: return "Long text"
        case .rules: return "Rules"
        case .build: return "Build"
        }
    }

    /// The parts it switches on.
    var summary: String {
        switch self {
        case .direct: return "The model answers, as it would with the harness off."
        case .exact: return "Code works it out, the model words the reply, and code checks the reply states the result."
        case .program: return "The model writes a program, the sandbox runs it, and code checks the reply states what it printed."
        case .code: return "The model writes the code, the sandbox runs it on the examples in the message, and only code that fails goes back."
        case .lookup: return "The model answers from memory first, then from sentences a lookup found, and code checks one of them backs the answer."
        case .document: return "Code picks the passages that matter, and checks the reply against them."
        case .rules: return "The model answers, code measures the reply against the rules, and only what breaks one is written again."
        case .build: return "The model writes the files, code runs and tries them, and what fails is fixed."
        }
    }
}

/// Where a task was sent, and why.
struct HarnessRouting: Equatable {
    let route: HarnessRoute
    /// What the loop's steps are told this is. `.other` for the routes that don't go through the loop.
    let kind: TestLab.TaskKind
    /// Why, in plain words, for the reply's steps.
    let reason: String
    /// How many times the model was asked on the way.
    var calls = 0

    /// The first line of a reply's steps.
    var step: String { "Route: \(route.title.lowercased()), \(reason)" }
}

/// Which routes the harness may take, and whether it may ask the model. A route that's switched off is answered
/// directly. This table is what gets tuned, and only from runs on questions that are open to study.
struct HarnessPolicy: Equatable {
    var off: Set<HarnessRoute> = []
    var asksModel = true

    /// Raised whenever the routes, their rules, this table or a part changes, so runs made by different
    /// revisions are never compared as one.
    static let revision = 1
    static let current = HarnessPolicy()
}

/// Sends a task down one route. It stops at the first of three layers that decides:
///
/// 1. Where the task comes from. With the harness off, or in Dev for a question, the model just answers.
/// 2. Plain rules on the text. These are the rules the loop already had: a rule only fires when what it needs is
///    written in the message, so most tasks cost no model call here.
/// 3. One question to the model, for what the rules left over: could a short program work this out? It replies
///    with one letter, and it's asked twice with the two options the other way round. Only two answers that
///    agree send the task to a program. A small model that repeats the question, always picks the first option
///    or writes something else gets Direct, which is the safe mistake: the reply is the one the plain model gives.
///
/// The model never picks a lookup. A wrong pick there would put a question about searching the web in front of
/// someone who asked nothing of the kind.
@MainActor
enum HarnessRouter {
    // MARK: Chat and tests

    /// Layers 2 and 3. `ask` gets one reply from the model.
    static func route(_ task: HarnessTask, policy: HarnessPolicy = .current, ask: (String) async -> String) async -> HarnessRouting {
        var routing: HarnessRouting
        if let ruled = byRules(task) {
            routing = ruled
        } else if !hasSomethingToCompute(task.body) {
            routing = HarnessRouting(route: .direct, kind: .other, reason: "nothing here for code to work out or check")
        } else if !policy.asksModel {
            routing = HarnessRouting(route: .direct, kind: .other, reason: "no rule fits, and asking the model is switched off")
        } else {
            routing = await byAsking(task, ask: ask)
        }
        if routing.route != .direct, policy.off.contains(routing.route) {
            routing = HarnessRouting(route: .direct, kind: .other, reason: "the \(routing.route.title.lowercased()) route is switched off", calls: routing.calls)
        }
        return routing
    }

    /// Layer 2: what plain rules make of a task, with no model. Nil when they say nothing.
    static func byRules(_ task: HarnessTask) -> HarnessRouting? {
        // Before anything else: a message that asks for code may show a call to print, and that isn't code to run.
        if asksForCode(task.prompt) {
            return HarnessRouting(route: .code, kind: .other, reason: "code to write, which can be run")
        }
        if let exact = ExactTools.solve(task.body) {
            return HarnessRouting(route: .exact, kind: .calculation, reason: "code can work out \(exact.what)")
        }
        if TestLab.exactArithmetic(in: task.body) != nil {
            return HarnessRouting(route: .exact, kind: .calculation, reason: "a sum written in the message")
        }
        switch TestLab.strictKind(of: task) {
        case .code: return HarnessRouting(route: .program, kind: .code, reason: "code in the message, to run")
        case .document: return HarnessRouting(route: .document, kind: .document, reason: "a long text to read from")
        case .writing: return HarnessRouting(route: .rules, kind: .writing, reason: "rules code can measure")
        case .calculation: return HarnessRouting(route: .program, kind: .calculation, reason: "numbers a program can work from")
        case .fact: return HarnessRouting(route: .lookup, kind: .fact, reason: "a short question about a fact")
        case .other: return HarnessRouting(route: .direct, kind: .other, reason: "a question to reason about, with nothing for code to check")
        case nil: return nil
        }
    }

    /// True when the message asks for code to be written, as opposed to showing code and asking what it does.
    /// "Write a function", "implement the class", "write Python code that": a verb, at most three words, then what
    /// to write, with no "of" or "about" in between: "a list of five script ideas" and "a story about a function"
    /// ask for something else. A signature to fill in, or examples the code must pass, also count. A wrong yes
    /// costs nothing, because this route starts from the model's own reply and only acts on code it finds there.
    static func asksForCode(_ text: String) -> Bool {
        func has(_ pattern: String) -> Bool { text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        if has(#"\b(write|implement|create|define|complete|make|build|code)\s+(?:me\s+)?(?:an?\s+|the\s+|some\s+)?(?:(?!(?:of|about|for|on|with|in|to|from)\b)[\w+#.-]+\s+){0,3}(function|program|script|class|method|code)\b"#) { return true }
        if has(#"(?m)^\s*def \w+\(.*\):\s*$"#), has(#"\b(complete|implement|fill in|finish|write)\b"#) { return true }
        return has(#"(?m)^\s*assert \w+\("#) && has(#"\b(function|pass(es)? (these|the) tests?)\b"#)
    }

    private static let numberWords = #"\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|billion|half|third|quarter|twice|double|triple|dozen|percent)\b"#

    /// A program needs something to work from. With no number in the message, written either way, the model isn't
    /// even asked: logic puzzles and plain questions are where a small model's program is worse than its answer.
    static func hasSomethingToCompute(_ text: String) -> Bool {
        text.contains(where: \.isNumber) || text.range(of: numberWords, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: The question

    private static let programOption = "A short computer program could work out the exact answer."
    private static let otherOption = "It needs knowledge, judgement or writing, not a calculation."

    /// The one thing the model is asked. Only the start of a long message is sent: this is about what kind of
    /// task it is, and a small context is better spent on the answer.
    static func question(for task: HarnessTask, programFirst: Bool) -> String {
        """
        \(task.body.prefix(600))

        ---
        Which is true of the message above?
        A. \(programFirst ? programOption : otherOption)
        B. \(programFirst ? otherOption : programOption)
        Reply with one letter, A or B.
        """
    }

    /// The letter a reply picks: an A or a B standing by itself at the start of its first line, after at most the
    /// word "answer". Nil for anything else. "Both" and "Because" aren't letters.
    static func letter(in reply: String) -> Character? {
        let line = reply.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        guard let regex = try? NSRegularExpression(pattern: #"^\W*(?:answer\W+)?([AB])(?![A-Za-z])"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        return line[range].uppercased().first
    }

    /// Layer 3. A "no" the first time is final, so most tasks that get here cost one short call.
    private static func byAsking(_ task: HarnessTask, ask: (String) async -> String) async -> HarnessRouting {
        let first = letter(in: await ask(question(for: task, programFirst: true)))
        guard first == "A" else {
            let reason = first == nil ? "the model's answer wasn't clear, so it answers directly" : "the model says this isn't for a program"
            return HarnessRouting(route: .direct, kind: .other, reason: reason, calls: 1)
        }
        let second = letter(in: await ask(question(for: task, programFirst: false)))
        guard second == "B" else {
            return HarnessRouting(route: .direct, kind: .other, reason: "the model's two answers didn't agree, so it answers directly", calls: 2)
        }
        return HarnessRouting(route: .program, kind: .calculation, reason: "the model says a program can work this out", calls: 2)
    }

    // MARK: Dev

    /// Layer 1 in Dev, where the task comes with a project. The word rule Dev already had sorts a question, which
    /// the model answers from the files, from a change, which is built.
    static func route(dev job: DevJob, harnessOn: Bool) -> HarnessRouting {
        guard harnessOn else { return HarnessRouting(route: .direct, kind: .other, reason: "the harness is off") }
        switch DevAgent.intent(of: job) {
        case .ask: return HarnessRouting(route: .direct, kind: .other, reason: "a question about the project")
        case .change: return HarnessRouting(route: .build, kind: .other, reason: job.failure == nil ? "something to make or change" : "a failed run to fix")
        }
    }
}
