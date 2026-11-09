import Foundation

/// v2 of the harness, kept as it was when it was replaced by the loop, so its results can be compared
/// with the versions either side of it. It works a task once, in a straight line: understand it, run one
/// tool, let the model answer from what that found, then have the model fix any writing against measured
/// facts. Improvements belong in the loop. A change here would stop this being v2.
@MainActor
enum PipelineHarness {
    private typealias Reply = TestLab.Reply
    private typealias TestSetup = TestLab.TestSetup
    private typealias TaskKind = TestLab.TaskKind

    /// What steps 1 and 2 leave for the model.
    private struct Preparation {
        let kind: TaskKind
        let evidence: [String]

        var readTheWeb: Bool { kind == .fact && !evidence.isEmpty }
    }

    private static let maxFixRounds = 2

    /// Works a task through the pipeline. `answer` is how the caller gets a reply from the model, so chat
    /// can stream it. `earlier` is the chat so far. The result lands in `total.answer`.
    static func run(prompt: String, earlier: String, setup: TestLab.TestSetup, maxTokens: Int, total: inout TestLab.Reply,
                    answer: (TestLab.AnswerPlan) async -> TestLab.Reply) async {
        let plan = await prepare(prompt: prompt, earlier: earlier, setup: setup, total: &total)

        // 3. Answer
        total.onStage?(.answer, 1)
        var step = TestLab.AnswerPlan(task: prompt)
        step.addendum = TestLab.evidenceNote(plan.evidence)
        let reply = await answer(step)
        TestLab.absorb(reply, into: &total)
        total.answer = reply.answer
        total.error = reply.error

        await check(prompt: prompt, plan: plan, setup: setup, maxTokens: maxTokens, total: &total)
        total.onDraft?(total.answer)
    }

    /// Steps 1 and 2. `earlier` is the chat so far, for making sense of a follow-up.
    private static func prepare(prompt: String, earlier: String, setup: TestSetup, total: inout Reply) async -> Preparation {
        let question = earlier.isEmpty ? prompt : "Earlier in this chat:\n\(earlier)\n\nThe new message:\n\(prompt)"

        // 1. Understand
        total.onStage?(.understand, 1)
        let (kind, search) = await understand(prompt, question: question, setup: setup, total: &total)
        total.toolLog.append("Understood: \(kind.rawValue) task")

        // 2. Act
        total.onStage?(.act, 1)
        var evidence: [String] = []
        switch kind {
        case .calculation, .code, .document:
            if let result = await runProgram(for: prompt, question: question, kind: kind, setup: setup, total: &total) { evidence.append(result) }
        case .fact:
            evidence = await research(search ?? firstLine(of: prompt), total: &total)
        case .writing, .other:
            break
        }
        return Preparation(kind: kind, evidence: evidence)
    }

    /// Step 4, on the reply in `total.answer`.
    private static func check(prompt: String, plan: Preparation, setup: TestSetup, maxTokens: Int, total: inout Reply) async {
        if plan.kind == .writing, total.error == nil, !total.answer.isEmpty, !Task.isCancelled {
            total.onStage?(.check, 1)
            await fixAgainstRules(prompt: prompt, setup: setup, maxTokens: maxTokens, total: &total)
        }
        if plan.readTheWeb {
            let filtered = PromptGuard.filterReply(total.answer)
            total.answer = filtered.text
            if filtered.blocked > 0 {
                total.toolLog.append("Removed \(filtered.blocked) untrusted link\(filtered.blocked == 1 ? "" : "s") from the reply")
            }
        }
    }

    // MARK: Understand

    private static func understand(_ prompt: String, question: String, setup: TestSetup, total: inout Reply) async -> (TaskKind, String?) {
        // Plain signals are cheaper and surer than asking the model.
        if prompt.contains("print(") || prompt.contains("console.log(") { return (.code, nil) }
        if prompt.count > 2_500 { return (.document, nil) }

        let request = """
        \(question)

        ---
        Don't solve this yet. Classify it, replying with exactly this line:
        TYPE: CALCULATION (needs arithmetic, counting or logic that a program could check), FACT (a fact worth looking up), WRITING (text that has to follow rules), or OTHER
        """
        let reply = await TestLab.converse([ChatTurn(role: "user", content: request)], setup: setup, maxTokens: 120, useTools: false,
                                   think: setup.think == nil ? nil : false)
        TestLab.absorb(reply, into: &total)
        switch capture(#"(?im)^\W*TYPE:\W*(\w+)"#, in: reply.answer)?.lowercased() {
        case "calculation": return (.calculation, nil)
        case "fact": return (.fact, await searchQuery(for: question, setup: setup, total: &total))
        case "writing": return (.writing, nil)
        default: return (.other, nil)
        }
    }

