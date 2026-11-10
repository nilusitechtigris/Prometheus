import Foundation

/// One question of the model test. Each has a single checkable answer, so grading is automatic
/// and works the same for every model.
struct ModelTestQuestion: Identifiable {
    enum Check {
        /// The last number in the final answer must equal this, so "47 × 23 = 1081" counts. So may
        /// the first, unless the answer is a sum, so "807 / 1000" counts too.
        case number(Double)
        /// At least one of these must appear as a whole word in the final answer (case-insensitive).
        case word([String])
        /// All of these must appear as whole words in the final answer (case-insensitive).
        case allWords([String])
        /// The final answer must contain this text (case-insensitive).
        case contains(String)
        /// Tests the final answer, for questions that end with an "Answer:" line.
        case final((String) -> Bool)
        /// Tests the whole reply, for questions about the reply's own format.
        case reply((String) -> Bool)
    }

    let id: String
    let category: ModelTestCategory
    let level: ModelTestLevel
    let title: String
    /// One sentence on what this question checks, shown when the row is expanded.
    let summary: String
    let prompt: String
    /// Stands in for `prompt` in saved results when the prompt is thousands of tokens of notes.
    var shortPrompt: String?
    let expected: String
    let check: Check
    /// For a question whose check has to run something, such as code against its tests. It replaces `check`.
    var asyncCheck: ((String) async -> Bool)?
    /// True for a question worth one point whatever its level, so a score is the share answered right. The
    /// level then only sets how much room the reply gets.
    var unweighted = false

    /// Whether a reply answers the question, by whichever check it has.
    func passes(_ raw: String) async -> Bool {
        if let asyncCheck { return await asyncCheck(raw) }
        return grade(raw)
    }

