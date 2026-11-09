import Foundation

/// The steps the harness takes on a task. Act, Answer and Check repeat until Check passes.
enum HarnessStage: Int, CaseIterable, Identifiable {
    case understand, act, answer, check

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .understand: return "Understand"
        case .act: return "Act"
        case .answer: return "Answer"
        case .check: return "Check"
        }
    }

    var summary: String {
        switch self {
        case .understand: return "Works out what kind of task this is."
        case .act: return "The kind of task picks the tool."
        case .answer: return "The model replies with the evidence in front of it."
        case .check: return "Code tests the reply. If it fails, back to Act."
        }
    }
}

/// A task as the harness reads it.
struct HarnessTask {
    let prompt: String
    /// What's being asked, for classifying and searching, with the chat so far if there is any.
    let subject: String
    /// What's being asked, without any long text it's about or the form of its last line.
    let body: String
    /// The long text the task is about, when only parts of it matter.
    let document: String?
    /// The task as the model should read it.
    let ask: String
    let rules: TextRules

    /// Asks that need the whole of a long text, so picking passages from it would lose what matters.
    private static let wholeText = #"\b(summar|translate|rewrite|rephrase|proofread|shorten|tl;?dr|main (idea|point)|key points)"#

    init(prompt: String, earlier: String = "") {
        self.prompt = prompt
        let paragraphs = prompt.components(separatedBy: "\n\n")
        var document: String?
        if prompt.count > 1_500, let longest = paragraphs.max(by: { $0.count < $1.count }), longest.count * 2 > prompt.count {
            let rest = paragraphs.filter { $0 != longest }.joined(separator: "\n\n")
            if !rest.isEmpty, rest.range(of: Self.wholeText, options: [.regularExpression, .caseInsensitive]) == nil { document = longest }
        }
        self.document = document
        let asked = paragraphs.filter { $0 != document }
        ask = document == nil ? prompt : asked.joined(separator: "\n\n")
        let body = asked.filter { !TextRules.isAnswerForm($0) }.joined(separator: "\n\n")
        self.body = body
        subject = earlier.isEmpty ? body : "Earlier in this chat:\n\(earlier)\n\nThe new message:\n\(body)"
        rules = TextRules(task: ask)
    }

