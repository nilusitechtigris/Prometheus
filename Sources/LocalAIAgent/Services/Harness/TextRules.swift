import Foundation

/// The rules a task sets for its reply, read from the task itself, with exact checks of a reply
/// against them. Small models can't count their own words, so code does the counting. Everything here
/// is general: it sees only the task and the reply, never an expected answer.
struct TextRules {
    /// What the task counts its reply in.
    enum Unit: String {
        case sentence, line
    }

    var unit: Unit?
    var count: Int?
    /// Exact words in one position, from 0.
    var wordsAt: [Int: Int] = [:]
    var wordsEach: Int?
    var startLetter: Character?
    var totalWords: Int?
    var maxWords: Int?
    var bannedLetters: [Character] = []
    var bannedWords: [String] = []
    var requiredWords: [String] = []
    var lowercase = false
    var uppercase = false
    var noPunctuation = false
    var jsonOnly = false
    var jsonKeys: [String] = []
    /// The label of a last line the task asks for, such as "Answer".
    var finalLabel: String?

    /// True when the task sets rules on the reply's shape, beyond its last line.
    var hasShape: Bool {
        unit != nil || count != nil || !wordsAt.isEmpty || wordsEach != nil || startLetter != nil || totalWords != nil
            || maxWords != nil || !bannedLetters.isEmpty || !bannedWords.isEmpty || !requiredWords.isEmpty
            || lowercase || uppercase || noPunctuation || jsonOnly
    }

    /// True when a rule applies to each sentence or line by itself, which is what rewriting one at a time fixes.
    var hasUnitRules: Bool { unit != nil && (!wordsAt.isEmpty || wordsEach != nil || startLetter != nil) }

    /// One sentence or line with a word count for the whole reply is the same as a count for that one sentence,
    /// and said that way it can be rewritten by itself until it fits.
    var countingTheOnlyUnit: TextRules {
        guard unit != nil, count == 1, let totalWords, wordsAt.isEmpty, wordsEach == nil else { return self }
        var rules = self
        rules.wordsAt[0] = totalWords
        return rules
    }

    /// The same task, keeping only its rule about the last line.
    var onlyFinalLine: TextRules {
        var rules = TextRules(task: "")
        rules.finalLabel = finalLabel
        return rules
    }

    // MARK: Reading the task

