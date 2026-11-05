import Foundation

/// One of v5's three agents. They're all the same loaded model taking turns, so three of them use no more
/// memory than one. A personality and a temperature are all that set them apart.
struct CouncilAgent: Identifiable, Equatable {
    let name: String
    let temperature: Double
    /// What the model reads.
    let personality: String
    /// What the user reads.
    let summary: String

    var id: String { name }

    /// In speaking order. The first holds the lowest temperature, so it's the safest hand for the final reply.
    static let all = [
        CouncilAgent(name: "Solver", temperature: 0.2,
                     personality: "You are methodical. You work in small steps and rely only on what you can show.",
                     summary: "Works step by step"),
        CouncilAgent(name: "Skeptic", temperature: 0.5,
                     personality: "You are hard to convince. You look for the flaw, test answers on a small case and say plainly what is wrong.",
                     summary: "Looks for the flaw"),
        CouncilAgent(name: "Explorer", temperature: 0.8,
                     personality: "You are curious. You come at the task from another direction and question what the others take for granted.",
                     summary: "Tries another route"),
    ]
}

/// The file v5's agents share. Code lays it out and does all the reading and writing: an agent is handed the
/// part that fits its context, and its reply goes in under its name. So a small model needs no file tools,
/// and a bad reply can't damage the file.
struct SharedNotes {
    struct Entry {
        let agent: CouncilAgent
        var note: String
        /// What the agent's reply comes down to. Nil for a draft, which is all note.
        var answer: String?
        /// What code found wrong with it, for the others to read.
        var problems: [String] = []

        func text(for reader: CouncilAgent? = nil, limit: Int = .max) -> String {
            var parts = ["### \(agent.name)\(agent == reader ? " (you)" : "")"]
            if !note.isEmpty { parts.append(SharedNotes.cut(note, to: limit)) }
            if let answer { parts.append("Answer: \(answer)") }
            parts += problems.map { "Code check: \($0)" }
            return parts.joined(separator: "\n\n")
        }
    }

    /// Where the agents stand after a round.
    struct Standing: Equatable {
        /// The answer at least two agents hold.
        var answer: String?
        var backers: [CouncilAgent] = []
        var total = 0

        var isUnanimous: Bool { backers.count == CouncilAgent.all.count }

        var summary: String? {
            guard let answer else { return nil }
            return isUnanimous ? "All three agree on \(answer)" : "\(backers.count) of \(total) agree on \(answer)"
        }
    }

    var model: String
    var task: String
    var earlier = ""
    var evidence: [String] = []
    var rounds: [[Entry]] = []
    var standing: String?
    var reply: String?

    // MARK: Writing the file

    /// The whole file.
    var markdown: String {
        let agents = CouncilAgent.all.map { "\($0.name) \($0.temperature)" }.joined(separator: ", ")
        var parts = ["# Shared notes", "\(model) · temperature: \(agents)"]
        parts += preparedSections(evidenceLimit: .max)
        for (index, entries) in rounds.enumerated() {
            parts.append("## Round \(index + 1)")
            parts += entries.map { $0.text() }
        }
        if let standing { parts.append("## Where the group stands\n\n\(standing)") }
        if let reply, !reply.isEmpty { parts.append("## Final reply\n\n\(reply)") }
        return parts.joined(separator: "\n\n") + "\n"
    }

    /// What code puts in the file before any agent writes.
    private func preparedSections(evidenceLimit: Int) -> [String] {
        var parts = ["## Task\n\n\(task)"]
        if !earlier.isEmpty { parts.append("## Chat so far\n\n\(earlier)") }
        if !evidence.isEmpty {
            parts.append("## What the tools found\n\n\(Self.cut(evidence.joined(separator: "\n\n"), to: evidenceLimit))")
        }
        return parts
    }

    // MARK: Reading the file

    /// What an agent reads on its turn, in about `characters`. In round 1 that's only what code prepared, so
    /// three agents give three separate answers rather than copying whoever went first. After that it's
    /// everything that fits, and the oldest rounds are the ones to go.
    func reading(for agent: CouncilAgent, round: Int, characters: Int) -> String {
        let fixed = task.count + earlier.count
        let prepared = preparedSections(evidenceLimit: max((characters - fixed) * 2 / 3, 200)).joined(separator: "\n\n")
        guard round > 1 else { return prepared }

        let room = characters - prepared.count
        // Enough for two full rounds, and always something of the last one.
        let noteLimit = max(min(room / 6, 600), 120)
        var kept: [String] = [], used = 0, leftOut = false
        for (index, entries) in rounds.enumerated().reversed() where !entries.isEmpty {
            let text = "## Round \(index + 1)\n\n" + entries.map { $0.text(for: agent, limit: noteLimit) }.joined(separator: "\n\n")
            if used + text.count > room, !kept.isEmpty {
                leftOut = true
                break
            }
            kept.insert(text, at: 0)
            used += text.count
        }
        if leftOut { kept.insert("(Older rounds are left out to fit.)", at: 0) }
        return ([prepared] + kept).joined(separator: "\n\n")
    }

