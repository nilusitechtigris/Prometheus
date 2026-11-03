import Foundation

/// The model test: short questions with one checkable answer each, so grading is automatic
/// and runs on any model. Every question asks for a bare answer to keep runs quick.
struct ModelTestQuestion: Identifiable {
    enum Check {
        /// The last number in the answer must equal this.
        case number(Double)
        /// One of these words must appear as a whole word (case-insensitive).
        case word([String])
        /// The answer must contain this text (case-insensitive).
        case contains(String)
        case custom((String) -> Bool)
    }

    let id: String
    let category: ModelTestCategory
    let title: String
    let prompt: String
    let expected: String
    let check: Check

    func grade(_ raw: String) -> Bool {
        let answer = ModelTestSuite.clean(raw)
        switch check {
        case .number(let value):
            guard let last = ModelTestSuite.numbers(in: answer).last else { return false }
            return abs(last - value) < 0.001
        case .word(let words):
            let lower = answer.lowercased()
            return words.contains { lower.range(of: "\\b\(NSRegularExpression.escapedPattern(for: $0.lowercased()))\\b", options: .regularExpression) != nil }
        case .contains(let text):
            return answer.lowercased().contains(text.lowercased())
        case .custom(let test):
            return test(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

enum ModelTestSuite {
    static let systemPrompt = "You are a helpful assistant. Follow the instructions in each question exactly, including the requested answer format."

    static let secretCode = "MAPLE-7342"

    static func questions(contextLength: Int) -> [ModelTestQuestion] {
        let bare = "Answer with only the number."
        return [
            // Math
            .init(id: "math-multiply", category: .math, title: "47 × 23",
                  prompt: "What is 47 × 23? \(bare)", expected: "1081", check: .number(1081)),
            .init(id: "math-discount", category: .math, title: "15% off $40",
                  prompt: "A jacket costs $40 and is discounted by 15%. What is the sale price in dollars? \(bare)",
                  expected: "34", check: .number(34)),
            .init(id: "math-sum", category: .math, title: "Sum of 1…50",
                  prompt: "What is the sum of all whole numbers from 1 to 50? \(bare)", expected: "1275", check: .number(1275)),
            .init(id: "math-equation", category: .math, title: "3x + 7 = 31",
                  prompt: "Solve for x: 3x + 7 = 31. \(bare)", expected: "8", check: .number(8)),

            // Reasoning
            .init(id: "reason-order", category: .reasoning, title: "Who is shortest",
                  prompt: "Tom is taller than Ana. Ana is taller than Lee. Who is the shortest? Answer with only the name.",
                  expected: "Lee", check: .word(["Lee"])),
            .init(id: "reason-machines", category: .reasoning, title: "Machines and widgets",
                  prompt: "If 5 machines take 5 minutes to make 5 widgets, how many minutes do 100 machines take to make 100 widgets? \(bare)",
                  expected: "5", check: .number(5)),
            .init(id: "reason-apples", category: .reasoning, title: "Apples",
                  prompt: "I have 3 apples. I eat 1, buy 4 more, then give half of what I have to a friend. How many apples do I have now? \(bare)",
                  expected: "3", check: .number(3)),
            .init(id: "reason-odd-one", category: .reasoning, title: "Odd one out",
                  prompt: "Which word does not belong: apple, banana, carrot, cherry? Answer with only the word.",
                  expected: "carrot", check: .word(["carrot"])),

            // Knowledge
            .init(id: "know-gold", category: .knowledge, title: "Symbol for gold",
                  prompt: "What is the chemical symbol for gold? Answer with only the symbol.", expected: "Au", check: .word(["Au"])),
            .init(id: "know-red-planet", category: .knowledge, title: "The Red Planet",
                  prompt: "Which planet is known as the Red Planet? Answer with one word.", expected: "Mars", check: .word(["Mars"])),
            .init(id: "know-austen", category: .knowledge, title: "Pride and Prejudice",
                  prompt: "Who wrote the novel Pride and Prejudice? Answer with only the author's name.",
                  expected: "Jane Austen", check: .word(["Austen"])),
            .init(id: "know-canada", category: .knowledge, title: "Capital of Canada",
                  prompt: "What is the capital city of Canada? Answer with one word.", expected: "Ottawa", check: .word(["Ottawa"])),

            // Instruction following
            .init(id: "follow-three-words", category: .instructions, title: "Exactly three words",
                  prompt: "Describe the sky in exactly three words, all lowercase, with no punctuation.",
                  expected: "3 lowercase words, no punctuation",
                  check: .custom { text in
                      let words = text.split(whereSeparator: \.isWhitespace)
                      return words.count == 3 && text == text.lowercased()
                          && text.allSatisfy { $0.isLetter || $0.isWhitespace }
                  }),
            .init(id: "follow-json", category: .instructions, title: "JSON only",
                  prompt: "Return only a JSON object with two keys: \"name\" (a string) and \"age\" (a number). No code fences and no other text.",
                  expected: "{\"name\": …, \"age\": …}",
                  check: .custom { text in
                      guard let data = text.data(using: .utf8),
                            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
                      return object["name"] is String && object["age"] is NSNumber && object.count == 2
                  }),
            .init(id: "follow-list", category: .instructions, title: "Numbered list of 4",
                  prompt: "List exactly 4 fruits as a numbered list, one per line, with no other text.",
                  expected: "4 numbered lines",
                  check: .custom { text in
                      let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                      return lines.count == 4 && lines.allSatisfy { $0.range(of: #"^\d+[.)]\s+\S"#, options: .regularExpression) != nil }
                  }),
            .init(id: "follow-reverse", category: .instructions, title: "Spell backwards",
                  prompt: "Write the word \"banana\" backwards. Answer with only the result.", expected: "ananab", check: .word(["ananab"])),

            // Coding
            .init(id: "code-python-sum", category: .coding, title: "Python output",
                  prompt: "What does this Python code print? Answer with only the output.\n\nprint(sum(x * x for x in range(4)))",
                  expected: "14", check: .number(14)),
            .init(id: "code-js-map", category: .coding, title: "JavaScript output",
                  prompt: "What does this JavaScript print? Answer with only the output.\n\nconsole.log([1, 2, 3].map(n => n * 2).join('-'))",
                  expected: "2-4-6", check: .contains("2-4-6")),
            .init(id: "code-set", category: .coding, title: "Unique letters",
                  prompt: "In Python, what is len(set(\"mississippi\"))? \(bare)", expected: "4", check: .number(4)),

            // Long context
            .init(id: "long-needle", category: .longContext, title: "Find the secret code",
                  prompt: haystack(contextLength: contextLength), expected: secretCode, check: .contains(secretCode)),
        ]
    }

    /// Filler notes with one secret sentence about 60 % of the way in, sized to about half the
    /// context window (at most ~3,000 tokens) so the question still leaves room to answer.
    static func haystack(contextLength: Int) -> String {
        let targetTokens = min(3_000, contextLength / 2)
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
        let count = max(targetTokens / 19, 10)
        let secretAt = count * 6 / 10
        var notes: [String] = []
        for i in 0..<count {
            notes.append("Note \(i + 1): \(sentences[i % sentences.count])")
            if i == secretAt { notes.append("Note \(i + 1)b: The secret code is \(secretCode).") }
        }
        return "Read the notes below, then answer the question at the end.\n\n" + notes.joined(separator: "\n")
            + "\n\nQuestion: What is the secret code mentioned in the notes? Answer with only the code."
    }

    /// Strips Markdown emphasis and code marks so "**Au**" grades like "Au".
    static func clean(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for mark in ["**", "__", "`"] { s = s.replacingOccurrences(of: mark, with: "") }
        return s
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
