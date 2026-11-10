#if DEBUG
import Foundation

/// Dev harness v2 checked with a scripted model and canned page reports, so nothing here needs a model.
enum DevChecksV2 {
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prometheus-devv2-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func scripted(_ replies: [String]) -> LLMBackend {
        let counter = Counter()
        return ScriptedBackend { _ in
            let text = replies[min(counter.next(), replies.count - 1)]
            return [.content(text), .finished(BackendStats(stopReason: "stop"))]
        }
    }

    private static func agent(_ root: URL, version: DevHarnessVersion, replies: [String] = [""], reports: [DevPageReport] = [],
                              notes: @escaping @Sendable (String) -> Void = { _ in }) -> DevAgent {
        var setup = DevSetup(model: "scripted", backend: scripted(replies), context: 8_192, think: false)
        setup.version = version
        let counter = Counter()
        setup.pageCheck = { _, _, _ in reports.isEmpty ? DevPageReport() : reports[min(counter.next(), reports.count - 1)] }
        return DevAgent(project: DevProject(root: root), setup: setup, emit: { event in
            if case .note(let text) = event { notes(text) }
        })
    }

    static func run() async -> [String] {
        var lines: [String] = []
        func expect(_ name: String, _ ok: Bool) { lines.append("\(ok ? "PASS" : "FAIL") \(name)") }

        // What counts as a game.
        let quiz = "Make a quiz about capital cities with a score and a button to play again"
        expect("v1 takes a quiz with \"play again\" for a game", DevAgent.isGame(quiz))
        expect("v2 doesn't", !DevAgent.isGameStrict(quiz))
        for request in ["Make a snake game", "Build a first-person shooter", "A breakout clone I can play with the arrow keys", "Shoot the balloons before they float away"] {
            expect("still a game, as in v1: \(request)", DevAgent.isGameStrict(request) && DevAgent.isGame(request))
        }
        for request in ["Make a habit tracker web app", "A music player page with a play button", "Smoothie bar ordering page",
                        "A sign-up sheet for breakout rooms", "A page about my pet snake", "A podcast page where I can play the audio"] {
            expect("not a game: \(request)", !DevAgent.isGameStrict(request))
        }

        // Pages that should show what was typed.
        let listPage = "<form id=\"add-form\"><input id=\"item-input\"><button>Add</button></form><ul id=\"item-list\"></ul>"
        let calculator = "<input id=\"bill\" type=\"number\"><input id=\"tip\" type=\"range\"><button id=\"work-out\" type=\"button\">Work it out</button><p id=\"results\"></p>"
        expect("a page with a text field and a list should show what's typed", DevAgent.keepsAList(listPage))
        expect("a calculator with number fields and a results line needn't", !DevAgent.keepsAList(calculator))
        expect("nor a login form", !DevAgent.keepsAList("<form id=\"login-form\"><input type=\"email\"><input type=\"password\"><button>Sign in</button></form>"))

        let script = """
        const state = { items: [] };
        const $ = (selector) => document.querySelector(selector);
        function render() { $("#item-list").innerHTML = state.items.map((text) => "<li>" + text + "</li>").join(""); }
        $("#add-form").addEventListener("submit", (event) => { event.preventDefault(); state.items.push($("#item-input").value); render(); });
        render();
        """
        func project(_ body: String, script: String = script) -> URL {
            let root = folder()
            try? DevKit.shell(title: "List", body: body, styles: "styles.css", script: "app.js", kit: "kit.css").write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
            try? script.write(to: root.appendingPathComponent("app.js"), atomically: true, encoding: .utf8)
            try? "body { margin: 0; }\n".write(to: root.appendingPathComponent("styles.css"), atomically: true, encoding: .utf8)
            try? DevKit.css.write(to: root.appendingPathComponent("kit.css"), atomically: true, encoding: .utf8)
            return root
        }
        func report(used: Bool? = true, typed: Bool? = true, fits: Bool = true, responded: Bool = true, loaded: Bool = true, styled: Bool = true) -> DevPageReport {
            var report = DevPageReport()
            report.hasContent = true
            report.loaded = loaded
            report.styled = styled
            report.used = used
            report.showsTyped = typed
            report.showedTyped = typed
            report.fits = fits
            report.responded = responded
            report.controls = 3
            return report
        }
        func issues(_ body: String, script: String = script, _ report: DevPageReport, kind: DevPageKind = .app) -> [DevAgent.Issue] {
            let root = project(body, script: script)
            defer { try? FileManager.default.removeItem(at: root) }
            let v2 = agent(root, version: .v2)
            v2.lastReport = report
            return v2.openIssues(page: "index.html", kind: kind)
        }

        // What a first use would show.
        let dead = issues(listPage, report(used: false))
        expect("buttons that change nothing: \(dead.map(\.key))", dead.map(\.key) == ["unused"] && dead.first?.failure.file == "app.js")
        let untyped = issues(listPage, report(typed: false))
        expect("typed text that never shows: \(untyped.map(\.key))", untyped.map(\.key) == ["typed"])
        var removedAgain = report(typed: true)
        removedAgain.showsTyped = false
        expect("an item that showed and was then removed by the next button isn't one", issues(listPage, removedAgain).isEmpty)
        let wide = issues(listPage, report(fits: false))
        expect("a page wider than the window, for the styles to fix: \(wide.first?.failure.file ?? "nothing")", wide.map(\.key) == ["fits"] && wide.first?.failure.file == "styles.css")
        expect("a page with nothing wrong has none", issues(listPage, report()).isEmpty)
        expect("a calculator isn't asked to show what was typed", issues(calculator, script: "document.querySelector(\"#work-out\").addEventListener(\"click\", () => { document.querySelector(\"#results\").textContent = \"12\"; });", report(typed: false)).isEmpty)
        expect("a game is as wide as its canvas was asked to be", issues("<canvas id=\"game\" width=\"800\" height=\"500\"></canvas>", script: "requestAnimationFrame(() => {});", report(fits: false), kind: .game).isEmpty)
        expect("a drawing pad's canvas changes where the check can't see", issues("<canvas id=\"pad\"></canvas><button id=\"clear\" type=\"button\">Clear</button>", script: "document.querySelector(\"#clear\").addEventListener(\"click\", () => {});", report(used: false)).isEmpty)
        var crashedReport = report(used: false, loaded: false)
        crashedReport.failure = DevFailure(file: "app.js", kind: "TypeError", message: "x", output: "")
        expect("a page that didn't open has other problems first", issues(listPage, crashedReport).isEmpty)

        // Controls nothing mentions.
        let withIdle = listPage + "<button id=\"clear-all\" type=\"button\" class=\"btn btn-outline-danger\">Clear all</button>"
        let idle = issues(withIdle, report())
        expect("a button no script mentions: \(idle.map(\.key))", idle.map(\.key) == ["idle:clear-all"] && idle.first?.failure.message.contains("clear-all") == true)
        expect("a button the script uses is fine", issues(withIdle, script: script + "\n$(\"#clear-all\").addEventListener(\"click\", () => { state.items = []; render(); });", report()).isEmpty)
        expect("a form's own button is fine", issues(listPage, report()).isEmpty)
        let keypad = "<div id=\"keys\"><button id=\"key-1\" type=\"button\">1</button><button id=\"key-2\" type=\"button\">2</button></div><p id=\"screen\"></p>"
        expect("buttons a listener on their container handles are left alone",
               issues(keypad, script: "document.querySelector(\"#keys\").addEventListener(\"click\", (e) => { document.querySelector(\"#screen\").textContent += e.target.textContent; });", report()).isEmpty)
        expect("so are ones written to act by themselves", issues(listPage + "<button id=\"reset\" type=\"button\" onclick=\"location.reload()\">Reset</button>", report()).isEmpty)

        // How far an attempt got.
        let good = DevAgent.progress(.failed(DevFailure(kind: "Advice", message: "typed", output: "")), report: report(typed: false))
        let link = DevAgent.progress(.failed(DevFailure(kind: "Link", message: "x", output: "")), report: nil)
        let frozen = DevAgent.progress(.failed(DevFailure(kind: "Limit", message: "froze", output: "")), report: DevPageReport())
        let syntax = DevAgent.progress(.failed(DevFailure(kind: "SyntaxError", message: "x", output: "")), report: nil)
        expect("attempts rank by how far they got: \(good) > \(link) > \(frozen) > \(syntax)",
               DevAgent.progress(.worked(""), report: nil) > good && good > link && link > frozen && frozen > syntax)

        // The whole build. The first script works but never shows what's typed; the fix for that breaks the page.
        let plan = "NAME: Shopping list\nACTIONS: add an item\nPARTS: a form; a list\nDATA: items with text"
        let broken = script + "\nstate.items.missing.push(1);"
        let better = script.replacingOccurrences(of: "render();\n});", with: "render(); // shows it\n});") + "\n// second try"
        func replies(_ second: String) -> [String] {
            [plan, "```html\n\(listPage)\n```", "```css\nh1 { color: teal; }\n```", "```javascript\n\(script)\n```", "```javascript\n\(second)\n```"]
        }
        var crashed = report(used: false, typed: nil, responded: false, loaded: false)
        crashed.failure = DevFailure(file: "app.js", line: 6, kind: "TypeError", message: "undefined is not an object (evaluating 'state.items.missing.push')", output: "")
        final class Notes: @unchecked Sendable { var all: [String] = [] }
        func build(_ version: DevHarnessVersion, second: String, reports: [DevPageReport]) async -> (outcome: DevOutcome, saved: String, notes: [String], calls: Int) {
            let root = folder()
            defer { try? FileManager.default.removeItem(at: root) }
            let notes = Notes()
            let builder = agent(root, version: version, replies: replies(second), reports: reports, notes: { notes.all.append($0) })
            let outcome = await builder.run(DevJob(request: "Make a shopping list web app"))
            return (outcome, (try? String(contentsOf: root.appendingPathComponent("app.js"), encoding: .utf8)) ?? "", notes.all, builder.calls)
        }
        let worse = await build(.v2, second: broken, reports: [report(typed: false), crashed])
        expect("v2 takes one more look at an app that works but doesn't show what was typed", worse.notes.contains { $0.contains("One more look") && $0.contains("never showed up") })
        expect("when the fix breaks the page, the working version is what's saved", !worse.saved.contains("missing.push") && worse.saved.contains("render();"))
        expect("the job still counts as done, as it would in v1", worse.outcome.worked == true)
        expect("and the report says what was left: \(worse.outcome.text.suffix(80))", worse.outcome.text.contains("Not fixed:") && worse.outcome.text.contains("never showed up"))

        let cured = await build(.v2, second: better, reports: [report(typed: false), report()])
        expect("when the fix works, it's kept and nothing is left to say", cured.saved.contains("second try") && cured.outcome.worked == true && !cured.outcome.text.contains("Not fixed"))

        let same = await build(.v2, second: script, reports: [report(typed: false), report(typed: false)])
        // One try at the fix. The fixing itself may ask for the cause and one part again, as it does in v1.
        expect("a fix that changes nothing leaves the app as it was and stops there: \(same.calls) calls, \(same.outcome.text.suffix(60))",
               same.outcome.worked == true && same.outcome.text.contains("Not fixed:") && same.saved.contains("render();") && same.calls <= 8)

        let plain = await build(.v1, second: broken, reports: [report(typed: false), crashed])
        expect("v1, given the same replies, calls it done after four calls and says nothing more: \(plain.calls)",
               plain.outcome.worked == true && plain.calls == 4 && !plain.outcome.text.contains("Not fixed"))
        return lines
    }
}
#endif
