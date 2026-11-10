import Foundation

/// v6, the evidence loop. It is v3's loop with stricter rules about what counts as evidence, each one added
/// because of something v3 got wrong in a run that was looked at:
///
/// - A weekday question went to Wikipedia. So questions a program can settle (dates, counting, unit sums, word
///   problems) are sent to code before anything is looked up, and plain code answers the simplest itself.
/// - A lookup opened a page about something else, and another time a model handed the right page answered
///   with a nearby year. So a lookup starts from the name in the question, the model reads a few sentences that
///   share words with the question instead of a page of text, and its answer only counts as backed when one
///   sentence holds both the answer and what was asked about.
/// - The model's own answer was right more often than not before a page talked it out of it, which studies of
///   small models with retrieval also found. So it's asked first without the page, and when the two answers
///   differ, the sentences behind each are put in front of it together.
/// - Four questions nobody solved took two thirds of a test's time. So it stops after two rounds, and the
///   reply's steps end by saying what code checked and what it couldn't.
/// - A reply with too many words was cut to fit a word count, which passes the rule and breaks the sentence.
///   So v6 doesn't cut: the reply goes back to be written again.
///
/// Nothing here changes v3 to v5: every difference sits behind `LoopState.strict`.
extension TestLab {
    // MARK: Understand

