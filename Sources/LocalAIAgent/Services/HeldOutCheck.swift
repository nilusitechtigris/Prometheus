#if DEBUG
import Foundation

/// The held-out loader and graders, checked without a model. It counts the held-out questions and makes sure
/// each can be graded, and never prints one.
enum HeldOutCheck {
    /// Grades replies made outside the app, such as a reference model's: a file of {"id": "reply"} for one set.
    /// For the held-out set it reports totals only, so reading the report shows nobody a question or a reply.
    static func grade(_ replies: [String: String], set: String) async -> [String] {
        let questions = HeldOut.questions(set)
        var lines: [String] = [], detail: [String] = []
        var right = 0, answered = 0
        for source in HeldOut.sources {
            var sourceRight = 0, sourceTotal = 0
            for question in questions where question.id.hasPrefix(source.prefix) {
                sourceTotal += 1
                guard let reply = replies[question.id] else { continue }
                answered += 1
                let passed = await question.passes(reply)
                if passed { sourceRight += 1 }
                detail.append("\(passed ? "right" : "wrong") \(question.id)")
            }
            right += sourceRight
            lines.append("\(source.name): \(sourceRight) of \(sourceTotal)")
        }
        lines.insert("\(set): \(right) of \(questions.count) right, \(answered) answered", at: 0)
        return set == HeldOut.current ? lines : lines + detail
    }

