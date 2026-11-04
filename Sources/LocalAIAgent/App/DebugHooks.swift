#if DEBUG
import AppKit
import SwiftUI

/// Debug-build-only automation used for UI verification without Screen Recording permission.
///   LOCALAI_SNAPSHOT_DIR=/path      write window snapshots (snap-N.png) every LOCALAI_SNAPSHOT_INTERVAL seconds
///   LOCALAI_AUTOPROMPT="text"       start a new chat and send this prompt after launch
///   LOCALAI_SHOW_LIBRARY=1          open the model library after launch
///   LOCALAI_SHOW_MODEL_PICKER=1     open the model + quant picker after launch
///   LOCALAI_NO_ACTIVATE=1           don't bring the app to the front on launch
///   LOCALAI_DATA_DIR=/path          keep chats in this folder instead of the user's
///   LOCALAI_DESTINATION=model|hardware|harness   open that test dashboard after launch
///   LOCALAI_AUTOTEST=model|hardware|harness      run that test after launch
///   LOCALAI_TEST_MODEL=tag          model the model test runs on (the chat's model stays as it is)
///   LOCALAI_SHOW_TEST_PICKER=1      open the model test's model picker after launch
///   LOCALAI_EXPAND_TESTS=id,id      open these questions in the model test dashboard
///   LOCALAI_DUMP_SUITE=/path.json   write the model test as JSON, to run it outside the app
///   LOCALAI_GRADE=/path.json        grade replies from {"id": "reply"}, writing /path.json.graded.json
///   LOCALAI_OPEN_WIDGETS=1          open both floating telemetry widgets after launch (see ContentView)
///   LOCALAI_WIDGET_CYCLE=1          close the open widgets after 3 s and reopen Generation after 6 s
///   LOCALAI_WIDGET_ZOOM=1.5         resize open widget windows by this factor after 3 s
///   LOCALAI_HARNESS_CHECK=/path.txt check the harness's allowlist, calculator, guard and web tools, writing a report
///   LOCALAI_WEB_VIA_CURL=1          make the harness's web requests with curl (see WebTools)
///   LOCALAI_LIGHT_MODE=1            force the light appearance
///   LOCALAI_CLOSE_MAIN=3            close the main window after this many seconds, like its red button
///   LOCALAI_DRAFT=1                 open the Forge draft after launch; =cycle leaves it again after 3 s
///   LOCALAI_RENDER_DIR=/path        render both full dashboards (narrow and wide) after LOCALAI_RENDER_DELAY seconds
@MainActor
enum DebugHooks {
    static func install(chat: ChatController, ui: UIState, lab: TestLab, backends: BackendController,
                        monitor: SystemMonitor, settings: AppSettings) {
        let env = ProcessInfo.processInfo.environment
        if env["LOCALAI_LIGHT_MODE"] != nil { NSApp.appearance = NSAppearance(named: .aqua) }
        if env["LOCALAI_CLOSE_MAIN"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(Double(env["LOCALAI_CLOSE_MAIN"] ?? "") ?? 3))
                let main = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
                print("closing:", main?.identifier?.rawValue ?? "no main window", "of", NSApp.windows.map { $0.identifier?.rawValue ?? "?" })
                main?.performClose(nil)
                main?.close()
            }
        }
        if let draft = env["LOCALAI_DRAFT"] {
            settings.draftLayout = true
            if draft == "cycle" {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    settings.draftLayout = false
                }
            }
        }
        switch env["LOCALAI_DESTINATION"] {
        case "model": ui.destination = .modelTest
        case "hardware": ui.destination = .hardwareTest
        case "harness": ui.destination = .harnessTest
        default: break
        }
        if let zoom = Double(env["LOCALAI_WIDGET_ZOOM"] ?? "") {
            Task {
                try? await Task.sleep(for: .seconds(3))
                for window in NSApp.windows where window.identifier?.rawValue.contains("widget") == true {
                    var frame = window.frame
                    frame.size = NSSize(width: frame.width * zoom, height: frame.height * zoom)
                    window.setFrame(frame, display: true)
                }
            }
        }
        if let dir = env["LOCALAI_RENDER_DIR"] {
            Task {
                try? await Task.sleep(for: .seconds(Double(env["LOCALAI_RENDER_DELAY"] ?? "") ?? 3))
                let pages: [(String, AnyView)] = [("model", AnyView(ModelTestDashboard(scrollable: false))),
                                                  ("hardware", AnyView(HardwareTestDashboard(scrollable: false))),
                                                  ("harness", AnyView(HarnessTestDashboard(scrollable: false)))]
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
                chat.send(prompt)
            }
        }
        if env["LOCALAI_SHOW_MODEL_PICKER"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                ui.showModelPicker = true
            }
        }
        if env["LOCALAI_SHOW_LIBRARY"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(2))
                ui.showLibrary = true
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
        for other in NSApp.windows where other.isVisible && other !== window {
            if let id = other.identifier?.rawValue, id.contains("widget") {
                write(other, to: path.replacingOccurrences(of: ".png", with: "-\(id.split(separator: "-").prefix(2).joined(separator: "-")).png"))
            }
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