    private static func searchQuery(for prompt: String, setup: TestSetup, total: inout Reply) async -> String? {
        let request = "\(prompt)\n\n---\nWrite a web search of 3 to 8 words that would find this. Reply with only the search words."
        let reply = await TestLab.converse([ChatTurn(role: "user", content: request)], setup: setup, maxTokens: 40, useTools: false,
                                   think: setup.think == nil ? nil : false)
        TestLab.absorb(reply, into: &total)
        let query = firstLine(of: reply.answer).trimmingCharacters(in: CharacterSet(charactersIn: " *\"'`"))
        return query.isEmpty ? nil : query
    }

    // MARK: Act

    /// Runs code the task shows as it is. Otherwise has the model write a program from a skeleton, runs it
    /// in the sandbox, and retries once if it fails or prints nothing.
    private static func runProgram(for prompt: String, question: String, kind: TaskKind, setup: TestSetup, total: inout Reply) async -> String? {
        if kind == .code, let (language, code) = shownCode(in: prompt) {
            let outcome = await CodeRunner.run(code, language: language)
            total.toolLog.append("Ran the \(language.rawValue) from the task: \(preview(outcome.output))" + (outcome.succeeded ? "" : HarnessTools.failedMark))
            if outcome.succeeded, !outcome.output.isEmpty { return evidence(from: outcome, total: &total) }
        }

        let task: String
        var extra = "Prefer simple brute force over clever maths, and check every case."
        if kind == .document {
            task = "A long text, followed by this question:\n\n\(prompt.suffix(500))"
            extra = "The whole text is in the file task.txt in the current folder. Read and parse that file in your program. Some of its lines look like this:\n\n\(sampleLines(of: prompt))"
        } else {
            task = question
        }
        var request = """
        Task:
        \(task)

        Write a real Python program that works out the exact answer. \(extra) Don't reason in comments, and don't work the answer out yourself: the program has to compute it. Reply with one code block in this shape:

        ```python
        def solve():
            # compute the answer here
            return answer

        print(solve())
        ```
        """
        for attempt in 0..<2 {
            let reply = await TestLab.converse([ChatTurn(role: "system", content: "You write short, correct programs."), ChatTurn(role: "user", content: request)],
                                       setup: setup, maxTokens: 1_024, useTools: false, think: setup.think == nil ? nil : false)
            TestLab.absorb(reply, into: &total)
            guard let (language, code) = codeBlock(in: reply.answer) else {
                total.toolLog.append("Wrote no program\(HarnessTools.failedMark)")
                return nil
            }
            let outcome = await CodeRunner.run(code, language: language, files: ["task.txt": prompt])
            let worked = outcome.succeeded && !outcome.output.isEmpty
            total.toolLog.append("Ran \(language.rawValue): \(preview(outcome.output))" + (worked ? "" : HarnessTools.failedMark))
            if worked { return evidence(from: outcome, total: &total) }
            if attempt == 0 {
                let problem = outcome.output.isEmpty ? "It printed nothing, so it must call print with the result." : String(outcome.output.suffix(600))
                request += "\n\nYour last program failed, so fix it:\n\(problem)\n\nThe program was:\n\(code.prefix(1_500))"
            }
        }
        return nil
    }

    private static func preview(_ output: String) -> String {
        output.split(separator: "\n").last.map { String($0.prefix(60)) } ?? "no output"
    }