    /// What the reply should be about, for asking for one part of it.
    var topic: String {
        for pattern in [#"\babout\s+([^.,;\n]+)"#, #"\b(?:write|compose|create|draft)\s+([^.,;\n]+)"#] {
            if let found = body.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                return String(body[found]).split(separator: " ").dropFirst().joined(separator: " ")
            }
        }
        return String(body.prefix(80))
    }

    /// True when the answer has to be added up from the text rather than found in it.
    var needsCounting: Bool {
        body.range(of: #"\b(how many|how much|total|sum|count|average|altogether|in all)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// How the harness acts on a task. Small models rarely call tools by themselves, so the harness drives
/// and does whatever plain code can do, leaving the model as little as possible to get wrong.
extension TestLab {
    // MARK: Understand

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The kind of task, when it's plain from the text. This is cheaper and surer than asking a small model.
    static func plainKind(of task: HarnessTask) -> TaskKind? {
        let text = task.body
        if task.prompt.contains("print(") || task.prompt.contains("console.log(") { return .code }
        if task.document != nil { return .document }
        if task.rules.hasShape, matches(#"\b(write|describe|compose|draft|return|reply|respond|list|give|say|explain|create|generate|make)\b"#, text) {
            return .writing
        }
        if text.contains(where: \.isNumber),
           matches(#"\d\s*[×*/÷+^]\s*\d|\d\s*%|\b(sum|product|remainder|modulo|mod|divided by|multiplied|factorial|square root|how many ways|how much|average)\b"#, text) {
            return .calculation
        }
        let edges = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'”’"))
        let sentences = text.split { ".!?".contains($0) }.map { $0.trimmingCharacters(in: edges) }.filter { !$0.isEmpty }
        let asks = sentences.contains { matches(#"^(who|whom|whose|which|when|where|what (is|was|are|were) the|what year|in what|in which|name the)\b"#, $0) }
        guard asks else { return nil }
        // A short question is something to look up. Clues before the question are something to reason about.
        if sentences.count > 2 { return .other }
        return text.count < 240 && !matches(#"\b(i|me|my|mine|we|our|you|your)\b"#, text) ? .fact : nil
    }

    static func understand(_ task: HarnessTask, setup: TestSetup, total: inout Reply) async -> TaskKind {
        if let kind = plainKind(of: task) { return kind }
        let request = """
        \(task.subject.prefix(1_500))

        ---
        Don't solve this yet. Classify it, replying with exactly this line:
        TYPE: CALCULATION (needs arithmetic, counting or logic that a program could check), FACT (a fact worth looking up), WRITING (text that has to follow rules), or OTHER
        """
        let reply = await stepReply(.understand, [ChatTurn(role: "user", content: request)], setup: setup, tokens: 120, total: &total)
        switch capture(#"(?im)^\W*TYPE:\W*(\w+)"#, in: reply.answer)?.lowercased() {
        case "calculation": return .calculation
        case "fact": return .fact
        case "writing": return .writing
        default: return .other
        }
    }

    // MARK: Act

    static func act(_ task: HarnessTask, state: inout LoopState, round: Int, mayConfirm: Bool, setup: TestSetup, total: inout Reply) async {
        switch state.kind {
        case .calculation, .code:
            if state.result == nil { await runProgram(task, state: &state, mayConfirm: mayConfirm, setup: setup, total: &total) }
        case .document:
            if round == 1 || state.wantsEvidence { readDocument(task, state: &state, round: round, setup: setup, total: &total) }
            if round > 1, task.needsCounting, state.result == nil {
                await runProgram(task, state: &state, mayConfirm: false, setup: setup, total: &total)
            }
        case .fact:
            if !state.webDeclined, round == 1 || state.wantsEvidence { await research(task, state: &state, setup: setup, total: &total) }
        case .writing, .other:
            break
        }
    }

    /// Most of the context a small model has is needed for the task and its reply.
    private static func evidenceLimit(_ setup: TestSetup) -> Int { min(setup.context / 2, 3_000) }

    private static func take(_ output: String, state: inout LoopState, total: inout Reply) {
        let safe = PromptGuard.wrap(output, source: "your program")
        total.guardRemoved += safe.removed
        state.evidence = ["Your program printed:\n\(safe.text)"]
        state.result = HarnessText.keyResult(of: output)
        state.failedProgram = nil
    }

    private static func runProgram(_ task: HarnessTask, state: inout LoopState, mayConfirm: Bool, setup: TestSetup, total: inout Reply) async {
        if state.kind == .calculation, let (expression, value) = exactArithmetic(in: task.body) {
            total.toolLog.append("Calculated: \(expression)")
            state.evidence = ["The calculator worked out \(expression) = \(value)"]
            state.result = value
            return
        }
        if state.kind == .code, !state.triedShownCode, let (language, code) = shownCode(in: task.prompt) {
            state.triedShownCode = true
            let outcome = await CodeRunner.run(code, language: language)
            total.toolLog.append("Ran the \(language.rawValue) from the task: \(preview(outcome.output))" + (outcome.succeeded ? "" : HarnessTools.failedMark))
            if outcome.succeeded, !outcome.output.isEmpty {
                take(outcome.output, state: &state, total: &total)
                return
            }
        }
        guard var output = await writeProgram(task, note: "", state: &state, setup: setup, total: &total) else { return }
        if state.kind == .calculation, mayConfirm {
            output = await confirmed(output, task: task, state: &state, setup: setup, total: &total)
        }
        take(output, state: &state, total: &total)
    }

    /// Has a second program check the first, and a third settle it if they disagree. If nothing
    /// settles it, the first stands.
    private static func confirmed(_ first: String, task: HarnessTask, state: inout LoopState, setup: TestSetup, total: inout Reply) async -> String {
        let note = "An earlier program printed \(preview(first)). Solve the task again a different way, to check that."
        guard let second = await writeProgram(task, note: note, state: &state, setup: setup, total: &total) else { return first }
        if HarnessText.sameResult(first, second) {
            total.toolLog.append("A second program agreed")
            return first
        }
        total.toolLog.append("A second program disagreed")
        let tiebreak = "One program printed \(preview(first)) and another printed \(preview(second)). Work out which is right with a third, simpler method."
        guard let third = await writeProgram(task, note: tiebreak, state: &state, setup: setup, total: &total) else { return first }
        return HarnessText.sameResult(third, second) ? second : first
    }

    /// Has the model write a program from a skeleton and runs it in the sandbox. What went wrong with
    /// the last program goes into the next request, across rounds. Returns everything it printed.
    private static func writeProgram(_ task: HarnessTask, note: String, state: inout LoopState, setup: TestSetup, total: inout Reply) async -> String? {
        let description: String
        var extra = "Prefer simple brute force over clever maths, and check every case."
        if let document = task.document {
            description = "A long text, followed by this question:\n\n\(task.body)"
            let lines = PassageFinder.chain(in: document, for: task.body, maxCharacters: 700, closeness: 0.55).passages
            extra = "The whole text is in the file task.txt in the current folder. Read and parse that file in your program. Some of its lines look like this:\n\n\(lines.joined(separator: "\n"))"
        } else {
            description = task.subject
        }
        let base = """
        Task:
        \(description)

        Write a real Python program that works out the exact answer. \(extra) Don't reason in comments, and don't work the answer out yourself: the program has to compute it. Reply with one code block in this shape:

        ```python
        def solve():
            # compute the answer here
            return answer

        print(solve())
        ```
        """
        for _ in 0..<2 {
            var request = base + (note.isEmpty ? "" : "\n\n\(note)")
            if let failed = state.failedProgram {
                request += "\n\nYour last program failed, so fix it.\n\(failed.problem)\n\nThe program was:\n\(failed.code)"
            }
            let reply = await stepReply(.act, [ChatTurn(role: "system", content: "You write short, correct programs."), ChatTurn(role: "user", content: request)],
                                        setup: setup, tokens: 1_024, total: &total)
            guard let (language, code) = codeBlock(in: reply.answer) else {
                total.toolLog.append("Wrote no program\(HarnessTools.failedMark)")
                return nil
            }
            let outcome = await CodeRunner.run(code, language: language, files: ["task.txt": task.document ?? task.prompt])
            let worked = outcome.succeeded && !outcome.output.isEmpty
            total.toolLog.append("Ran \(language.rawValue): \(worked ? preview(outcome.output) : errorLine(of: outcome.output))" + (worked ? "" : HarnessTools.failedMark))
            if worked { return outcome.output }
            state.failedProgram = (outcome.output.isEmpty ? "It printed nothing, so it must call print with the result." : String(outcome.output.suffix(400)),
                                   String(code.prefix(1_200)))
        }
        return nil
    }

    /// The line of a failed program's output that says what went wrong.
    private static func errorLine(of output: String) -> String {
        output.split(whereSeparator: \.isNewline).last.map { String($0.prefix(70)) } ?? "no output"
    }

    /// All of a program's output on one line, for the log.
    private static func preview(_ output: String) -> String {
        let text = output.split(whereSeparator: \.isNewline).joined(separator: " ")
        return text.isEmpty ? "no output" : String(text.prefix(70))
    }

    /// A plain sum in a short task, which needs no model at all. Only a sum the whole question is about, with
    /// an exact result, counts: a shortcut that's wrong here overrides a reply the model got right.
    static func exactArithmetic(in text: String) -> (String, String)? {
        guard text.count < 160, let expression = capture(#"(\d[\d.]*(?:\s*[×x*/÷+^]\s*\d[\d.]*)+)"#, in: text) else { return nil }
        if let parts = powerRemainder(in: text) {
            let call = "powmod(\(parts.base),\(parts.exponent),\(parts.modulus))"
            return (call, Calculator.evaluate(call))
        }
        if matches(#"\b(mod|modulo|remainder|divided by|digits?|percent)\b"#, text) { return nil }
        let plain = expression.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "x", with: "*").replacingOccurrences(of: "÷", with: "/")
        let value = Calculator.evaluate(plain)
        // Past what a Double holds exactly, the digits are wrong, or it's "inf".
        guard !value.hasPrefix("Error"), value.rangeOfCharacter(from: .letters) == nil else { return nil }
        return (expression, value)
    }

    /// "7^222 mod 1000", or "the remainder when 7^222 is divided by 1000".
    private static func powerRemainder(in text: String) -> (base: String, exponent: String, modulus: String)? {
        let pattern = #"(\d+)\s*\^\s*(\d+)\s*(?:mod(?:ulo)?|%|(?:is\s+)?divided\s+by)\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let parts = (1...3).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
        return parts.count == 3 ? (parts[0], parts[1], parts[2]) : nil
    }

    /// The code in a task: the paragraphs that read like code rather than sentences.
    private static func shownCode(in prompt: String) -> (CodeRunner.Language, String)? {
        let code = prompt.components(separatedBy: "\n\n").filter { paragraph in
            let text = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let last = text.last, !".?:!".contains(last) else { return false }
            return text.contains("(") || text.contains(" = ") || text.hasPrefix("import ") || text.hasPrefix("from ")
        }
        guard !code.isEmpty else { return nil }
        let joined = code.joined(separator: "\n\n") + "\n"
        return (joined.contains("console.log") || joined.contains("=>") ? .javascript : .python, joined)
    }

    // MARK: Reading

    /// Follows the text from the question to the answer, so the model reads only the lines that matter.
    /// A later round casts the net wider.
    private static func readDocument(_ task: HarnessTask, state: inout LoopState, round: Int, setup: TestSetup, total: inout Reply) {
        guard let document = task.document else { return }
        let counting = task.needsCounting
        let selection = PassageFinder.chain(in: document, for: task.body, maxCharacters: evidenceLimit(setup) * (counting ? 2 : 1) * round,
                                            closeness: counting ? 0.55 : (round == 1 ? 0.8 : 0.6))
        guard !selection.passages.isEmpty else { return }
        let safe = PromptGuard.wrap(selection.passages.joined(separator: "\n"), source: "the text")
        total.guardRemoved += safe.removed
        total.toolLog.append("Found \(selection.passages.count) passages in the text")
        state.evidence = ["The parts of the text that matter, in order:\n\(safe.text)"]
    }

    /// Reads the best pages not read yet, searching again when none are left.
    private static func research(_ task: HarnessTask, state: inout LoopState, setup: TestSetup, total: inout Reply) async {
        var snippets: String?
        if state.hits.isEmpty, let query = await nextQuery(task, state: &state, setup: setup, total: &total) {
            let call = ToolCall(name: "web_search", arguments: ["query": query])
            let found = await HarnessTools.run(call)
            if found.failed, found.text.hasSuffix(WebTools.declined) {
                total.toolLog.append(WebTools.declinedNote)
                state.webDeclined = true
                return
            }
            total.toolLog.append(HarnessTools.describe(call) + (found.failed ? HarnessTools.failedMark : ""))
            total.guardRemoved += found.removed
            guard !found.failed else { return }
            state.hits = HarnessText.ranked(HarnessText.hits(in: found.text), for: task.body + " " + query).filter { !state.opened.contains($0.url) }
            snippets = String(found.text.prefix(evidenceLimit(setup)))
        }

        // A page that doesn't cover the question often sits right next to one that does.
        var best: (selection: PassageFinder.Selection, hit: SearchHit)?
        for _ in 0..<2 where !state.hits.isEmpty && (best?.selection.coverage ?? 0) < 0.6 {
            let hit = state.hits.removeFirst()
            state.opened.insert(hit.url)
            let result = await WebTools.open(hit.url, limit: WebTools.maxSearchableCharacters)
            let describe = HarnessTools.describe(ToolCall(name: "open_page", arguments: ["url": hit.url]))
            guard case .success(let text) = result else {
                total.toolLog.append(describe + HarnessTools.failedMark)
                continue
            }
            total.toolLog.append(describe)
            let selection = PassageFinder.best(in: text, for: task.body, maxCharacters: evidenceLimit(setup))
            if selection.coverage > (best?.selection.coverage ?? -1) { best = (selection, hit) }
        }
        if let best, !best.selection.passages.isEmpty {
            let safe = PromptGuard.wrap(best.selection.passages.joined(separator: "\n"), source: best.hit.url)
            total.guardRemoved += safe.removed
            state.evidence = ["From \(best.hit.title):\n\(safe.text)"]
            state.readTheWeb = true
        } else if let snippets {
            state.evidence = [snippets]
            state.readTheWeb = true
        }
    }

    /// The model's own search first, then one built from the task's keywords.
    private static func nextQuery(_ task: HarnessTask, state: inout LoopState, setup: TestSetup, total: inout Reply) async -> String? {
        let fromTask = PassageFinder.keywords(in: task.body).prefix(7).joined(separator: " ")
        var query: String?
        switch state.queries.count {
        case 0:
            let request = "\(task.subject)\n\n---\nWrite a web search of 3 to 8 words that would find this. Reply with only the search words."
            let reply = await stepReply(.act, [ChatTurn(role: "user", content: request)], setup: setup, tokens: 40, total: &total)
            query = HarnessText.cleanQuery(firstLine(of: reply.answer))
        case 1:
            query = fromTask
        default:
            return nil
        }
        let chosen = (query?.isEmpty == false ? query : fromTask) ?? fromTask
        guard !chosen.isEmpty, !state.queries.contains(chosen) else { return nil }
        state.queries.append(chosen)
        return chosen
    }

    // MARK: Helpers

    private static func firstLine(of text: String) -> String {
        String(text.split(whereSeparator: \.isNewline).first ?? "").trimmingCharacters(in: .whitespaces)
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// The first fenced code block, and the language it's tagged with. A reply cut off before its
    /// closing fence still counts, and so does a bare program with no fence, from its first line of code.
    private static func codeBlock(in text: String) -> (CodeRunner.Language, String)? {
        guard let regex = try? NSRegularExpression(pattern: #"```([a-zA-Z0-9+#-]*)[^\n]*\n(.*?)(?:```|\z)"#, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let tag = Range(match.range(at: 1), in: text), let body = Range(match.range(at: 2), in: text) else {
            guard text.contains("print(") else { return nil }
            let lines = text.components(separatedBy: .newlines)
            let start = lines.firstIndex { $0.range(of: #"^(def |import |from |for |while |class |print\(|[A-Za-z_]\w* *=)"#, options: .regularExpression) != nil }
            return (.python, lines[(start ?? 0)...].joined(separator: "\n"))
        }
        let isJavaScript = ["js", "javascript", "node"].contains(text[tag].lowercased())
        var code = String(text[body])
        // Small models often drop the skeleton's last line.
        if !isJavaScript, code.contains("def solve("), !code.contains("print(") { code += "\nprint(solve())\n" }
        return (isJavaScript ? .javascript : .python, code)
    }

    /// What the model reads after the task, when the tools found something.
    static func evidenceNote(_ evidence: [String]) -> String {
        evidence.isEmpty ? "" : "\n\nYour tools already found this. Trust it over your memory:\n\n\(evidence.joined(separator: "\n\n"))"
    }
}

/// A search result worth opening.
struct SearchHit {
    let title: String
    let url: String
    var snippet = ""
}

/// Reading what tools and models return. General text handling that knows nothing about any test.
enum HarnessText {
    /// What a program's output comes down to: its answer, without the words around it.
    static func keyResult(of output: String) -> String? {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let last = lines.last else { return nil }
        // One short value per line is one answer, printed in parts.
        if lines.count > 1, lines.allSatisfy({ !$0.contains(" ") && $0.count < 12 }) { return lines.joined(separator: " ") }
        if !last.contains(" ") { return plainNumber(last) }
        if let number = ModelTestSuite.numbers(in: last).last { return plainNumber(number.formatted(.number.grouping(.never))) }
        return last.count <= 80 ? last : nil
    }

    /// "54.0" reads as 54.
    private static func plainNumber(_ text: String) -> String {
        guard let value = Double(text), value == value.rounded(), abs(value) < 1e15 else { return text }
        return "\(Int(value))"
    }

    static func sameResult(_ first: String, _ second: String) -> Bool {
        keyResult(of: first) == keyResult(of: second)
    }

    /// Whether a reply states a tool's result: every part, in order, in the last line if the task asks for one.
    static func mentions(_ result: String, in reply: String, label: String?) -> Bool {
        let scope = label == nil ? reply : ModelTestSuite.finalAnswer(reply)
        if let value = Double(result), ModelTestSuite.numbers(in: scope).contains(value) { return true }
        var rest = Substring(scope.lowercased())
        for part in result.lowercased().split(separator: " ") {
            guard let found = rest.range(of: part) else { return false }
            rest = rest[found.upperBound...]
        }
        return true
    }

    /// Writes the result into a reply the model couldn't get right.
    static func adding(_ result: String, to reply: String, label: String?) -> String {
        guard let label else { return reply.isEmpty ? result : "\(reply)\n\n\(result)" }
        var lines = reply.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if let last = lines.last, last.lowercased().contains(label.lowercased() + ":") { lines.removeLast() }
        return (lines + ["\(label): \(result)"]).joined(separator: "\n")
    }

    /// A model's search with any "Answer:" style lead-in and punctuation removed.
    static func cleanQuery(_ raw: String) -> String {
        var query = raw
        if let colon = query.firstIndex(of: ":"), query.distance(from: query.startIndex, to: colon) < 24 {
            query = String(query[query.index(after: colon)...])
        }
        let kept = query.map { "\"'`*<>[](){},;".contains($0) ? " " : $0 }
        return String(kept).split(whereSeparator: \.isWhitespace).prefix(8).joined(separator: " ")
    }

    static func hits(in results: String) -> [SearchHit] {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^\d+\. (.+?) — (https://\S+)(?:\n[ \t]+(.+))?"#) else { return [] }
        return regex.matches(in: results, range: NSRange(results.startIndex..., in: results)).compactMap { match in
            guard let title = Range(match.range(at: 1), in: results), let url = Range(match.range(at: 2), in: results) else { return nil }
            return SearchHit(title: String(results[title]), url: String(results[url]),
                             snippet: Range(match.range(at: 3), in: results).map { String(results[$0]) } ?? "")
        }
    }

    /// Best match first, with a title counting double a snippet. Wikipedia wins ties, since it's written to
    /// be read on its own. Pages with nothing in common with the question aren't worth a request.
    static func ranked(_ hits: [SearchHit], for question: String) -> [SearchHit] {
        let wanted = Set(PassageFinder.keywords(in: question))
        func matches(_ text: String) -> Int { PassageFinder.keywords(in: text).filter(wanted.contains).count }
        let scored = hits.enumerated().map { hit in
            (offset: hit.offset, hit: hit.element,
             score: Double(matches(hit.element.title) * 2 + matches(hit.element.snippet)) + (hit.element.url.contains("wikipedia.org") ? 0.5 : 0))
        }
        let relevant = scored.filter { $0.score >= 1 }
        return (relevant.isEmpty ? scored : relevant).sorted { ($0.score, $1.offset) > ($1.score, $0.offset) }.map(\.hit)
    }
}
