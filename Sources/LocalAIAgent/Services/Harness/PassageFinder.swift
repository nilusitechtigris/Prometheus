import Foundation

/// Finds the few passages of a long text that matter to a question, so a small model with a small
/// context window reads those rather than thousands of words. Plain word matching, so it costs no
/// model time and always gives the same result.
enum PassageFinder {
    struct Selection {
        var passages: [String]
        /// Share of the question's keywords that the passages contain.
        var coverage: Double
    }

    private static let stopWords: Set<String> = [
        "a", "about", "after", "again", "all", "also", "am", "an", "and", "any", "are", "as", "at", "be", "been", "before", "being",
        "both", "but", "by", "can", "could", "did", "do", "does", "each", "every", "few", "for", "from", "had", "has", "have", "he",
        "her", "here", "him", "his", "how", "i", "if", "in", "into", "is", "it", "its", "just", "many", "may", "me", "might", "more",
        "most", "much", "must", "my", "no", "not", "now", "of", "on", "once", "one", "only", "or", "other", "our", "out", "over", "own",
        "same", "she", "should", "so", "some", "such", "than", "that", "the", "their", "them", "then", "there", "these", "they", "this",
        "those", "to", "too", "under", "until", "up", "very", "was", "we", "were", "what", "when", "where", "which", "while", "who",
        "whom", "whose", "why", "will", "with", "would", "you", "your",
    ]

    private static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    private static func stem(_ word: String) -> String {
        var word = word
        if word.hasSuffix("'s") || word.hasSuffix("’s") { word.removeLast(2) }
        if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") { word.removeLast() }
        return word
    }

    private static func tokens(in text: String) -> [String] {
        folded(text).split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }.map { stem(String($0)) }
    }

    /// The words of a text worth matching on, in order, without repeats.
    static func keywords(in text: String) -> [String] {
        var seen = Set<String>()
        return tokens(in: text).filter { !stopWords.contains($0) && $0.count > 1 && seen.insert($0).inserted }
    }

    /// The text cut into lines, with long lines cut again at sentence ends.
    private static func passages(of text: String) -> [String] {
        let maxCharacters = 420
        var passages: [String] = []
        for line in text.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
            if line.count <= maxCharacters {
                passages.append(line)
                continue
            }
            var current = ""
            for sentence in line.replacingOccurrences(of: #"(?<=[.!?])\s+"#, with: "\n", options: .regularExpression).split(separator: "\n") {
                if current.count + sentence.count > maxCharacters, !current.isEmpty {
                    passages.append(current)
                    current = ""
                }
                current += (current.isEmpty ? "" : " ") + sentence
            }
            if !current.isEmpty { passages.append(String(current.prefix(maxCharacters * 2))) }
        }
        return passages
    }

    private struct Index {
        let passages: [String]
        let words: [Set<String>]
        let frequency: [String: Int]

        init(_ text: String) {
            passages = PassageFinder.passages(of: text)
            words = passages.map { Set(PassageFinder.tokens(in: $0)) }
            var frequency: [String: Int] = [:]
            for set in words { for word in set { frequency[word, default: 0] += 1 } }
            self.frequency = frequency
        }

        /// Rare words count for more, so a name outweighs a word on every line.
        func weight(_ word: String) -> Double {
            log(1 + Double(passages.count) / Double(max(frequency[word] ?? 0, 1)))
        }

        func ranked(for keywords: [String], skipping used: Set<Int>) -> [(index: Int, score: Double)] {
            passages.indices.filter { !used.contains($0) }
                .map { index in (index, keywords.filter { words[index].contains($0) }.map(weight).reduce(0, +)) }
                .filter { $0.1 > 0 }
                .sorted { ($0.score, $1.index) > ($1.score, $0.index) }
        }
    }

    /// The best passages for a question, in their original order. `closeness` is how near a passage's
    /// score must be to the top one for it to stay in.
    static func best(in text: String, for question: String, maxCharacters: Int, closeness: Double = 0.6) -> Selection {
        let index = Index(text)
        let wanted = keywords(in: question)
        let ranked = index.ranked(for: wanted, skipping: [])
        guard let top = ranked.first else { return Selection(passages: [], coverage: 0) }
        var chosen: [Int] = [], used = 0
        for candidate in ranked where candidate.score >= top.score * closeness {
            if used + index.passages[candidate.index].count > maxCharacters, !chosen.isEmpty { break }
            chosen.append(candidate.index)
            used += index.passages[candidate.index].count
        }
        return selection(chosen.sorted(), in: index, wanted: wanted)
    }

    /// Like `best`, then follows what those passages point at: a name that's new to the question, or a
    /// reference such as "log 12". That's how an answer gets found when each note only leads to the next.
    /// Passages stay in the order they were reached, which is the order of the reasoning.
    static func chain(in text: String, for question: String, maxCharacters: Int, closeness: Double = 0.8, maxHops: Int = 3) -> Selection {
        let index = Index(text)
        let wanted = keywords(in: question)
        var chosen: [Int] = [], used = 0
        var search = wanted, known = Set(wanted)

        for _ in 0...maxHops {
            let ranked = index.ranked(for: search, skipping: Set(chosen))
            guard let top = ranked.first else { break }
            var reached: [Int] = []
            for candidate in ranked where candidate.score >= top.score * closeness {
                if used + index.passages[candidate.index].count > maxCharacters, !chosen.isEmpty { break }
                reached.append(candidate.index)
                used += index.passages[candidate.index].count
            }
            guard !reached.isEmpty else { break }
            chosen += reached
            search = pointers(in: reached.map { index.passages[$0] }, index: index, known: &known)
            if search.isEmpty { break }
        }
        return selection(chosen, in: index, wanted: wanted)
    }

    /// Words in these passages that lead somewhere new: names found on few lines, and numbered references.
    private static func pointers(in passages: [String], index: Index, known: inout Set<String>) -> [String] {
        let rareLimit = max(3, index.passages.count / 20)
        var found: [String] = []
        for passage in passages {
            let words = passage.split { !$0.isLetter && !$0.isNumber }.map(String.init)
            for (position, word) in words.enumerated() {
                // A number after a word is a reference, unless it's this line's own label.
                if word.allSatisfy(\.isNumber), position > 1, let name = words[safe: position - 1], name.allSatisfy(\.isLetter) {
                    let reference = stem(folded(name)) + " " + word
                    if known.insert(reference).inserted { found.append(word) }
                    continue
                }
                guard let first = word.first, first.isUppercase, word.count > 2, word.allSatisfy(\.isLetter) else { continue }
                let key = stem(folded(word))
                guard !stopWords.contains(key), (index.frequency[key] ?? 0) <= rareLimit, known.insert(key).inserted else { continue }
                found.append(key)
            }
        }
        return found
    }

    private static func selection(_ chosen: [Int], in index: Index, wanted: [String]) -> Selection {
        let reached = chosen.reduce(into: Set<String>()) { $0.formUnion(index.words[$1]) }
        let covered = wanted.filter { reached.contains($0) }.count
        return Selection(passages: chosen.map { index.passages[$0] }, coverage: wanted.isEmpty ? 0 : Double(covered) / Double(wanted.count))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
