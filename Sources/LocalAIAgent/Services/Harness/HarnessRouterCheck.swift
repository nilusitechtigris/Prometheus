#if DEBUG
import Foundation

/// The router checked by itself: what the rules decide, what each answer a model might give to its one question
/// leads to, and what switching a route off does. The model here is a script, so nothing needs one.
extension HarnessRouter {
    static func selfCheck() async -> [String] {
        var lines: [String] = []
        func expect(_ name: String, _ ok: Bool) { lines.append("\(ok ? "PASS" : "FAIL") \(name)") }

        /// A model that gives these replies in turn, and counts how often it was asked.
        final class Script {
            var replies: [String]
            var asked: [String] = []
            init(_ replies: [String]) { self.replies = replies }
            func reply(_ question: String) -> String {
                asked.append(question)
                return replies.isEmpty ? "" : replies.removeFirst()
            }
        }
        func route(_ prompt: String, _ replies: [String] = [], policy: HarnessPolicy = .current) async -> (routing: HarnessRouting, asked: [String]) {
            let script = Script(replies)
            let routing = await HarnessRouter.route(HarnessTask(prompt: prompt), policy: policy) { script.reply($0) }
            return (routing, script.asked)
        }

        // Layer 2: rules alone, with no call to the model.
        let longText = (1...40).map { "Entry \($0): the lease for lot \($0 + 10) was signed by clerk number \($0 % 7) before two witnesses." }.joined(separator: "\n")
        let ruled: [(String, HarnessRoute, TestLab.TaskKind)] = [
            ("What is 48271 × 9377?", .exact, .calculation),
            ("What day of the week was 14 March 1879?", .exact, .calculation),
            ("How many times does the letter \"r\" appear in \"strawberry raspberry\"?", .exact, .calculation),
            ("How much do 3 boxes of 12 eggs weigh if each egg is 50 grams?", .program, .calculation),
            ("A shop sells pens at 3 dollars each. Mia buys 14 pens and pays with a 50 dollar note. How much change does she get?", .program, .calculation),
            ("What does this print?\n\ntotal = 0\nfor n in range(1, 7):\n    total += n\nprint(total)", .program, .code),
            ("Write a function that returns the largest of three numbers.", .code, .other),
            ("Write a python function to count the vowels in a string. Your code should pass these tests:\n\nassert count_vowels(\"banana\") == 3\nassert count_vowels(\"sky\") == 0", .code, .other),
            ("Implement the Stack class with push, pop and peek in JavaScript.", .code, .other),
            ("Complete this function.\n\ndef mean(values):\n", .code, .other),
            ("Write Python code that prints the first ten squares, like print(1), print(4) and so on.", .code, .other),
            ("Write a script to rename the files in a folder by date.", .code, .other),
            ("Write a 30-second radio script in exactly 3 sentences.", .rules, .writing),
            ("What does this print?\n\ndef complete(n):\n    return n * 2\n\nprint(complete(4))", .program, .code),
            (longText + "\n\nThe clerks want to build a program for onboarding. Who signed the lease for lot 22?", .document, .document),
            ("Which one is better?", .direct, .other),
            ("When was it built?", .direct, .other),
            ("What is the capital of Australia?", .lookup, .fact),
            ("What year did the first crewed moon landing happen?", .lookup, .fact),
            ("Who proved the Mordell conjecture?", .lookup, .fact),
            (longText + "\n\nWho signed the lease for lot 22?", .document, .document),
            ("Write exactly 2 sentences about rain. Each sentence must start with the letter S.", .rules, .writing),
            ("Ann is taller than Ben. Ben is taller than Cy. Dee is shorter than Cy. Who is the shortest?", .direct, .other),
            ("Tell me something nice about autumn.", .direct, .other),
            ("Hello!", .direct, .other),
            ("Can you help me word an apology to my neighbour about the noise?", .direct, .other),
        ]
        for (prompt, wanted, kind) in ruled {
            let got = await route(prompt)
            expect("\(wanted.rawValue), no call: \(prompt.prefix(60).replacingOccurrences(of: "\n", with: " ")) -> \(got.routing.step)",
                   got.routing.route == wanted && got.routing.kind == kind && got.asked.isEmpty && got.routing.calls == 0)
        }
        for prompt in ["Write a short story about a programmer who loved one function.", "Write exactly 2 sentences about rain.",
                       "What does this print?\n\nprint(sum(range(4)))", "Explain what a class method is.", "Make me a list of five script ideas for a podcast.",
                       "Create a 12-week training program for a first marathon.", "Write a class reunion invitation.", "Define method acting in two sentences.",
                       "What does this print?\n\nimport sys\ndef finish(n):\n    sys.stdout.write(str(n))\nfinish(3)"] {
            expect("not a request for code: \(prompt.prefix(50).replacingOccurrences(of: "\n", with: " "))", !HarnessRouter.asksForCode(prompt))
        }
        expect("every route has a name and a line on what it does", HarnessRoute.allCases.allSatisfy { !$0.title.isEmpty && $0.summary.count > 30 })

        // Layer 3: the one question, for what the rules leave over. It has a number and no rule fits.
        let leftover = "I have 3 apples and my sister gives me twice as many again, so what do I end up with"
        expect("the rules say nothing about the leftover", HarnessRouter.byRules(HarnessTask(prompt: leftover)) == nil && HarnessRouter.hasSomethingToCompute(leftover))
        let yes = await route(leftover, ["A", "B"])
        expect("two answers that agree send it to a program: \(yes.routing.step)", yes.routing.route == .program && yes.routing.kind == .calculation && yes.routing.calls == 2 && yes.asked.count == 2)
        expect("the second question has the options the other way round",
               yes.asked.count == 2 && yes.asked[0].contains("A. A short computer program") && yes.asked[1].contains("B. A short computer program") && yes.asked[0] != yes.asked[1])
        expect("the question ends by asking for one letter", yes.asked.first?.hasSuffix("Reply with one letter, A or B.") == true)
        let no = await route(leftover, ["B"])
        expect("a no the first time is final, after one call: \(no.routing.step)", no.routing.route == .direct && no.asked.count == 1 && no.routing.calls == 1)
        let first = await route(leftover, ["A", "A"])
        expect("a model that always picks the first option gets Direct: \(first.routing.step)", first.routing.route == .direct && first.routing.calls == 2)
        let echo = await route(leftover, ["A. A short computer program could work out the exact answer.", "A. It needs knowledge, judgement or writing, not a calculation."])
        expect("a model that repeats the first option gets Direct", echo.routing.route == .direct)
        let solved = await route(leftover, ["You end up with 9 apples."])
        expect("a model that answers the task instead gets Direct: \(solved.routing.step)", solved.routing.route == .direct && solved.routing.calls == 1)
        let empty = await route(leftover, [""])
        expect("no reply at all gets Direct", empty.routing.route == .direct)
        let both = await route(leftover, ["Both could be true."])
        expect("\"Both\" isn't a B", both.routing.route == .direct && both.routing.reason.contains("wasn't clear"))
        let wordy = await route(leftover, ["Answer: A", "(b) I think."])
        expect("a letter with a few words round it still counts: \(wordy.routing.step)", wordy.routing.route == .program)
        for (reply, letter) in [("A", "A"), ("b", "B"), ("  B.", "B"), ("**A**", "A"), ("Answer: B", "B"), ("(A)", "A"), ("A) the first", "A")] as [(String, Character)] {
            expect("reads \"\(reply)\" as \(letter)", HarnessRouter.letter(in: reply) == letter)
        }
        for (reply, letter) in [("The answer is A", "A"), ("Option B", "B"), ("\n  \nB", "B"), ("<think>Is it A? Let me see.</think>\nB", "B"), ("The correct answer is: (a)", "A")] as [(String, Character)] {
            expect("reads \"\(reply.replacingOccurrences(of: "\n", with: " "))\" as \(letter)", HarnessRouter.letter(in: reply) == letter)
        }
        for reply in ["", "Because it has numbers", "Apples", "The answer is 9", "Both", "AB", "An answer needs thought", "<think>A</think>"] {
            expect("reads no letter in \"\(reply)\"", HarnessRouter.letter(in: reply) == nil)
        }
        let words = "Thirteen friends each bring fifteen cookies to the party, so what do they have altogether"
        expect("numbers written as words are something to compute from", HarnessRouter.hasSomethingToCompute(words) && HarnessRouter.byRules(HarnessTask(prompt: words)) == nil)
        let spelled = await route(words, ["A", "B"])
        expect("so the model is asked about them: \(spelled.routing.step)", spelled.routing.route == .program && spelled.asked.count == 2)
        let long = String(repeating: "The ledger has 12 lines and each line has 4 numbers. ", count: 60) + "so what is all of it worth to me"
        let cut = HarnessRouter.question(for: HarnessTask(prompt: long), programFirst: true)
        expect("a long message is cut for the question (\(cut.count) characters)", cut.count < 900)

        // The policy: a route that's off is answered directly, and asking can be switched off.
        var policy = HarnessPolicy()
        policy.off = [.lookup, .rules]
        let offLookup = await route("Who proved the Mordell conjecture?", policy: policy)
        expect("a route that's switched off is Direct: \(offLookup.routing.step)", offLookup.routing.route == .direct && offLookup.routing.reason.contains("switched off"))
        let stillOn = await route("What is 48271 × 9377?", policy: policy)
        expect("the others still run", stillOn.routing.route == .exact)
        policy = HarnessPolicy()
        policy.asksModel = false
        let silent = await route(leftover, ["A", "B"], policy: policy)
        expect("with asking switched off the leftover is Direct, with no call", silent.routing.route == .direct && silent.asked.isEmpty)
        policy = HarnessPolicy()
        policy.off = [.program]
        let offProgram = await route(leftover, ["A", "B"], policy: policy)
        expect("a model's yes can't switch on a route that's off", offProgram.routing.route == .direct && offProgram.routing.calls == 2)
        expect("the policy starts with every route on", HarnessPolicy.current.off.isEmpty && HarnessPolicy.current.asksModel && HarnessPolicy.revision >= 1)

        // Layer 1 in Dev: the word rule Dev already had.
        expect("Dev: harness off is Direct", HarnessRouter.route(dev: DevJob(request: "Make a todo list web app"), harnessOn: false).route == .direct)
        expect("Dev: a question is Direct", HarnessRouter.route(dev: DevJob(request: "What does main.py do?"), harnessOn: true).route == .direct)
        expect("Dev: a change is Build", HarnessRouter.route(dev: DevJob(request: "Make a todo list web app"), harnessOn: true).route == .build)
        let fix = DevJob(request: "fix it", failure: DevFailure(file: "main.py", line: 1, kind: "ZeroDivisionError", message: "division by zero", output: ""))
        expect("Dev: a failed run is Build", HarnessRouter.route(dev: fix, harnessOn: true) == HarnessRouting(route: .build, kind: .other, reason: "a failed run to fix"))
        return lines
    }
}
#endif
