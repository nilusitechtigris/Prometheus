import Foundation

/// What code can say about two replies to the same message, one from the plain model and one from the
/// harness. It only states what it has checked. Where code has nothing to go on it says so, because a
/// green tick it couldn't back up would be the same confident guess the harness is there to catch.
struct CompareVerdict: Equatable {
    enum Kind: Equatable {
        /// Code worked out a value and the plain reply never states it.
        case plainLacksResult
        /// Code worked out a value and both replies state it.
        case bothStateResult
        /// The message set rules code can check, such as a word count, and the replies differ on them.
        case rules(plainBroken: Int, harnessBroken: Int)
        /// The harness read pages. Code can't tell which reply is right.
        case readSources(pages: Int)
        /// Nothing for code to check.
        case nothingToCheck
        /// The plain model gave no reply to compare.
        case noPlainReply
    }

    let kind: Kind
    /// One plain sentence for under the two replies.
    let text: String
    /// True when code found the harness reply better on something it checked.
    var harnessAhead: Bool {
        switch kind {
        case .plainLacksResult: return true
        case .rules(let plain, let harness): return harness < plain
        default: return false
        }
    }

    /// `question` is the message both replied to. `result` is the exact value a tool produced for the harness
    /// reply, if one did, and `steps` is what the harness logged.
    static func judge(question: String, plain: String, harness: String, result: String?, steps: [String]) -> CompareVerdict {
        let plainText = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plainText.isEmpty else {
            return CompareVerdict(kind: .noPlainReply, text: "The plain model gave no reply to compare.")
        }
        if let result, !result.isEmpty {
            let shown = result.count > 60 ? String(result.prefix(60)) + "…" : result
            if HarnessText.mentions(result, in: plainText, label: nil) {
                return CompareVerdict(kind: .bothStateResult, text: "Code worked out \(shown). Both replies state it.")
            }
            return CompareVerdict(kind: .plainLacksResult, text: "Code worked out \(shown). The plain model's reply doesn't state it.")
        }
        let rules = TextRules(task: question)
        if rules.hasShape {
            // Each reply is judged as it was written. The harness's own tidying is part of its reply already, and
            // doing it to the plain reply would hide the very slips this is here to show.
            let plainBroken = rules.violations(of: plainText.replacingOccurrences(of: "**", with: "")).count
            let harnessBroken = rules.violations(of: harness.trimmingCharacters(in: .whitespacesAndNewlines)).count
            let text: String
            switch (plainBroken, harnessBroken) {
            case (0, 0): text = "Code checked the rules in your message. Both replies keep them."
            case (_, 0): text = "Code checked the rules in your message. The plain reply breaks \(count(plainBroken)), the harness reply keeps them all."
            case (0, _): text = "Code checked the rules in your message. The plain reply keeps them all, the harness reply breaks \(count(harnessBroken))."
            default: text = "Code checked the rules in your message. The plain reply breaks \(count(plainBroken)) and the harness reply breaks \(count(harnessBroken))."
            }
            return CompareVerdict(kind: .rules(plainBroken: plainBroken, harnessBroken: harnessBroken), text: text)
        }
        let pages = steps.filter { $0.hasPrefix("Opened") && !$0.hasSuffix(HarnessTools.failedMark) }.count
        if pages > 0 || steps.contains(where: { $0.hasPrefix("Searched") && !$0.hasSuffix(HarnessTools.failedMark) }) {
            let read = pages == 0 ? "searched the web" : "read \(pages) page\(pages == 1 ? "" : "s")"
            return CompareVerdict(kind: .readSources(pages: pages),
                                  text: "The harness \(read) for its reply. Code can't tell which reply is right, so check the sources in its steps.")
        }
        return CompareVerdict(kind: .nothingToCheck, text: "There was nothing here for code to check, so these are two tries at the same message.")
    }

    private static func count(_ rules: Int) -> String { rules == 1 ? "one" : "\(rules)" }

    #if DEBUG
    static func selfCheck() -> [String] {
        var lines: [String] = []
        func expect(_ name: String, _ ok: Bool) { lines.append("\(ok ? "PASS" : "FAIL") \(name)") }
        let sum = judge(question: "What is 48271 × 9377?", plain: "48271 × 9377 = 452,688,567, confirmed.",
                        harness: "48271 × 9377 = 452637167", result: "452637167", steps: ["Calculated: 48271 × 9377"])
        expect("a wrong sum: the plain reply doesn't state what code worked out", sum.kind == .plainLacksResult && sum.harnessAhead)
        let right = judge(question: "What is 12 × 12?", plain: "It's **144**.", harness: "12 × 12 = 144", result: "144", steps: [])
        expect("a right sum: both state it, and nobody is called ahead", right.kind == .bothStateResult && !right.harnessAhead)
        let grouped = judge(question: "What is 48271 × 9377?", plain: "That is 452,637,167.", harness: "452637167", result: "452637167", steps: [])
        expect("a number written with commas still counts as stated", grouped.kind == .bothStateResult)
        let rambling = judge(question: "How many r's?", plain: "It appears 10 times. Wait, 3 + 3 + 3 = 9? No: 10.", harness: "9", result: "9", steps: [])
        expect("a reply that mentions the value in passing isn't called wrong: \(rambling.text)", rambling.kind == .bothStateResult && !rambling.harnessAhead)

        let words = "Write one sentence about the sea with exactly five words."
        let rule = judge(question: words, plain: "The sea is wide, deep, cold and blue today.", harness: "The sea is very deep.", result: nil, steps: [])
        expect("a word count: \(rule.text)", rule.kind == .rules(plainBroken: 1, harnessBroken: 0) && rule.harnessAhead)
        let bothKeep = judge(question: words, plain: "Waves roll onto the sand.", harness: "The sea is very deep.", result: nil, steps: [])
        expect("both keep the rule", bothKeep.kind == .rules(plainBroken: 0, harnessBroken: 0) && !bothKeep.harnessAhead)
        let harnessWorse = judge(question: words, plain: "Waves roll onto the sand.", harness: "The sea is very, very deep today.", result: nil, steps: [])
        expect("the harness can lose, and the words say so: \(harnessWorse.text)", harnessWorse.kind == .rules(plainBroken: 0, harnessBroken: 1) && !harnessWorse.harnessAhead)

        let fact = judge(question: "Who proved the Mordell conjecture?", plain: "Gerd Faltings, 1983.", harness: "Gerd Faltings in 1986.",
                         result: nil, steps: ["Searched: Mordell conjecture proof year", "Opened: https://en.wikipedia.org/wiki/Gerd_Faltings"])
        expect("a looked-up fact gets no winner: \(fact.text)", fact.kind == .readSources(pages: 1) && !fact.harnessAhead)
        let refused = judge(question: "Who proved the Mordell conjecture?", plain: "Faltings.", harness: "Faltings.",
                            result: nil, steps: [WebTools.declinedNote])
        expect("a lookup that wasn't allowed isn't called a source", refused.kind == .nothingToCheck)
        let chat = judge(question: "Explain how transformers work.", plain: "They use attention.", harness: "They use attention layers.", result: nil, steps: [])
        expect("ordinary chat: nothing to check, said plainly", chat.kind == .nothingToCheck && !chat.harnessAhead)
        expect("no plain reply", judge(question: "x", plain: "  ", harness: "y", result: "1", steps: []).kind == .noPlainReply)
        return lines
    }
    #endif
}
