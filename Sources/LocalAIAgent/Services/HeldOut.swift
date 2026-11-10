import Foundation

/// The held-out questions: fixed samples of public benchmarks that the harness is never tuned on, with their
/// graders. The files, where they come from and the rules for using them are in benchmarks/heldout. Everything
/// is graded by code. None of it is judged by a model.
enum HeldOut {
    /// The set that results are reported on.
    static let current = "heldout-v1"
    /// The set for looking at failures. It shares no question with the other.
    static let practice = "practice-v1"
    /// Far from the app's own test versions, so a build that doesn't know these sets labels their runs "old test"
    /// instead of mixing them with the other tests' scores. Each set has its own, because an older build saves
    /// a run back without its set's name and the number is then all that tells the two apart.
    private static let suiteVersions = [current: 101, practice: 102]
    static func suiteVersion(_ name: String) -> Int? { suiteVersions[name] }
    static func set(forSuiteVersion version: Int?) -> String? { suiteVersions.first { $0.value == version }?.key }
    /// How many questions each file must hold. A file that comes up short was damaged, and its scores would
    /// pass for scores on the whole set.
    private static let expected = [current: 120, practice: 60]
    static func isWhole(_ name: String) -> Bool { size(name) > 0 && size(name) == expected[name] }
    /// How many questions each set holds. Read once, and 0 when this copy of the app has no file.
    private static let sizes = [current: load(current).count, practice: load(practice).count]
    static func size(_ name: String = current) -> Int { sizes[name] ?? 0 }
    /// Where the questions come from, told apart by the start of a question's id.
    static let sources: [(prefix: String, name: String, what: String)] = [
        ("gsm8k-", "GSM8K", "School maths word problems"),
        ("gsmplus-", "GSM-Plus", "The same kind, reworded to catch pattern matching"),
        ("ifeval-", "IFEval", "Writing tasks with rules that code can check"),
        ("mbpp-", "MBPP", "Small Python functions, run against their tests"),
    ]

    struct Item: Decodable {
        let id: String
        let source: String
        let category: String
        let prompt: String
        let check: Check
    }

    struct Check: Decodable {
        let type: String
        var value: String?
        var instructions: [Instruction]?
        var imports: [String]?
        var tests: [String]?
    }

    struct Instruction: Decodable {
        let id: String
        var kwargs: [String: Value] = [:]
    }

    /// What an instruction's settings hold: a count, a word, or a list of words.
    enum Value: Decodable {
        case number(Double), text(String), list([String]), other

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                self = .number(number)
            } else if let text = try? container.decode(String.self) {
                self = .text(text)
            } else if let list = try? container.decode([String].self) {
                self = .list(list)
            } else {
                self = .other
            }
        }

        var int: Int? { if case .number(let value) = self { return Int(value) } else { return nil } }
        var string: String? { if case .text(let value) = self { return value } else { return nil } }
        var strings: [String] { if case .list(let values) = self { return values } else { return [] } }
    }

    private static func folder() -> URL? {
        var folder = Bundle.main.resourceURL?.appendingPathComponent("Benchmarks")
        #if DEBUG
        // Debug builds run outside the app bundle, so use the copy in the repo.
        if folder.map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true {
            folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("benchmarks/heldout")
        }
        #endif
        return folder
    }

    static func load(_ name: String = current) -> [Item] {
        guard let url = folder()?.appendingPathComponent("\(name).jsonl"), let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        // One question a line, split on the line feed alone: a question may hold other kinds of line break.
        return text.components(separatedBy: "\n").filter { !$0.isEmpty }.compactMap { try? decoder.decode(Item.self, from: Data($0.utf8)) }
    }

    /// The set as questions the tests can ask. Every one counts the same, so a score is the share answered right.
    static func questions(_ name: String = current) -> [ModelTestQuestion] {
        load(name).compactMap { item in
            guard var question = question(item) else { return nil }
            question.unweighted = true
            return question
        }
    }

    private static func question(_ item: Item) -> ModelTestQuestion? {
            let category: ModelTestCategory = item.category == "math" ? .math : item.category == "coding" ? .coding : .instructions
            let source = sources.first { item.id.hasPrefix($0.prefix) }?.name ?? item.source
            let title = "\(source) \(item.id.split(separator: "-").last ?? "")"
            switch item.check.type {
            case "number":
                guard let gold = item.check.value else { return nil }
                return ModelTestQuestion(id: item.id, category: category, level: .intermediate, title: title,
                                         summary: "A word problem from \(source). The number on the last line has to be right.",
                                         prompt: item.prompt, expected: gold, check: .reply { HeldOutGrader.number($0, gold: gold) })
            case "ifeval":
                guard let instructions = item.check.instructions, !instructions.isEmpty else { return nil }
                return ModelTestQuestion(id: item.id, category: category, level: .intermediate, title: title,
                                         summary: "A writing task from \(source) with rules about the reply's form. Code checks every rule.",
                                         prompt: item.prompt, expected: instructions.map { IFEvalChecks.describe($0) }.joined(separator: "; "),
                                         check: .reply { reply in instructions.allSatisfy { IFEvalChecks.followed($0, in: reply) } })
            case "python_tests":
                guard let tests = item.check.tests, !tests.isEmpty else { return nil }
                let imports = item.check.imports ?? []
                var question = ModelTestQuestion(id: item.id, category: category, level: .intermediate, title: title,
                                                 summary: "A small function from \(source). Its \(tests.count) tests are run in the sandbox.",
                                                 prompt: item.prompt, expected: "Code that passes its \(tests.count) tests", check: .reply { _ in false })
                question.asyncCheck = { reply in await HeldOutGrader.passesTests(reply, imports: imports, tests: tests) }
                return question
            default:
                return nil
            }
    }
}

