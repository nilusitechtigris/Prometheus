import AppKit
import CryptoKit
import Foundation
import Observation

/// One thing the agent did on its way to a reply.
struct DevStep: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case stage, note, run }

    var id = UUID()
    var kind: Kind
    var text: String
    var output: String?
    var passed: Bool?
}

struct DevMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    var isUser: Bool
    var text: String
    var steps: [DevStep] = []
    var changes: [DevChange] = []
    /// Nil for a plain answer.
    var worked: Bool?
    var failure: DevFailure?
    var undone = false
    var seconds: Double?
    /// False for a reply made with the harness off. Nil in conversations from before the switch.
    var harness: Bool?
    /// How many times the model was asked something.
    var calls: Int?
}

/// One program run in the Terminal, or one page opened in Preview.
struct DevTerminalRun: Identifiable, Equatable {
    let id = UUID()
    let command: String
    let arguments: [String]
    var output = ""
    var result: DevRunResult?
    var failure: DevFailure?
    var isPage = false

    var isRunning: Bool { result == nil }
}

/// A request to show a line in the editor.
struct DevJump: Equatable {
    let id = UUID()
    let line: Int
}

/// What's open in Dev mode: one project folder, its editor, its Terminal and its agent.
@Observable
@MainActor
final class DevSession {
    private static let onKey = "devModeOn"
    private static let harnessKey = "devHarnessOn"
    private static let recentsKey = "devRecentProjects"
    private static let maxRuns = 30
    /// Output the Terminal keeps on screen for one run.
    static let outputShown = 40_000

    var isOn = UserDefaults.standard.bool(forKey: DevSession.onKey) {
        didSet { UserDefaults.standard.set(isOn, forKey: Self.onKey) }
    }
    private(set) var project: DevProject?
    private(set) var entries: [DevEntry] = []
    var collapsed: Set<String> = []
    private(set) var recents: [String] = UserDefaults.standard.stringArray(forKey: DevSession.recentsKey) ?? []

    private(set) var openPath: String?
    /// What the editor shows, which may be ahead of the disk.
    var text = ""
    private(set) var savedText = ""
    private(set) var unreadable = false
    private(set) var jump: DevJump?
    private(set) var errorLine: Int?

    /// The page in the Preview pane, while it's showing.
    private(set) var previewPath: String?
    private(set) var previewLoad = UUID()
    /// Gives the Preview the whole window, for playing.
    var previewFills = false
    private var previewRun: UUID?

    private(set) var messages: [DevMessage] = []
    private(set) var isWorking = false
    private(set) var stage: String?
    /// What the model is writing right now.
    private(set) var writing = ""
    var draft = ""

    private(set) var runs: [DevTerminalRun] = []
    var failureText: String?