    static func run() async -> [String] {
        var lines: [String] = []
        func expect(_ name: String, _ ok: Bool) { lines.append("\(ok ? "PASS" : "FAIL") \(name)") }

        let held = HeldOut.load(HeldOut.current), practice = HeldOut.load(HeldOut.practice)
        expect("the held-out file holds 120 questions (\(held.count))", held.count == 120)
        expect("the practice file holds 60 (\(practice.count))", practice.count == 60)
        expect("the two share no question", Set(held.map(\.id)).isDisjoint(with: practice.map(\.id)))
        expect("every question in both can be asked and graded", HeldOut.questions(HeldOut.current).count == 120 && HeldOut.questions(HeldOut.practice).count == 60)
        let kinds = Set((held + practice).flatMap { $0.check.instructions ?? [] }.map(\.id))
        expect("every instruction kind in the files has a check (\(kinds.count))", kinds.isSubset(of: IFEvalChecks.supported))
        let byCategory = Dictionary(grouping: HeldOut.questions(HeldOut.current), by: \.category).mapValues(\.count)
        expect("a third each of math, instructions and coding: \(byCategory.map { "\($0.key.rawValue) \($0.value)" }.sorted())",
               byCategory[.math] == 40 && byCategory[.instructions] == 40 && byCategory[.coding] == 40)

        // Numbers.
        for (answer, gold, right) in [("Answer: 42", "42", true), ("Answer: 42.0", "42", true), ("Answer: $1,250", "1250", true),
                                      ("Answer: 1,250.00", "1250", true), ("Answer: 25%", "25", true),
                                      ("Answer: 41.6", "42", false), ("Answer: 43", "42", false), ("Answer: 4.333", "4.33", true),
                                      ("Answer: 4.3", "4.33", false), ("Answer: 4.34", "4.33", false), ("Answer: 12 + 30 = 42", "42", true),
                                      ("Answer: 42 apples in 3 boxes", "42", true), ("Answer: none", "42", false), ("Answer: -7", "-7", true),
                                      // A gold written out by a computer has every decimal. Two are enough.
                                      ("Answer: 66.67", "66.66666666666667", true), ("Answer: 66.666", "66.66666666666667", true),
                                      ("Answer: 66.7", "66.66666666666667", false), ("Answer: 67", "66.66666666666667", false),
                                      ("Answer: \u{2212}7", "-7", true), ("Answer: 7", "-7", false), ("Answer: 3/4", "0.75", true),
                                      ("Answer: .5", "0.5", true), ("Area = 5 m2\nAnswer: 5 m2", "5", true), ("Answer: 12 cm3", "12", true),
                                      // Without a line marked as the answer only the last number counts.
                                      ("She buys 5 apples at $2, which is $10", "5", false), ("She buys 5 apples at $2, which is $10", "10", true),
                                      ("The total is 18.", "18", true), ("**Answer:** 18 dollars", "18", true)] {
            expect("number: \"\(answer.replacingOccurrences(of: "\n", with: " / "))\" for \(gold) is \(right ? "right" : "wrong")", HeldOutGrader.number(answer, gold: gold) == right)
        }

        // Code against its tests, in the sandbox, with a practice question.
        if await HeldOutGrader.canRunCode() {
            let tests = ["assert max_Abs_Diff((2,1,5,3)) == 4", "assert max_Abs_Diff((9,3,2,5,1)) == 8", "assert max_Abs_Diff((3,2,1)) == 2"]
            let right = "def max_Abs_Diff(arr):\n    return max(arr) - min(arr)\n"
            let wrong = "def max_Abs_Diff(arr):\n    return arr[0] - arr[-1]\n"
            func fenced(_ code: String) -> String { "```python\n\(code)```" }
            func passes(_ reply: String, imports: [String] = [], _ tests: [String] = tests) async -> Bool {
                await HeldOutGrader.passesTests(reply, imports: imports, tests: tests)
            }
            let cases: [(String, String, Bool)] = [
                ("code that passes its tests is right", "Here it is:\n\(fenced(right))\nIt takes the largest minus the smallest.", true),
                ("code that fails one is wrong", fenced(wrong), false),
                ("code that never ends is wrong", fenced("def max_Abs_Diff(arr):\n    while True:\n        pass\n"), false),
                ("a reply with no code is wrong", "I would subtract the smallest from the largest.", false),
                ("bare code with no fence is run", right, true),
                // A wrong program must not pass by ending before the tests run.
                ("wrong code that exits cleanly is still wrong", fenced(wrong + "import sys\nsys.exit(0)\n"), false),
                ("wrong code that runs its own unittest is still wrong", fenced(wrong + "import unittest\nif __name__ == \"__main__\":\n    unittest.main()\n"), false),
                ("wrong code that quits the process is still wrong", fenced(wrong + "import os\nos._exit(0)\n"), false),
                // A right function must not fail for what else the reply does.
                ("right code that exits at the end is right", fenced(right + "import sys\nsys.exit(0)\n"), true),
                ("right code with a main block is right", fenced(right + "if __name__ == \"__main__\":\n    print(max_Abs_Diff((1, 2)))\n    raise SystemExit(1)\n"), true),
                ("right code that asks for input after the function is right", fenced(right + "print(max_Abs_Diff(tuple(map(int, input().split()))))\n"), true),
                ("right code that prints a lot is right", fenced(right + "for n in range(5000):\n    print('line', n)\n"), true),
                ("a newer type hint doesn't fail on an older Python", fenced("def max_Abs_Diff(arr: tuple[int, ...] | list[int]) -> int | None:\n    return max(arr) - min(arr)\n"), true),
                ("an example block after the function is left out", "\(fenced(right))\nUse it like this:\n\(fenced("print(max_Abs_Diff((1, 2)))\nassert max_Abs_Diff((1, 2)) == 5\n"))", true),
                ("a test block of the model's own after the function is left out", "\(fenced(right))\n\(fenced("def test():\n    assert max_Abs_Diff((1, 2)) == 5\ntest()\n"))", true),
                ("a helper in an earlier block comes along", "\(fenced("def spread(low, high):\n    return high - low\n"))\nThen:\n\(fenced("def max_Abs_Diff(arr):\n    return spread(min(arr), max(arr))\n"))", true),
                ("an earlier block that crashes doesn't stop the later one", "\(fenced("import nothing_like_this\ndef broken():\n    pass\n"))\n\(fenced(right))", true),
                ("a block inside a list keeps working", "1. The function:\n\n   ```python\n   def max_Abs_Diff(arr):\n       return max(arr) - min(arr)\n   ```\n", true),
                ("Windows line endings work", fenced(right).replacingOccurrences(of: "\n", with: "\r\n"), true),
                ("a function under another name is wrong", fenced(right.replacingOccurrences(of: "max_Abs_Diff", with: "max_diff")), false),
            ]
            for (name, reply, expected) in cases {
                let got = await passes(reply)
                expect(name, got == expected)
            }
            let needsImport = await passes(fenced("def root(n):\n    return math.sqrt(n)\n"), imports: ["import math"], ["assert root(9) == 3"])
            expect("a task's own imports reach the code", needsImport)
            expect("the names the tests call are found", HeldOutGrader.calledNames(in: tests).contains("max_Abs_Diff"))
            let version = await HeldOutGrader.pythonVersion()
            expect("the Python version is recorded: \(version ?? "none")", version?.first?.isNumber == true)
        } else {
            lines.append("SKIP code tests: Python isn't available in the sandbox on this Mac")
        }

        // Each instruction kind, followed and not.
        func instruction(_ id: String, _ kwargs: [String: HeldOut.Value] = [:]) -> HeldOut.Instruction { HeldOut.Instruction(id: id, kwargs: kwargs) }
        let cases: [(HeldOut.Instruction, String, String)] = [
            (instruction("keywords:existence", ["keywords": .list(["sea", "salt"])]), "The Sea is full of salt.", "The sea is wide."),
            (instruction("keywords:forbidden_words", ["forbidden_words": .list(["water"])]), "Waterfalls roar.", "The water is cold."),
            (instruction("keywords:frequency", ["keyword": .text("blue"), "frequency": .number(2), "relation": .text("at least")]), "Blue sky, blue sea.", "A blue sky."),
            (instruction("keywords:frequency", ["keyword": .text("blue"), "frequency": .number(2), "relation": .text("less than")]), "A blue sky.", "Blue sky, blue sea."),
            (instruction("keywords:letter_frequency", ["letter": .text("Z"), "let_frequency": .number(2), "let_relation": .text("at least")]), "Zebras buzz.", "A zebra."),
            (instruction("length_constraints:number_paragraphs", ["num_paragraphs": .number(2)]), "One.\n***\nTwo.", "One.\n***\nTwo.\n***\nThree."),
            (instruction("length_constraints:number_words", ["num_words": .number(4), "relation": .text("at least")]), "One two three four.", "One two three."),
            (instruction("length_constraints:nth_paragraph_first_word", ["num_paragraphs": .number(2), "nth_paragraph": .number(2), "first_word": .text("Then")]),
             "First part.\n\n\"Then, the rest.", "First part.\n\nAnd the rest."),
            (instruction("detectable_content:postscript", ["postscript_marker": .text("P.S.")]), "Body.\nP.S. One more thing.", "Body.\nPS one more thing."),
            (instruction("detectable_format:constrained_response"), "I think: My answer is maybe.", "Maybe."),
            (instruction("detectable_format:json_format"), "```json\n{\"a\": [1, 2]}\n```", "Here you go: {\"a\": 1}"),
            (instruction("detectable_format:number_bullet_lists", ["num_bullets": .number(2)]), "* one\n- two", "* one\n* two\n* three"),
            (instruction("detectable_format:number_highlighted_sections", ["num_highlights": .number(2)]), "*one* and **two**", "*one* only"),
            (instruction("detectable_format:title"), "<<A Title>>\nBody", "<< >>\nBody"),
            (instruction("combination:two_responses"), "First reply.\n******\nSecond reply.", "Same.\n******\nSame."),
            (instruction("combination:repeat_prompt", ["prompt_to_repeat": .text("Write a poem")]), "write a poem\nRoses are red.", "Roses are red."),
            (instruction("startend:end_checker", ["end_phrase": .text("Is there anything else?")]), "Done. Is there anything else?\"", "Is there anything else? No."),
            (instruction("startend:quotation"), "\"All of it.\"", "\"Only the start."),
            (instruction("punctuation:no_comma"), "No commas here.", "One, two."),
        ]
        for (rule, follows, breaks) in cases {
            expect("\(rule.id): followed and broken", IFEvalChecks.followed(rule, in: follows) && !IFEvalChecks.followed(rule, in: breaks))
        }
        expect("an instruction kind with no check counts as broken", !IFEvalChecks.followed(instruction("language:response_language"), in: "anything"))

        // How a run on these questions is saved and told apart from the app's own tests.
        expect("each set's size is read once (\(HeldOut.size()), \(HeldOut.size(HeldOut.practice)))", HeldOut.size() == 120 && HeldOut.size(HeldOut.practice) == 60 && HeldOut.size("other") == 0)
        expect("both files are whole, and a set this build doesn't have isn't", HeldOut.isWhole(HeldOut.current) && HeldOut.isWhole(HeldOut.practice) && !HeldOut.isWhole("other"))
        expect("each size asks its own file", HarnessTestSize.heldOut.questionSet == HeldOut.current && HarnessTestSize.practice.questionSet == HeldOut.practice
               && HarnessTestSize.max.questionSet == nil && HarnessTestSize.normal.questionSet == nil)
        let questions = HeldOut.questions()
        expect("every question counts the same", questions.allSatisfy(\.unweighted))
        func made(_ version: HarnessVersion?, set: String? = HeldOut.current, quick: Bool = false, right: Int = 0, total: Int = 120,
                  group: UUID? = nil, index: Int? = nil, at seconds: Double = 0) -> ModelTestResult {
            var run = ModelTestResult(suiteVersion: set == nil ? ModelTestSuite.version : HeldOut.suiteVersion(set ?? "") ?? 101, harness: version == nil ? nil : true,
                                      harnessVersion: version.map(SavedHarnessVersion.init), model: "m", displayName: "M", quant: "Q4", quantProvider: "p",
                                      backend: "Ollama", thinking: false, contextLength: 8_192)
            run.questionSet = set
            run.quick = quick ? true : nil
            run.repeatGroup = group
            run.repeatIndex = index
            run.date = Date(timeIntervalSince1970: 1_800_000_000 + seconds)
            run.items = (0..<total).map { ModelTestItemResult(id: "q-\($0)", category: .math, title: "Q \($0)", expected: "", answer: "", passed: $0 < right, seconds: 1) }
            return run
        }
        let single = made(.loop, right: 90)
        expect("a held-out run is its own size", single.size == .heldOut && made(nil, set: nil, quick: true).size == .normal && made(nil, set: nil).size == .max)
        expect("a practice run is never taken for a held-out one", made(.loop, set: HeldOut.practice).size == .practice && made(.loop, set: HeldOut.practice).isCurrentSuite)
        expect("its points are its right answers: \(single.points) of \(single.maxPoints)", single.points == 90 && single.maxPoints == 120 && single.score == 75)
        expect("it counts as the current test, and another set's run doesn't", single.isCurrentSuite && !made(.loop, set: "heldout-v0").isCurrentSuite
               && made(nil, set: nil).isCurrentSuite)
        let coder = JSONEncoder(), decoder = JSONDecoder()
        let back = (try? coder.encode(made(.evidence, right: 3, group: UUID(), index: 2))).flatMap { try? decoder.decode(ModelTestResult.self, from: $0) }
        expect("the set and the repeat number survive saving", back?.questionSet == HeldOut.current && back?.repeatIndex == 2 && back?.repeatGroup != nil && back?.version == .evidence)
        let old = #"{"id":"6F0C9E5E-27B6-4B0B-9B1F-0C8A30E0F001","suiteVersion":3,"date":0,"model":"m","displayName":"M","quant":"Q4","quantProvider":"p","backend":"Ollama","thinking":false,"contextLength":8192,"items":[],"duration":1}"#
        let earlier = try? decoder.decode(ModelTestResult.self, from: Data(old.utf8))
        expect("a run saved before any of this still loads, as a Max run", earlier?.size == .max && earlier?.repeatGroup == nil)
        // An older build reads these runs and saves them back without the fields it doesn't know.
        var stripped = made(.loop, set: HeldOut.practice, right: 3, group: UUID(), index: 1)
        stripped.questionSet = nil
        stripped.repeatGroup = nil
        stripped.repeatIndex = nil
        var strippedHeld = single
        strippedHeld.questionSet = nil
        expect("a run an older build saved back is still told apart by its number", stripped.size == .practice && stripped.isCurrentSuite
               && strippedHeld.size == .heldOut && strippedHeld.isCurrentSuite && stripped.askedSet != strippedHeld.askedSet)
        var failed = made(nil, right: 50)
        failed.items[70].error = "The framework stopped."
        expect("a run with questions that got no reply says how many", failed.errorCount == 1 && single.errorCount == 0)

        // Whether a gap is more than luck.
        func near(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 1e-9 } ?? false }
        expect("nothing flipped: nothing to test", FlipTest.chance(gained: 0, lost: 0) == nil)
        expect("one flip tells nothing", near(FlipTest.chance(gained: 1, lost: 0), 1))
        expect("ten flips one way: 2 in 1024", near(FlipTest.chance(gained: 10, lost: 0), 2.0 / 1024))
        expect("eight against two: 0.109", near(FlipTest.chance(gained: 8, lost: 2), 112.0 / 1024))
        expect("an even split is all luck", near(FlipTest.chance(gained: 5, lost: 5), 1) && near(FlipTest.chance(gained: 2, lost: 8), 112.0 / 1024))
        expect("a clear gap says how rare: \(FlipTest.sentence(gained: 10, lost: 0))", FlipTest.sentence(gained: 10, lost: 0).hasSuffix("about 1 time in 512."))
        expect("a gap that could be luck says so: \(FlipTest.sentence(gained: 8, lost: 2))", FlipTest.sentence(gained: 8, lost: 2).contains("about 11 times in 100")
               && FlipTest.sentence(gained: 8, lost: 2).contains("doesn't show a difference"))
        expect("one question is written as one", FlipTest.sentence(gained: 1, lost: 3).hasPrefix("1 question went from wrong to right and 3 questions from right to wrong."))
        expect("nothing changed says so", FlipTest.sentence(gained: 0, lost: 0) == "No question changed between the two runs.")

