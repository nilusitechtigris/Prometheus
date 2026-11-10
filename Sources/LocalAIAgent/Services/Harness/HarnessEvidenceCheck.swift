#if DEBUG
import Foundation

/// v6's logic checked with a scripted model and canned pages, so nothing here needs a model or the internet.
extension TestLab {
    static func evidenceCheck() async -> [String] {
        var lines: [String] = []
        func expect(_ name: String, _ ok: Bool) { lines.append("\(ok ? "PASS" : "FAIL") \(name)") }

        // Plain code answers.
        for (question, value) in [("How many times does the letter r appear in 'strawberry raspberry cranberry'?", "9"),
                                  ("How many r's are in strawberry?", "3"),
                                  ("How many times does the letter \"s\" appear in \"Mississippi\"?", "4"),
                                  ("Count the letter e in \"Tennessee\"", "4"),
                                  ("How many r's are in the word arrow?", "2"),
                                  ("How many words are in \"the quick brown fox\"?", "4"),
                                  ("What day of the week was 14 March 1879?", "Friday"),
                                  ("What day of the week was July 4, 1776?", "Thursday"),
                                  ("On what day of the week will 2030-01-01 fall?", "Tuesday"),
                                  ("How many days are there from 14 March 1879 to 18 April 1955?", "27793"),
                                  ("How many days are between January 1, 2024 and March 1, 2024?", "60")] {
            let got = ExactTools.solve(question)?.value
            expect("exact: \(question.prefix(52)) = \(value) (got \(got ?? "nothing"))", got == value)
        }
        for question in ["How many moons does Mars have?", "What day of the week is best for a meeting?",
                         "How many times does the letter r appear in the Bible?", "What day of the week was 1 January 1500?",
                         "How many days are there between Christmas and Easter?", "How many r's are in this sentence, roughly?",
                         "Who was born on 14 March 1879?"] {
            expect("exact leaves alone: \(question)", ExactTools.solve(question) == nil)
        }

        // Routing.
        func kind(_ prompt: String) -> TaskKind? { strictKind(of: HarnessTask(prompt: prompt)) }
        let baker = "A baker makes 12 trays of 24 rolls. She sells 150 rolls in the morning and 96 in the afternoon. How many rolls are left?"
        for prompt in ["What day of the week was 14 March 1879?", "How many days are there from 14 March 1879 to 18 April 1955?", baker,
                       "How many vowels are in \"onomatopoeia\"?", "Convert 26.2 miles to kilometers.",
                       "How old was someone born on 3 May 1961 on 3 May 2000?"] {
            expect("goes to code: \(prompt.prefix(60))", kind(prompt) == .calculation)
        }
        for prompt in ["How many moons does Mars have?", "Who proved the Mordell conjecture, and in what year?",
                       "How many countries joined the European Union between 2004 and 2007?", "What is the capital of Burkina Faso?"] {
            expect("stays a lookup or a plain question: \(prompt.prefix(60))", kind(prompt) != .calculation)
        }
        let suite = ModelTestSuite.questions(contextLength: 4_096)
        let moved = suite.filter { strictKind(of: HarnessTask(prompt: $0.prompt)) != plainKind(of: HarnessTask(prompt: $0.prompt)) }
        lines.append("INFO the app's own questions v6 reads differently from v3: \(moved.map { "\($0.id) → \(strictKind(of: HarnessTask(prompt: $0.prompt))?.rawValue ?? "asks the model")" })")
        expect("v6 never sends a writing, code or long-text question elsewhere",
               suite.allSatisfy { question in
                   let plain = plainKind(of: HarnessTask(prompt: question.prompt))
                   return ![.writing, .code, .document].contains(plain) || strictKind(of: HarnessTask(prompt: question.prompt)) == plain
               })

        // Programs that compute nothing.
        expect("a program that returns its own guess is caught", onlyPrintsLiteral("def solve():\n    # 12 * 24 - 246\n    return 42\n\nprint(solve())"))
        expect("so is a bare print", onlyPrintsLiteral("print(42)"))
        expect("a program that computes is not", !onlyPrintsLiteral("def solve():\n    return 12 * 24 - 150 - 96\n\nprint(solve())"))
        expect("nor one with steps", !onlyPrintsLiteral("def solve():\n    rolls = 12 * 24\n    return rolls - 246\n\nprint(solve())"))

        // The name a question is about.
        for (question, name) in [("Who proved the Mordell conjecture, and in what year?", "Mordell conjecture"),
                                 ("What is the capital of Burkina Faso?", "Burkina Faso"),
                                 ("When was the Treaty of Versailles signed?", "Treaty of Versailles")] {
            expect("names \(name): \(HarnessText.namedThing(in: question) ?? "nothing")", HarnessText.namedThing(in: question) == name)
        }
        for question in ["Which chemical element has atomic number 74?",
                         "Which Hittite king concluded the peace treaty with Ramesses II after the Battle of Kadesh?"] {
            expect("names nothing single: \(question.prefix(50))", HarnessText.namedThing(in: question) == nil)
        }

        // Sentences and what backs an answer.
        let page = """
        Faltings's theorem is a result in arithmetic geometry about curves of genus greater than 1. This was conjectured in 1922 by \
        Louis Mordell, and known as the Mordell conjecture until its 1983 proof by Gerd Faltings. The conjecture was later generalized \
        by replacing the rationals with any number field. Gerd Faltings was awarded the Fields Medal in 1986 for proving the Mordell \
        conjecture. He was born in Gelsenkirchen and studied at the University of Münster.
        """
        let mordell = HarnessTask(prompt: "Who proved the Mordell conjecture, and in what year?")
        let sentences = Quotes.sentences(of: page)
        let picked = Quotes.pick(from: sentences, question: mordell.body)
        expect("the page splits into sentences (\(sentences.count))", sentences.count == 5)
        expect("the sentences about the question are picked (\(picked.count))", picked.count >= 2 && picked.allSatisfy { $0.contains("Mordell") })
        let element = HarnessTask(prompt: "Which chemical element has atomic number 74?")
        let rows = ["Tin is a chemical element with symbol Sn and atomic number 50.", "Tungsten is a chemical element with symbol W and atomic number 74."]
        expect("a neighbouring row doesn't back an answer", !isBacked("Tin", by: rows, task: element))
        expect("the right row does", isBacked("Tungsten", by: rows, task: element))
        expect("an answer that adds nothing is left alone", isBacked("The element with atomic number 74.", by: rows, task: element))

        // The whole loop, with a scripted model and canned pages.
        func finished(_ reason: String = "stop") -> StreamEvent {
            var stats = BackendStats()
            stats.stopReason = reason
            return .finished(stats)
        }
        func run(_ version: HarnessVersion, _ prompt: String, _ script: @escaping (String) -> String) async -> (asked: [String], reply: Reply) {
            let backend = ScriptedBackend { request in [.content(script(request.messages.last?.content ?? "")), finished()] }
            let setup = TestSetup(model: LocalModel(id: "scripted"), backend: backend, context: 8_192, think: nil, supportsTools: false)
            let reply = await harnessReply(version, prompt: prompt, setup: setup, maxTokens: 512)
            return (backend.requests.map { $0.messages.last?.content ?? "" }, reply)
        }
        WebConsent.shared.allowForChecks()
        defer { WebTools.stub = nil }

        let weekday = await run(.evidence, "What day of the week was 14 March 1879?") { _ in "It was a Friday." }
        expect("a weekday: one model call, to word the reply (\(weekday.asked.count))", weekday.asked.count == 1)
        expect("the reply states what code worked out", weekday.reply.answer.contains("Friday") && weekday.reply.result == "Friday")
        expect("its steps say so: \(weekday.reply.toolLog)", weekday.reply.toolLog.contains { $0.hasPrefix("Worked out:") } && weekday.reply.toolLog.last == "Checked: code worked this out")
        let wrongDay = await run(.evidence, "What day of the week was 14 March 1879?") { _ in "It was a Saturday." }
        expect("a model that words it wrongly is overruled: \(wrongDay.reply.answer.suffix(40))", wrongDay.reply.answer.contains("Friday"))

        let stubbed: (URL) -> String? = { url in
            let address = url.absoluteString
            if address.contains("search/title") { return #"{"pages":[{"title":"Faltings's theorem","key":"Faltings's_theorem","description":"Curves of genus > 1 have finitely many rational points"}]}"# }
            if address.contains("wiki/Faltings") { return "<main><p>\(page)</p></main>" }
            if address.contains("search/page") {
                return #"{"pages":[{"title":"List of chemical elements","key":"List_of_chemical_elements","excerpt":"chemical element atomic number list"},{"title":"Tungsten","key":"Tungsten","excerpt":"chemical element with atomic number 74"}]}"#
            }
            if address.contains("wiki/Tungsten") { return "<main><p>\(rows[1]) It is a rare metal found in several ores. Tungsten has the highest melting point of all metals.</p></main>" }
            if address.contains("wiki/List_of") { return "<main><p>\(rows[0]) \(rows[1])</p></main>" }
            return "{}"
        }
        WebTools.stub = stubbed

        let talkedOut = await run(.evidence, mordell.prompt) { asked in
            if asked.contains("Answer in one short line") { return "Gerd Faltings, 1983" }
            if asked.contains("point to different answers") { return "Gerd Faltings proved the Mordell conjecture in 1983." }
            return "Gerd Faltings proved the Mordell conjecture in 1986."
        }
        expect("it looks the name up before anything else: \(talkedOut.reply.toolLog.prefix(4))",
               talkedOut.reply.toolLog.contains("Looked up: Mordell conjecture") && talkedOut.reply.toolLog.contains { $0.hasPrefix("Opened: https://en.wikipedia.org/wiki/Faltings") })
        expect("the model is given sentences, not the page", talkedOut.asked.contains { $0.contains("Your tools found these sentences") && !$0.contains("Gelsenkirchen") })
        expect("a page that talks the model out of its answer gets both sentences put to it",
               talkedOut.reply.toolLog.contains("Two sentences point to different answers, so it reads both again"))
        expect("and the reply is the one it settles on: \(talkedOut.reply.answer)", talkedOut.reply.answer.contains("1983") && !talkedOut.reply.answer.contains("1986"))
        expect("which a sentence backs", talkedOut.reply.toolLog.last == "Checked: a sentence from the page backs this")

        let agreed = await run(.evidence, mordell.prompt) { asked in
            asked.contains("Answer in one short line") ? "Faltings in 1983" : "Gerd Faltings proved it in 1983."
        }
        expect("when memory and the page agree there's no second round", !agreed.reply.toolLog.contains { $0.contains("different answers") }
               && agreed.asked.filter { $0.contains("Your tools found") }.count == 1)

        let tungsten = await run(.evidence, element.prompt) { asked in
            if asked.contains("Answer in one short line") { return "I don't know" }
            if asked.contains("Write a web search") { return "atomic number 74 chemical element" }
            return "It is tungsten."
        }
        let opened = tungsten.reply.toolLog.filter { $0.hasPrefix("Opened") }
        expect("a list page isn't opened ahead of the page about the thing: \(opened)", opened.first?.contains("Tungsten") == true)
        expect("the answer is backed by the row with 74", tungsten.reply.answer.lowercased().contains("tungsten") && tungsten.reply.toolLog.last == "Checked: a sentence from the page backs this")
        expect("not being sure is logged as that", tungsten.reply.toolLog.contains("From memory: not sure"))

        let neighbour = await run(.evidence, element.prompt) { asked in
            if asked.contains("Answer in one short line") { return "I don't know" }
            if asked.contains("Write a web search") { return "atomic number 74 chemical element" }
            return "It is tin."
        }
        expect("an answer no sentence backs ends as not checked: \(neighbour.reply.toolLog.last ?? "")", neighbour.reply.toolLog.last?.hasPrefix("Not checked:") == true)
        expect("and it stops after two rounds", neighbour.asked.filter { $0.contains("Which chemical element") && !$0.contains("one short line") && !$0.contains("web search") }.count <= 2)

        let sea = "Write one sentence about the sea with exactly five words."
        var seaTries = 0
        let rewritten = await run(.evidence, sea) { _ in
            seaTries += 1
            return seaTries == 1 ? "The sea is wide, deep, cold and blue today." : "The sea is very deep."
        }
        expect("too many words: v6 asks again instead of cutting: \(rewritten.reply.answer)", rewritten.reply.answer == "The sea is very deep.")
        let cut = await run(.loop, sea) { _ in "The sea is wide, deep, cold and blue today." }
        expect("v3 still cuts, as it was measured: \(cut.reply.answer)", cut.reply.answer == "The sea is wide, deep,")

        var programs = 0
        let guessed = await run(.evidence, baker) { asked in
            guard asked.contains("Write a real Python program") else { return "42 rolls are left." }
            programs += 1
            return programs == 1 ? "```python\ndef solve():\n    return 40\n\nprint(solve())\n```"
                                 : "```python\ndef solve():\n    return 12 * 24 - 150 - 96\n\nprint(solve())\n```"
        }
        expect("a guessed program is sent back, and the computed one stands: \(guessed.reply.result ?? "nothing")",
               guessed.reply.result == "42" && guessed.reply.toolLog.contains { $0.contains("only printed its own guess") })
        return lines
    }
}
#endif