    /// Shortens text, and closes any outside source it cuts through so what follows doesn't read as part of it.
    static func cut(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let kept = String(text.prefix(limit))
        if let open = kept.range(of: "<untrusted", options: .backwards)?.lowerBound,
           kept.range(of: "</untrusted>", options: .backwards).map({ $0.lowerBound < open }) ?? true {
            return kept + "…\n</untrusted>"
        }
        return kept + "…"
    }

    // MARK: Reading replies

    /// The form an agent fills in, so that it gives a reason. A small model that has been thinking tends to
    /// reply with the answer alone, which gives the others nothing to discuss.
    static func form(label: String) -> String { "\(reasonLabel): <your reason, in one or two sentences>\n\(label): <your answer>" }

    private static let reasonLabel = "Why"
    /// Fewer words than this isn't a reason.
    private static let reasonWords = 4

    /// Splits a reply into what it says to the others and the answer on its last line.
    static func parse(_ reply: String, label: String) -> (note: String, answer: String?) {
        // Small models copy the form's lines as well as filling them in.
        let blanks = form(label: label).lowercased().components(separatedBy: .newlines)
        let lines = ModelTestSuite.clean(reply).components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !blanks.contains($0.lowercased()) }
        let marker = label + ":"
        for (index, line) in lines.enumerated().reversed() {
            guard let found = line.range(of: marker, options: .caseInsensitive) else { continue }
            var rest = String(line[found.upperBound...])
            if rest.trimmingCharacters(in: .whitespaces).isEmpty, index + 1 < lines.count { rest = lines[index + 1] }
            // Small models copy the form's placeholder, or its brackets.
            let answer = rest.replacingOccurrences(of: "<your answer>", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "<>. ").union(.whitespaces))
            var note = Array(lines[..<index])
            let before = line[..<found.lowerBound].trimmingCharacters(in: .whitespaces)
            if !before.isEmpty { note.append(before) }
            return (note.joined(separator: "\n"), answer.isEmpty ? nil : answer)
        }
        return (lines.joined(separator: "\n"), lines.last)
    }

    /// Small models copy whoever they read last, and one bare "Answer: ta" can undo another agent's right
    /// answer. So an agent can only change its answer by saying why. Otherwise the old one stands.
    static func holdingFirm(_ entry: Entry, after earlier: Entry?) -> Entry {
        guard let old = earlier?.answer, let new = entry.answer, key(of: old) != key(of: new) else { return entry }
        let reason = entry.note.replacingOccurrences(of: reasonLabel + ":", with: "", options: .caseInsensitive)
        guard reason.split(whereSeparator: \.isWhitespace).count < reasonWords else { return entry }
        var firm = entry
        firm.answer = old
        firm.problems.append("It changed to \(new) without a reason, so its answer stays \(old).")
        return firm
    }

    /// What an answer comes down to, for telling whether two agents agree. A lone number counts whatever is
    /// around it, so "$12.50" and "12.5" agree. Text too long to compare gets nil.
    static func key(of answer: String) -> String? {
        let text = ModelTestSuite.clean(answer).lowercased()
        guard !text.isEmpty, text.count <= 80 else { return nil }
        let numbers = ModelTestSuite.numbers(in: text)
        if numbers.count == 1 { return "\(numbers[0])" }
        let words = text.split { !$0.isLetter && !$0.isNumber }.filter { !["the", "a", "an"].contains($0) }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    static func standing(of entries: [Entry]) -> Standing {
        var groups: [String: [Entry]] = [:]
        for entry in entries {
            if let key = entry.answer.flatMap(key(of:)) { groups[key, default: []].append(entry) }
        }
        guard let largest = groups.values.max(by: { $0.count < $1.count }), largest.count >= 2 else {
            return Standing(total: entries.count)
        }
        return Standing(answer: largest[0].answer, backers: largest.map(\.agent), total: entries.count)
    }

    // MARK: On disk

    /// Kept beside the chats. A chat's notes are named after the reply and go when it does; a test's are named
    /// after the question, so the next run replaces them.
    static var folder: URL { ConversationStore.directory.appendingPathComponent("Shared Notes", isDirectory: true) }

    static func fileURL(named name: String) -> URL { folder.appendingPathComponent(name + ".md") }

    func save(as name: String) {
        let url = Self.fileURL(named: name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    static func discard(_ names: [String]) {
        for name in names { try? FileManager.default.removeItem(at: fileURL(named: name)) }
    }
}