        // Repeats.
        let group = UUID()
        let runs = [made(.loop, right: 84, group: group, index: 2, at: 50), made(nil, right: 72, group: group, index: 1, at: 0),
                    made(.loop, right: 90, group: group, index: 1, at: 10), made(nil, right: 78, group: group, index: 2, at: 40),
                    made(nil, right: 75, group: group, index: 3, at: 80), made(.loop, right: 87, group: group, index: 3, at: 90)]
        let rows = TestLab.repeatRows(runs)
        expect("repeats come out plain model first, each score under its round: \(rows.map { row in "\(row.title) \(row.rounds.map { Int(row.scores[$0] ?? 0) })" })",
               rows.count == 2 && rows[0].version == nil && rows[0].scores == [1: 60, 2: 65, 3: 62.5] && rows[1].scores == [1: 75, 2: 70, 3: 72.5])
        expect("mean and range", rows.count == 2 && rows[0].mean == 62.5 && rows[0].low == 60 && rows[0].high == 65 && rows[1].mean == 72.5)
        // The lab names the version. The standard edition only says "Harness".
        let named = HarnessVersion.loop.runTitle()
        expect("higher in every round says so: \(rows.count == 2 ? rows[1].verdict(against: rows[0]) ?? "" : "")",
               rows.count == 2 && rows[1].verdict(against: rows[0]) == "\(named) scored higher than the plain model in all 3 rounds, by 10.0 points on average.")
        let off = RepeatRow(version: nil, scores: [1: 60, 2: 65, 3: 62.5])
        let mixed = RepeatRow(version: .loop, scores: [1: 64, 2: 61, 3: 67]).verdict(against: off) ?? ""
        expect("rounds that go both ways aren't called a gain: \(mixed)", mixed.contains("higher than the plain model in 2 of 3 rounds and lower in 1") && mixed.hasSuffix("the rounds don't agree."))
        expect("lower in every round says so", RepeatRow(version: .council, scores: [1: 50, 2: 55]).verdict(against: off)?.contains("scored lower than the plain model in all 2 rounds, by 10.0") == true)
        // Stopped in round 2: two plain scores and one harness score.
        let stopped = TestLab.repeatRows(runs.filter { !($0.usesHarness && ($0.repeatIndex ?? 0) > 1) && ($0.repeatIndex ?? 0) < 3 })
        expect("a set stopped part way gives no verdict", stopped.count == 2 && stopped[1].scores == [1: 75] && stopped[1].verdict(against: stopped[0]) == nil)
        // The middle round's harness run deleted: round 3 must stay round 3.
        let gap = TestLab.repeatRows(runs.filter { !($0.usesHarness && $0.repeatIndex == 2) })
        expect("a deleted run leaves the later rounds where they were", gap.count == 2 && gap[1].scores == [1: 75, 3: 72.5]
               && gap[1].verdict(against: gap[0]) == "\(named) scored higher than the plain model in all 2 rounds, by 12.5 points on average.")
        expect("one run alone is not a set of repeats", TestLab.repeatRows([made(.loop, right: 90, group: group, index: 1)]).isEmpty)
        func join(_ versions: [HarnessVersion], repeats: Int = 3, size: HarnessTestSize = .heldOut, context: Int = 8_192, from saved: [ModelTestResult]? = nil) -> UUID? {
            TestLab.repeatGroupToJoin(in: saved ?? runs, model: "m", size: size, thinking: false, context: context, repeats: repeats, versions: versions)
        }
        expect("another version joins a set that has a plain run for every round", join([.evidence]) == group)
        expect("a version the set already has starts a new one", join([.loop]) == nil && join([.evidence, .loop]) == nil)
        expect("more rounds than the set has plain runs for starts a new one", join([.evidence], repeats: 5) == nil)
        expect("another size or context starts a new one", join([.evidence], size: .practice) == nil && join([.evidence], context: 4_096) == nil)
        expect("a set missing a plain run isn't joined", join([.evidence], from: runs.filter { $0.usesHarness || $0.repeatIndex != 2 }) == nil)
        let spoiled = runs.map { run -> ModelTestResult in
            var run = run
            if !run.usesHarness, run.repeatIndex == 3 { run.items[0].error = "The framework stopped." }
            return run
        }
        expect("a set whose plain run lost questions to an error isn't joined", join([.evidence], from: spoiled) == nil)
        return lines
    }
}
#endif