enum HeldOutGrader {
    /// Whether a reply gives the answer. A whole-number answer has to match exactly. One with decimals is
    /// compared to two places at most, so 66.67 is right for two thirds of a hundred and 4.333 for 4.33.
    static func number(_ reply: String, gold: String) -> Bool {
        guard let target = Double(gold) else { return false }
        let marked = reply.range(of: "answer:", options: .caseInsensitive) != nil
        let answer = ModelTestSuite.finalAnswer(reply)
        let found = values(in: answer)
        guard let first = found.first, let last = found.last else { return false }
        let parts = gold.split(separator: ".")
        let decimals = parts.count == 2 ? min(parts[1].count, 2) : 0
        func matches(_ value: Double) -> Bool {
            guard decimals > 0 else { return abs(value - target) < 1e-6 }
            let scale = pow(10, Double(decimals))
            return abs((value * scale).rounded() - (target * scale).rounded()) < 0.5
        }
        // The first number counts only on a line the model marked as its answer and that isn't a sum, such as
        // "Answer: 42 apples in 3 boxes". Without the mark, "5 apples at $2 is $10" would pass for 5.
        return matches(last) || (marked && !answer.contains("=") && matches(first))
    }

    /// The numbers in an answer line. "3/4" is one number, a square or cube on a unit ("5 m2") is not one, and a
    /// typographic minus sign counts as a minus.
    static func values(in answer: String) -> [Double] {
        var text = answer.replacingOccurrences(of: "\u{2212}", with: "-")
        text = text.replacingOccurrences(of: #"\b([A-Za-z]{1,3})[23]\b"#, with: "$1", options: .regularExpression)
        let number = #"(?:\d[\d,]*(?:\.\d+)?|(?<![\d.])\.\d+)"#
        guard let regex = try? NSRegularExpression(pattern: "(-?\(number))(?:\\s*/\\s*(\(number)))?") else { return [] }
        func value(_ range: NSRange) -> Double? {
            Range(range, in: text).flatMap { Double(text[$0].replacingOccurrences(of: ",", with: "")) }
        }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let top = value(match.range(at: 1)) else { return nil }
            if match.range(at: 2).location != NSNotFound, let bottom = value(match.range(at: 2)), bottom != 0 { return top / bottom }
            return top
        }
    }