    private static func evidence(from outcome: CodeRunner.Outcome, total: inout Reply) -> String {
        let safe = PromptGuard.wrap(outcome.output, source: "your program")
        total.guardRemoved += safe.removed
        return "Your program printed:\n\(safe.text)"
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

    /// A few lines from the start of a long text, plus any that start differently from most of them,
    /// since those are often the ones that matter.
    private static func sampleLines(of text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        func firstWord(_ line: String) -> String { String(line.split(separator: " ").first ?? "") }
        var counts: [String: Int] = [:]
        for line in lines { counts[firstWord(line), default: 0] += 1 }
        let common = counts.max { $0.value < $1.value }?.key
        let unusual = lines.dropFirst(2).filter { firstWord($0) != common && $0.count < 200 }.suffix(6)
        return (lines.filter { firstWord($0) == common }.prefix(5) + unusual).joined(separator: "\n")
    }

    private static func research(_ query: String, total: inout Reply) async -> [String] {
        var evidence: [String] = []
        let searchCall = ToolCall(name: "web_search", arguments: ["query": query])
        let found = await HarnessTools.run(searchCall)
        // The one change since this version was frozen: a lookup the person didn't allow was never sent, so the
        // log says that instead of listing it as a search.
        let refused = found.failed && found.text.hasSuffix(WebTools.declined)
        total.toolLog.append(refused ? WebTools.declinedNote : HarnessTools.describe(searchCall) + (found.failed ? HarnessTools.failedMark : ""))
        total.guardRemoved += found.removed
        guard !found.failed else { return [] }
        evidence.append(found.text)

        if let link = capture(#"(https://en\.wikipedia\.org/wiki/[^\s<]+)"#, in: found.text) {
            let openCall = ToolCall(name: "open_page", arguments: ["url": link])
            let page = await HarnessTools.run(openCall)
            total.toolLog.append(HarnessTools.describe(openCall) + (page.failed ? HarnessTools.failedMark : ""))
            total.guardRemoved += page.removed
            if !page.failed { evidence.append(page.text) }
        }
        return evidence
    }

    // MARK: Verify

    /// Measures the draft and shows the model the numbers, since models can't reliably count their own words.
    private static func fixAgainstRules(prompt: String, setup: TestSetup, maxTokens: Int, total: inout Reply) async {
        for _ in 0..<maxFixRounds {
            let request = """
            Task:
            \(prompt)

            Your draft reply:
            \(total.answer)

            Measured facts about the draft:
            \(TextFacts.describe(total.answer, task: prompt))

            Compare the draft with every rule in the task, using the measured facts. If every rule holds, reply with exactly: OK
            Otherwise reply with only the corrected text.
            """
            let review = await TestLab.converse([ChatTurn(role: "user", content: request)], setup: setup, maxTokens: maxTokens, useTools: false)
            TestLab.absorb(review, into: &total)
            let revised = review.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if review.error != nil || revised.isEmpty || revised.uppercased().hasPrefix("OK") {
                total.toolLog.append("Checked the reply against the rules")
                return
            }
            total.answer = revised
            total.toolLog.append("Rewrote the reply to fit the rules")
        }
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
    /// closing fence still counts, and so does a bare program with no fence at all.
    private static func codeBlock(in text: String) -> (CodeRunner.Language, String)? {
        guard let regex = try? NSRegularExpression(pattern: #"```([a-zA-Z0-9+#-]*)[^\n]*\n(.*?)(?:```|\z)"#, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let tag = Range(match.range(at: 1), in: text), let body = Range(match.range(at: 2), in: text) else {
            return text.contains("print(") ? (.python, text) : nil
        }
        let isJavaScript = ["js", "javascript", "node"].contains(text[tag].lowercased())
        return (isJavaScript ? .javascript : .python, String(text[body]))
    }
}

/// Exact measurements of a piece of text. General ones only: they know nothing about any test.
enum TextFacts {
    static func describe(_ text: String, task: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let sentences = trimmed.split { ".!?".contains($0) }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        func wordCount(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }
        var facts = [
            "Total words: \(wordCount(trimmed))",
            "Lines: \(lines.count). Words per line: \(lines.map { "\(wordCount($0))" }.joined(separator: ", "))",
            "First letter of each line: \(lines.compactMap { $0.first.map(String.init) }.joined(separator: ", "))",
            "Sentences: \(sentences.count). Words per sentence: \(sentences.map { "\(wordCount($0))" }.joined(separator: ", "))",
            "First letter of each sentence: \(sentences.compactMap { $0.first.map(String.init) }.joined(separator: ", "))",
        ]
        // If the task talks about a particular letter or quoted word, say exactly where it appears.
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        for letter in mentions(of: #"(?i)\bletter\s+"?([a-z])\b"#, in: task) {
            let hits = words.filter { $0.lowercased().contains(letter.lowercased()) }
            facts.append("Words containing the letter \(letter): \(hits.isEmpty ? "none" : hits.joined(separator: ", "))")
        }
        for phrase in mentions(of: #""([^"]{2,30})""#, in: task) {
            facts.append("Times \"\(phrase)\" appears: \(trimmed.lowercased().components(separatedBy: phrase.lowercased()).count - 1)")
        }
        return facts.joined(separator: "\n")
    }

    private static func mentions(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var seen = Set<String>()
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
        .filter { seen.insert($0.lowercased()).inserted }
    }
}