    private static func has(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// True for a question a program can answer exactly, where looking it up would only find something near it.
    static func computable(_ text: String) -> Bool {
        guard text.contains(where: \.isNumber) || text.contains("\"") || text.contains("'") else { return false }
        // Dates and ages.
        if has(#"\b(what|which) day of the week\b|\bwhat weekday\b|\bhow many (days|weeks|months|years)\b.*\b(between|from|since|until|after|before)\b|\bhow old (is|was|were|will|would)\b.*\d"#, text) { return true }
        // Counting what's written in the question.
        if has(#"\bhow many (letters|words|vowels|consonants|characters|syllables)\b|\bhow many times (does|do)\b|\bcount the\b"#, text),
           text.contains("\"") || text.contains("'") { return true }
        // Units.
        if has(#"\bconvert\s+\d|\bhow many (kilometers|kilometres|km|miles|meters|metres|feet|inches|centimeters|centimetres|cm|kilograms|kg|pounds|lbs|ounces|grams|liters|litres|gallons|seconds|minutes|hours) (is|are|in)\b"#, text) { return true }
        // A word problem: a few sentences of numbers, then a question about how many or how much.
        let sentences = text.split { ".!?".contains($0) }.filter { $0.contains(where: \.isLetter) }
        let numbers = (try? NSRegularExpression(pattern: #"\d[\d,.]*"#))?.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) ?? 0
        return sentences.count >= 2 && numbers >= 2
            && has(#"\bhow (many|much)\b|\bwhat (is|was|are|were) the (total|sum|difference|average|mean|area|perimeter|volume|cost|price|profit|speed|distance|probability|percentage|ratio)\b|\b(in total|altogether|in all)\b"#, text)
    }

    /// The kind of task when it's plain from the text, with computable questions caught before they can read
    /// as something to look up.
    static func strictKind(of task: HarnessTask) -> TaskKind? {
        if ExactTools.solve(task.body) != nil { return .calculation }
        let plain = plainKind(of: task)
        if let plain, plain != .fact, plain != .other { return plain }
        return computable(task.body) ? .calculation : plain
    }

    static func understandStrict(_ task: HarnessTask, setup: TestSetup, total: inout Reply) async -> TaskKind {
        if let kind = strictKind(of: task) { return kind }
        return await understand(task, setup: setup, total: &total)
    }

    // MARK: Programs

    /// True for a "program" that only hands back a value the model worked out in its head, which is the mental
    /// arithmetic the program was there to replace.
    static func onlyPrintsLiteral(_ code: String) -> Bool {
        let lines = code.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let literal = #"-?\d[\d_.,]*|"[^"]*"|'[^']*'"#
        let body = lines.filter { !$0.hasPrefix("def solve") && $0 != "print(solve())" && !$0.hasPrefix("import ") && !$0.hasPrefix("from ") }
        guard body.count == 1, let only = body.first else { return false }
        return only.range(of: "^(return|answer\\s*=|print\\()\\s*\\(?(\(literal))\\)?\\)?$", options: .regularExpression) != nil
    }

    // MARK: Facts

    /// What the model says with no page in front of it, in one line. Nil when it says it isn't sure.
    static func fromMemory(_ task: HarnessTask, setup: TestSetup, total: inout Reply) async -> String? {
        let request = "\(task.subject.prefix(1_500))\n\n---\nAnswer in one short line, with no explanation. If you aren't sure, reply exactly: I don't know."
        let reply = await stepReply(.act, [ChatTurn(role: "user", content: request)], setup: setup, tokens: 60, log: false, total: &total)
        let line = reply.answer.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let unsure = line.isEmpty || has(#"\b(don'?t|do not) know\b|\bnot sure\b|\bunsure\b|\bno idea\b|\bcannot (say|answer|determine)\b"#, line)
        total.toolLog.append(unsure ? "From memory: not sure" : "From memory: \(line.prefix(70))")
        return unsure ? nil : line
    }

    /// Pages that list many things are where a small model reads the wrong row.
    private static func isListPage(_ title: String) -> Bool {
        has(#"^(lists? of|timeline of|index of|outline of|glossary of)\b|\(disambiguation\)"#, title)
    }

    /// Looks the question up, starting from the thing it names, and keeps the few sentences that bear on it.
    static func researchQuoted(_ task: HarnessTask, state: inout LoopState, setup: TestSetup, total: inout Reply) async {
        if state.hits.isEmpty {
            var results: String?
            // The name in the question is usually the title of the page that answers it.
            if state.queries.isEmpty, let name = HarnessText.namedThing(in: task.body) {
                state.queries.append(name)
                switch await WebTools.titleSearch(name) {
                case .success(let text):
                    total.toolLog.append("Looked up: \(name)")
                    if !HarnessText.hits(in: text).isEmpty { results = text }
                case .failure(let failure) where failure.message == WebTools.declined:
                    total.toolLog.append(WebTools.declinedNote)
                    state.webDeclined = true
                    return
                case .failure:
                    total.toolLog.append("Looked up: \(name)" + HarnessTools.failedMark)
                }
            }
            if results == nil, let query = await strictQuery(task, state: &state, setup: setup, total: &total) {
                let call = ToolCall(name: "web_search", arguments: ["query": query])
                let found = await HarnessTools.run(call)
                if found.failed, found.text.hasSuffix(WebTools.declined) {
                    total.toolLog.append(WebTools.declinedNote)
                    state.webDeclined = true
                    return
                }
                total.toolLog.append(HarnessTools.describe(call) + (found.failed ? HarnessTools.failedMark : ""))
                total.guardRemoved += found.removed
                if !found.failed { results = found.text }
            }
            guard let results else { return }
            let ranked = HarnessText.ranked(HarnessText.hits(in: results), for: task.body).filter { !state.opened.contains($0.url) }
            state.hits = ranked.filter { !isListPage($0.title) } + ranked.filter { isListPage($0.title) }
        }

        for _ in 0..<2 where !state.hits.isEmpty {
            let hit = state.hits.removeFirst()
            state.opened.insert(hit.url)
            let describe = HarnessTools.describe(ToolCall(name: "open_page", arguments: ["url": hit.url]))
            guard case .success(let text) = await WebTools.open(hit.url, limit: WebTools.maxSearchableCharacters) else {
                total.toolLog.append(describe + HarnessTools.failedMark)
                continue
            }
            total.toolLog.append(describe)
            let sentences = Quotes.sentences(of: text)
            state.pageSentences += sentences.prefix(400)
            let picked = Quotes.pick(from: sentences, question: task.body)
            guard !picked.isEmpty else { continue }
            let safe = PromptGuard.wrap(picked.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"), source: hit.url)
            total.guardRemoved += safe.removed
            state.quotes = picked
            state.evidence = ["Sentences from \(hit.title):\n\(safe.text)"]
            state.readTheWeb = true
            return
        }
    }

    /// The model's own search the first time, then one built from the question's words.
    private static func strictQuery(_ task: HarnessTask, state: inout LoopState, setup: TestSetup, total: inout Reply) async -> String? {
        let fromTask = PassageFinder.keywords(in: task.body).prefix(7).joined(separator: " ")
        // The first entry may be the name already tried as a title.
        let written = state.queries.filter { $0 != HarnessText.namedThing(in: task.body) }.count
        var query: String?
        switch written {
        case 0:
            let request = "\(task.subject)\n\n---\nWrite a web search of 3 to 8 words that would find this. Reply with only the search words."
            let reply = await stepReply(.act, [ChatTurn(role: "user", content: request)], setup: setup, tokens: 40, total: &total)
            query = HarnessText.cleanQuery(reply.answer.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
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

    /// What the model reads after the task once sentences have been found. It may fall back on what it knows,
    /// since a page that doesn't answer the question is worse than none.
    static func quotedNote(_ evidence: [String]) -> String {
        guard !evidence.isEmpty else { return "" }
        return "\n\nYour tools found these sentences. If one of them answers the question, answer from it and trust it over your memory. "
            + "If none of them does, answer from what you know.\n\n\(evidence.joined(separator: "\n\n"))"
    }

    // MARK: Check

    /// The names and numbers in an answer that the question didn't already hold: what makes it this answer.
    static func distinctive(_ answer: String, beyond question: String) -> [String] {
        let asked = question.lowercased()
        var seen = Set<String>()
        let words = answer.split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "-" }.map(String.init)
        return words.enumerated().compactMap { index, word -> String? in
            let isNumber = word.first?.isNumber == true
            let isName = word.first?.isUppercase == true && word.count > 1 && index > 0
            guard isNumber || isName, !asked.contains(word.lowercased()), seen.insert(word.lowercased()).inserted else { return nil }
            return word
        }
    }

    /// Whether a sentence is about what the question asked: it holds the question's own names and numbers when
    /// it has any, since "atomic number 50" shares every ordinary word with a question about number 74, and
    /// otherwise one of its words.
    private static func isAbout(_ sentence: String, task: HarnessTask) -> Bool {
        let lower = sentence.lowercased()
        func holds(_ mark: String) -> Bool {
            lower.range(of: "\\b\(NSRegularExpression.escapedPattern(for: mark.lowercased()))\\b", options: .regularExpression) != nil
        }
        let marks = distinctive(task.body, beyond: "")
        if !marks.isEmpty { return marks.filter(holds).count >= max(1, (marks.count + 1) / 2) }
        let asked = Set(PassageFinder.keywords(in: task.body))
        return PassageFinder.keywords(in: sentence).contains(where: asked.contains)
    }

    /// A sentence that holds one of these names or numbers and is about what the question asked.
    static func sentence(holding marks: [String], task: HarnessTask, in sentences: [String]) -> String? {
        guard !marks.isEmpty else { return nil }
        return sentences.first { sentence in
            let lower = sentence.lowercased()
            guard marks.contains(where: { lower.range(of: "\\b\(NSRegularExpression.escapedPattern(for: $0.lowercased()))\\b", options: .regularExpression) != nil }) else { return false }
            return isAbout(sentence, task: task)
        }
    }

    /// Whether one of the quoted sentences holds what the reply adds to the question and is about what was
    /// asked. Words that turn up anywhere on a page aren't enough: that is how a nearby year or a neighbouring
    /// row passed in v3.
    static func isBacked(_ text: String, by quotes: [String], task: HarnessTask) -> Bool {
        let asked = Set(PassageFinder.keywords(in: task.body))
        let added = PassageFinder.keywords(in: ModelTestSuite.finalAnswer(text)).filter { !asked.contains($0) }
        guard !added.isEmpty else { return true }
        return quotes.contains { quote in
            PassageFinder.keywords(in: quote).contains(where: added.contains) && isAbout(quote, task: task)
        }
    }

    /// After Check: when the model's own answer and the page's differ, puts the sentences behind each in front
    /// of it, once. Returns the attempt, marked to go round again if so.
    static func reconciled(_ attempt: Attempt, task: HarnessTask, state: inout LoopState, total: inout Reply) -> Attempt {
        guard state.kind == .fact, !state.reconciled, let memory = state.memoryAnswer, !attempt.text.isEmpty,
              !state.pageSentences.isEmpty else { return attempt }
        let missing = distinctive(memory, beyond: task.body).filter { !attempt.text.lowercased().contains($0.lowercased()) }
        guard !missing.isEmpty, let rival = sentence(holding: missing, task: task, in: state.pageSentences) else { return attempt }
        // What the page's answer has that the model's own didn't, and the sentence it came from.
        let differing = distinctive(ModelTestSuite.finalAnswer(attempt.text), beyond: task.body).filter { !memory.lowercased().contains($0.lowercased()) }
        let own = sentence(holding: differing, task: task, in: state.quotes)
        guard own != rival else { return attempt }
        state.reconciled = true
        let pair = [own, rival].compactMap { $0 }
        let safe = PromptGuard.wrap(pair.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"), source: "the page")
        total.guardRemoved += safe.removed
        state.quotes = pair
        state.evidence = ["Sentences from the page:\n\(safe.text)"]
        total.toolLog.append(pair.count == 2 ? "Two sentences point to different answers, so it reads both again"
                                             : "A sentence on the page backs the answer from memory, so it reads that again")
        let problem = Problem.rule(pair.count == 2
            ? "Two sentences on the page point to different answers. Read the question again and answer from the sentence that says exactly what was asked."
            : "A sentence on the page says something else. Read it and the question again.")
        return Attempt(text: attempt.text, problems: [problem] + attempt.problems.filter { $0 != .unsupported })
    }

    /// The last line of a reply's steps in v6: what code checked, said plainly.
    static func checkedLine(_ best: Attempt?, state: LoopState) -> String {
        guard let best, !best.text.isEmpty else { return "Not checked: there was no reply to check" }
        if state.result != nil { return "Checked: code worked this out" }
        if !best.problems.isEmpty { return "Not checked: \(best.problems[0].text)" }
        if state.kind == .fact {
            if !state.quotes.isEmpty { return "Checked: a sentence from the page backs this" }
            return state.webDeclined ? "Not checked: answered from memory, with no lookup" : "Not checked: nothing found backs this, so it's from memory"
        }
        if state.rules.hasShape { return "Checked: the rules in the message, by code" }
        return "Nothing here for code to check"
    }
}

/// Picks the sentences of a page that bear on a question. A small model given three sentences reads them; given
/// a page, it mostly doesn't.
enum Quotes {
    static func sentences(of text: String) -> [String] {
        text.replacingOccurrences(of: #"(?<=[.!?])\s+(?=[A-Z0-9"“(])"#, with: "\n", options: .regularExpression)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 25 && $0.count <= 500 && $0.contains(where: \.isLetter) }
    }

    /// Up to `limit` sentences that share the most words with the question, in the order the page has them.
    /// The page's opening sentences win ties, since that's where a page says what it's about.
    static func pick(from sentences: [String], question: String, limit: Int = 3) -> [String] {
        let asked = Set(PassageFinder.keywords(in: question))
        guard !asked.isEmpty else { return [] }
        let need = asked.count >= 4 ? 2 : 1
        let scored = sentences.prefix(600).enumerated().map { index, sentence in
            (index: index, hits: Set(PassageFinder.keywords(in: sentence)).intersection(asked).count)
        }
        let best = scored.filter { $0.hits >= need }.sorted { ($0.hits, -$0.index) > ($1.hits, -$1.index) }.prefix(limit)
        return best.sorted { $0.index < $1.index }.map { sentences[$0.index] }
    }
}

extension HarnessText {
    private static let kindWords: Set<String> = [
        "conjecture", "theorem", "hypothesis", "problem", "lemma", "paradox", "effect", "law", "principle", "equation", "constant",
        "treaty", "war", "battle", "revolution", "river", "mountain", "lake", "sea", "ocean", "island", "desert", "empire", "dynasty",
        "kingdom", "prize", "medal", "award", "syndrome", "disease", "algorithm", "protocol", "language", "script", "alphabet",
        "mission", "program", "project", "act", "agreement", "convention", "conference", "crisis", "expedition", "bridge", "tower",
        "cathedral", "temple", "canal", "university", "museum", "inequality", "function", "series", "sequence", "scale", "test",
    ]
    private static let joiners: Set<String> = ["of", "the", "de", "van", "von", "da", "di", "la", "le", "del", "al", "bin", "ibn"]

    /// The one thing a question names, such as "Mordell conjecture" or "Battle of Kadesh". Nil when it names
    /// nothing or several things, because guessing which of several pages matters is the model's job.
    static func namedThing(in question: String) -> String? {
        var runs: [[String]] = []
        for sentence in question.split(whereSeparator: { ".!?\n".contains($0) }) {
            let words = sentence.split(whereSeparator: { $0.isWhitespace || ",;:()\"“”".contains($0) }).map(String.init)
            var run: [String] = []
            func close() {
                while let last = run.last, joiners.contains(last.lowercased()) { run.removeLast() }
                if !run.isEmpty { runs.append(run) }
                run = []
            }
            for (index, word) in words.enumerated() {
                let plain = word.trimmingCharacters(in: CharacterSet(charactersIn: "'’"))
                let capital = plain.first?.isUppercase == true && plain.contains(where: \.isLetter)
                if capital, index > 0 || (words.count > 1 && words[1].first?.isUppercase == true) {
                    run.append(plain.hasSuffix("'s") || plain.hasSuffix("’s") ? String(plain.dropLast(2)) : plain)
                } else if !run.isEmpty, joiners.contains(plain.lowercased()) {
                    run.append(plain)
                } else if run.count == 1, kindWords.contains(plain.lowercased()) {
                    run.append(plain)
                    close()
                } else {
                    close()
                }
            }
            close()
        }
        let named = runs.map { $0.joined(separator: " ") }.filter { $0.count > 2 }
        return Set(named).count == 1 ? named.first : nil
    }
}