    func grade(_ raw: String) -> Bool {
        let answer = ModelTestSuite.finalAnswer(raw)
        switch check {
        case .number(let value):
            let found = ModelTestSuite.numbers(in: answer)
            guard let first = found.first, let last = found.last else { return false }
            return abs(last - value) < 0.001 || (!answer.contains("=") && abs(first - value) < 0.001)
        case .word(let words):
            return words.contains { ModelTestSuite.containsWord($0, in: answer) }
        case .allWords(let words):
            return words.allSatisfy { ModelTestSuite.containsWord($0, in: answer) }
        case .contains(let text):
            return answer.lowercased().contains(text.lowercased())
        case .final(let test):
            return test(answer)
        case .reply(let test):
            return test(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

/// How much of the Harness Test runs.
enum HarnessTestSize: String, CaseIterable, Identifiable {
    case normal, max
    /// Public questions the harness was never tuned on. See `HeldOut`.
    case heldOut
    /// Public questions of the same kinds, for looking at failures. The harness may be tuned on these.
    case practice

    var id: String { rawValue }
    var title: String { self == .heldOut ? "Held-out" : rawValue.capitalized }
    /// The file of public questions this size asks, when it asks one.
    var questionSet: String? {
        switch self {
        case .heldOut: HeldOut.current
        case .practice: HeldOut.practice
        case .normal, .max: nil
        }
    }
}

/// The model test: six topics, each with four levels of difficulty. A question is worth twice the
/// one below it, so most of the score sits in the expert questions and only a frontier-class model
/// reaches 100.
enum ModelTestSuite {
    /// Bump when the questions, weights or token limits change: scores from different versions don't compare.
    static let version = 3

    /// The model a score of 100 stands for.
    static let referenceModel = "Opus 5.5"
    /// From a blind run of this suite: the model saw only the questions, with no tools.
    /// Repeat it when the questions change (LOCALAI_DUMP_SUITE and LOCALAI_GRADE in DebugHooks).
    static let scaleNote = "100 is \(referenceModel) at max effort, which scored 90 of 90 points in a blind run of these questions."
    static let questionCount = 24
    /// Harness - Normal: the topics where the harness gained most and that run fastest, one for each thing
    /// it adds (the code sandbox, web search and the rule checks), without the basic questions nearly
    /// everything passes. Harness - Max is every question.
    static let quickIDs: Set<String> = ["code-2", "code-3", "code-4", "know-2", "know-3", "know-4", "follow-2", "follow-3", "follow-4"]

    static let systemPrompt = "You are a helpful assistant. Follow the instructions in each question exactly, including the requested answer format."

    private static let finish = "Work it out, then finish with a last line in exactly this form:\nAnswer: <your answer>"

    static func questions(contextLength: Int) -> [ModelTestQuestion] {
        math + reasoning + knowledge + instructions + coding + longContext(contextLength: contextLength)
    }

    // MARK: Math

    private static let math: [ModelTestQuestion] = [
        .init(id: "math-1", category: .math, level: .basic, title: "47 × 23",
              summary: "Plain multiplication.",
              prompt: "What is 47 × 23?\n\n\(finish)", expected: "1081", check: .number(1081)),
        .init(id: "math-2", category: .math, level: .intermediate, title: "Two discounts in a row",
              summary: "Percentages applied one after the other. Adding them to 35 % off is the usual mistake.",
              prompt: "A jacket costs $80. It's discounted by 25 %, and then a further 10 % comes off the discounted price. What is the final price in dollars?\n\n\(finish)",
              expected: "54", check: .number(54)),
        .init(id: "math-3", category: .math, level: .advanced, title: "7²⁰²⁵ mod 1000",
              summary: "Modular arithmetic: the power is far too large to compute directly, so the model has to find the cycle.",
              prompt: "What is the remainder when 7^2025 is divided by 1000?\n\n\(finish)", expected: "807", check: .number(807)),
        .init(id: "math-4", category: .math, level: .expert, title: "Factorizations of 10800",
              summary: "Counting without double counting: unordered factorizations need symmetry arguments, then the cases with a factor of 1 removed.",
              prompt: "In how many ways can 10800 be written as a product of three integers that are each greater than 1? Order doesn't matter, so 2 × 3 × 1800 and 3 × 2 × 1800 count as the same way.\n\n\(finish)",
              expected: "126", check: .number(126)),
    ]

    // MARK: Reasoning

    private static let reasoning: [ModelTestQuestion] = [
        .init(id: "reason-1", category: .reasoning, level: .basic, title: "Who is shortest",
              summary: "A two-step comparison.",
              prompt: "Tom is taller than Ana. Ana is taller than Lee. Who is the shortest?\n\n\(finish)",
              expected: "Lee", check: .word(["Lee"])),
        .init(id: "reason-2", category: .reasoning, level: .intermediate, title: "Three pets",
              summary: "Elimination: each clue rules out an option, and the answer only appears after combining them.",
              prompt: "Anna, Ben and Cara each have one different pet: a cat, a dog or a fish. Anna's pet has no fur. Ben is afraid of dogs. Who owns the dog?\n\n\(finish)",
              expected: "Cara", check: .word(["Cara"])),
        .init(id: "reason-3", category: .reasoning, level: .advanced, title: "Knights and knaves",
              summary: "Self-reference: knights always tell the truth and knaves always lie, so every case has to be tested for consistency.",
              prompt: "On an island, knights always tell the truth and knaves always lie. You meet A, B and C.\nA says: \"Exactly one of the three of us is a knight.\"\nB says: \"A is a knave.\"\nC says: \"Exactly one of A and B is a knight.\"\nWhich of them are knights? List their letters.\n\n\(finish)",
              expected: "B, C",
              check: .final { answer in
                  // "A is a knave, B and C are knights" only names A to rule it out.
                  let knights = answer.replacingOccurrences(of: #"\b[ABC]\s+is\s+a\s+knave\b|(?i:knaves?)\W+[ABC]\b"#, with: "",
                                                            options: .regularExpression)
                  let letters = knights.split { !$0.isLetter }.filter { word in word.allSatisfy { "ABC".contains($0) } }
                  return Set(letters.joined()) == ["B", "C"]
              }),
        .init(id: "reason-4", category: .reasoning, level: .expert, title: "The on-call puzzle",
              summary: "A 13-clue logic grid across three dimensions, with exactly one solution. It has to be deduced in full; it can't be recalled from memory.",
              prompt: """
              Five engineers (Ada, Bo, Cy, Dee, Eli) are each on call on a different weekday, Monday to Friday. Each writes a different language (Rust, Go, Swift, Zig, Perl) and has a different drink (tea, coffee, cocoa, juice, water).
              1. Cy writes Rust.
              2. Ada is on call earlier in the week than Eli.
              3. Bo's day is right next to the Go programmer's day.
              4. The Zig programmer drinks tea.
              5. Dee drinks coffee.
              6. Dee is on call the day right after the Swift programmer.
              7. The Perl programmer is not on call on Monday or Friday.
              8. Monday's engineer drinks water.
              9. Friday's engineer drinks cocoa.
              10. Cy is not on call on Wednesday, and is on call later in the week than the Zig programmer.
              11. Bo is on call on Monday or Friday.
              12. The Go programmer is on call on Wednesday, or Eli is on call on Thursday, or both.
              13. Ada does not write Zig.

              Who drinks juice, and which language do they write?

              \(finish)
              """,
              expected: "Ada, Perl", check: .allWords(["Ada", "Perl"])),
    ]

    // MARK: Knowledge

    /// How sources spell the king who signed the treaty. Accents don't matter: see `containsWord`.
    private static let hattusiliSpellings = ["Hattusili", "Hattusilis", "Hattusilli", "Hattushili", "Hattushilish",
                                             "Khattusili", "Khattusilis"]

    private static let knowledge: [ModelTestQuestion] = [
        .init(id: "know-1", category: .knowledge, level: .basic, title: "Symbol for gold",
              summary: "Common school knowledge.",
              prompt: "What is the chemical symbol for gold?\n\n\(finish)", expected: "Au", check: .word(["Au"])),
        .init(id: "know-2", category: .knowledge, level: .intermediate, title: "Element 74",
              summary: "A specific fact that's easy to confuse with its neighbours in the periodic table.",
              prompt: "Which chemical element has atomic number 74?\n\n\(finish)",
              expected: "Tungsten", check: .word(["Tungsten", "Wolfram"])),
        .init(id: "know-3", category: .knowledge, level: .advanced, title: "The Mordell conjecture",
              summary: "Specialist knowledge of 20th-century mathematics.",
              prompt: "Which mathematician proved the Mordell conjecture in 1983?\n\n\(finish)",
              expected: "Gerd Faltings", check: .word(["Faltings"])),
        .init(id: "know-4", category: .knowledge, level: .expert, title: "The treaty of Kadesh",
              summary: "Two linked facts from ancient history. Small models tend to name the king who fought the battle, not the one who signed the peace.",
              prompt: "After the Battle of Kadesh, a peace treaty was concluded with Ramesses II. Which Hittite king concluded it, and in which language was the copy found at the Hittite capital written?\n\n\(finish)",
              expected: "Hattusili III, Akkadian",
              check: .final { answer in
                  containsWord("Akkadian", in: answer) && hattusiliSpellings.contains { containsWord($0, in: answer) }
              }),
    ]

    // MARK: Instructions

    private static let instructions: [ModelTestQuestion] = [
        .init(id: "follow-1", category: .instructions, level: .basic, title: "Exactly three words",
              summary: "A simple format rule, with nothing but the requested words in the reply.",
              prompt: "Describe the sky in exactly three words, all lowercase, with no punctuation.",
              expected: "3 lowercase words, no punctuation",
              check: .reply { text in
                  text.split(whereSeparator: \.isWhitespace).count == 3 && text == text.lowercased()
                      && text.allSatisfy { $0.isLetter || $0.isWhitespace }
              }),
        .init(id: "follow-2", category: .instructions, level: .intermediate, title: "JSON only",
              summary: "Machine-readable output: the reply must parse as JSON, with no code fences or extra text.",
              prompt: "Return only a JSON object with two keys: \"name\" (a string) and \"age\" (a number). No code fences and no other text.",
              expected: "{\"name\": …, \"age\": …}",
              check: .reply { text in
                  guard let data = text.data(using: .utf8),
                        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let age = object["age"] as? NSNumber else { return false }
                  // JSON's true and false also arrive as NSNumber.
                  return object["name"] is String && CFGetTypeID(age) != CFBooleanGetTypeID() && object.count == 2
              }),
        .init(id: "follow-3", category: .instructions, level: .advanced, title: "Four rules at once",
              summary: "Several rules that all have to hold together: sentence count, first letters, an exact word count and a banned word.",
              prompt: "Write exactly 3 sentences about the sea. Every sentence must begin with the letter S. The second sentence must have exactly 5 words. Do not use the word \"water\". Reply with only the sentences.",
              expected: "3 sentences, all starting with S, the second 5 words, no \"water\"",
              check: .reply { text in
                  let sentences = text.split { ".!?".contains($0) }
                      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                      .filter { !$0.isEmpty }
                  return sentences.count == 3
                      && sentences.allSatisfy { $0.lowercased().hasPrefix("s") }
                      && sentences[1].split(whereSeparator: \.isWhitespace).count == 5
                      && !containsWord("water", in: text)
              }),
        .init(id: "follow-4", category: .instructions, level: .expert, title: "Poem without the letter e",
              summary: "A lipogram with exact line lengths. Models see tokens rather than letters, so this takes real checking and rewriting.",
              prompt: "Write a 4-line poem. Line 1 must have exactly 3 words, line 2 exactly 5 words, line 3 exactly 7 words and line 4 exactly 9 words. Every line must begin with the letter T. The letter e must not appear anywhere in the poem, in upper or lower case. Reply with only the poem.",
              expected: "4 lines of 3, 5, 7 and 9 words, each starting with T, no letter e",
              check: .reply { text in
                  let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                  return lines.map { $0.split(whereSeparator: \.isWhitespace).count } == [3, 5, 7, 9]
                      && lines.allSatisfy { $0.lowercased().hasPrefix("t") }
                      && !text.lowercased().contains("e")
              }),
    ]

    // MARK: Coding

    private static let coding: [ModelTestQuestion] = [
        .init(id: "code-1", category: .coding, level: .basic, title: "Python generator sum",
              summary: "Reading a one-line Python expression.",
              prompt: "What does this Python code print?\n\nprint(sum(x * x for x in range(4)))\n\n\(finish)",
              expected: "14", check: .number(14)),
        .init(id: "code-2", category: .coding, level: .intermediate, title: "Mutable default argument",
              summary: "A classic Python trap: the default list is shared between calls.",
              prompt: "What does this Python code print?\n\ndef f(x, acc=[]):\n    acc.append(x)\n    return acc\n\nf(1)\nf(2)\nprint(len(f(3)))\n\n\(finish)",
              expected: "3", check: .number(3)),
        .init(id: "code-3", category: .coding, level: .advanced, title: "JavaScript event loop",
              summary: "Execution order across synchronous code, microtasks, async functions and timers.",
              prompt: "In what order does this JavaScript print its numbers? Give them as one string of digits.\n\nconsole.log(1);\nsetTimeout(() => console.log(2), 0);\nPromise.resolve().then(() => console.log(3));\n(async () => {\n  console.log(4);\n  await null;\n  console.log(5);\n})();\nconsole.log(6);\n\n\(finish)",
              expected: "146352",
              check: .final { $0.filter(\.isNumber) == "146352" }),
        .init(id: "code-4", category: .coding, level: .expert, title: "Tracing a deque",
              summary: "Following 52 rounds of state exactly, or recognising the Josephus problem and working its recurrence without a slip.",
              prompt: "What does this Python code print?\n\nfrom collections import deque\n\ndef survivor(n, k):\n    q = deque(range(1, n + 1))\n    while len(q) > 1:\n        q.rotate(-(k - 1))\n        q.popleft()\n    return q[0]\n\nprint(survivor(53, 7))\n\n\(finish)",
              expected: "22", check: .number(22)),
    ]

    // MARK: Long context

    static let secretCode = "MAPLE-7342"

    private static func longContext(contextLength: Int) -> [ModelTestQuestion] {
        let ledger = warehouseLedger(contextLength: contextLength)
        return [
            .init(id: "long-1", category: .longContext, level: .basic, title: "Find the code",
                  summary: "One fact buried in a short document, near its start.",
                  prompt: notes(tokens: min(800, contextLength / 4), inserts: [(0.3, "The access code is \(secretCode).")],
                                question: "What is the access code mentioned in the notes?"),
                  shortPrompt: "About 800 tokens of notes with one access code in them. Question: what is the access code?",
                  expected: secretCode, check: .contains(secretCode)),
            .init(id: "long-2", category: .longContext, level: .intermediate, title: "Current code, not the old one",
                  summary: "A long document with decoys: the model has to pick the right one of three similar codes.",
                  prompt: notes(tokens: min(3_000, contextLength / 2),
                                inserts: [(0.2, "The old access code was RIVER-1180. It was retired last year."),
                                          (0.6, "The current access code is \(secretCode)."),
                                          (0.85, "The code proposed for next year is STONE-9021, but it isn't in use yet.")],
                                question: "What is the access code in use right now?"),
                  shortPrompt: "About 3,000 tokens of notes with three codes in them: a retired one, the current one and a proposed one. Question: which is in use right now?",
                  expected: secretCode, check: .contains(secretCode)),
            .init(id: "long-3", category: .longContext, level: .advanced, title: "Three-step lookup",
                  summary: "Linking facts that are far apart: each note only points to the next, and a near-identical code sits nearby as a decoy.",
                  prompt: notes(tokens: min(3_000, contextLength / 2),
                                inserts: [(0.15, "Project Ibis has budget code K-552."),
                                          (0.3, "Project Wren has budget code K-525."),
                                          (0.5, "Project Heron shares its budget code with Project Lark."),
                                          (0.7, "Project Finch has budget code K-255."),
                                          (0.88, "Project Lark shares its budget code with Project Ibis.")],
                                question: "What is Project Heron's budget code?"),
                  shortPrompt: "About 3,000 tokens of notes. Heron shares a code with Lark, Lark shares one with Ibis, and Ibis has K-552, with similar codes for other projects as decoys. Question: what is Project Heron's budget code?",
                  expected: "K-552", check: .contains("K-552")),
            .init(id: "long-4", category: .longContext, level: .expert, title: "Audit a shipping log",
                  summary: "Adding up every matching entry in a long log, after applying the corrections, cancellations and redirects scattered through it.",
                  prompt: ledger.prompt,
                  shortPrompt: "A shipping log of about 3,000 tokens, with corrections, cancellations and redirects in it. Question: how many crates of bolts reached Oslo in the end?",
                  expected: "\(ledger.total)", check: .number(Double(ledger.total))),
        ]
    }

    /// Filler notes with the given sentences inserted at fractions of the way through.
    private static func notes(tokens: Int, inserts: [(position: Double, text: String)], question: String) -> String {
        let sentences = [
            "The river near the old mill flows east toward the valley.",
            "Morning markets open early and close before the afternoon heat.",
            "The library keeps its rare maps in a cool room on the second floor.",
            "A narrow path climbs the hill behind the school to a small lookout.",
            "Fishing boats return to the harbor when the tide begins to turn.",
            "The town clock was repaired last spring and now runs on time.",
            "Gardeners plant tulips in autumn so they bloom in early spring.",
            "The bakery on the corner is known for its rye bread and plum cake.",
        ]
        // About 19 tokens per note.
        let count = max(tokens / 19, 10)
        var lines: [String] = []
        for i in 0..<count {
            lines.append("Note \(i + 1): \(sentences[i % sentences.count])")
            for insert in inserts where Int(insert.position * Double(count)) == i {
                lines.append("Note \(i + 1)b: \(insert.text)")
            }
        }
        return "Read the notes below, then answer the question at the end.\n\n" + lines.joined(separator: "\n")
            + "\n\nQuestion: \(question)\n\n\(finish)"
    }

    /// A shipping log, the same on every run, whose answer needs every matching line plus the changes
    /// made to them later on. Sized to about half the context window, at most ~3,000 tokens.
    private static func warehouseLedger(contextLength: Int) -> (prompt: String, total: Int) {
        var random = SeededNumbers(state: 42)
        let goods = ["bolts", "nails", "hinges"], cities = ["Oslo", "Bergen", "Tromso"]
        struct Entry { let number: Int; let good: String; var city: String; var crates: Int }

        let count = max(min(3_000, contextLength / 2) / 19, 40)
        var entries = (1...count).map { number in
            Entry(number: number, good: goods[random.next(3)], city: cities[random.next(3)], crates: 5 + random.next(56))
        }
        var lines = entries.map { "Log \($0.number): Shipped \($0.crates) crates of \($0.good) to \($0.city)." }

        let matching = entries.indices.filter { entries[$0].good == "bolts" && entries[$0].city == "Oslo" }
        let toBergen = entries.indices.first { entries[$0].good == "bolts" && entries[$0].city == "Bergen" }
        var changes: [(entry: Int, text: String)] = []
        if matching.count >= 3 {
            let (a, b, c) = (matching[0], matching[matching.count / 2], matching[matching.count - 1])
            changes.append((a, "Correction to log \(entries[a].number): the true quantity was \(entries[a].crates + 11) crates."))
            entries[a].crates += 11
            changes.append((b, "Log \(entries[b].number) was cancelled and nothing was shipped."))
            entries[b].crates = 0
            changes.append((c, "The crates from log \(entries[c].number) were redirected to Bergen."))
            entries[c].city = "Bergen"
        }
        if let toBergen {
            changes.append((toBergen, "The crates from log \(entries[toBergen].number) were redirected to Oslo."))
            entries[toBergen].city = "Oslo"
        }
        // Scattered through the second half, always after the entry they change.
        for (i, change) in changes.enumerated() {
            let position = max(change.entry + 2 + i, lines.count * (6 + i) / 10)
            lines.insert("Notice: \(change.text)", at: min(lines.count, position))
        }

        let total = entries.filter { $0.good == "bolts" && $0.city == "Oslo" }.map(\.crates).reduce(0, +)
        let prompt = "Read this shipping log, then answer the question at the end.\n\n" + lines.joined(separator: "\n")
            + "\n\nQuestion: After applying every notice in the log, how many crates of bolts reached Oslo in total?\n\n\(finish)"
        return (prompt, total)
    }

    /// Repeatable random numbers, so the log is identical on every run and every Mac.
    private struct SeededNumbers {
        var state: UInt32

        mutating func next(_ bound: Int) -> Int {
            state = state &* 1_103_515_245 &+ 12_345
            return Int((state >> 16) & 0x7FFF) % bound
        }
    }

    // MARK: Grading helpers

    /// The text after the last "Answer:" marker, or the last line if the model didn't write one.
    static func finalAnswer(_ raw: String) -> String {
        let lines = clean(raw).split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for (i, line) in lines.enumerated().reversed() {
            guard let marker = line.range(of: "answer:", options: .caseInsensitive) else { continue }
            let rest = line[marker.upperBound...].trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { return rest }
            if i + 1 < lines.count { return lines[i + 1] }
        }
        return lines.last ?? ""
    }

    /// Strips Markdown and LaTeX marks so "**Au**" grades like "Au", plus the "/think" switch Qwen
    /// models sometimes echo after an answer.
    static func clean(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for mark in ["**", "__", "`", "$", "\\boxed{", "\\text{", "/no_think", "/think"] {
            s = s.replacingOccurrences(of: mark, with: "")
        }
        return s
    }

    /// Ignores case and accents, so "Ḫattušili" counts as "Hattusili".
    static func containsWord(_ word: String, in text: String) -> Bool {
        let plain = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return plain.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
                           options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func numbers(in text: String) -> [Double] {
        let pattern = #"-?\d[\d,]*(\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).flatMap { Double(text[$0].replacingOccurrences(of: ",", with: "")) }
        }
    }
}
