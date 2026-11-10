import Foundation

/// Questions plain code answers exactly, with no model and no program for the model to write: counting
/// letters and words in a quoted text, the weekday of a date, and the days between two dates. Small models get
/// these wrong in ways that look right, and a lookup can't help, so v6 settles them here.
///
/// Each one only fires when the whole question is about it and nothing else. A shortcut that fires on the wrong
/// question overrides a reply the model might have got right, and says code checked it. So anything left over
/// in the question that code doesn't understand ("10 days after", "inclusive") makes it return nil, and the
/// question goes the usual way.
enum ExactTools {
    struct Answer: Equatable {
        /// What was worked out, for the log and for the model.
        let what: String
        let value: String
    }

    static func solve(_ question: String) -> Answer? {
        let text = question.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'").replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count < 260, !text.contains("\n\n") else { return nil }
        return letterCount(text) ?? wordCount(text) ?? weekday(text) ?? daysBetween(text)
    }

    // MARK: Text

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let match = matches(pattern, in: text).first else { return nil }
        return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }

    /// The text a question quotes: its last quoted stretch. A single quote only opens one after a space, so the
    /// apostrophe in "r's" or "don't" isn't taken for one, and a stretch that is just the letter being counted
    /// isn't the text.
    private static func quoted(in text: String, besides letter: Character? = nil) -> String? {
        var found: [(location: Int, inside: String)] = []
        for pattern in ["\"([^\"]+)\"", #"(?:^|(?<=[\s(]))'(.+?)'(?=$|[\s?.!,;:)])"#] {
            for match in matches(pattern, in: text) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                found.append((match.range.location, String(text[range])))
            }
        }
        let real = found.sorted { $0.location < $1.location }.map(\.inside).filter { inside in
            let trimmed = inside.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return false }
            if let letter, trimmed.count == 1, trimmed.lowercased().first == letter { return false }
            return true
        }
        return real.last
    }

    private static func letterCount(_ text: String) -> Answer? {
        let lead = #"^\W*(?:and\s+|so\s+|now\s+|ok\s+|okay\s+)?"#
        // "How many times does the letter r appear in 'strawberry'?" The word "letter" is what makes it this question.
        let asked = lead + #"(?:how many|count the(?: number of)?)\s+(?:times\s+)?(?:does\s+|do\s+|is\s+)?(?:the\s+)?letters?\s+["']?([a-z])["']?(?:'s|s)?\s+(?:appears?|occurs?|shows? up|comes? up|is used|is there|are there)?"#
        // "How many r's are in strawberry?" Without the word "letter" the s has to be there: "how many m in km" is about units.
        let short = lead + #"(?:how many|count the(?: number of)?)\s+["']?([a-z])["']?(?:'s|s)\s+(?:are|is|appear|occur)?\s*(?:there\s+)?in\b"#
        guard let letter = (groups(asked, in: text) ?? groups(short, in: text))?.first?.lowercased().first else { return nil }
        let target: String
        if let inside = quoted(in: text, besides: letter) {
            target = inside
        } else if let word = (groups(#"\bin\s+the\s+(?:word|name)\s+([a-z]+)\s*[?.!]*$"#, in: text) ?? groups(#"\bin\s+([a-z]+)\s*[?.!]*$"#, in: text))?.first,
                  !word.isEmpty, !["the", "this", "that", "it", "total", "all", "there", "english", "here"].contains(word.lowercased()) {
            // Unquoted, so only one word at the very end counts as the text. "In the Bible" is a different question.
            target = word
        } else {
            return nil
        }
        let count = target.lowercased().filter { $0 == letter }.count
        return Answer(what: "how many times the letter \(letter) appears in \"\(target)\"", value: "\(count)")
    }

    /// Only when the question calls it a sentence or a phrase. "How many words are in 'War and Peace'?" may mean
    /// the book.
    private static func wordCount(_ text: String) -> Answer? {
        guard groups(#"^\W*how many words\s+(?:are|is)\s+(?:there\s+)?in\s+(?:the|this)\s+(?:sentence|phrase|text|string|line|title)\b"#, in: text) != nil,
              let inside = quoted(in: text) else { return nil }
        let count = inside.split(whereSeparator: \.isWhitespace).count
        return Answer(what: "how many words are in \"\(inside)\"", value: "\(count)")
    }

    // MARK: Dates

    private static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
                                 "november", "december"]
    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private static func month(_ name: String) -> Int? {
        let lower = name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return months.firstIndex { $0 == lower || (lower.count >= 3 && $0.hasPrefix(lower)) }.map { $0 + 1 }
    }

    /// A real day in the calendar in use today. Before 1753 countries disagreed on the date, Britain among the
    /// last, so those are left to the model and a lookup.
    private static func date(day: Int, month: Int, year: Int) -> Date? {
        guard (1753...9999).contains(year) else { return nil }
        let parts = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: parts) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == year && back.month == month && back.day == day ? date : nil
    }

    /// Every date written out in the text, in the order they appear, with what was written.
    static func dates(in text: String) -> [(date: Date, written: String)] {
        let name = #"(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\.?"#
        let patterns: [(String, ([String]) -> (Int, Int, Int)?)] = [
            (#"\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?"# + name + #",?\s+(\d{4})\b"#, { g in Int(g[0]).flatMap { d in month(g[1]).flatMap { m in Int(g[2]).map { (d, m, $0) } } } }),
            (#"\b"# + name + #"\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b"#, { g in month(g[0]).flatMap { m in Int(g[1]).flatMap { d in Int(g[2]).map { (d, m, $0) } } } }),
            (#"\b(\d{4})-(\d{2})-(\d{2})\b"#, { g in Int(g[0]).flatMap { y in Int(g[1]).flatMap { m in Int(g[2]).map { ($0, m, y) } } } }),
        ]
        var found: [(location: Int, date: Date, written: String)] = []
        for (pattern, read) in patterns {
            for match in matches(pattern, in: text) {
                let parts = (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
                guard let (day, month, year) = read(parts), let date = date(day: day, month: month, year: year),
                      let whole = Range(match.range, in: text), !found.contains(where: { $0.location == match.range.location }) else { continue }
                found.append((match.range.location, date, String(text[whole])))
            }
        }
        return found.sorted { $0.location < $1.location }.map { ($0.date, $0.written) }
    }

    /// True when, with the dates taken out, the question holds nothing but these words. Anything else, such as
    /// "10 days after" or "inclusive", changes what is being asked.
    private static func isOnly(_ text: String, dates: [String], words: Set<String>) -> Bool {
        var rest = text
        for written in dates { rest = rest.replacingOccurrences(of: written, with: " ") }
        return rest.lowercased().split { !$0.isLetter && !$0.isNumber }.allSatisfy { words.contains(String($0)) }
    }

    private static func weekday(_ text: String) -> Answer? {
        guard groups(#"\b(?:what|which)\s+day\s+of\s+the\s+week\b|\bwhat\s+weekday\b"#, in: text) != nil else { return nil }
        let found = dates(in: text)
        guard found.count == 1, let day = found.first,
              isOnly(text, dates: [day.written], words: ["what", "which", "on", "day", "of", "the", "week", "weekday", "was", "is", "will", "did", "does", "be",
                                                         "fall", "falls", "fell", "it", "date", "that", "a", "tell", "me", "please", "were", "would", "have", "been"]) else { return nil }
        let name = weekdays[calendar.component(.weekday, from: day.date) - 1]
        return Answer(what: "the day of the week of \(day.written)", value: name)
    }

    private static func daysBetween(_ text: String) -> Answer? {
        guard groups(#"\bhow\s+many\s+days\b.*\b(?:between|from)\b"#, in: text) != nil else { return nil }
        let found = dates(in: text)
        guard found.count == 2,
              isOnly(text, dates: found.map(\.written), words: ["how", "many", "days", "are", "there", "is", "it", "between", "from", "to", "and", "until", "the",
                                                                "dates", "of", "were", "was", "passed", "elapsed", "did", "pass", "have", "please", "tell", "me"]),
              let days = calendar.dateComponents([.day], from: found[0].date, to: found[1].date).day else { return nil }
        return Answer(what: "the days from \(found[0].written) to \(found[1].written)", value: "\(abs(days))")
    }
}