    /// The names a task's tests call, which is how the function they expect is found in a reply.
    static func calledNames(in tests: [String]) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"\b([A-Za-z_][A-Za-z0-9_]*)\s*\("#) else { return [] }
        let text = tests.joined(separator: "\n")
        return Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } })
    }

    /// Takes away the indent every line shares, as a code block inside a list has.
    static func dedented(_ code: String) -> String {
        let lines = code.components(separatedBy: "\n")
        let indent = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
        return lines.map { String($0.dropFirst(min(indent, $0.prefix { $0 == " " || $0 == "\t" }.count))) }.joined(separator: "\n")
    }

    /// The parts of a reply to run, in order. With `names`, it is the last block that defines one of them, after
    /// any earlier blocks that hold helpers or imports. Blocks after it are usually examples of use. Without a
    /// match it is the last block with a function, then the whole reply when that is bare code.
    static func code(in reply: String, defining names: Set<String> = []) -> [String] {
        var blocks: [String] = []
        if let regex = try? NSRegularExpression(pattern: #"```[^\n]*\n(.*?)(?:```|\z)"#, options: .dotMatchesLineSeparators) {
            blocks = regex.matches(in: reply, range: NSRange(reply.startIndex..., in: reply))
                .compactMap { Range($0.range(at: 1), in: reply).map { dedented(String(reply[$0])) } }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        func has(_ block: String, _ pattern: String) -> Bool { block.range(of: pattern, options: .regularExpression) != nil }
        func defines(_ block: String) -> Bool {
            names.contains { has(block, "(?m)^\\s*(?:async\\s+def|def|class)\\s+\($0)\\b|^\($0)\\s*=") }
        }
        if let index = blocks.lastIndex(where: defines) {
            return blocks[..<index].filter { has($0, #"(?m)^(?:def|class|import|from)\s"#) } + [blocks[index]]
        }
        if let block = blocks.last(where: { $0.contains("def ") }) ?? blocks.last { return [block] }
        return reply.contains("def ") ? [dedented(reply)] : []
    }

    /// What runs in the sandbox: the reply's code, then the task's tests, then a word only this run knows.
    /// The reply's code is loaded as a module, so an `if __name__ == "__main__":` block stays quiet, and whatever
    /// it does at the top level (ask for input, exit, crash in an example) is set aside: the tests decide. Type
    /// hints are not worked out, so newer ways of writing them don't fail on an older Python. What the code
    /// prints is thrown away, and only reaching the end prints the word.
    private static func runner(parts: Int, token: String) -> String {
        """
        import __future__, os, sys
        out = sys.stdout
        sys.stdout = open(os.devnull, "w")
        space = {"__name__": "solution"}
        for number in range(\(parts)):
            try:
                with open("solution_%d.py" % number) as file:
                    exec(compile(file.read(), "solution_%d.py" % number, "exec", __future__.annotations.compiler_flag, True), space)
            except BaseException:
                pass
        with open("tests.py") as file:
            exec(compile(file.read(), "tests.py", "exec"), space)
        sys.stdout = out
        print("\(token)")
        """
    }

    /// Runs the reply's code with the task's tests in the sandbox. It passes only when every test ran and held:
    /// a program that ends early without an error doesn't count.
    static func passesTests(_ reply: String, imports: [String], tests: [String]) async -> Bool {
        let parts = code(in: reply, defining: calledNames(in: tests))
        guard !parts.isEmpty else { return false }
        var files = ["tests.py": (imports + tests).joined(separator: "\n") + "\n"]
        for (number, part) in parts.enumerated() { files["solution_\(number).py"] = part + "\n" }
        let token = "ran-\(UUID().uuidString)"
        let outcome = await CodeRunner.run(runner(parts: parts.count, token: token), language: .python, files: files)
        return outcome.succeeded && outcome.output.hasSuffix(token)
    }

    /// Whether the sandbox can run Python at all. Without it every coding question would fail for a reason that
    /// has nothing to do with the model.
    static func canRunCode() async -> Bool {
        await passesTests("def one():\n    return 1", imports: [], tests: ["assert one() == 1"])
    }

    /// The Python the code questions ran on, such as "3.9.6". Hints and library calls differ between versions,
    /// so a run records it.
    static func pythonVersion() async -> String? {
        let outcome = await CodeRunner.run("import sys\nprint(sys.version.split()[0])", language: .python)
        return outcome.succeeded && !outcome.output.isEmpty ? outcome.output : nil
    }
}

enum IFEvalChecks {
    static let supported: Set<String> = [
        "keywords:existence", "keywords:forbidden_words", "keywords:frequency", "keywords:letter_frequency",
        "length_constraints:number_paragraphs", "length_constraints:number_words", "length_constraints:nth_paragraph_first_word",
        "detectable_content:postscript", "detectable_format:constrained_response", "detectable_format:json_format",
        "detectable_format:number_bullet_lists", "detectable_format:number_highlighted_sections", "detectable_format:title",
        "combination:two_responses", "combination:repeat_prompt", "startend:end_checker", "startend:quotation", "punctuation:no_comma",
    ]

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options) -> NSRegularExpression? {
        // The reference hands words to its pattern matcher as they are, so a word that isn't a valid pattern is matched as written.
        (try? NSRegularExpression(pattern: pattern, options: options))
            ?? (try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: pattern), options: options))
    }

    private static func matches(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String] {
        guard let regex = regex(pattern, options) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    /// The text between matches, with empty pieces kept, as the reference's split gives them.
    private static func split(_ text: String, by pattern: String) -> [String] {
        guard let regex = regex(pattern, []) else { return [text] }
        var pieces: [String] = []
        var start = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            pieces.append(String(text[start..<range.lowerBound]))
            start = range.upperBound
        }
        pieces.append(String(text[start...]))
        return pieces
    }

    private static func stripped(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private static func compare(_ actual: Int, _ relation: String?, _ wanted: Int) -> Bool {
        relation == "less than" ? actual < wanted : actual >= wanted
    }

    static func followed(_ instruction: HeldOut.Instruction, in value: String) -> Bool {
        let kwargs = instruction.kwargs
        switch instruction.id {
        case "keywords:existence":
            return (kwargs["keywords"]?.strings ?? []).allSatisfy { !matches($0, in: value, options: .caseInsensitive).isEmpty }
        case "keywords:forbidden_words":
            return (kwargs["forbidden_words"]?.strings ?? []).allSatisfy { matches("\\b\($0)\\b", in: value, options: .caseInsensitive).isEmpty }
        case "keywords:frequency":
            guard let keyword = kwargs["keyword"]?.string, let frequency = kwargs["frequency"]?.int else { return false }
            return compare(matches(stripped(keyword), in: value, options: .caseInsensitive).count, kwargs["relation"]?.string, frequency)
        case "keywords:letter_frequency":
            guard let letter = kwargs["letter"]?.string.map(stripped)?.lowercased().first, let frequency = kwargs["let_frequency"]?.int else { return false }
            return compare(value.lowercased().filter { $0 == letter }.count, kwargs["let_relation"]?.string, frequency)
        case "length_constraints:number_paragraphs":
            guard let wanted = kwargs["num_paragraphs"]?.int else { return false }
            let paragraphs = split(value, by: #"\s?\*\*\*\s?"#)
            var count = paragraphs.count
            for (index, paragraph) in paragraphs.enumerated() where stripped(paragraph).isEmpty {
                if index == 0 || index == paragraphs.count - 1 { count -= 1 } else { return false }
            }
            return count == wanted
        case "length_constraints:number_words":
            guard let wanted = kwargs["num_words"]?.int else { return false }
            return compare(matches(#"\w+"#, in: value).count, kwargs["relation"]?.string, wanted)
        case "length_constraints:nth_paragraph_first_word":
            guard let wanted = kwargs["num_paragraphs"]?.int, let nth = kwargs["nth_paragraph"]?.int, let firstWord = kwargs["first_word"]?.string else { return false }
            let paragraphs = value.components(separatedBy: "\n\n")
            let count = paragraphs.count - paragraphs.filter { stripped($0).isEmpty }.count
            guard nth >= 1, nth <= count, nth <= paragraphs.count else { return false }
            let paragraph = stripped(paragraphs[nth - 1])
            guard !paragraph.isEmpty, var word = paragraph.split(whereSeparator: \.isWhitespace).first.map(String.init) else { return false }
            while word.hasPrefix("'") { word.removeFirst() }
            while word.hasPrefix("\"") { word.removeFirst() }
            var first = ""
            for letter in word {
                if [".", ",", "?", "!", "'", "\""].contains(letter) { break }
                first += letter.lowercased()
            }
            return count == wanted && first == firstWord.lowercased()
        case "detectable_content:postscript":
            guard let marker = kwargs["postscript_marker"]?.string else { return false }
            let pattern: String
            switch marker {
            case "P.P.S": pattern = #"\s*p\.\s?p\.\s?s.*$"#
            case "P.S.": pattern = #"\s*p\.\s?s\..*$"#
            default: pattern = #"\s*"# + marker.lowercased() + ".*$"
            }
            return !matches(pattern, in: value.lowercased(), options: .anchorsMatchLines).isEmpty
        case "detectable_format:constrained_response":
            let text = stripped(value)
            return ["My answer is yes.", "My answer is no.", "My answer is maybe."].contains { text.contains($0) }
        case "detectable_format:json_format":
            var text = stripped(value)
            for prefix in ["```json", "```Json", "```JSON", "```"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
            if text.hasSuffix("```") { text.removeLast(3) }
            guard let data = stripped(text).data(using: .utf8) else { return false }
            return (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil
        case "detectable_format:number_bullet_lists":
            guard let wanted = kwargs["num_bullets"]?.int else { return false }
            let stars = matches(#"^\s*\*[^\*].*$"#, in: value, options: .anchorsMatchLines).count
            let dashes = matches(#"^\s*-.*$"#, in: value, options: .anchorsMatchLines).count
            return stars + dashes == wanted
        case "detectable_format:number_highlighted_sections":
            guard let wanted = kwargs["num_highlights"]?.int else { return false }
            let single = matches(#"\*[^\n\*]*\*"#, in: value).filter { !stripped($0.trimmingCharacters(in: CharacterSet(charactersIn: "*"))).isEmpty }.count
            let double = matches(#"\*\*[^\n\*]*\*\*"#, in: value).filter { highlight in
                var inner = highlight
                if inner.hasPrefix("**") { inner.removeFirst(2) }
                if inner.hasSuffix("**") { inner.removeLast(2) }
                return !stripped(inner).isEmpty
            }.count
            return single + double >= wanted
        case "detectable_format:title":
            return matches(#"<<[^\n]+>>"#, in: value).contains { title in
                var inner = Substring(title)
                while inner.hasPrefix("<") { inner.removeFirst() }
                while inner.hasSuffix(">") { inner.removeLast() }
                return !stripped(String(inner)).isEmpty
            }
        case "combination:two_responses":
            let responses = value.components(separatedBy: "******")
            var valid: [String] = []
            for (index, response) in responses.enumerated() {
                if stripped(response).isEmpty {
                    if index != 0, index != responses.count - 1 { return false }
                } else {
                    valid.append(response)
                }
            }
            return valid.count == 2 && stripped(valid[0]) != stripped(valid[1])
        case "combination:repeat_prompt":
            guard let prompt = kwargs["prompt_to_repeat"]?.string else { return false }
            return stripped(value).lowercased().hasPrefix(stripped(prompt).lowercased())
        case "startend:end_checker":
            guard let phrase = kwargs["end_phrase"]?.string else { return false }
            let text = stripped(value).trimmingCharacters(in: CharacterSet(charactersIn: "\"")).lowercased()
            return text.hasSuffix(stripped(phrase).lowercased())
        case "startend:quotation":
            let text = stripped(value)
            return text.count > 1 && text.first == "\"" && text.last == "\""
        case "punctuation:no_comma":
            return !value.contains(",")
        default:
            return false
        }
    }

    /// One instruction in a few words, for the results table.
    static func describe(_ instruction: HeldOut.Instruction) -> String {
        let kwargs = instruction.kwargs
        func count(_ key: String) -> String { kwargs[key]?.int.map(String.init) ?? "?" }
        func relation(_ key: String) -> String { kwargs[key]?.string == "less than" ? "fewer than" : "at least" }
        switch instruction.id {
        case "keywords:existence": return "uses \(kwargs["keywords"]?.strings.joined(separator: ", ") ?? "the keywords")"
        case "keywords:forbidden_words": return "never uses \(kwargs["forbidden_words"]?.strings.joined(separator: ", ") ?? "the banned words")"
        case "keywords:frequency": return "\"\(kwargs["keyword"]?.string ?? "?")\" \(relation("relation")) \(count("frequency")) times"
        case "keywords:letter_frequency": return "the letter \(kwargs["letter"]?.string ?? "?") \(relation("let_relation")) \(count("let_frequency")) times"
        case "length_constraints:number_paragraphs": return "\(count("num_paragraphs")) paragraphs split by ***"
        case "length_constraints:number_words": return "\(relation("relation")) \(count("num_words")) words"
        case "length_constraints:nth_paragraph_first_word": return "\(count("num_paragraphs")) paragraphs, number \(count("nth_paragraph")) starting with \"\(kwargs["first_word"]?.string ?? "?")\""
        case "detectable_content:postscript": return "ends with a \(kwargs["postscript_marker"]?.string ?? "P.S.")"
        case "detectable_format:constrained_response": return "says \"My answer is yes.\", no or maybe"
        case "detectable_format:json_format": return "all in JSON"
        case "detectable_format:number_bullet_lists": return "exactly \(count("num_bullets")) bullet points"
        case "detectable_format:number_highlighted_sections": return "at least \(count("num_highlights")) *highlighted* parts"
        case "detectable_format:title": return "a title in <<double angle brackets>>"
        case "combination:two_responses": return "two different replies split by ******"
        case "combination:repeat_prompt": return "repeats the request first"
        case "startend:end_checker": return "ends with \"\(kwargs["end_phrase"]?.string ?? "?")\""
        case "startend:quotation": return "wrapped in double quotes"
        case "punctuation:no_comma": return "no commas"
        default: return instruction.id
        }
    }
}