    /// With the harness off, a request gets one reply from the model, saved as it came, which is what
    /// the agent gets compared with.
    var harnessOn = UserDefaults.standard.object(forKey: DevSession.harnessKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(harnessOn, forKey: Self.harnessKey) }
    }

    /// Every comparison made, newest first.
    private(set) var comparisons: [DevComparison] = DevCompare.load()
    /// The comparison on screen, while the Compare view is showing.
    var shownComparison: UUID?
    var showsCompare = false
    /// The side given the whole window, harness off (false) or on (true). Nil while both show.
    var compareFills: Bool?
    /// Whether one side of a comparison has the window, so nothing else shows.
    var compareFillsWindow: Bool { showsCompare && compareFills != nil && shownComparison != nil }
    /// The comparison being made right now.
    private(set) var comparing: DevComparison?
    /// Which side is being built: false for the harness off, true for on.
    private(set) var compareSide: Bool?
    private(set) var compareStage: String?
    private(set) var compareWriting = ""
    private(set) var compareSteps: [DevStep] = []
    private var compareTask: Task<Void, Never>?

    private let backends: BackendController
    private let settings: AppSettings
    private var process: DevProcess?
    private var agentTask: Task<Void, Never>?
    private var lastChanged: String?
    /// Whether the job in progress came from a Fix button in the Terminal.
    private var showsCheck = false
    private var lastCheck: (command: String, result: DevRunResult)?

    init(backends: BackendController, settings: AppSettings) {
        self.backends = backends
        self.settings = settings
        if isOn, let last = recents.first, FileManager.default.fileExists(atPath: last) { open(URL(fileURLWithPath: last)) }
    }

    var isDirty: Bool { openPath != nil && !unreadable && text != savedText }
    var isRunning: Bool { process != nil }
    var isBusy: Bool { isWorking || isRunning || isComparing }
    var isComparing: Bool { compareTask != nil }

    /// The agent and a program in the Terminal never run at once. A program in the real folder could be
    /// changing it while the agent saves, swapping a folder for a link just after it was checked.
    var canSend: Bool {
        project != nil && !isWorking && !isRunning && !isComparing && backends.status.isOnline && backends.selectedModel != nil && backends.activeTest == nil
    }

    /// A comparison needs no open project, since it makes folders of its own.
    var canCompare: Bool {
        !isWorking && !isRunning && !isComparing && backends.status.isOnline && backends.selectedModel != nil && backends.activeTest == nil
    }

    var testFiles: [String] {
        entries.filter { $0.isPython && ($0.name.hasPrefix("test_") || $0.name.hasSuffix("_test.py")) }.map(\.path)
    }

    /// Why the agent can't take a message, if it can't.
    var blockedReason: String? {
        if !backends.status.isOnline { return "Start \(backends.kind.displayName) to use the agent." }
        if backends.selectedModel == nil { return "Choose a model to use the agent." }
        if let test = backends.activeTest, !isWorking { return "\(test) is running." }
        if isRunning { return "Stop the program in the Terminal to use the agent." }
        return nil
    }

    // MARK: - The project

    /// Makes a folder for a new project and opens it.
    func newProject() {
        let panel = NSSavePanel()
        panel.title = "New Project"
        panel.prompt = "Create"
        panel.message = "Name a folder for the project. The agent and your programs can only change files inside it."
        panel.nameFieldLabel = "Project:"
        panel.nameFieldStringValue = "My App"
        panel.canCreateDirectories = true
        try? FileManager.default.createDirectory(at: DevCompare.projectsRoot, withIntermediateDirectories: true)
        panel.directoryURL = DevCompare.projectsRoot
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            showsCompare = false
            open(url)
        } catch {
            failureText = error.localizedDescription
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        panel.message = "Choose a project folder. The agent and your programs can only change files inside it."
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        save()
        stopAgent()
        stopRun()
        persist()
        closePreview()
        project = DevProject(root: url)
        entries = []
        openPath = nil
        text = ""
        savedText = ""
        errorLine = nil
        runs = []
        lastChanged = nil
        messages = loadMessages()
        recents = ([url.path] + recents.filter { $0 != url.path }).prefix(6).map { $0 }
        UserDefaults.standard.set(recents, forKey: Self.recentsKey)
        refresh()
        if let first = entries.first(where: { $0.name == "main.py" }) ?? entries.first(where: \.isPython) { openFile(first.path) }
    }

    func closeProject() {
        save()
        stopAgent()
        stopRun()
        closePreview()
        persist()
        project = nil
        entries = []
        openPath = nil
        messages = []
        runs = []
    }

    func refresh() {
        entries = project?.entries() ?? []
        if let openPath, !entries.contains(where: { $0.path == openPath }) {
            self.openPath = nil
            text = ""
            savedText = ""
        }
        if let previewPath, !entries.contains(where: { $0.path == previewPath }) { closePreview() }
    }

    /// Picks up changes made outside the app, without touching unsaved work.
    func refreshFromDisk() {
        refresh()
        guard let project, let openPath, !isDirty, let disk = project.read(openPath), disk != savedText else { return }
        text = disk
        savedText = disk
    }

    func revealInFinder(_ path: String? = nil) {
        guard let project else { return }
        let url = path.flatMap { try? project.url(for: $0) } ?? project.root
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Files

    func openFile(_ path: String, line: Int? = nil) {
        // The path may come from a traceback, which is a program's own text.
        guard let project, (try? project.url(for: path)) != nil, project.exists(path) else { return }
        if path != openPath {
            save()
            guard let disk = project.read(path) else {
                openPath = path
                unreadable = true
                text = ""
                savedText = ""
                return
            }
            unreadable = false
            openPath = path
            text = disk
            savedText = disk
            errorLine = nil
        }
        if let line {
            errorLine = line
            jump = DevJump(line: line)
        }
    }

    func save() {
        guard let project, let openPath, isDirty else { return }
        do {
            try project.write(text, to: openPath)
            savedText = text
        } catch {
            failureText = error.localizedDescription
        }
    }

    func newFile(named name: String) {
        guard let project else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let path = clean.contains(".") ? clean : clean + ".py"
        do {
            guard !project.exists(path) else {
                openFile(path)
                return
            }
            try project.write("", to: path)
            refresh()
            openFile(path)
        } catch {
            failureText = error.localizedDescription
        }
    }

    /// To the Trash, so a slip can be taken back.
    func trash(_ path: String) {
        guard let project, let url = try? project.url(for: path) else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            refresh()
        } catch {
            failureText = error.localizedDescription
        }
    }

    // MARK: - The Terminal

    /// Runs a file in the project itself, so anything it writes stays. The sandbox still holds it there.
    func run(_ path: String, arguments: [String] = []) {
        if DevWeb.isPage(path) {
            preview(path)
            return
        }
        if path == openPath { save() }
        start([path] + arguments, command: (["python", path] + arguments).joined(separator: " "))
    }

    func runOpenFile() {
        guard let openPath, openPath.hasSuffix(".py") || DevWeb.isPage(openPath) else { return }
        run(openPath)
    }

    /// Opens a page in the Preview pane, from the project as it is now. It can't change any files, so
    /// unlike a program this doesn't have to take turns with the agent.
    func preview(_ path: String) {
        guard let project, (try? project.url(for: path)) != nil, project.exists(path) else { return }
        save()
        previewPath = path
        previewLoad = UUID()
        let run = DevTerminalRun(command: "preview \(path)", arguments: [path], result: DevRunResult(output: "", exitCode: 0, seconds: 0), isPage: true)
        runs.append(run)
        if runs.count > Self.maxRuns { runs.removeFirst(runs.count - Self.maxRuns) }
        previewRun = run.id
    }

    func closePreview() {
        previewPath = nil
        previewFills = false
        previewRun = nil
    }

    /// What the page in Preview said, which is shown like a program's output. Everything in here comes
    /// from the page, so a file it names goes through the same guard as any other path.
    func pageSaid(_ message: DevPageHost.Message) {
        guard let index = runs.firstIndex(where: { $0.id == previewRun }), let path = previewPath else { return }
        switch message.kind {
        case .console:
            runs[index].output += message.text + "\n"
        case .resource:
            let name = DevWeb.path(of: message.text) ?? message.text
            runs[index].output += "Couldn't load \(name)\n"
            if runs[index].failure == nil {
                runs[index].failure = DevFailure(file: path, kind: "Resource", message: "Couldn't load \(name).", output: "")
                runs[index].result?.exitCode = 1
            }
        case .error:
            runs[index].output += message.text + (message.line.map { " (line \($0))" } ?? "") + "\n"
            if runs[index].failure == nil {
                let parts = message.text.groups(of: #"^(?:Uncaught )?(\w*Error): (.*)$"#)
                let file = message.file.flatMap { DevWeb.isWebFile($0) && (try? project?.url(for: $0)) != nil ? $0 : nil } ?? path
                runs[index].failure = DevFailure(file: file, line: message.line.flatMap { $0 > 0 ? $0 : nil }, kind: parts?[1] ?? "PageError", message: parts?[2] ?? message.text, output: String(message.text.suffix(500)))
                runs[index].result?.exitCode = 1
            }
        }
    }

    func pageCrashed() {
        pageSaid(.init(kind: .error, text: "The page crashed. It may have used too much memory."))
    }

    func runTests() {
        save()
        let tests = testFiles
        guard !tests.isEmpty else { return }
        start(DevRunner.testArguments(tests), command: "run tests: " + tests.joined(separator: " "))
    }

    /// Takes a line as a shell would, for the few forms this Terminal runs.
    func runCommand(_ line: String) {
        var words = Self.words(in: line)
        if let first = words.first, ["python", "python3"].contains(first) { words.removeFirst() }
        guard let file = words.first else { return }
        if DevWeb.isPage(file), project?.exists(file) == true {
            preview(file)
            return
        }
        guard file.hasSuffix(".py"), let project, project.read(file) != nil else {
            runs.append(DevTerminalRun(command: line, arguments: [], output: "This Terminal runs the project's Python files, as in: python main.py\n",
                                       result: DevRunResult(output: "", exitCode: 0, seconds: 0)))
            return
        }
        run(file, arguments: Array(words.dropFirst()))
    }

    static func words(in line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        for character in line {
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == " " {
                if !current.isEmpty { words.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private func start(_ arguments: [String], command: String) {
        guard let project else { return }
        guard !isWorking else {
            failureText = "The agent is working on this folder. You can run this when it's done."
            return
        }
        stopRun()
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        guard let process = DevProcess(arguments: arguments, in: project.root, limits: DevProcess.terminalLimits, onOutput: { continuation.yield($0) }) else {
            failureText = "Python isn't available. Install the Command Line Tools with: xcode-select --install"
            return
        }
        let run = DevTerminalRun(command: command, arguments: arguments)
        runs.append(run)
        if runs.count > Self.maxRuns { runs.removeFirst(runs.count - Self.maxRuns) }
        self.process = process
        let root = project.realPath + "/"
        let id = run.id
        Task { [weak self] in
            for await chunk in stream {
                self?.append(chunk.replacingOccurrences(of: root, with: ""), to: id)
            }
        }
        Task { [weak self] in
            var result = await process.run()
            continuation.finish()
            result.output = result.output.replacingOccurrences(of: root, with: "")
            self?.finished(result, id: id, process: process)
        }
    }

    private func append(_ chunk: String, to id: UUID) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        runs[index].output += Self.plain(chunk)
    }

    private func finished(_ result: DevRunResult, id: UUID, process finished: DevProcess) {
        if process === finished { process = nil }
        refresh()
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        runs[index].result = result
        guard !result.succeeded, !result.stoppedByUser else {
            errorLine = nil
            return
        }
        let failure = DevFailure.parse(result.output) ?? .ending(result)
        runs[index].failure = failure
        if failure.file == openPath { errorLine = failure.line }
    }

    /// Terminal colour codes mean nothing here, and a carriage return would overwrite the line.
    static func plain(_ text: String) -> String {
        var text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if text.contains("\u{1B}") {
            text = text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
        }
        return text
    }

    func sendInput(_ line: String) {
        guard let process, let index = runs.indices.last else { return }
        process.send(line + "\n")
        runs[index].output += line + "\n"
    }

    func stopRun() {
        process?.stop()
    }

    func clearTerminal() {
        // The open page keeps its entry, or its later errors would have nowhere to go.
        runs.removeAll { !$0.isRunning && $0.id != previewRun }
        if let index = runs.firstIndex(where: { $0.id == previewRun }) { runs[index].output = "" }
    }

    // MARK: - The agent

    func send(_ message: String? = nil, failing run: DevTerminalRun? = nil) {
        let request = (message ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, canSend, let project, let model = backends.selectedModel else { return }
        draft = ""
        save()
        messages.append(DevMessage(isUser: true, text: request))
        let reply = DevMessage(isUser: false, text: "")
        messages.append(reply)
        isWorking = true
        stage = "Starting"
        writing = ""
        backends.activeTest = "Dev agent"

        let command = run.flatMap { $0.arguments.first == "-c" ? nil : $0.arguments }
        showsCheck = run != nil
        lastCheck = nil
        var job = DevJob(request: request, openFile: openPath, lastChanged: lastChanged, failure: run?.failure, command: command)
        job.history = messages.filter { !$0.isUser && !$0.text.isEmpty }.suffix(2).map { String($0.text.prefix(120)) }
        let id = reply.id
        let backends = backends
        let started = Date()
        let harness = harnessOn
        if let index = messages.firstIndex(where: { $0.id == id }) { messages[index].harness = harness }
        agentTask = Task { [weak self] in
            let details = await backends.capabilities(of: model)
            let setup = DevSetup(model: model.id, backend: backends.backend, context: details.context,
                                 think: backends.kind.supportsThinkingControl && details.supportsThinking ? false : nil)
            let (events, continuation) = AsyncStream.makeStream(of: DevEvent.self, bufferingPolicy: .bufferingNewest(400))
            let consumer = Task { [weak self] in
                for await event in events { self?.handle(event, reply: id) }
            }
            let worker = Task.detached {
                guard harness else {
                    return await DevOneReply.run(request: job.request, project: project, setup: setup, failure: job.failure, emit: { continuation.yield($0) })
                }
                return await DevAgent(project: project, setup: setup, emit: { continuation.yield($0) }).run(job)
            }
            let outcome = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            continuation.finish()
            await consumer.value
            self?.finish(outcome, reply: id, seconds: Date().timeIntervalSince(started))
        }
    }

    private func handle(_ event: DevEvent, reply id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        switch event {
        case .stage(let text):
            stage = text
            writing = ""
            if messages[index].steps.last?.text != text { messages[index].steps.append(DevStep(kind: .stage, text: text)) }
        case .writing(let text):
            writing = text
        case .note(let text):
            messages[index].steps.append(DevStep(kind: .note, text: text))
        case .ran(let command, let result):
            messages[index].steps.append(DevStep(kind: .run, text: command, output: String(Self.plain(result.output).suffix(4_000)), passed: result.succeeded))
            lastCheck = (command, result)
        case .answer(let text):
            messages[index].text = text
        }
    }

    private func finish(_ outcome: DevOutcome, reply id: UUID, seconds: Double) {
        isWorking = false
        stage = nil
        writing = ""
        agentTask = nil
        if backends.activeTest == "Dev agent" { backends.activeTest = nil }
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = outcome.text
        messages[index].changes = outcome.changes
        messages[index].worked = outcome.worked
        messages[index].failure = outcome.failure
        messages[index].seconds = seconds
        messages[index].calls = outcome.calls
        if let last = outcome.changes.last { lastChanged = last.path }
        refresh()
        if let change = outcome.changes.first(where: { $0.path == openPath }) ?? outcome.changes.last {
            reload(change.path)
        }
        persist()
        // A page can't touch any files, so unlike a program it's safe to show it straight away.
        if let page = outcome.page {
            preview(page)
        } else if outcome.worked == true, showsCheck, let lastCheck {
            // A failed run stays on screen, so show the agent's own run of it. Running it here instead
            // would start code the model wrote, in the real folder, without anyone pressing Run.
            runs.append(DevTerminalRun(command: "\(lastCheck.command)   (the agent's check, in a copy)", arguments: [lastCheck.command],
                                       output: Self.plain(lastCheck.result.output), result: lastCheck.result))
        }
        showsCheck = false
        lastCheck = nil
    }

    /// Shows a file as it now is on disk.
    private func reload(_ path: String) {
        guard let project, let disk = project.read(path) else { return }
        openPath = path
        unreadable = false
        text = disk
        savedText = disk
        errorLine = nil
    }

    func stopAgent() {
        agentTask?.cancel()
    }

    /// Asks the agent to fix what a Terminal run showed.
    func fix(_ run: DevTerminalRun) {
        guard let failure = run.failure else { return }
        send("Fix this error: \(failure.title)", failing: run)
    }

    /// Whether a reply's changes can still be taken back. Not if the files have changed since.
    func canUndo(_ message: DevMessage) -> Bool {
        guard let project, !message.undone, !message.changes.isEmpty else { return false }
        return message.changes.allSatisfy { project.read($0.path) == $0.after }
    }

    func undo(_ message: DevMessage) {
        // Saved first, so unsaved typing counts as a change and stops the undo, rather than getting lost.
        save()
        guard let project, canUndo(message), let index = messages.firstIndex(where: { $0.id == message.id }) else {
            if !message.undone { failureText = "These files have changed since, so Undo can't put them back." }
            return
        }
        do {
            for change in message.changes.reversed() {
                if let before = change.before {
                    try project.write(before, to: change.path)
                } else {
                    try project.remove(change.path)
                }
            }
            messages[index].undone = true
            refresh()
            if let path = openPath { reload(path) }
            persist()
        } catch {
            failureText = error.localizedDescription
        }
    }

    func clearConversation() {
        messages = []
        lastChanged = nil
        persist()
    }

    #if DEBUG
    func restoreForChecks(_ list: [DevMessage]) { messages = list }
    #endif

    // MARK: - Comparing

    /// The comparison the Compare view shows.
    var shown: DevComparison? {
        if let comparing, comparing.id == shownComparison { return comparing }
        return comparisons.first { $0.id == shownComparison } ?? comparing ?? comparisons.first
    }

    /// Builds the same request twice on the same model, first with the harness off and then on, each in a
    /// new folder, and scores both with the same checks. The model is loaded before either clock starts.
    func compare(_ message: String? = nil) {
        let request = (message ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, canCompare, let model = backends.selectedModel else { return }
        save()
        let date = Date()
        let parent = DevCompare.comparisonsRoot.appendingPathComponent(DevCompare.folderName(for: request, date: date), isDirectory: true)
        let off = parent.appendingPathComponent("harness-off", isDirectory: true)
        let on = parent.appendingPathComponent("harness-on", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: off, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: on, withIntermediateDirectories: true)
        } catch {
            failureText = "Couldn't make the folders for the comparison: \(error.localizedDescription)"
            return
        }
        if message == nil { draft = "" }
        var record = DevComparison(request: request, date: date, model: model.id, framework: backends.kind.displayName, context: 0, folder: parent.path,
                                   off: DevCompareSide(folder: off.path, harness: false), on: DevCompareSide(folder: on.path, harness: true))
        comparing = record
        shownComparison = record.id
        showsCompare = true
        compareFills = nil
        compareSide = nil
        compareStage = "Loading the model"
        compareWriting = ""
        compareSteps = []
        backends.activeTest = "Dev compare"
        let backends = backends
        compareTask = Task { [weak self] in
            let details = await backends.capabilities(of: model)
            let setup = DevSetup(model: model.id, backend: backends.backend, context: details.context,
                                 think: backends.kind.supportsThinkingControl && details.supportsThinking ? false : nil)
            record.context = details.context
            self?.comparing = record
            if backends.settings.unloadOnSwitch { await backends.freeOtherFrameworks() }
            await DevCompare.warmUp(setup)
            for harness in [false, true] {
                if Task.isCancelled { break }
                self?.compareSide = harness
                self?.compareSteps = []
                self?.compareWriting = ""
                let folder = harness ? on : off
                let started = Date()
                let outcome = await Self.streamed(onEvent: { self?.compareEvent($0) }) { emit in
                    let project = DevProject(root: folder)
                    if harness { return await DevAgent(project: project, setup: setup, emit: emit).run(DevJob(request: request)) }
                    return await DevOneReply.run(request: request, project: project, setup: setup, emit: emit)
                }
                var side = harness ? record.on : record.off
                side.seconds = Date().timeIntervalSince(started)
                side.calls = outcome.calls
                side.text = outcome.text
                side.stopped = outcome.stopped
                if !outcome.stopped {
                    self?.compareStage = "Checking what it made"
                    let graded = await DevCompare.grade(folder: folder, request: request, picture: URL(fileURLWithPath: side.picture))
                    side.page = graded.page
                    side.files = graded.files
                    side.score = graded.score
                }
                side.finished = !outcome.stopped
                if harness { record.on = side } else { record.off = side }
                self?.comparing = record
            }
            self?.finishCompare(record)
        }
    }

    /// Runs one side's work away from the main thread and passes its events back here.
    private static func streamed(onEvent: @escaping @MainActor (DevEvent) -> Void,
                                 work: @escaping @Sendable (@escaping @Sendable (DevEvent) -> Void) async -> DevOutcome) async -> DevOutcome {
        let (events, continuation) = AsyncStream.makeStream(of: DevEvent.self, bufferingPolicy: .bufferingNewest(400))
        let consumer = Task { @MainActor in
            for await event in events { onEvent(event) }
        }
        let worker = Task.detached { await work { continuation.yield($0) } }
        let outcome = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        continuation.finish()
        await consumer.value
        return outcome
    }

    private func compareEvent(_ event: DevEvent) {
        switch event {
        case .stage(let text):
            compareStage = text
            compareWriting = ""
            if compareSteps.last?.text != text { compareSteps.append(DevStep(kind: .stage, text: text)) }
        case .writing(let text):
            compareWriting = text
        case .note(let text):
            compareSteps.append(DevStep(kind: .note, text: text))
        case .ran(let command, let result):
            compareSteps.append(DevStep(kind: .run, text: command, output: String(Self.plain(result.output).suffix(4_000)), passed: result.succeeded))
        case .answer:
            break
        }
    }

    private func finishCompare(_ record: DevComparison) {
        compareTask = nil
        compareSide = nil
        compareStage = nil
        compareWriting = ""
        if backends.activeTest == "Dev compare" { backends.activeTest = nil }
        comparing = nil
        comparisons.removeAll { $0.id == record.id }
        comparisons.insert(record, at: 0)
        DevCompare.save(comparisons)
    }

    func stopCompare() {
        compareTask?.cancel()
    }

    func showComparison(_ id: UUID) {
        shownComparison = id
        showsCompare = true
        compareFills = nil
    }

    func closeCompare() {
        showsCompare = false
        compareFills = nil
    }

    /// Takes a comparison off the list. Its folders stay where they are.
    func removeComparison(_ id: UUID) {
        guard comparing?.id != id else { return }
        comparisons.removeAll { $0.id == id }
        DevCompare.save(comparisons)
        if shownComparison == id { shownComparison = comparisons.first?.id }
        if comparisons.isEmpty, comparing == nil { showsCompare = false }
    }

    /// Opens one side's folder as the project, to look at its files or keep working on it.
    func openSide(_ side: DevCompareSide) {
        guard !isComparing || comparing?.on.folder != side.folder && comparing?.off.folder != side.folder else { return }
        showsCompare = false
        compareFills = nil
        open(URL(fileURLWithPath: side.folder))
    }

    func revealComparison(_ comparison: DevComparison) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: comparison.folder)])
    }

    // MARK: - Saving

    private var conversationFile: URL? {
        guard let project else { return nil }
        let digest = SHA256.hash(data: Data(project.root.path.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
        return ConversationStore.directory.appendingPathComponent("Dev", isDirectory: true).appendingPathComponent("\(digest).json")
    }

    private func loadMessages() -> [DevMessage] {
        guard let file = conversationFile, let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([DevMessage].self, from: data)) ?? []
    }

    func persist() {
        guard let file = conversationFile, let data = try? JSONEncoder().encode(messages.suffix(80)) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// Nothing the app started should outlive it.
    func shutDown() {
        save()
        stopAgent()
        stopCompare()
        stopRun()
        persist()
    }
}
