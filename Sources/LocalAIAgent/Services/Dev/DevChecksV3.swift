#if DEBUG
import Foundation

/// Dev harness v3 checked with a scripted model and canned page reports, so nothing here needs a model. What it
/// has to show: v3's sizes follow the context window, v1 and v2 keep theirs at any window, and a file too long
/// for v2's reply gets written by v3.
enum DevChecksV3 {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            return value - 1
        }
    }

    private static func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prometheus-devv3-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A model that says its lines in order, and is cut off like a real one: a reply longer than the request
    /// allows stops there, with the reason a framework gives.
    private static func scripted(_ replies: [String]) -> ScriptedBackend {
        let counter = Counter()
        return ScriptedBackend { request in
            let text = replies[min(counter.next(), replies.count - 1)]
            if let room = request.maxTokens, DevAgent.tokens(text) > room {
                return [.content(String(text.prefix(room * 35 / 10))), .finished(BackendStats(stopReason: "length"))]
            }
            return [.content(text), .finished(BackendStats(stopReason: "stop"))]
        }
    }

    private static func works() -> DevPageReport {
        var report = DevPageReport()
        report.hasContent = true
        report.loaded = true
        report.styled = true
        report.responded = true
        report.used = true
        report.showsTyped = true
        report.showedTyped = true
        report.controls = 3
        return report
    }

    private struct Built {
        var outcome: DevOutcome
        var requests: [ChatRequest]
        var script: String
    }

    /// One whole job: a new web app, from a plan to a page that works.
    private static func build(_ version: DevHarnessVersion, context: Int, replies: [String], request: String = "Make a shopping list web app") async -> Built {
        let root = folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = scripted(replies)
        var setup = DevSetup(model: "scripted", backend: backend, context: context, think: false)
        setup.version = version
        setup.pageCheck = { _, _, _ in works() }
        let outcome = await DevAgent(project: DevProject(root: root), setup: setup, emit: { _ in }).run(DevJob(request: request))
        return Built(outcome: outcome, requests: backend.requests, script: (try? String(contentsOf: root.appendingPathComponent("app.js"), encoding: .utf8)) ?? "")
    }

    private static func said(_ request: ChatRequest) -> String { request.messages.map(\.content).joined(separator: "\n") }

    static func run() async -> [String] {
        var lines: [String] = []
        func expect(_ name: String, _ ok: Bool) { lines.append("\(ok ? "PASS" : "FAIL") \(name)") }

        // The sizes.
        let small = DevBudget.small
        expect("the small budget is what v1 and v2 always had: a reply of 4,096 tokens, a page under 90 lines, styles under 40",
               small.reply == 4_096 && small.pageLines == 90 && small.styleLines == 40 && small.oneReply == 8_192)
        for context in [2_048, 4_096, 8_192] {
            expect("at \(context) v3's sizes are the small ones", DevBudget.roomy(context: context) == small)
        }
        let middle = DevBudget.roomy(context: 16_384), large = DevBudget.roomy(context: 32_768)
        expect("at 16K a reply and the files may be larger: \(middle.reply) tokens, \(middle.pageLines) and \(middle.styleLines) lines",
               middle.reply > small.reply && middle.pageLines > small.pageLines && middle.styleLines > small.styleLines)
        expect("at 32K larger again: \(large.reply) tokens, \(large.pageLines) and \(large.styleLines) lines",
               large.reply > middle.reply && large.pageLines > middle.pageLines && large.styleLines > middle.styleLines)
        expect("and the plan may list more: \(large.planActions) actions, \(large.planParts) parts", large.planActions > small.planActions && large.planParts > small.planParts)
        expect("a window larger than 32K gets what 32K gets", DevBudget.roomy(context: 65_536) == large && DevBudget.roomy(context: 131_072) == large)
        let sizes = AppSettings.contextOptions.map { DevBudget.roomy(context: $0) }
        expect("no size shrinks as the window grows", zip(sizes, sizes.dropFirst()).allSatisfy { a, b in
            b.reply >= a.reply && b.pageLines >= a.pageLines && b.styleLines >= a.styleLines && b.planActions >= a.planActions && b.planParts >= a.planParts
        })
        expect("a file's reply never takes more than half the window from 16K up", AppSettings.contextOptions.filter { $0 >= 16_384 }.allSatisfy { DevBudget.roomy(context: $0).reply * 2 <= $0 })
        expect("a page of that many lines fits its reply, at about 14 tokens a line", [middle, large].allSatisfy { $0.pageLines * 14 <= $0.reply && $0.styleLines * 14 <= $0.reply })
        for version in [DevHarnessVersion.v1, .v2] {
            expect("\(version.rawValue) keeps the small sizes at any window", AppSettings.contextOptions.allSatisfy { DevBudget.of(version, context: $0) == small })
        }
        expect("v3 gets its own", DevBudget.of(.v3, context: 32_768) == large)

        // Which version works.
        expect("the version in use is still v1: v3 has no measured run", DevHarnessVersion.recommended == .v1)
        expect("the standard edition runs v1 when v3 is stored, and the lab runs v3",
               DevHarnessVersion.allowed(.v3, in: .standard) == .v1 && DevHarnessVersion.allowed(.v3, in: .lab) == .v3)
        expect("the lab offers v3, the standard edition doesn't",
               DevHarnessVersion.offered(in: .lab).contains(.v3) && !DevHarnessVersion.offered(in: .standard).contains(.v3))

        // What the model is asked.
        let plan = "NAME: Shopping list\nACTIONS: add an item\nPARTS: a form; a list\nDATA: items with text"
        let page = "<form id=\"add-form\"><input id=\"item-input\"><button>Add</button></form><ul id=\"item-list\"></ul>"
        let script = """
        const state = { items: [] };
        const $ = (selector) => document.querySelector(selector);
        function render() { $("#item-list").innerHTML = state.items.map((text) => "<li>" + text + "</li>").join(""); }
        $("#add-form").addEventListener("submit", (event) => { event.preventDefault(); state.items.push($("#item-input").value); render(); });
        render();
        """
        let replies = [plan, "```html\n\(page)\n```", "```css\nh1 { color: teal; }\n```", "```javascript\n\(script)\n```"]

        let v2Small = await build(.v2, context: 8_192, replies: replies)
        let v3Small = await build(.v3, context: 8_192, replies: replies)
        expect("at 8K v3 asks the model exactly what v2 asks: \(v3Small.requests.count) requests",
               v3Small.requests.count == v2Small.requests.count && v3Small.requests.count >= 4
                   && zip(v3Small.requests, v2Small.requests).allSatisfy { said($0) == said($1) && $0.maxTokens == $1.maxTokens && $0.temperature == $1.temperature })
        expect("and both build the app", v2Small.outcome.worked == true && v3Small.outcome.worked == true)

        let v3Large = await build(.v3, context: 32_768, replies: replies)
        let asked = v3Large.requests.map(said)
        expect("at 32K v3's plan may list \(large.planActions) actions and \(large.planParts) parts, in a reply of \(large.planReply) tokens",
               asked.first?.contains("3 to \(large.planActions) actions and 3 to \(large.planParts) parts") == true && v3Large.requests.first?.maxTokens == large.planReply)
        expect("the page is asked to stay under \(large.pageLines) lines", asked.contains { $0.contains("Keep it under \(large.pageLines) lines.") && $0.contains("You write the HTML") })
        expect("the style sheet under \(large.styleLines)", asked.contains { $0.contains("Keep it under \(large.styleLines) lines.") && $0.contains("You write the style sheet") })
        expect("and each file's reply may run to \(large.reply) tokens", v3Large.requests.dropFirst().allSatisfy { $0.maxTokens == large.reply })
        expect("the app is built there too", v3Large.outcome.worked == true)

        let v3Middle = await build(.v3, context: 16_384, replies: replies)
        expect("at 16K the page is asked to stay under \(middle.pageLines) lines, in replies of \(middle.reply) tokens",
               v3Middle.requests.map(said).contains { $0.contains("Keep it under \(middle.pageLines) lines.") } && v3Middle.requests.dropFirst().allSatisfy { $0.maxTokens == middle.reply })

        let v2Large = await build(.v2, context: 32_768, replies: replies)
        expect("v2 at 32K asks what it asks at 8K: under 90 and 40 lines, in replies of 4,096 tokens",
               zip(v2Large.requests, v2Small.requests).allSatisfy { said($0) == said($1) }
                   && v2Large.requests.map(said).contains { $0.contains("Keep it under 90 lines.") } && v2Large.requests.dropFirst().allSatisfy { $0.maxTokens == 4_096 })
        let v1Large = await build(.v1, context: 32_768, replies: replies)
        expect("so does v1, with its own smaller plan",
               v1Large.requests.first.map(said)?.contains("3 to 6 parts and 3 to 6 actions") == true && v1Large.requests.dropFirst().allSatisfy { $0.maxTokens == 4_096 })

        // A request that nearly fills the window leaves less room than the budget, and the reply is cut to it.
        let long = "Make a shopping list web app. " + String(repeating: "It keeps a list of things to buy. ", count: 1_150)
        let tight = await build(.v3, context: 16_384, replies: replies, request: long)
        expect("a reply never asks for more than the window has left: \(tight.requests.compactMap(\.maxTokens).map(String.init).joined(separator: ", "))",
               !tight.requests.isEmpty && tight.requests.allSatisfy { request in
                   guard let room = request.maxTokens else { return false }
                   return room >= 96 && room + DevAgent.tokens(request.messages[0].content) + DevAgent.tokens(request.messages[1].content) + 32 <= 16_384
               } && tight.requests.contains { ($0.maxTokens ?? 0) < middle.reply })

        // The case v3 is for: a script too long for one reply of 4,096 tokens.
        let padding = (1...330).map { "const note\($0) = \"this line stands for one more line of a larger app's script\";" }.joined(separator: "\n")
        let longScript = script + "\n" + padding
        let size = DevAgent.tokens("```javascript\n\(longScript)\n```")
        expect("the long script is longer than v2's reply and shorter than v3's at 32K: \(size) tokens", size > small.reply && size < large.reply)
        let longReplies = [plan, "```html\n\(page)\n```", "```css\nh1 { color: teal; }\n```", "```javascript\n\(longScript)\n```"]
        let cut = await build(.v2, context: 32_768, replies: longReplies)
        expect("v2 at 32K has its reply cut off, asks for a shorter one, and ends with no script: \(cut.outcome.text.prefix(70))",
               cut.outcome.worked != true && cut.outcome.text.contains("didn't write usable code for app.js")
                   && cut.requests.map(said).contains { $0.contains("too long and got cut off") })
        let whole = await build(.v3, context: 32_768, replies: longReplies)
        expect("v3 at 32K gets all of it in one reply and builds the app: \(whole.requests.count) requests",
               whole.outcome.worked == true && whole.script.contains("const note330") && whole.requests.count == 4
                   && !whole.requests.map(said).contains { $0.contains("cut off") })
        let narrow = await build(.v3, context: 8_192, replies: longReplies)
        expect("v3 at 8K has no more room than v2, and says so the same way", narrow.outcome.worked != true && narrow.outcome.text.contains("didn't write usable code for app.js"))

        // The harness off, which a comparison measures against.
        func oneReply(_ version: DevHarnessVersion, context: Int) async -> Int? {
            let root = folder()
            defer { try? FileManager.default.removeItem(at: root) }
            let backend = scripted(["```python\nprint('hello')\n```"])
            var setup = DevSetup(model: "scripted", backend: backend, context: context, think: false)
            setup.version = version
            _ = await DevOneReply.run(request: "print hello", project: DevProject(root: root), setup: setup, emit: { _ in })
            return backend.requests.first?.maxTokens
        }
        let offV1 = await oneReply(.v1, context: 32_768), offV2 = await oneReply(.v2, context: 32_768), offV3 = await oneReply(.v3, context: 32_768)
        expect("with the harness off, one reply may run to 8,192 tokens with v1 or v2 chosen", offV1 == 8_192 && offV2 == 8_192)
        expect("with v3 chosen the plain model gets v3's room for a whole app: \(offV3.map(String.init) ?? "unset")", offV3 == large.oneReply && large.oneReply > 8_192)
        let offSmall = await oneReply(.v3, context: 8_192), offSmallV1 = await oneReply(.v1, context: 8_192)
        expect("at 8K it has what v1's has: \(offSmall.map(String.init) ?? "unset")", offSmall == offSmallV1 && (offSmall ?? 0) < 8_192)
        return lines
    }
}
#endif
