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
        // Before the others: a message that asks for code may show a call to print, and that isn't code to run. Only
        // what is asked counts, not a long text it came with.
        if asksForCode(task.body) {
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
        case .fact:
            // A lookup needs something to look for: a name, or a few words that carry meaning. "Which one is
            // better?" has neither, and would only put a question about searching in front of whoever asked.
            guard HarnessText.namedThing(in: task.body) != nil || PassageFinder.keywords(in: task.body).count >= 3 else {
                return HarnessRouting(route: .direct, kind: .other, reason: "a question with nothing in it to look up")
            }
            return HarnessRouting(route: .lookup, kind: .fact, reason: "a short question about a fact")
        case .other: return HarnessRouting(route: .direct, kind: .other, reason: "a question to reason about, with nothing for code to check")
        case nil: return nil
        }
    }

    /// Words that only turn up when the talk is about programming.
    private static let codeCue = #"\b(python|javascript|typescript|java|swift|kotlin|rust|golang|ruby|php|c\+\+|c#|bash|shell|sql|html|css|node|regex|json|csv|returns?|prints?|takes|inputs?|outputs?|arrays?|lists?|strings?|integers?|loops?|recursive|recursion|algorithm|variables?|parameters?|arguments?|files?|folder|directory|command line|stdin|stdout)\b|\(\)"#

    /// A line that is code, as opposed to a sentence about it.
    private static func looksLikeCode(_ line: Substring) -> Bool {
        line.range(of: #"^\s{2,}\S|^\s*(def |class |import |from \w+ import|return\b|assert |print\(|for .+ in .+:|while .+:|if .+:|#|//|[A-Za-z_][\w.]*\s*(=|\+=|-=)[^=]|[A-Za-z_][\w.]*\(.*\)\s*;?\s*$)"#, options: .regularExpression) != nil
    }

    /// True when the message asks for code to be written, as opposed to showing code and asking what it does.
    /// "Write a function", "implement the class in JavaScript", "write Python code that": a verb, at most three
    /// words with no "of" or "about" among them, then what to write. A function is always code. A program, a
    /// script, a class or a method is only code when something else in the message is about programming: a radio
    /// script and a training program are not. A signature to fill in, or examples the code must pass, also count,
    /// when the asking is done in a sentence and not by a word inside the code.
    static func asksForCode(_ text: String) -> Bool {
        func has(_ pattern: String, in text: String = text) -> Bool { text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        // Code that's shown with a question about what it does is code to run.
        if has(#"\bwhat (does|will|would|is)\b[^.?!\n]{0,60}\b(print|output|return|do|display|result)"#) { return false }
        let verb = #"\b(write|implement|create|define|complete|make|build|code)\s+(?:me\s+)?(?:an?\s+|the\s+|some\s+|this\s+)?"#
        let between = #"(?:(?!(?:of|about|for|on|with|in|to|from)\b)[\w+#.-]+\s+){0,3}"#
        if has(verb + between + #"function\b"#) { return true }
        if has(verb + between + #"(program|script|class|method|code)\b"#), has(codeCue) { return true }
        let sentences = text.split(whereSeparator: \.isNewline).filter { !looksLikeCode($0) }.joined(separator: "\n")
        if has(#"(?m)^\s*def \w+\(.*\):\s*$"#), has(#"\b(complete|implement|fill in|finish|write)\b"#, in: sentences) { return true }
        return has(#"(?m)^\s*assert \w+\("#) && has(#"\b(function|pass(es)? (these|the) tests?)\b"#, in: sentences)
    }

    /// "One" is left out: "which one" asks for nothing to be worked out.
    private static let numberWords = #"\b(zero|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundreds?|thousands?|millions?|billions?|hal(f|ves)|thirds?|quarters?|twice|double|triple|dozens?|couple|pair|percent)\b"#

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

    /// The letter a reply picks: an A or a B standing by itself at the start of its first line of text, after at
    /// most a lead-in such as "The answer is" or "Option". Thinking written into the reply isn't the answer.
    /// Nil for anything else: "Both" and "Because" aren't letters.
    static func letter(in reply: String) -> Character? {
        let spoken = reply.replacingOccurrences(of: #"(?s)<think>.*?(</think>|\z)"#, with: "", options: .regularExpression)
        let line = spoken.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        let pattern = #"^\W*(?:(?:the\s+)?(?:correct\s+|right\s+)?(?:answer|option|choice)\b\W*(?:is\b\W*)?)?([AB])(?![A-Za-z])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
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

// MARK: - By route

/// One line of the Harness Test's "By route": how the questions that took one route did, with the harness and
/// without. A route is judged on its own questions, which is what says whether it earns its time.
struct RouteRow: Identifiable, Equatable {
    /// Nil for questions whose route isn't known, from a version that logged none.
    let route: HarnessRoute?
    var questions = 0
    var right = 0
    /// Nil when there's no run without the harness to compare with.
    var rightPlain: Int?
    /// Wrong without the harness and right with it, and the other way round.
    var gained = 0
    var lost = 0
    var seconds = 0.0
    var secondsPlain: Double?

    var id: String { route?.rawValue ?? "unknown" }
    var title: String { route?.title ?? "Not known" }
}

extension ModelTestItemResult {
    /// The route this question took. The one harness saves it. The loop versions before it only logged the kind
    /// of task they took a question for, and whether plain code or a program worked it out, which is enough to
    /// say which route that would have been. Nil for a version that logged neither.
    var routeTaken: HarnessRoute? {
        if let route { return HarnessRoute(rawValue: route) }
        let log = toolLog ?? []
        guard let line = log.first(where: { $0.hasPrefix("Understood: ") }) else { return nil }
        switch line.dropFirst("Understood: ".count).split(separator: " ").first.map(String.init) {
        case "calculation": return log.contains { $0.hasPrefix("Calculated:") || $0.hasPrefix("Worked out:") } ? .exact : .program
        case "code": return .program
        case "fact": return .lookup
        case "document": return .document
        case "writing": return .rules
        case "other": return .direct
        default: return nil
        }
    }
}

extension ModelTestResult {
    /// This run's questions by the route they took, each beside the same questions in a run without the harness.
    func routeRows(against plain: ModelTestResult?) -> [RouteRow] {
        var before: [String: ModelTestItemResult] = [:]
        for item in plain?.items ?? [] { before[item.id] = item }
        var rows: [String: RouteRow] = [:]
        for item in items {
            let route = item.routeTaken
            var row = rows[route?.rawValue ?? "unknown"] ?? RouteRow(route: route)
            row.questions += 1
            row.seconds += item.seconds
            if item.passed { row.right += 1 }
            if let old = before[item.id] {
                row.rightPlain = (row.rightPlain ?? 0) + (old.passed ? 1 : 0)
                row.secondsPlain = (row.secondsPlain ?? 0) + old.seconds
                if item.passed, !old.passed { row.gained += 1 }
                if !item.passed, old.passed { row.lost += 1 }
            }
            rows[row.id] = row
        }
        return HarnessRoute.allCases.compactMap { rows[$0.rawValue] } + [rows["unknown"]].compactMap { $0 }
    }
}
