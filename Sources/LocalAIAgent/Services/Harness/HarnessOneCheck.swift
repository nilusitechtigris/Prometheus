#if DEBUG
import Foundation

/// The one harness from start to finish against a scripted model, canned pages and the real sandbox, so this needs
/// Python and no model or internet. It checks what each route asks of the model, what it does with each answer it
/// might get, and that the reply the plain model gave is only ever replaced for a reason code can state.
extension TestLab {
    static func oneHarnessCheck() async -> [String] {
        var lines: [String] = []
        func expect(_ name: String, _ ok: Bool) { lines.append("\(ok ? "PASS" : "FAIL") \(name)") }
        let stop = StreamEvent.finished(BackendStats(stopReason: "stop"))

        func text(_ request: ChatRequest) -> String { request.messages.last?.content ?? "" }
        func isPlain(_ request: ChatRequest, _ prompt: String) -> Bool {
            request.messages.count == 2 && request.messages[0].content == ModelTestSuite.systemPrompt && request.messages[1].content == prompt
        }
        func same(_ one: ChatRequest, _ two: ChatRequest) -> Bool {
            one.model == two.model && one.temperature == two.temperature && one.contextLength == two.contextLength && one.maxTokens == two.maxTokens
                && one.think == two.think && one.tools.map(\.name) == two.tools.map(\.name)
                && one.messages.map(\.role) == two.messages.map(\.role) && one.messages.map(\.content) == two.messages.map(\.content)
        }
        func setup(_ backend: LLMBackend, think: Bool? = nil) -> TestSetup {
            TestSetup(model: LocalModel(id: "scripted"), backend: backend, context: 8_192, think: think, supportsTools: false)
        }
        /// A task through the one harness, as the Harness Test runs it.
        func run(_ prompt: String, think: Bool? = nil, policy: HarnessPolicy? = nil, _ script: @escaping (ChatRequest) -> String) async -> (requests: [ChatRequest], reply: Reply) {
            let backend = ScriptedBackend { request in [.content(script(request)), stop] }
            let made = setup(backend, think: think)
            guard let policy else {
                let reply = await harnessReply(.unified, prompt: prompt, setup: made, maxTokens: 512)
                return (backend.requests, reply)
            }
            var total = Reply()
            await runOne(prompt: prompt, setup: made, policy: policy, total: &total) { plan in
                plan.direct ? await plainReply(plan.task, setup: made, maxTokens: 512)
                            : await converse([ChatTurn(role: "user", content: plan.task + plan.addendum)], setup: made, maxTokens: plan.maxTokens ?? 512, useTools: false)
            }
            return (backend.requests, total)
        }
        /// The same task with the harness off.
        func off(_ prompt: String, think: Bool? = nil, _ reply: String) async -> (request: ChatRequest?, answer: String) {
            let backend = ScriptedBackend { _ in [.content(reply), stop] }
            let got = await plainReply(prompt, setup: setup(backend, think: think), maxTokens: 512)
            return (backend.requests.first, got.answer)
        }
        func python(_ code: String) -> String { "```python\n\(code)\n```" }
        func checked(_ reply: Reply) -> String { reply.toolLog.last ?? "" }

        // MARK: Direct is the harness off

        let chat = "Tell me something nice about autumn."
        let odd = "  **Autumn** is lovely.\n\nHere is why:  \n- the light\n"
        let direct = await run(chat) { _ in odd }
        let plain = await off(chat, odd)
        expect("Direct asks once", direct.requests.count == 1)
        expect("Direct sends the request the harness-off path sends, word for word", direct.requests.first.map { one in plain.request.map { same(one, $0) } ?? false } ?? false)
        expect("Direct hands back the reply untouched, spaces and stars and all", direct.reply.answer == plain.answer && direct.reply.answer == odd)
        expect("its steps are one line, the route: \(direct.reply.toolLog)", direct.reply.toolLog.count == 1 && direct.reply.toolLog[0].hasPrefix("Route: direct") && direct.reply.route == .direct)
        let thinking = await run(chat, think: true) { _ in odd }
        let plainThinking = await off(chat, think: true, odd)
        expect("with Think on too", thinking.requests.count == 1 && thinking.requests.first.map { one in plainThinking.request.map { same(one, $0) } ?? false } ?? false && thinking.requests.first?.think == true)

        // MARK: Exact

        let sum = await run("What is 48271 × 9377?") { _ in "That comes to 452,637,167." }
        expect("a sum goes to code, not to a program: \(sum.reply.toolLog)", sum.reply.route == .exact && sum.reply.result == "452637167"
                   && !sum.requests.contains { text($0).contains("Write a real Python program") } && checked(sum.reply) == "Checked: code worked this out")
        let wrongSum = await run("What is 48271 × 9377?") { _ in "That comes to 452,000,000." }
        expect("a reply that words the sum wrongly is overruled: \(wrongSum.reply.answer.suffix(30))", wrongSum.reply.answer.contains("452637167"))

        // MARK: Program

        let eggs = "How much do 3 boxes of 12 eggs weigh if each egg is 50 grams?"
        func eggModel(own: String, first: String, second: String, reworded: String = "They weigh 1800 grams.") -> (ChatRequest) -> String {
            { request in
                if isPlain(request, eggs) { return own }
                if text(request).contains("different way") { return second }
                if text(request).contains("Write a real Python program") { return first }
                if text(request).contains("The exact result is:") { return reworded }
                return "?"
            }
        }
        let printing = { (value: String) in python("def solve():\n    return \(value)\n\nprint(solve())") }
        let agree = await run(eggs, eggModel(own: "3 × 12 × 50 = 1800 grams.", first: printing("3 * 12 * 50"), second: "?"))
        expect("a word problem starts with the plain model's own answer", agree.reply.route == .program && agree.requests.first.map { isPlain($0, eggs) } == true)
        expect("a program that agrees ends it there, in two calls (\(agree.requests.count))", agree.requests.count == 2 && agree.reply.answer == "3 × 12 × 50 = 1800 grams."
                   && agree.reply.result == "1800" && checked(agree.reply).hasPrefix("Checked: a program was run for this, and the reply agrees"))
        let overruled = await run(eggs, eggModel(own: "About 2000 grams.", first: printing("3 * 12 * 50"), second: printing("sum(12 * 50 for _ in range(3))")))
        expect("two programs that agree overrule the reply: \(overruled.reply.answer)", overruled.requests.count == 4 && overruled.reply.answer.contains("1800") && !overruled.reply.answer.contains("2000")
                   && overruled.reply.toolLog.contains { $0.hasPrefix("A second program agreed") } && overruled.reply.result == "1800")
        expect("the second program is asked for a different way, and the last call gets the result",
               overruled.requests.count == 4 && text(overruled.requests[2]).contains("An earlier program printed 1800") && text(overruled.requests[3]).contains("The exact result is: 1800"))
        let stubborn = await run(eggs, eggModel(own: "About 2000 grams.", first: printing("3 * 12 * 50"), second: printing("sum(12 * 50 for _ in range(3))"), reworded: "Still 2000 grams, I think."))
        expect("a reworded reply that leaves the result out has it written in: \(stubborn.reply.answer.suffix(30))", stubborn.reply.answer.contains("1800"))
        let sided = await run(eggs, eggModel(own: "They weigh 1800 grams.", first: printing("3 * 12 * 5"), second: printing("3 * 12 * 50")))
        expect("a second program that sides with the reply leaves it alone: \(checked(sided.reply))", sided.requests.count == 3 && sided.reply.answer == "They weigh 1800 grams."
                   && checked(sided.reply) == "Checked: a second program agrees with the reply, and the first didn't" && sided.reply.result == "1800")
        let unsettled = await run(eggs, eggModel(own: "About 2000 grams.", first: printing("3 * 12 * 50"), second: printing("3 * 12 * 5")))
        expect("with no two agreeing the reply stands, and the steps say so: \(checked(unsettled.reply))", unsettled.reply.answer == "About 2000 grams."
                   && checked(unsettled.reply).hasPrefix("Not checked: the reply and the programs disagree") && unsettled.reply.result == nil)
        let guessed = await run(eggs, eggModel(own: "About 2000 grams.", first: printing("3 * 12 * 50"), second: printing("1800")))
        expect("a second program that only prints a number is no second opinion: \(checked(guessed.reply))", guessed.reply.answer == "About 2000 grams." && checked(guessed.reply).hasPrefix("Not checked:"))
        expect("180 isn't stated by a reply that says 1800", !states("180", in: "They weigh 1800 grams.", label: nil) && states("1800", in: "They weigh 1,800 grams.", label: nil)
                   && states("Friday", in: "It was a Friday.", label: nil))
        let noProgram = await run(eggs, eggModel(own: "About 2000 grams.", first: "I would multiply them.", second: "?"))
        expect("a model that writes no program keeps its reply: \(checked(noProgram.reply))", noProgram.reply.answer == "About 2000 grams."
                   && checked(noProgram.reply).hasPrefix("Not checked: no program ran to the end"))
        let leftover = "I have 3 apples and my sister gives me twice as many again, so what do I end up with"
        let asked = await run(leftover) { request in
            if text(request).contains("Which is true of the message above?") { return text(request).contains("A. A short computer program") ? "A" : "B" }
            if isPlain(request, leftover) { return "You end up with 9 apples." }
            return python("def solve():\n    return 3 + 3 * 2\n\nprint(solve())")
        }
        expect("a task the model sends to a program: two letters, its own answer, one program (\(asked.requests.count)): \(asked.reply.toolLog.first ?? "")",
               asked.reply.route == .program && asked.requests.count == 4 && asked.requests[0].maxTokens == 16 && asked.reply.answer == "You end up with 9 apples." && asked.reply.result == "9")
        let traced = "What does this print?\n\ntotal = 0\nfor n in range(1, 7):\n    total += n\nprint(total)"
        let trace = await run(traced) { _ in "It prints 21." }
        expect("code shown in the message is run, not rewritten: \(trace.reply.toolLog)", trace.reply.route == .program && trace.reply.result == "21"
                   && trace.reply.toolLog.contains { $0.hasPrefix("Ran the python from the task: 21") })

        // MARK: Code

        let vowels = "Write a python function to count the vowels in a string. Your code should pass these tests:\n\nassert count_vowels(\"banana\") == 3\nassert count_vowels(\"sky\") == 0"
        let right = "Here it is.\n\n" + python("def count_vowels(text):\n    return sum(1 for letter in text.lower() if letter in \"aeiou\")") + "\n\nIt counts a, e, i, o and u."
        let wrong = python("def count_vowels(text):\n    return sum(1 for letter in text.lower() if letter in \"aeiouy\")")
        let broken = python("def count_vowels(text)\n    return 0")
        func isFix(_ request: ChatRequest) -> Bool { text(request).contains("Your code was run and it failed") }
        let passes = await run(vowels) { _ in right }
        expect("code that passes the message's examples is asked for once and left alone", passes.reply.route == .code && passes.requests.count == 1 && isPlain(passes.requests[0], vowels) && passes.reply.answer == right)
        expect("its steps say what ran: \(passes.reply.toolLog.dropFirst())", passes.reply.toolLog.contains("Ran the code on the 2 examples in the message: 2 held")
                   && checked(passes.reply) == "Checked: the code passes the 2 examples in the message")
        let fixed = await run(vowels) { isFix($0) ? right : wrong }
        expect("code that fails an example goes back once and the fix stays", fixed.requests.count == 2 && fixed.reply.answer == right && checked(fixed.reply).hasPrefix("Checked: the code passes"))
        expect("the fix hears which example failed and what the code gave: \(fixed.requests.count == 2 ? String(text(fixed.requests[1]).suffix(330).prefix(200)) : "")",
               fixed.requests.count == 2 && text(fixed.requests[1]).contains("assert count_vowels(\"sky\") == 0") && text(fixed.requests[1]).contains("it gave 1 and the example expects 0")
                   && text(fixed.requests[1]).contains("def count_vowels(text):"))
        let worse = await run(vowels) { isFix($0) ? broken : wrong }
        expect("fixes that do no better leave the first reply in place, after two tries (\(worse.requests.count))", worse.requests.count == 3 && worse.reply.answer == wrong
                   && checked(worse.reply) == "Not checked: the code still fails 1 of the 2 examples in the message")
        let renamed = await run(vowels) { isFix($0) ? right : python("def countVowels(text):\n    return 0") }
        expect("a wrong name is said as it is", renamed.requests.count == 2 && text(renamed.requests[1]).contains("NameError") && renamed.reply.answer == right)
        let forever = await run(vowels) { isFix($0) ? right : python("def count_vowels(text):\n    while True:\n        pass") }
        expect("code that never ends is stopped and sent back", forever.requests.count == 2 && text(forever.requests[1]).contains("ten seconds") && forever.reply.answer == right)
        let largest = "Write a function that returns the largest of three numbers."
        let valid = await run(largest) { _ in python("def largest(a, b, c):\n    return max(a, b, c)\n\nprint(largest(int(input()), 2, 3))") }
        expect("with no examples only the code's grammar is checked, so waiting for input isn't a fault: \(checked(valid.reply))",
               valid.requests.count == 1 && checked(valid.reply) == "Checked: the code is valid Python. The message gave no examples to run it on")
        let unreadable = await run(largest) { isFix($0) ? python("def largest(a, b, c):\n    return max(a, b, c)") : python("def largest(a, b, c)\n    return max(a, b, c)") }
        expect("code Python can't read goes back with the line", unreadable.requests.count == 2 && text(unreadable.requests[1]).contains("Python can't read it: line 1") && checked(unreadable.reply).hasPrefix("Checked: the code is valid Python"))
        let prose = await run(largest) { _ in "Compare the three and keep the biggest." }
        expect("a reply with no code is left as it is: \(checked(prose.reply))", prose.requests.count == 1 && prose.reply.answer == "Compare the three and keep the biggest." && checked(prose.reply).hasPrefix("Nothing here for code to check"))
        expect("examples are the message's own assert lines", CodeCheck.examples(in: vowels).count == 2 && CodeCheck.examples(in: largest).isEmpty)
        let two = "```python\ndef helper():\n    return 1\n```\n\nThen use it:\n\n```python\nprint(helper())\n```\n\n```bash\npip install nothing\n```"
        expect("the code is the blocks that define something, not the one that uses them or the shell", CodeCheck.python(in: two) == "def helper():\n    return 1\n")
        expect("a reply that is only code counts, and prose doesn't", CodeCheck.python(in: "def f():\n    return 1") != nil && CodeCheck.python(in: "Just add them up.") == nil)
        let shouting = await CodeCheck.run("print(\"check RESULT 2 2\")\ndef count_vowels(text):\n    return 9", examples: CodeCheck.examples(in: vowels))
        expect("what the code prints can't pass for the count", !shouting.passed && shouting.score == 0)
        let quitting = await CodeCheck.run("import sys\ndef count_vowels(text):\n    return 9\nsys.exit(0)", examples: CodeCheck.examples(in: vowels))
        expect("code that quits is still tried on the examples", !quitting.passed && quitting.score == 0 && quitting.problem.contains("it gave 9"))

        // MARK: Rules

        let rain = "Write exactly 2 sentences about rain. Each sentence must start with the letter S."
        let kept = await run(rain) { _ in "Storms sweep over the hills. Soft drops follow them." }
        expect("writing that keeps its rules is asked for once, uncapped, and left as written", kept.reply.route == .rules && kept.requests.count == 1 && isPlain(kept.requests[0], rain)
                   && kept.requests[0].maxTokens == 512 && kept.reply.answer == "Storms sweep over the hills. Soft drops follow them." && checked(kept.reply).hasSuffix("as the model wrote it"))
        let mended = await run(rain) { request in
            if isPlain(request, rain) { return "Rain falls on the roof. Drops run down the glass." }
            if text(request).contains("List 12 different words") { return "Storm\nSoft\nSilver\nSteady\nSudden\nSpring\nSummer\nStreet\nShower\nSound\nStill\nSky" }
            let first = text(request).range(of: #"first word must be "(\w+)""#, options: .regularExpression).map { String(text(request)[$0]).components(separatedBy: "\"")[1] }
            return "\(first ?? "Soft") rain taps on the window."
        }
        expect("writing that breaks a rule is mended a sentence at a time: \(mended.reply.answer)", mended.requests.count > 1 && checked(mended.reply) == "Checked: the rules in the message, by code"
                   && TextRules(task: rain).violations(of: mended.reply.answer).isEmpty)
        let words = "Write exactly 3 words about the sky, in all lowercase."
        let tidied = await run(words) { _ in "Here you go:\nblue vast endless" }
        expect("a lead-in line is tidied away by code, with no second call: \(tidied.reply.answer)", tidied.requests.count == 1 && tidied.reply.answer == "blue vast endless"
                   && tidied.reply.toolLog.contains("Tidied the reply so it keeps the rules"))
        let never = await run(words) { _ in "the sky is very blue today" }
        expect("writing that never fits stops after two more tries and says so (\(never.requests.count)): \(checked(never.reply))", never.requests.count <= 3 && checked(never.reply).hasPrefix("Not checked:"))
        let starred = await run(words) { _ in "**the sky** is very blue today" }
        expect("and it is left as the model wrote it, stars and all, when nothing did better: \(starred.reply.answer)", starred.reply.answer == "**the sky** is very blue today")

        // MARK: Look up

        WebConsent.shared.allowForChecks()
        let before = WebTools.stub
        defer { WebTools.stub = before }
        var fetched = 0
        WebTools.stub = { url in
            fetched += 1
            let address = url.absoluteString
            if address.contains("search/title") { return #"{"pages":[{"title":"Faltings's theorem","key":"Faltings's_theorem","description":"Curves of genus above 1 have finitely many rational points"}]}"# }
            if address.contains("wiki/Faltings") { return "<main><p>Faltings's theorem, formerly the Mordell conjecture, says such a curve has finitely many rational points. The Mordell conjecture was proved by Gerd Faltings in 1983.</p></main>" }
            if address.contains("search/page") { return #"{"pages":[]}"# }
            if address.contains("api.stackexchange.com") { return #"{"items":[]}"# }
            if address.contains("developer.mozilla.org") { return #"{"documents":[]}"# }
            if address.contains("arxiv.org") { return "<feed></feed>" }
            return "<main><p>Nothing here.</p></main>"
        }
        let mordell = "Who proved the Mordell conjecture?"
        func isMemory(_ request: ChatRequest) -> Bool { text(request).contains("Answer in one short line") }
        let sure = await run(mordell) { isMemory($0) ? "Gerd Faltings" : "Gerd Faltings proved it, in 1983." }
        expect("the same answer from memory three times means nothing is looked up (\(fetched) fetches)", sure.reply.route == .lookup && fetched == 0
                   && sure.requests.filter(isMemory).count == 3 && sure.requests.count == 4 && sure.requests.last.map { isPlain($0, mordell) } == true)
        expect("the second and third are asked with some chance in them", sure.requests.filter(isMemory).map(\.temperature) == [0, 0.8, 0.8])
        expect("the reply is the plain model's, and the steps say it wasn't looked up: \(checked(sure.reply))", sure.reply.answer == "Gerd Faltings proved it, in 1983."
                   && checked(sure.reply) == "Not checked: answered from memory, with no lookup")
        fetched = 0
        let unsure = await run(mordell) { request in
            if isMemory(request) { return "I don't know." }
            return text(request).contains("Write a web search") ? "Mordell conjecture proof" : "Gerd Faltings proved it in 1983."
        }
        expect("a model that isn't sure is asked once, not again by the lookup", unsure.requests.filter(isMemory).count == 1)
        expect("a model that isn't sure is given a lookup (\(fetched) fetches): \(checked(unsure.reply))", fetched > 0 && unsure.reply.toolLog.contains("Not sure from memory, so it's looked up")
                   && unsure.reply.toolLog.contains { $0.hasPrefix("Opened:") } && checked(unsure.reply) == "Checked: a sentence from the page holds this answer")
        fetched = 0
        var turn = 0
        let wavering = await run(mordell) { request in
            guard isMemory(request) else { return "Gerd Faltings proved it in 1983." }
            turn += 1
            return turn == 2 ? "Louis Mordell" : "Gerd Faltings"
        }
        expect("answers that differ are a guess, so it's looked up, after two questions and no third", fetched > 0 && wavering.requests.filter(isMemory).count == 2
                   && wavering.reply.toolLog.contains("Memory gave different answers, so it's looked up") && wavering.reply.answer.contains("Faltings"))
        fetched = 0
        let now = await run("Who is the current president of France?") { isMemory($0) ? "Someone" : "I can't be sure." }
        expect("a question about what is true now skips memory and goes to the lookup", fetched > 0 && now.requests.filter(isMemory).isEmpty)
        let task = HarnessTask(prompt: mordell)
        expect("two short answers agree when one holds the other's names", sameAnswer("Gerd Faltings, in 1983", "Faltings", task: task) && sameAnswer("Canberra", "canberra.", task: task)
                   && !sameAnswer("In 1983", "In 1986", task: task) && !sameAnswer("Gerd Faltings", "Louis Mordell", task: task))

        // MARK: The policy and the long text

        var policy = HarnessPolicy()
        policy.off = [.rules, .code]
        let switchedOff = await run(rain, policy: policy) { _ in "Rain falls on the roof. Drops run down the glass." }
        expect("a route that's switched off is the plain model: \(switchedOff.reply.toolLog)", switchedOff.requests.count == 1 && isPlain(switchedOff.requests[0], rain)
                   && switchedOff.reply.answer == "Rain falls on the roof. Drops run down the glass." && switchedOff.reply.route == .direct)
        let ledger = (1...40).map { "Entry \($0): the lease for lot \($0 + 10) was signed by clerk number \($0 % 7) before two witnesses." }.joined(separator: "\n")
        let reading = await run(ledger + "\n\nWhich clerk signed the lease for lot 22?") { _ in "Clerk number 5 signed it." }
        expect("a long text goes through its passages: \(reading.reply.toolLog.prefix(3))", reading.reply.route == .document && reading.reply.toolLog.contains { $0.hasPrefix("Found ") })
        expect("every route was reached here", Set([direct.reply.route, sum.reply.route, agree.reply.route, passes.reply.route, kept.reply.route, sure.reply.route, reading.reply.route].compactMap { $0 })
                   == Set(HarnessRoute.allCases).subtracting([.build]))
        return lines
    }
}
#endif
