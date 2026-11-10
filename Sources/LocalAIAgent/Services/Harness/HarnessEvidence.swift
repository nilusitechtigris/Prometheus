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
    /// Each rule needs what a program would work from to be written in the question: a date, a quoted text, an
    /// amount. "How old is the universe?" and "How many years after Apollo 11…" have none, and stay lookups.
    static func computable(_ text: String) -> Bool {
        let hasNumber = text.contains(where: \.isNumber)
        // Dates and ages, from a date written out in full or a span between two years.
        if hasNumber, has(#"\b(what|which) day of the week\b|\bwhat weekday\b|\bhow many (days|weeks|months|years)\b|\bhow old (is|was|were|will|would)\b"#, text),
           !ExactTools.dates(in: text).isEmpty || has(#"\b(from|between)\s+\d{4}\s+(to|and|until)\s+\d{4}\b"#, text) { return true }
        // Counting what's quoted in the question. An apostrophe isn't a quotation.
        if has(#""[^"]+"|(?:^|\s)'[^']+'(?=$|[\s?.!,;:)])"#, text),
           has(#"\bhow many (letters|words|vowels|consonants|characters|syllables)\b|\bhow many times (does|do)\b|\bcount the\b"#, text) { return true }
        // Units, with the amount to convert.
        if has(#"\bconvert\s+\d|\bhow many (kilometers|kilometres|km|miles|meters|metres|feet|inches|centimeters|centimetres|cm|kilograms|kg|pounds|lbs|ounces|grams|liters|litres|gallons|seconds|minutes|hours) (is|are|in)\s+\d"#, text) { return true }
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
            var hits: [SearchHit] = []
            // The name in the question is usually the title of the page that answers it. Only the page that
            // title leads to is tried, so a wrong guess costs one page and the model's own search still runs.
            if state.queries.isEmpty, let name = HarnessText.namedThing(in: task.body) {
                state.queries.append(name)
                switch await WebTools.titleSearch(name) {
                case .success(let text):
                    total.toolLog.append("Looked up: \(name)")
                    hits = Array(HarnessText.hits(in: text).prefix(1))
                case .failure(let failure) where failure.message == WebTools.declined:
                    total.toolLog.append(WebTools.declinedNote)
                    state.webDeclined = true
                    return
                case .failure:
                    total.toolLog.append("Looked up: \(name)" + HarnessTools.failedMark)
                }
            }
            if hits.isEmpty, let query = await strictQuery(task, state: &state, setup: setup, total: &total) {
                let call = ToolCall(name: "web_search", arguments: ["query": query])
                let found = await HarnessTools.run(call)
                if found.failed, found.text.hasSuffix(WebTools.declined) {
                    total.toolLog.append(WebTools.declinedNote)
                    state.webDeclined = true
                    return
                }
                total.toolLog.append(HarnessTools.describe(call) + (found.failed ? HarnessTools.failedMark : ""))
                total.guardRemoved += found.removed
                if !found.failed {
                    let ranked = HarnessText.ranked(HarnessText.hits(in: found.text), for: task.body)
                    hits = ranked.filter { !isListPage($0.title) } + ranked.filter { isListPage($0.title) }
                }
            }
            state.hits = hits.filter { !state.opened.contains($0.url) }
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
            // From here on the reply may carry something a page said, so its links get checked whatever happens next.
            state.readTheWeb = true
            // The guard cleans the page before anything is picked from it, so nothing it removes can be chosen as
            // evidence, quoted to the model, or counted as backing an answer.
            let clean = PromptGuard.sanitize(text)
            total.guardRemoved += clean.removed
            let sentences = Quotes.sentences(of: clean.text)
            state.pageSentences += sentences.prefix(400)
            let picked = Quotes.pick(from: sentences, question: task.body)
            guard !picked.isEmpty else { continue }
            let title = PromptGuard.sanitize(hit.title).text.prefix(80)
            let safe = PromptGuard.wrap("From the page \"\(title)\":\n" + picked.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"), source: hit.url)
            total.guardRemoved += safe.removed
            state.quotes = picked
            state.evidence = [safe.text]
            return
        }
    }

    /// The model's own search the first time, then one built from the question's words.
    private static func strictQuery(_ task: HarnessTask, state: inout LoopState, setup: TestSetup, total: inout Reply) async -> String? {
        let fromTask = PassageFinder.keywords(in: task.body).prefix(7).joined(separator: " ")
        // The first entry may be the name already tried as a title.
        let name = HarnessText.namedThing(in: task.body)
        let written = state.queries.filter { $0 != name }.count
        var candidates: [String] = []
        if written == 0 {
            let request = "\(task.subject)\n\n---\nWrite a web search of 3 to 8 words that would find this. Reply with only the search words."
            let reply = await stepReply(.act, [ChatTurn(role: "user", content: request)], setup: setup, tokens: 40, total: &total)
            candidates.append(HarnessText.cleanQuery(reply.answer.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""))
        }
        if written <= 1 { candidates.append(fromTask) }
        // A search the same as one already made finds the same pages, so the next one is tried instead.
        guard let chosen = candidates.first(where: { !$0.isEmpty && !state.queries.contains($0) }) else { return nil }
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

    private static let openers: Set<String> = ["the", "it", "a", "an", "in", "on", "this", "that", "there", "he", "she", "they", "i", "we", "yes", "no",
                                               "who", "what", "which", "when", "where", "why", "how", "is", "are", "was", "were", "did", "does", "do",
                                               "can", "could", "will", "would", "should", "name", "tell", "give", "according", "answer"]

    private static func isNumberMark(_ mark: String) -> Bool { mark.first?.isNumber == true }

    /// The names and numbers in a text that `question` didn't already hold: what makes an answer this answer.
    /// `leading` also counts a first word that is a name, for a one-line answer such as "Canberra".
    static func distinctive(_ answer: String, beyond question: String, leading: Bool = false) -> [String] {
        let asked = question.lowercased()
        var seen = Set<String>()
        let words = answer.split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" && $0 != "-" }.map { word -> String in
            var word = String(word)
            if word.hasSuffix("'s") || word.hasSuffix("’s") { word.removeLast(2) }
            return word.trimmingCharacters(in: CharacterSet(charactersIn: "'’-"))
        }
        return words.enumerated().compactMap { index, word -> String? in
            guard !word.isEmpty else { return nil }
            let isNumber = word.first?.isNumber == true
            let isName = word.first?.isUppercase == true && word.count > 1 && (index > 0 || (leading && !openers.contains(word.lowercased())))
            guard isNumber || isName, !asked.contains(word.lowercased()), seen.insert(word.lowercased()).inserted else { return nil }
            return word
        }
    }

    private static func holds(_ mark: String, in lower: String) -> Bool {
        lower.range(of: "(?<![\\w])\(NSRegularExpression.escapedPattern(for: mark.lowercased()))(?![\\w])", options: .regularExpression) != nil
    }

    /// Whether a sentence is about what the question asked. It has to hold every number the question gives,
    /// since "the 2010 World Cup" shares every other word with a question about 2014, and at least half its
    /// names. A question with neither only needs one of its words.
    private static func isAbout(_ sentence: String, task: HarnessTask) -> Bool {
        let lower = sentence.lowercased()
        let marks = distinctive(task.body, beyond: "")
        if marks.isEmpty {
            let asked = Set(PassageFinder.keywords(in: task.body))
            return PassageFinder.keywords(in: sentence).contains(where: asked.contains)
        }
        let numbers = marks.filter(isNumberMark), names = marks.filter { !isNumberMark($0) }
        guard numbers.allSatisfy({ holds($0, in: lower) }) else { return false }
        return names.isEmpty || names.filter { holds($0, in: lower) }.count >= (names.count + 1) / 2
    }

    /// A sentence that holds one of these names or numbers and is about what the question asked.
    static func sentence(holding marks: [String], task: HarnessTask, in sentences: [String]) -> String? {
        guard !marks.isEmpty else { return nil }
        return sentences.first { sentence in
            let lower = sentence.lowercased()
            return marks.contains { holds($0, in: lower) } && isAbout(sentence, task: task)
        }
    }

    /// Whether one of the quoted sentences holds what the reply adds to the question and is about what was
    /// asked. What the reply adds is its names and numbers when it has any: an answer of "1890" isn't backed by
    /// a sentence that shares the word "built" and says 1887. Words that turn up anywhere on a page aren't
    /// enough either: that is how a nearby year or a neighbouring row passed in v3.
    static func isBacked(_ text: String, by quotes: [String], task: HarnessTask) -> Bool {
        let answer = ModelTestSuite.finalAnswer(text)
        let marks = distinctive(answer, beyond: task.body, leading: true)
        if !marks.isEmpty {
            return quotes.contains { quote in
                let lower = quote.lowercased()
                return marks.contains { holds($0, in: lower) } && isAbout(quote, task: task)
            }
        }
        let asked = Set(PassageFinder.keywords(in: task.body))
        let added = PassageFinder.keywords(in: answer).filter { !asked.contains($0) }
        guard !added.isEmpty else { return true }
        return quotes.contains { quote in
            PassageFinder.keywords(in: quote).contains(where: added.contains) && isAbout(quote, task: task)
        }
    }

    /// After Check: when the model's own answer and the page's give different names or numbers, puts the
    /// sentences behind each in front of it, once, and only while there's a round left to read them in.
    /// A reply that just leaves out part of what memory said isn't a disagreement.
    static func reconciled(_ attempt: Attempt, task: HarnessTask, state: inout LoopState, total: inout Reply, mayGoAgain: Bool) -> Attempt {
        guard mayGoAgain, state.kind == .fact, !state.reconciled, let memory = state.memoryAnswer, !attempt.text.isEmpty,
              !state.pageSentences.isEmpty else { return attempt }
        let reply = ModelTestSuite.finalAnswer(attempt.text)
        let missing = distinctive(memory, beyond: task.body, leading: true).filter { !holds($0, in: attempt.text.lowercased()) }
        let differing = distinctive(reply, beyond: task.body, leading: true).filter { !holds($0, in: memory.lowercased()) }
        // A year against a year, or a name against a name.
        let clash = (missing.contains(where: isNumberMark) && differing.contains(where: isNumberMark))
            || (missing.contains { !isNumberMark($0) } && differing.contains { !isNumberMark($0) })
        guard clash, let rival = sentence(holding: missing, task: task, in: state.pageSentences) else { return attempt }
        let own = sentence(holding: differing, task: task, in: state.quotes)
        guard own != rival else { return attempt }
        state.reconciled = true
        state.readTheWeb = true
        let pair = [own, rival].compactMap { $0 }
        let safe = PromptGuard.wrap(pair.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"), source: "the page")
        total.guardRemoved += safe.removed
        state.quotes = pair
        state.evidence = [safe.text]
        total.toolLog.append(pair.count == 2 ? "Two sentences point to different answers, so it reads both again"
                                             : "A sentence on the page backs the answer from memory, so it reads that again")
        let problem = Problem.rule(pair.count == 2
            ? "Two sentences on the page point to different answers. Read the question again and answer from the sentence that says exactly what was asked."
            : "A sentence on the page says something else. Read it and the question again.")
        return Attempt(text: attempt.text, problems: [problem] + attempt.problems.filter { $0 != .unsupported })
    }

    /// The last line of a reply's steps in v6: what was checked, and by what, said plainly.
    static func checkedLine(_ best: Attempt?, state: LoopState) -> String {
        guard let best, !best.text.isEmpty else { return "Not checked: there was no reply to check" }
        if state.result != nil {
            return state.computedByCode ? "Checked: code worked this out" : "Checked: a program was run for this, and the reply states what it printed"
        }
        if !best.problems.isEmpty { return "Not checked: \(best.problems[0].text)" }
        switch state.kind {
        case .fact:
            if !state.quotes.isEmpty { return "Checked: a sentence from the page holds this answer" }
            return state.webDeclined ? "Not checked: answered from memory, with no lookup" : "Not checked: nothing found backs this, so it's from memory"
        case .calculation, .code:
            return "Not checked: no program ran to the end, so this is the model's own working"
        default:
            return state.rules.hasShape ? "Checked: the rules in the message, by code" : "Nothing here for code to check"
        }
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
    /// Words a question starts with, which are capitalised without naming anything.
    private static let questionWords: Set<String> = [
        "who", "whom", "whose", "what", "which", "when", "where", "why", "how", "is", "are", "was", "were", "did", "does", "do", "can",
        "could", "will", "would", "should", "has", "have", "had", "in", "on", "at", "the", "a", "an", "name", "tell", "give", "list",
        "explain", "describe", "according", "please", "if", "for", "to", "from", "by", "with", "about", "after", "before", "during",
    ]

    /// The one thing a question names, such as "Mordell conjecture" or "Battle of Kadesh". Nil when it names
    /// nothing or several things, because guessing which of several pages matters is the model's job. A single
    /// word that reads as "of somewhere", such as American or Chinese, names a people or a language, not a page
    /// worth opening first.
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
                var plain = word.trimmingCharacters(in: CharacterSet(charactersIn: "'’"))
                if plain.hasSuffix("'s") || plain.hasSuffix("’s") { plain.removeLast(2) }
                let capital = plain.first?.isUppercase == true && plain.contains(where: \.isLetter)
                if capital, index > 0 || !questionWords.contains(plain.lowercased()) {
                    run.append(plain)
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
        let named = runs.map { $0.joined(separator: " ") }.filter { name in
            guard name.count > 2 else { return false }
            let single = !name.contains(" ")
            return !(single && name.lowercased().range(of: #"(ian|ean|ese|ish|ch|can|man)$"#, options: .regularExpression) != nil)
        }
        return Set(named).count == 1 ? named.first : nil
    }
}