    private static let number = "(\\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)"
    private static let numberWords = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
                                      "nine": 9, "ten": 10, "eleven": 11, "twelve": 12]
    private static let ordinals = ["first": 0, "second": 1, "third": 2, "fourth": 3, "fifth": 4, "sixth": 5, "seventh": 6, "eighth": 7]

    private static func value(_ text: String) -> Int? { Int(text) ?? numberWords[text.lowercased()] }

    /// The capture groups of every match.
    private static func all(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
        }
    }

    /// True for the paragraph of a task that sets the form of its last line.
    static func isAnswerForm(_ paragraph: String) -> Bool { label(in: paragraph) != nil }

    private static func label(in text: String) -> String? {
        all(#"\b(?:last|final)\s+line\b[^\n]*\n\s*([A-Za-z][A-Za-z ]{0,20}):\s*<"#, in: text).first?.first
    }

    init(task raw: String) {
        let task = raw.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
        finalLabel = Self.label(in: task)
        let number = Self.number

        for match in Self.all("\\b(sentence|line)\\s+(\\d+)\\b[^.,;\\n]*?\\b\(number)\\s+words?\\b", in: task) where match.count == 3 {
            guard let position = Int(match[1]), let words = Self.value(match[2]) else { continue }
            unit = Unit(rawValue: match[0].lowercased())
            wordsAt[position - 1] = words
        }
        let names = Self.ordinals.keys.joined(separator: "|")
        for match in Self.all("\\b(\(names))\\s+(sentence|line)\\b[^.,;\\n]*?\\b\(number)\\s+words?\\b", in: task) where match.count == 3 {
            guard let position = Self.ordinals[match[0].lowercased()], let words = Self.value(match[2]) else { continue }
            unit = Unit(rawValue: match[1].lowercased())
            wordsAt[position] = words
        }
        for match in Self.all("\\b(?:each|every)\\s+(sentence|line)\\b[^.;\\n]*?\\b\(number)\\s+words?\\b", in: task) where match.count == 2 {
            unit = Unit(rawValue: match[0].lowercased())
            wordsEach = Self.value(match[1])
        }
        for candidate in [Unit.sentence, .line] {
            if let match = Self.all("\\b\(number)[- ]\(candidate.rawValue)s?\\b", in: task).first, let found = Self.value(match[0]) {
                unit = candidate
                count = found
            }
        }
        if wordsAt.isEmpty, wordsEach == nil,
           let match = Self.all("\\b(?:exactly|in|only|just)\\s+\(number)\\s+words?\\b", in: task).first {
            totalWords = Self.value(match[0])
        }
        if let match = Self.all("\\b(?:at most|no more than|up to|maximum of)\\s+\(number)\\s+words?\\b", in: task).first {
            maxWords = Self.value(match[0])
            totalWords = nil
        }
        if let letter = Self.all(#"\b(?:begin|start)s?\s+with\s+(?:the\s+|a\s+capital\s+|a\s+|an\s+)?letter\s+"?([A-Za-z])\b"#, in: task).first?.first?.first {
            startLetter = Character(letter.lowercased())
            if unit == nil { unit = task.lowercased().contains("line") ? .line : .sentence }
        }
        let letterPatterns = [#"\bletter\s+"?([A-Za-z])"?\s+(?:must not|mustn't|may not|cannot|can't|should not|shouldn't)\b"#,
                              #"\b(?:without|avoid|avoiding|no|never use|not use)\s+(?:using\s+)?(?:the\s+)?letter\s+"?([A-Za-z])\b"#]
        for pattern in letterPatterns {
            for match in Self.all(pattern, in: task) {
                if let letter = match.first?.first, !bannedLetters.contains(Character(letter.lowercased())) {
                    bannedLetters.append(Character(letter.lowercased()))
                }
            }
        }
        for match in Self.all(#"\b(?:do not|don't|must not|never|without|avoid|cannot|can't|no)\s+(?:using\s+|use\s+|contain\s+|include\s+|the\s+)*word\s+"([^"]+)""#, in: task) {
            if let word = match.first { bannedWords.append(word) }
        }
        for match in Self.all(#"\b(?:must|should|has to|have to)\s+(?:include|contain|mention|use)\s+(?:the\s+)?(?:word\s+)?"([^"]+)""#, in: task) {
            if let word = match.first, !bannedWords.contains(word) { requiredWords.append(word) }
        }
        lowercase = !Self.all(#"\b(all|in|only)\s+(lower-?case)\b"#, in: task).isEmpty
        uppercase = !Self.all(#"\b(all|in|only)\s+(upper-?case|capitals)\b"#, in: task).isEmpty
        noPunctuation = !Self.all(#"\b(no|without)\s+(punctuation)\b"#, in: task).isEmpty
        jsonOnly = !Self.all(#"\b(only|just)\s+(?:a\s+|an\s+|valid\s+)*(json)\b|\b(json)\s+only\b"#, in: task).isEmpty
        if jsonOnly, let keys = Self.all(#"\bkeys?\b([^\n]*)"#, in: task).first?.first {
            jsonKeys = Self.all(#""([^"]+)""#, in: keys).compactMap(\.first)
        }
    }

    // MARK: Measuring a reply

    private static func wordCount(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }

    /// The reply's sentences or lines.
    func units(of text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch unit {
        case .line:
            return trimmed.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        case .sentence:
            return Self.all(#"([^.!?]+[.!?]*)"#, in: trimmed).compactMap(\.first)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.contains(where: \.isLetter) }
        case nil:
            return []
        }
    }

    /// A sentence with nothing to end it would run into the next one when the reply is read back.
    func joined(_ units: [String]) -> String {
        if unit == .line { return units.joined(separator: "\n") }
        return units.map { noPunctuation || ".!?".contains($0.last ?? ".") ? $0 : $0 + "." }.joined(separator: " ")
    }

    private func wordsNeeded(at index: Int) -> Int? { wordsAt[index] ?? wordsEach }

    /// What's wrong with one sentence or line.
    func violations(ofUnit text: String, at index: Int) -> [String] {
        let name = "\((unit ?? .sentence).rawValue.capitalized) \(index + 1)"
        var found: [String] = []
        if let needed = wordsNeeded(at: index), Self.wordCount(text) != needed {
            found.append("\(name) has \(Self.wordCount(text)) words, it needs exactly \(needed).")
        }
        if let startLetter, text.first(where: \.isLetter).map({ Character($0.lowercased()) }) != startLetter {
            found.append("\(name) must start with the letter \(startLetter.uppercased()).")
        }
        found += bannedProblems(in: text)
        return found
    }

    private func bannedProblems(in text: String) -> [String] {
        var found: [String] = []
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        for letter in bannedLetters {
            let hits = words.filter { $0.lowercased().contains(letter) }
            if !hits.isEmpty { found.append("The letter \(letter) appears in: \(hits.prefix(6).joined(separator: ", ")).") }
        }
        for word in bannedWords where text.lowercased().contains(word.lowercased()) {
            found.append("The word \"\(word)\" isn't allowed.")
        }
        return found
    }

    /// Asks for one sentence or line that keeps every rule, in the short, concrete form small models follow.
    func request(at index: Int, firstWord: String?) -> String {
        let name = (unit ?? .sentence).rawValue
        var lines = ["Write one \(name)" + (wordsNeeded(at: index).map { " of exactly \($0) words" } ?? "") + "."]
        if let firstWord {
            lines.append("Its first word must be \"\(firstWord)\".")
        } else if let startLetter {
            lines.append("It must start with the letter \(startLetter.uppercased()).")
        }
        lines += bannedWords.map { "Don't use the word \"\($0)\"." }
        lines += bannedLetters.map { "Don't use any word with the letter \($0) in it." }
        lines.append("Reply with only the \(name).")
        return lines.joined(separator: " ")
    }

    /// Usable first words in a list from the model, in whatever layout it wrote the list.
    func firstWords(in reply: String) -> [String] {
        guard let startLetter else { return [] }
        var seen = Set<String>()
        return reply.split { !$0.isLetter }.map(String.init).filter { word in
            let plain = word.lowercased()
            return plain.first == startLetter && word.count > 2 && !bannedLetters.contains(where: plain.contains)
                && !bannedWords.contains { $0.lowercased() == plain } && seen.insert(plain).inserted
        }
        .map(\.capitalized)
    }

    /// The first sentence or line of a reply, without any numbering or quotes around it.
    func firstUnit(in reply: String) -> String? {
        let plain = reply.replacingOccurrences(of: #"(?m)^\s*(\d+[.)]|[-*•])\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\"", with: "")
        return units(of: tidied(plain)).first
    }

    /// Every rule the reply breaks, in words the model can act on. An empty list means it passes.
    func violations(of reply: String) -> [String] {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        var found: [String] = []
        if jsonOnly {
            if let data = text.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                found += jsonKeys.filter { object[$0] == nil }.map { "The key \"\($0)\" is missing." }
            } else {
                found.append("It isn't valid JSON.")
            }
        }
        if unit != nil {
            let units = units(of: text)
            if let count, units.count != count {
                found.append("It has \(units.count) \((unit ?? .sentence).rawValue)s, it needs exactly \(count).")
            }
            for (index, part) in units.enumerated() {
                found += violations(ofUnit: part, at: index).filter { !$0.hasPrefix("The ") }
            }
        }
        found += bannedProblems(in: text)
        if let totalWords, Self.wordCount(text) != totalWords {
            found.append("It has \(Self.wordCount(text)) words, it needs exactly \(totalWords).")
        }
        if let maxWords, Self.wordCount(text) > maxWords {
            found.append("It has \(Self.wordCount(text)) words, it can have at most \(maxWords).")
        }
        for word in requiredWords where !text.lowercased().contains(word.lowercased()) {
            found.append("The word \"\(word)\" is missing.")
        }
        if lowercase, text != text.lowercased() { found.append("It must be all lowercase.") }
        if uppercase, text != text.uppercased() { found.append("It must be all uppercase.") }
        if noPunctuation, text.contains(where: { $0.isPunctuation }) { found.append("It must have no punctuation.") }
        if let finalLabel {
            if !text.lowercased().contains(finalLabel.lowercased() + ":") {
                found.append("The last line must start with \(finalLabel):")
            } else if ModelTestSuite.finalAnswer(text).lowercased().hasSuffix(finalLabel.lowercased() + ":") {
                found.append("The last line has nothing after \(finalLabel):")
            }
        }
        return found
    }

    // MARK: Fixing what code can fix

    /// Fixes everything that needs no judgment, so the model is only asked about the rest. `cutting` also trims
    /// a reply with too many words down to the count, which v6 leaves to the model: a sentence cut short keeps
    /// the rule and stops being a sentence.
    func tidied(_ reply: String, cutting: Bool = true) -> String {
        var text = reply
        for echo in ["/no_think", "/think"] { text = text.replacingOccurrences(of: echo, with: "") }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        if jsonOnly, let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close {
            return String(text[open...close])
        }
        if hasShape {
            text = text.replacingOccurrences(of: "**", with: "")
            // A lead-in such as "Here is the poem:" isn't part of the reply.
            var lines = text.components(separatedBy: .newlines)
            if lines.count > 1, let first = lines.first?.trimmingCharacters(in: .whitespaces), first.hasSuffix(":") {
                lines.removeFirst()
                text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if lowercase { text = text.lowercased() }
        if uppercase { text = text.uppercased() }
        if noPunctuation { text = String(text.filter { !$0.isPunctuation }) }
        if let count, unit != nil {
            let parts = units(of: text)
            if parts.count > count { text = joined(Array(parts.prefix(count))) }
        }
        if cutting, let totalWords {
            let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
            if words.count > totalWords { text = words.prefix(totalWords).joined(separator: " ") }
        }
        if let finalLabel { text = withFinalLine(text, label: finalLabel) }
        return text
    }

    /// Clears a placeholder the model copied from the task, and adds the last line if it's missing.
    private func withFinalLine(_ text: String, label: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        guard let index = lines.lastIndex(where: { $0.lowercased().contains(label.lowercased() + ":") }) else {
            guard let last = lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return text }
            return text + "\n\(label): \(last.trimmingCharacters(in: .whitespaces))"
        }
        var line = lines[index]
        line = line.replacingOccurrences(of: #"</?[^<>]*answer[^<>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
        line = line.replacingOccurrences(of: #"<([^<>]*)>"#, with: "$1", options: .regularExpression)
        lines[index] = line
        return lines.joined(separator: "\n")
    }
}
