import Darwin
import Foundation

/// The model and how much it can hold.
struct DevSetup: @unchecked Sendable {
    var model: String
    var backend: LLMBackend
    var context: Int
    var think: Bool?
    /// Which coding harness does the work.
    var version = DevHarnessVersion.v1
    /// Opens a page out of sight and tries it.
    var pageCheck: @Sendable (_ folder: URL, _ page: String, _ kind: DevPageKind) async -> DevPageReport = { folder, page, kind in
        await DevPageCheck.run(folder: folder, page: page, kind: kind)
    }
}

/// What someone asked for.
struct DevJob: Sendable {
    var request: String
    var openFile: String?
    /// The file the last reply changed, for "now make it…".
    var lastChanged: String?
    /// The failed run behind a Fix button.
    var failure: DevFailure?
    var command: [String]?
    /// One line for each of the last few things done here.
    var history: [String] = []
}

enum DevEvent: Sendable {
    case stage(String)
    /// Everything the model has written so far at this step.
    case writing(String)
    /// The harness ran something, with the command as a person would type it.
    case ran(String, DevRunResult)
    case note(String)
    /// The text of a plain answer so far.
    case answer(String)
}

struct DevOutcome: Sendable {
    var text: String
    var changes: [DevChange] = []
    /// Nil for a plain answer.
    var worked: Bool?
    var failure: DevFailure?
    var stopped = false
    var rounds = 0
    /// A page that's ready to look at.
    var page: String?
    /// How many times the model was asked something.
    var calls = 0
}

/// The coding harness. A small model can't drive a loop of tools by itself: it loses the thread and
/// forgets what it did. So code runs the loop, and each call gives the model one small job, with only
/// what that job needs. Code picks the file, fits the reply into it, runs it and reads the traceback.
/// Nothing reaches the project until the end, and every run happens in a throwaway copy, so
/// model-written code that deletes things only deletes a copy.
final class DevAgent: @unchecked Sendable {
    /// Goes for a fix at most this many times.
    static let maxRounds = 6
    /// How often one failure gets tried before it counts as out of reach.
    static let maxRepeats = 3
    /// Past this a file is edited a function at a time. Output tokens are the slow part, and
    /// retyping a long file is where a small model starts to drop things.
    static let wholeFileTokens = 1_200
    /// What `input()` gets during the harness's runs, so a menu or guessing game gets somewhere: the
    /// answers the program itself checks for, a few rounds of them, then some numbers. Plain numbers
    /// alone would only ever reach its "invalid choice" branch.
    static func sampleInput(for source: String?) -> String {
        let numbers = (1...10).map(String.init)
        guard let source else { return numbers.joined(separator: "\n") + "\n" }
        var words: [String] = []
        let quoted = #"["']([\w -]{1,20})["']"#
        func collect(_ pattern: String, from text: String) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let word = String(text[range])
                if !word.contains("__"), !words.contains(word), !["q", "n", "no", "quit", "exit", "stop", "end", "bye", "x"].contains(word.lowercased()) { words.append(word) }
            }
        }
        collect("==\\s*" + quoted, from: source)
        if let lists = try? NSRegularExpression(pattern: #"\bin\s*[\[\(\{]([^\]\)\}]*)[\]\)\}]"#) {
            for match in lists.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                if let range = Range(match.range(at: 1), in: source) { collect(quoted, from: String(source[range])) }
            }
        }
        let rounds = Array(repeating: Array(words.prefix(10)), count: words.isEmpty ? 0 : 6).flatMap { $0 }
        return (rounds + numbers).joined(separator: "\n") + "\n"
    }

    /// The line that shows a game going nowhere: moves went in, and everything with a number in it, such
    /// as the score, came out the same every time. Nil if anything changed.
    static func stuckLine(in output: String) -> String? {
        // The traceback from running out of test input has line numbers of its own.
        let played = output.components(separatedBy: "Traceback (most recent call last)").first ?? output
        let lines = played.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.contains(where: \.isNumber) }
        guard lines.count >= 12, let first = lines.first else { return nil }
        let counts = Dictionary(grouping: lines, by: { $0 }).mapValues(\.count)
        return counts.values.allSatisfy { $0 >= 12 } ? first : nil
    }

    enum Intent { case ask, change }

    enum Verdict {
        case worked(String)
        /// It ran well until it asked for more than anyone had typed.
        case needsInput(String)
        case failed(DevFailure)
        /// Nothing in the job could be run, such as a README.
        case notRun
    }

    struct Reply {
        var text = ""
        var cutOff = false
        var error: String?
    }

    let project: DevProject
    let setup: DevSetup
    let emit: @Sendable (DevEvent) -> Void
    /// What the agent has written so far, by path, in the order it wrote them.
    var versions: [String: String] = [:]
    var order: [String] = []
    /// Each file as it was before this job. Nil for a file that didn't exist.
    var originals: [String: String?] = [:]
    var backendError: String?
    /// Tests taken out of a new test file because they didn't hold, for the report.
    private var dropped: [String] = []
    /// Why the work didn't reach the project, when something stopped it at the end.
    private var saveProblem: String?
    /// Whether this job wants something to look at, which takes a display programs don't have here.
    var wantsDisplay = false
    /// The page tried most recently, when the job is about one.
    var triedPage: String?
    /// How many times the model has been asked something in this job.
    var calls = 0
    /// Whether this job built a new app, which gets used as well as looked at.
    var builtApp = false
    /// Notes already shown, so a retry doesn't repeat them.
    var noted: Set<String> = []
    /// v2: what the last try of the page showed. Nil when the try never got as far as opening it.
    var lastReport: DevPageReport?
    /// v2: the attempt that got furthest so far.
    var best: (score: Int, versions: [String: String], order: [String], verdict: Verdict)?
    /// v2: the things a first use would show that have had their one try at a fix.
    var raisedKeys: Set<String> = []
    /// v2: the ones that try didn't cure, for the report.
    var unresolved: [String] = []

    init(project: DevProject, setup: DevSetup, emit: @escaping @Sendable (DevEvent) -> Void = { _ in }) {
        self.project = project
        self.setup = setup
        self.emit = emit
    }

    static func tokens(_ text: String) -> Int { text.count * 10 / 35 + 1 }

    private static var languageName: String {
        CodeRunner.pythonRuntime?.home.groups(of: #"(\d\.\d+)$"#).map { "Python \($0[1])" } ?? "Python 3"
    }

    // MARK: - What was asked

    static func intent(of job: DevJob) -> Intent {
        if job.failure != nil { return .change }
        let words = job.request.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard let first = words.first else { return .ask }
        if ["what", "why", "how", "where", "which", "who", "when", "explain", "describe", "summarize", "summarise", "tell"].contains(first) {
            return .ask
        }
        let building: Set<String> = ["create", "make", "write", "add", "build", "implement", "fix", "change", "update", "rename", "remove", "delete",
                                     "refactor", "rewrite", "improve", "generate", "convert", "replace", "debug", "handle", "use", "support"]
        if ["does", "do", "did", "is", "are", "should"].contains(first) { return .ask }
        if ["can", "could", "would", "will"].contains(first), building.isDisjoint(with: words) { return .ask }
        return .change
    }

    func run(_ job: DevJob) async -> DevOutcome {
        var outcome: DevOutcome
        switch Self.intent(of: job) {
        case .ask: outcome = await answer(job)
        case .change: outcome = await change(job)
        }
        outcome.calls = calls
        return outcome
    }

    // MARK: - Questions

    private func answer(_ job: DevJob) async -> DevOutcome {
        emit(.stage("Reading the project"))
        var parts = [await summary(excluding: nil, budget: setup.context / 8)]
        let named = await namedFiles(in: job.request) + (job.openFile.map { [$0] } ?? [])
        if let path = named.first(where: { project.read($0) != nil }), let text = project.read(path) {
            parts.append("\(path):\n```\n\(String(text.prefix(setup.context * 2)))\n```")
        }
        if !job.history.isEmpty { parts.append("Recent work:\n" + job.history.suffix(3).joined(separator: "\n")) }
        parts.append("Question: \(job.request)")
        emit(.stage("Answering"))
        let system = "You help someone with their Python project. Answer briefly, in plain words, from the files you're shown. If they don't hold the answer, say so."
        let reply = await complete(system: system, user: parts.joined(separator: "\n\n"), temperature: 0.3, limit: 1_024, quiet: true) { [emit] partial in
            emit(.answer(partial))
        }
        if Task.isCancelled { return DevOutcome(text: reply.text.isEmpty ? "Stopped." : reply.text, stopped: true) }
        if let error = reply.error { return DevOutcome(text: "The model couldn't answer: \(error)") }
        return DevOutcome(text: reply.text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Changes

    /// Asked for a game, a model reaches for pygame. Told that's missing and nothing else, it keeps the
    /// shape of the program and fakes the rest: a pretend event loop that quits at once, and no game. So
    /// jobs like this hear up front what can really work here.
    static func wantsDisplay(_ request: String) -> Bool {
        request.lowercased().matches(#"\b(games?|gui|windows?|graphics?|graphical|animation|animated|canvas|pygame|tkinter|turtle|sprites?|shooter|shooting|plot|chart|draw)\b"#)
    }

    static func isGame(_ request: String) -> Bool {
        request.lowercased().matches(#"\b(games?|shooter|shooting|shoot|play)\b"#)
    }

    /// Whether this is better made as a web page, which can show graphics here. Saying Python or
    /// asking for text keeps it a program.
    static func wantsPage(_ request: String) -> Bool {
        let lower = request.lowercased()
        // An app with nothing to say it's for the terminal is something to see and click, which here is a page.
        let isPage = wantsDisplay(lower) || lower.matches(#"\b(web ?page|website|web ?app|html|css|javascript|landing page|dashboard|user interface|ui|portfolio)\b|\bapps?\b(?!\.\w)"#)
        return isPage && !lower.matches(#"\b(python|terminal|text[- ]based|text game|text version|command line|cli|console|pygame|tkinter|turtle)\b"#)
    }

    private func change(_ job: DevJob) async -> DevOutcome {
        wantsDisplay = job.failure == nil && Self.wantsDisplay(job.request)
        emit(.stage("Choosing the files"))
        let targets = await pickTargets(job).filter { (try? project.url(for: $0)) != nil }
        guard !targets.isEmpty else { return DevOutcome(text: "That isn't a file inside this project, so nothing changed.", worked: false) }
        // No text to read isn't the same as no file: it would count as new, and get replaced.
        if let unreadable = targets.first(where: { project.exists($0) && project.read($0) == nil }) {
            return DevOutcome(text: "\(unreadable) isn't text, or it's over 2 MB, so I left it alone.", worked: false)
        }
        for path in targets where originals[path] == nil { originals[path] = .some(project.read(path)) }
        // A script can be edited a function at a time. A page or a style sheet has to come back whole.
        if let long = targets.first(where: { DevWeb.isWebFile($0) && !$0.hasSuffix(".js") && project.read($0).map { Self.tokens($0) * 2 + 500 > setup.context } == true }) {
            return DevOutcome(text: "\(long) is too long to rewrite in this context window, so nothing changed. Try a larger context window.", worked: false)
        }

        // A new page that isn't a game is built as an app, a file at a time.
        if job.failure == nil, targets.count == 1, let page = targets.first, DevWeb.isPage(page), !project.exists(page), !isGameRequest(job.request) {
            return await buildApp(page: page, job: job)
        }

        if job.failure == nil, let rename = Self.renaming(job.request) {
            return await renameEverywhere(rename, job: job)
        }

        if let failure = job.failure, let path = targets.first {
            // The file already exists and already fails, so this goes straight to the fixing.
            order.append(path)
            return await finish(job, verdict: .failed(failure), rounds: 0)
        }

        for path in await webGroup(targets, job: job) {
            guard await author(path, job: job) else {
                if Task.isCancelled { return DevOutcome(text: "Stopped. Nothing changed.", stopped: true) }
                if let backendError { return DevOutcome(text: "The model couldn't answer: \(backendError)") }
                return DevOutcome(text: "The model didn't write usable code for \(path), so nothing changed. Try a smaller step, or a larger context window.", worked: false)
            }
        }
        let verdict = await verify(job)
        return await finish(job, verdict: verdict, rounds: 0)
    }

    /// The fixing loop, which ends with something saved and a report written by code rather than by the
    /// model. A model will say it worked either way.
    func finish(_ job: DevJob, verdict first: Verdict, rounds: Int) async -> DevOutcome {
        var verdict = first
        var round = 0
        var seen: [String: Int] = [:]
        defer { dropped = [] }
        noteAttempt(verdict)
        repeat {
            while case .failed(let failure) = verdict, round < Self.maxRounds {
                if Task.isCancelled || failure.isSandboxLimit || seen[failure.signature, default: 0] >= Self.maxRepeats { break }
                round += 1
                seen[failure.signature, default: 0] += 1
                emit(.note(failure.title))
                guard let path = target(of: failure, job: job) else { break }
                guard let fixed = await fix(path, failure: failure, job: job, round: round, repeats: seen[failure.signature] ?? 1) else {
                    if backendError != nil { break }
                    continue
                }
                record(fixed, for: path)
                verdict = await verify(job)
                noteAttempt(verdict)
            }
            if Task.isCancelled || backendError != nil { break }
            if case .failed = verdict { break }
            guard job.failure == nil, round < Self.maxRounds, let problem = await tryOut(job) else { break }
            verdict = .failed(problem)
            // What looked like the best attempt has just been shown not to work, so it's no longer one to go back to.
            best = nil
            noteAttempt(verdict)
        } while true
        if Task.isCancelled { return DevOutcome(text: "Stopped. Nothing changed.", stopped: true, rounds: round) }
        if let backendError, versions.isEmpty { return DevOutcome(text: "The model couldn't answer: \(backendError)", worked: false) }
        verdict = await improve(job, verdict, round: &round)
        if Task.isCancelled { return DevOutcome(text: "Stopped. Nothing changed.", stopped: true, rounds: round) }
        verdict = bestOf(verdict)

        switch verdict {
        case .worked(let output):
            let changes = save()
            if let page = triedPage {
                let left = unresolved.isEmpty ? "" : " Not fixed: \(unresolved.joined(separator: "; "))."
                return DevOutcome(text: report(changes, ending: "It loads without errors. \(output)\(left)"), changes: changes, worked: saveProblem == nil, rounds: round, page: saveProblem == nil ? page : nil)
            }
            let ending = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "It ran without errors and printed nothing." : "It ran without errors."
            return DevOutcome(text: report(changes, ending: ending + textOnlyNote), changes: changes, worked: saveProblem == nil, rounds: round)
        case .needsInput:
            let changes = save()
            let ending = wantsDisplay ? "It ran until it asked for more input than I could give, so press Run and type your moves in the Terminal."
                                      : "It ran until it asked for more input than I could give, so try it yourself in the Terminal."
            return DevOutcome(text: report(changes, ending: ending + textOnlyNote), changes: changes, worked: saveProblem == nil, rounds: round)
        case .notRun:
            let changes = save()
            return DevOutcome(text: report(changes, ending: "There was nothing to run."), changes: changes, rounds: round)
        case .failed(let failure):
            let fixes = "\(round) \(round == 1 ? "fix" : "fixes")"
            let blocked = failure.isSandboxLimit
            // Code you already have is only replaced by code that runs, unless you asked to fix a failure.
            // Whether the old code worked can't be known for sure, since it may need input or arguments.
            let replacesCode = order.contains { path in (originals[path] ?? nil) != nil && versions[path] != nil && versions[path] != originals[path] ?? nil }
            if job.failure == nil, replacesCode {
                let reason = blocked ? "It needs something the sandbox blocks: the network, or files outside this folder. \(failure.title)"
                                     : "I couldn't get this to work after \(fixes). The last error was \(failure.title)."
                return DevOutcome(text: "Nothing changed. \(reason)", worked: false, failure: failure, rounds: round)
            }
            let changes = save()
            let ending = blocked ? "It needs something the sandbox blocks: the network, or files outside this folder. \(failure.title)"
                                 : "It still fails after \(fixes): \(failure.title)."
            return DevOutcome(text: report(changes, ending: ending), changes: changes, worked: false, failure: failure, rounds: round, page: changes.isEmpty ? nil : triedPage)
        }
    }

    // MARK: - Trying it out

    /// A clean run only shows a program doesn't crash when started plainly, so this checks what code can
    /// check: the commands the request spells out, in one folder so that each sees what the last one saved,
    /// and whether a program asked to print anything did. There's no model in this on purpose. Asked to
    /// judge its own work, the 1.7B model got 6 of 9 right, and a review after every run took four times
    /// as long and scored no better: 20 of 24 tasks in 356 seconds, against 21 in 87 without. Nil if it passes.
    private func tryOut(_ job: DevJob) async -> DevFailure? {
        guard let path = order.last(where: { isPython($0) && !isTest($0) }), let code = source(path), let folder = workingCopy() else { return nil }
        defer { try? FileManager.default.removeItem(at: folder) }
        if Self.isGame(job.request) {
            guard versions.values.contains(where: { $0.contains("input(") }) else {
                return DevFailure(file: path, kind: "Output", message: "It's a game, but it never asks the player for anything.", output: "")
            }
            if let command = await entries(job).first, case .needsInput(let output) = await execute(command, label: "", in: folder, quiet: true),
               let line = Self.stuckLine(in: output) {
                return DevFailure(file: path, kind: "Output", message: "Nothing changes as you play: after many moves it still says \"\(line.prefix(80))\".", output: String(output.suffix(500)))
            }
        }
        let commands = Self.commands(in: job.request).filter { ($0.first.map { try? project.url(for: $0) } ?? nil) != nil }
        if commands.isEmpty {
            // A program should show something. A file of functions doesn't have to, unless it was asked to.
            let asked = job.request.lowercased().matches(#"\b(print|prints|printing|display|displays|show|shows)\b"#)
            if !asked, await !DevPython.outline(code).hasMain { return nil }
            return await silence(job, path: path, folder: folder)
        }
        emit(.stage("Trying the commands you gave"))
        for arguments in commands {
            if case .failed(let failure) = await execute(arguments, label: "python " + arguments.joined(separator: " "), in: folder) { return failure }
        }
        return nil
    }

    /// A failure if every program ran and left nothing to see: no output, and no file written. Only
    /// silence from all of them counts, since a helper file has nothing to print.
    private func silence(_ job: DevJob, path: String, folder: URL) async -> DevFailure? {
        let before = Self.files(in: folder)
        for command in await entries(job) {
            guard case .worked(let output) = await execute(command, label: "", in: folder, quiet: true),
                  output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        }
        guard Self.files(in: folder) == before else { return nil }
        return DevFailure(file: path, kind: "Output", message: "It ran and ended at once, showing nothing.", output: "")
    }

    /// Every file in a folder, with what tells whether it changed.
    private static func files(in folder: URL) -> [String: String] {
        var found: [String: String] = [:]
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return [:] }
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            found[url.path] = "\(values.fileSize ?? 0) \(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }
        return found
    }

    /// The commands a request spells out, such as 'python todo.py add some text'. A lone capital or a
    /// <placeholder> stands for a value, so it becomes one.
    static func commands(in request: String) -> [[String]] {
        var commands: [[String]] = []
        let regex = try? NSRegularExpression(pattern: "python3? +(\\S+\\.py)([^'\"`\\n,;]*)")
        for match in regex?.matches(in: request, range: NSRange(request.startIndex..., in: request)) ?? [] {
            guard let file = Range(match.range(at: 1), in: request), let rest = Range(match.range(at: 2), in: request) else { continue }
            let words = request[rest].split(separator: " ").map { word -> String in
                if word.count == 1, word.first?.isUppercase == true { return "1" }
                return word.hasPrefix("<") ? "sample" : String(word)
            }
            commands.append([String(request[file])] + words)
        }
        return Array(commands.prefix(5))
    }

    static func renaming(_ request: String) -> (from: String, to: String)? {
        guard let parts = request.groups(of: #"(?i)^\W*(?:please\s+)?rename\s+(?:the\s+)?(?:function\s+|class\s+|method\s+|variable\s+)?`?(\w+)`?\s+to\s+`?(\w+)`?"#) else { return nil }
        return (parts[1], parts[2])
    }

    /// A rename is exact work that a model does slowly and code does perfectly, in every file at once.
    private func renameEverywhere(_ rename: (from: String, to: String), job: DevJob) async -> DevOutcome {
        emit(.stage("Renaming \(rename.from)"))
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: rename.from))\\b"
        for path in project.pythonFiles {
            guard let text = project.read(path), text.matches(pattern) else { continue }
            originals[path] = .some(text)
            record(text.replacingOccurrences(of: pattern, with: rename.to, options: .regularExpression), for: path)
        }
        guard !order.isEmpty else { return DevOutcome(text: "I couldn't find \(rename.from) in any Python file, so nothing changed.", worked: false) }
        return await finish(job, verdict: await verify(job), rounds: 0)
    }

    /// Said whenever the result isn't quite what was asked for, so it doesn't pass for the real thing.
    private var textOnlyNote: String {
        wantsDisplay && triedPage == nil ? " Programs here can't open a window or show graphics, so this is a text version." : ""
    }

    private func report(_ changes: [DevChange], ending: String) -> String {
        guard !changes.isEmpty else { return saveProblem ?? "Nothing needed changing. \(ending)" }
        let ending = dropped.isEmpty ? ending : ending + " " + dropped.joined(separator: " ")
        let lines = changes.map { change -> String in
            let size = change.after.split(separator: "\n", omittingEmptySubsequences: false).count
            return change.isNew ? "Created \(change.path) (\(size) lines)." : "Updated \(change.path) (+\(change.counts.added) −\(change.counts.removed))."
        }
        return (lines + [ending]).joined(separator: " ")
    }

    func record(_ text: String, for path: String) {
        guard (try? project.url(for: path)) != nil else { return }
        if !order.contains(path) { order.append(path) }
        versions[path] = text
    }

    func source(_ path: String) -> String? { versions[path] ?? project.read(path) }

    func isPython(_ path: String) -> Bool { path.hasSuffix(".py") }

    private func isTest(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return isPython(path) && (name.hasPrefix("test_") || name.hasSuffix("_test.py"))
    }

    /// Writes the results to the project, all of them or none, since half a change is a mix nothing has
    /// tested. A file that changed under the agent keeps those changes.
    private func save() -> [DevChange] {
        var changes: [DevChange] = []
        for path in order {
            guard let after = versions[path] else { continue }
            let before = originals[path] ?? nil
            if before != after { changes.append(DevChange(path: path, before: before, after: after)) }
        }
        for change in changes where project.read(change.path) != change.before || (change.before == nil && project.exists(change.path)) {
            saveProblem = "\(change.path) changed while I was working, so nothing was saved."
            emit(.note(saveProblem ?? ""))
            return []
        }
        var saved: [DevChange] = []
        for change in changes {
            do {
                try project.write(change.after, to: change.path)
                saved.append(change)
            } catch {
                for done in saved.reversed() {
                    if let before = done.before { try? project.write(before, to: done.path) } else { try? project.remove(done.path) }
                }
                saveProblem = "Couldn't save \(change.path), so nothing was saved: \(error.localizedDescription)"
                return []
            }
        }
        return saved
    }

    /// One function or class of a file, as far as the file has that many lines. The line numbers are
    /// Python's, which also counts a lone carriage return as a line.
    private func text(of definition: DevPython.Definition, in lines: [String]) -> String {
        guard definition.start >= 1, definition.start <= lines.count else { return "" }
        return lines[(definition.start - 1)..<min(max(definition.end, definition.start), lines.count)].joined(separator: "\n")
    }

    // MARK: - Choosing files

    private static let dataFiles = #"[\w./-]+\.(?:py|txt|md|json|csv|toml|ya?ml|html|css|js|ini|cfg|sql)\b"#

    /// File names the request spells out or clearly means, which exist or could.
    private func namedFiles(in text: String) async -> [String] {
        var names: [String] = []
        let regex = try? NSRegularExpression(pattern: Self.dataFiles)
        for match in regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? [] {
            guard let range = Range(match.range, in: text) else { continue }
            let name = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: "./"))
            if (try? project.url(for: name)) != nil, !names.contains(name) { names.append(name) }
        }
        return names
    }

    private func pickTargets(_ job: DevJob) async -> [String] {
        if let failure = job.failure {
            if let file = failure.file, project.read(file) != nil { return [file] }
            if let file = job.command?.first(where: { $0.hasSuffix(".py") || DevWeb.isPage($0) }) { return [file] }
            if let open = job.openFile { return [open] }
        }
        let lower = job.request.lowercased()
        let named = await namedFiles(in: job.request)
        let python = project.pythonFiles
        let code = named.filter(isPython)
        if !code.isEmpty {
            // A new test file for existing code goes after what it tests. Nothing else is reordered.
            return Array(code.prefix(4))
        }
        let namedWeb = named.filter(DevWeb.isWebFile)
        if !namedWeb.isEmpty { return Array(namedWeb.prefix(3)) }
        let isProgram = lower.matches(#"\b(script|program|code|function|python|class)\b"#)
        if !isProgram, let file = named.first, lower.matches("^\\W*(create|write|make|add|update|edit|generate)\\s+(a\\s+|an\\s+|the\\s+|new\\s+|file\\s+){0,3}" + NSRegularExpression.escapedPattern(for: file.lowercased())) {
            return [file]
        }

        let words = Set(lower.split { !$0.isLetter && !$0.isNumber && $0 != "_" }.map(String.init))
        // "Make a game" is something new, and "make the player red" isn't.
        let startsNew = lower.matches(#"^\W*(please\s+)?(create|write|make|build|generate)\s+(me\s+)?(a|an|another|new|some|one|code|game|program|script|page|tool|app)\b"#)
            && !words.contains("it") && !words.contains("this")
        // "Make the enemies faster" is about the page that's open, whatever words it uses.
        let pages = project.entries().filter { !$0.isFolder && DevWeb.isPage($0.path) }.map(\.path)
        let openPage = job.openFile.flatMap { DevWeb.isWebFile($0) ? $0 : nil }
        let lastPage = job.lastChanged.flatMap { DevWeb.isPage($0) && project.read($0) != nil ? $0 : nil }
        let editingPython = job.openFile.map(isPython) == true
        if let page = openPage ?? (editingPython ? nil : lastPage) ?? (python.isEmpty ? pages.first { $0 == "index.html" } ?? pages.first : nil) {
            if !startsNew { return [page] }
            if await changes(page, job: job) { return [page] }
        }
        if Self.wantsPage(job.request) {
            if !startsNew, let only = pages.first, pages.count == 1 { return [only] }
            return [pages.contains("index.html") ? await newName(for: job.request, taken: pages, ending: "html") : "index.html"]
        }

        let wantsTests = words.contains("test") || words.contains("tests") || words.contains("unittest") || words.contains("unittests")
        let subject = python.first { words.contains(($0 as NSString).deletingPathExtension.lowercased()) }
            ?? job.openFile.flatMap { isPython($0) ? $0 : nil } ?? job.lastChanged ?? python.first
        if wantsTests, let subject, !isTest(subject) {
            return [testName(for: subject)]
        }
        if python.isEmpty { return ["main.py"] }
        if let stem = python.first(where: { words.contains(($0 as NSString).deletingPathExtension.lowercased()) }) { return [stem] }

        // A function or class the request names says which file it's about.
        var defining: [String] = []
        if words.count < 60 {
            for path in python.prefix(12) {
                guard let text = project.read(path), text.count < 40_000 else { continue }
                let names = await DevPython.outline(text).definitions.map { $0.name.lowercased() }
                if names.contains(where: { words.contains($0) && $0 != "main" }) { defining.append(path) }
            }
        }
        if defining.count == 1 { return defining }

        if startsNew { return [await newName(for: job.request, taken: python)] }
        if let open = job.openFile, isPython(open) { return [open] }
        if let last = job.lastChanged, isPython(last), project.read(last) != nil { return [last] }
        if python.count == 1 { return python }
        return [await chooseFile(from: python, job: job)]
    }

    /// "Make a boss appear" and "make a calculator" start the same way, and only one is about the game
    /// that's open. That's a call for the model, which takes one word.
    private func changes(_ page: String, job: DevJob) async -> Bool {
        let opening = source(page).map { String($0.prefix(240)) } ?? ""
        let reply = await complete(system: "You decide whether a request changes something that exists or asks for something new. Reply CHANGE or NEW and nothing else.",
                                   user: "The project has \(page), which starts:\n\(opening)\n\nRequest: \(job.request)\n\nDoes this change \(page), or is it something separate?",
                                   temperature: 0.1, limit: 8, quiet: true)
        return reply.text.uppercased().contains("CHANGE")
    }

    private func testName(for path: String) -> String {
        let name = (path as NSString).lastPathComponent
        let folder = (path as NSString).deletingLastPathComponent
        return (folder as NSString).appendingPathComponent("test_\(name)")
    }

    private func newName(for request: String, taken: [String], ending: String = "py") async -> String {
        let reply = await complete(system: "You name files. Reply with one short snake_case file name ending in .\(ending) and nothing else.",
                                   user: "Name the file for this: \(request)", temperature: 0.2, limit: 24, quiet: true)
        if var name = reply.text.lowercased().groups(of: "[a-z][a-z0-9_]*\\.\(ending)")?[0], !["main.py", "index.html"].contains(name) || !taken.contains(name) {
            if taken.contains(name) { name = "new_\(name)" }
            return name
        }
        var index = 2
        while taken.contains("program_\(index).\(ending)") { index += 1 }
        return "program_\(index).\(ending)"
    }

    private func chooseFile(from files: [String], job: DevJob) async -> String {
        emit(.stage("Finding the right file"))
        let list = await summary(excluding: nil, budget: setup.context / 6)
        let reply = await complete(system: "You choose which file a change belongs in. Reply with one file name and nothing else.",
                                   user: "\(list)\n\nChange: \(job.request)\n\nWhich file?", temperature: 0.1, limit: 32, quiet: true)
        return files.first { reply.text.contains($0) } ?? files.first { reply.text.contains(($0 as NSString).lastPathComponent) } ?? files[0]
    }

    // MARK: - What the model sees

    /// The project in as few words as will do: each file and what it defines, and the first lines of
    /// data files, since a program can't read a format it hasn't seen.
    func summary(excluding path: String?, budget: Int) async -> String {
        var lines: [String] = []
        var left = budget * 35 / 10
        for entry in project.entries() where !entry.isFolder && entry.path != path {
            guard left > 0 else {
                lines.append("(and more files)")
                break
            }
            var line = entry.path
            if entry.isPython, let text = source(entry.path) {
                let definitions = await DevPython.outline(text).definitions.filter { $0.kind != "method" }.map(\.signature)
                if !definitions.isEmpty { line += ": " + definitions.prefix(12).joined(separator: "; ") }
            } else if entry.path.matches(#"\.(csv|json|txt|tsv)$"#), let text = project.read(entry.path) {
                let head = text.components(separatedBy: "\n").prefix(3).joined(separator: " / ")
                line += ", which starts: \(head.prefix(160))"
            }
            left -= line.count
            lines.append("- " + line)
        }
        return lines.isEmpty ? "The project is empty." : "Project files:\n" + lines.joined(separator: "\n")
    }

    func rules(_ path: String, partial: Bool = false) -> String {
        if path.hasSuffix(".js") {
            let page = pageLinking(path) ?? "the page"
            var lines = ["You write \(path), the JavaScript behind \(page). Rules:"]
            lines.append(partial ? "- Reply with one ```javascript block holding only the functions you change or add, each one complete, and any new addEventListener lines, and nothing else."
                                 : "- Reply with one ```javascript block holding the whole file, and nothing else.")
            lines.append("- Plain JavaScript for a browser: no libraries, imports or modules, and nothing from the internet.")
            lines.append("- Use only the element ids \(page) has. Keep the file's shape: state, render() and the event listeners.")
            lines.append("- Write every line. Never leave a placeholder or TODO.")
            return lines.joined(separator: "\n")
        }
        if path.hasSuffix(".css") {
            return "You write \(path), a style sheet. Reply with one ```css block holding the whole file, and nothing else. Nothing from the internet: no fonts or images."
        }
        if DevWeb.isPage(path), let page = source(path), !DevWebLinks.linkedFiles(in: page).scripts.isEmpty || !DevWebLinks.linkedFiles(in: page).styles.isEmpty {
            let files = DevWebLinks.linkedFiles(in: page)
            var lines = ["You write \(path), one page of a web app. Rules:", "- Reply with one ```html block holding the whole file, and nothing else."]
            lines.append("- Keep its <link> and <script src> tags. Its styles live in \((files.styles + files.scripts).joined(separator: " and ")), not in this file.")
            if files.styles.contains(where: { project.read($0)?.hasPrefix(DevKit.marker) == true || versions[$0]?.hasPrefix(DevKit.marker) == true }) {
                lines.append("- Style with the Bootstrap 5 classes kit.css has, such as \(DevKit.vocabulary.prefix(260))…")
            }
            lines.append("- Keep the ids the script uses. Give any new element the script needs an id.")
            lines.append("- Nothing from the internet. Write every line. Never leave a placeholder or TODO.")
            return lines.joined(separator: "\n")
        }
        if DevWeb.isPage(path) {
            return """
            You write one complete web page. Rules:
            - Reply with one ```html block holding the whole file, and nothing else.
            - Put all CSS in a <style> tag and all JavaScript in a <script> tag, in this one file.
            - Nothing from the internet: no libraries, fonts, images or sounds. Draw with the canvas 2D API.
            - Write every line. Never leave a placeholder or TODO.
            - Keep it under 150 lines. It has to really work with the keyboard or mouse.
            """
        }
        guard isPython(path) else {
            return "You write files for a project. Reply with one ``` block holding the complete file, and nothing else."
        }
        var lines = ["You write \(Self.languageName) code. Rules:"]
        if partial {
            lines.append("- Reply with one ```python block holding only the functions you change or add, each one complete, and nothing else.")
        } else {
            lines.append("- Reply with one ```python block holding the complete file, and nothing else.")
        }
        lines.append("- Use only the standard library.")
        lines.append("- Write every line. Never leave a placeholder or TODO.")
        if wantsDisplay {
            lines.append("- It runs in a plain text terminal with no display, so never use pygame, tkinter, turtle or graphics.")
            lines.append("- Show everything with print() and take every choice with input(). Play in turns: print the scene, ask what to do, update, repeat until it ends.")
            lines.append("- It has to really work. Never simulate keys or events.")
            lines.append("- Keep it short, under 60 lines. Every turn must change something, and it must be possible to win or lose. Don't use continue in the main loop.")
        }
        if !partial, !isTest(path) { lines.append("- Keep it simple. Start the program from a main() function, called under if __name__ == \"__main__\":") }
        if isTest(path) { lines.append("- Use unittest. Import what you test from its file. Only check results you are sure of.") }
        return lines.joined(separator: "\n")
    }

    func fence(_ text: String, path: String) -> String {
        let language = isPython(path) ? "python" : DevWeb.isPage(path) ? "html" : path.hasSuffix(".js") ? "javascript" : path.hasSuffix(".css") ? "css" : ""
        return "```\(language)\n\(text.trimmingCharacters(in: .newlines))\n```"
    }

    /// Whether a file can be retyped whole in the room this model has.
    func fitsWhole(_ text: String) -> Bool {
        let tokens = Self.tokens(text)
        return tokens <= Self.wholeFileTokens && tokens * 2 + 500 <= setup.context
    }

    /// The prompt's other half: the job, plus whatever else it needs to see.
    private func brief(for path: String, job: DevJob, extra: [String] = []) async -> String {
        var parts = [await summary(excluding: path, budget: setup.context / 10)]
        if isTest(path) {
            // Tests are written against the code they test, not against an outline of it.
            let tested = versions.keys.first { !isTest($0) && isPython($0) }
                ?? job.openFile.flatMap { isPython($0) && !isTest($0) ? $0 : nil } ?? job.lastChanged.flatMap { isTest($0) ? nil : $0 }
                ?? project.pythonFiles.first { !isTest($0) }
            if let tested, let text = source(tested), Self.tokens(text) * 3 < setup.context {
                parts.append("\(tested):\n\(fence(text, path: tested))")
                let module = (tested as NSString).deletingPathExtension.replacingOccurrences(of: "/", with: ".")
                let names = await DevPython.outline(text).definitions.filter { $0.kind != "method" && $0.name != "main" }.map(\.name)
                if !names.isEmpty {
                    parts.append("Start the test file with:\n```python\nimport unittest\nfrom \(module) import \(names.joined(separator: ", "))\n```")
                }
            }
        }
        parts += webContext(for: path)
        if let recent = job.history.last { parts.append("Last thing done: \(recent)") }
        return (parts + extra).joined(separator: "\n\n")
    }

    // MARK: - Writing

    /// Gets one file written, going back to the model until the reply is usable or the tries run out.
    private func author(_ path: String, job: DevJob) async -> Bool {
        var problem: String?
        var broken: String?
        for attempt in 0..<3 {
            if Task.isCancelled { return false }
            let existing = source(path)
            emit(.stage(existing == nil ? "Writing \(path)" : "Editing \(path)"))
            let temperature = [0.2, 0.3, 0.5][attempt]
            let text: String?
            if let existing, isPython(path), !fitsWhole(existing) {
                text = await editPieces(of: existing, path: path, task: job.request, job: job, note: problem, temperature: temperature)
            } else if let existing, path.hasSuffix(".js"), !fitsWhole(existing) {
                text = await editScriptPieces(of: existing, path: path, task: job.request, job: job, note: problem, temperature: temperature)
            } else {
                var extra: [String] = []
                if let existing { extra.append("\(path) now:\n\(fence(existing, path: path))") }
                extra.append("Task: \(job.request)")
                var skeleton: String?
                if existing == nil, DevWeb.isPage(path), isGameRequest(job.request) {
                    let firstPerson = job.request.lowercased().matches(#"\b(pov|first[- ]person|fps)\b"#)
                    skeleton = firstPerson ? DevWeb.firstPersonSkeleton : DevWeb.gameSkeleton
                    extra.append("Start from this and fill it in, keeping what's there:\n\(fence(skeleton ?? "", path: path))")
                    if firstPerson {
                        extra.append("Make it first-person: there's no player on screen. Enemies appear far away, small and near the middle, and grow as they come closer. The mouse moves a crosshair, and a click shoots whatever is under it. Shooting, drawing, the score and lives already work. Your part is how the enemies move: fill in the loop in update(), and add anything else the task asks for.")
                    }
                }
                if let problem { extra.append(problem) }
                // A slip is quicker to correct than to rewrite, and a rewrite can slip somewhere else.
                if let broken { extra.append("Your code so far:\n\(fence(broken, path: path))") }
                extra.append(broken != nil ? "Correct that error and change nothing else. Reply with the whole \(path)." : existing == nil ? "Write \(path)." : "Reply with the whole new \(path).")
                let reply = await complete(system: rules(path), user: await brief(for: path, job: job, extra: extra), temperature: temperature)
                if Task.isCancelled { return false }
                if let error = reply.error { backendError = error; return false }
                // Half a program isn't worth correcting, and sending it back would fill the context window.
                if reply.cutOff {
                    problem = "Your last reply was too long and got cut off. Write a much shorter version."
                    broken = nil
                    continue
                }
                text = DevWeb.isPage(path) ? DevWeb.page(from: reply.text, current: existing).map { page in
                    tidied(skeleton.map { DevWeb.restoringCanvas(in: page, from: $0) } ?? page, was: existing)
                } : webCode(reply.text, path: path)
                if text == nil { problem = "Your last reply had no usable code. Reply with one code block." }
            }
            guard let text else { continue }
            if DevWeb.isWebFile(path), DevWeb.hasPlaceholders(text) {
                problem = "Your last reply left parts out. Write every line."
                continue
            }
            if path.hasSuffix(".js"), let error = DevJS.syntaxError(in: text) {
                problem = "Your last reply had this error on line \(error.line): \(error.message)."
                broken = Self.tokens(text) * 2 + 500 <= setup.context ? text : nil
                emit(.note("The reply had a syntax error, so I asked again."))
                continue
            }
            if isPython(path) {
                let fitted = await fit(text, path: path, request: job.request)
                guard let fitted else {
                    problem = "Your last reply left parts out. Write every line."
                    continue
                }
                let syntax = await DevPython.check(fitted, name: path)
                if !syntax.ok {
                    problem = "Your last reply had this error on line \(syntax.line ?? 0): \(syntax.message ?? "invalid syntax")."
                    broken = Self.tokens(fitted) * 2 + 500 <= setup.context ? fitted : nil
                    emit(.note("The reply had a syntax error, so I asked again."))
                    continue
                }
                record(DevRepair.callingMain(fitted) ?? fitted, for: path)
            } else {
                record(text, for: path)
            }
            return true
        }
        return false
    }

    private func usable(_ reply: String, path: String) -> String? {
        DevRepair.code(in: reply, python: isPython(path))
    }

    /// Fits a reply into the file it's meant for. Models often send back only what changed, or stand
    /// a comment in for the rest. A reply that keeps the whole file replaces it. Nil if it can't be used.
    private func fit(_ reply: String, path: String, request: String) async -> String? {
        guard let original = source(path) else {
            return DevRepair.hasPlaceholders(reply) ? nil : reply
        }
        let old = await DevPython.outline(original), new = await DevPython.outline(reply)
        let placeholders = DevRepair.hasPlaceholders(reply)
        guard old.ok, new.ok else { return placeholders ? nil : reply }
        let names = { (outline: DevPython.Outline) in Set(outline.definitions.filter { $0.kind != "method" }.map(\.name)) }
        let missing = names(old).subtracting(names(new))
        let keepsMain = !old.hasMain || new.hasMain
        let removing = request.lowercased().matches(#"\b(delete|remove|drop|get rid of|rewrite|replace|rename)\b"#)
        // A reply with the program's ending and most of its length is the whole file, whatever it left out.
        let looksWhole = old.hasMain && new.hasMain && reply.count * 10 >= original.count * 7
        if !placeholders, looksWhole {
            // Keeps anything it dropped along the way that nobody asked it to drop.
            let lost = missing.filter { !request.lowercased().contains($0.lowercased()) }
            guard !lost.isEmpty else { return reply }
            let lines = original.components(separatedBy: "\n")
            let pieces = old.definitions.filter { lost.contains($0.name) }.map { text(of: $0, in: lines) }
            let merged = await DevPython.merge(pieces.joined(separator: "\n\n"), into: reply)
            return merged.ok ? merged.source : reply
        }
        if !placeholders, missing.isEmpty, keepsMain {
            // A script has no functions to compare, so its length has to tell.
            let tooShort = old.definitions.isEmpty && !removing && original.count > 200 && reply.count * 3 < original.count
            return tooShort ? nil : reply
        }
        if !placeholders, removing { return reply }
        let merged = await DevPython.merge(DevRepair.withoutPlaceholders(reply), into: original)
        // Nothing to fit in means it wasn't a piece of this file, but a different take on the whole thing.
        if merged.ok, merged.source == original, !placeholders { return reply }
        return merged.ok ? merged.source : nil
    }

    /// Edits a long file through just the parts that matter, with the rest shown as an outline.
    private func editPieces(of source: String, path: String, task: String, job: DevJob, note: String?, temperature: Double, failure: DevFailure? = nil) async -> String? {
        let outline = await DevPython.outline(source)
        guard outline.ok else { return nil }
        let lines = source.components(separatedBy: "\n")
        var chosen = relevant(outline.definitions, task: task, failure: failure)
        if chosen.isEmpty {
            let list = outline.definitions.map(\.signature).joined(separator: "\n")
            let reply = await complete(system: "You choose which function a change belongs in. Reply with one function name, or NEW if it needs a new function.",
                                       user: "\(path) has:\n\(list)\n\nChange: \(task)\n\nWhich function?", temperature: 0.1, limit: 24, quiet: true)
            chosen = outline.definitions.filter { definition in
                reply.text.contains(definition.name) || reply.text.contains(definition.name.components(separatedBy: ".").last ?? definition.name)
            }
            chosen = Array(chosen.prefix(2))
        }
        var pieces = chosen.map { text(of: $0, in: lines) }
        if chosen.isEmpty, let imports = Optional(lines.prefix(12).filter { $0.hasPrefix("import ") || $0.hasPrefix("from ") }), !imports.isEmpty {
            pieces = [imports.joined(separator: "\n")]
        }
        var parts = ["\(path) defines:\n" + outline.definitions.map(\.signature).joined(separator: "\n")]
        if !pieces.isEmpty { parts.append("The part that matters:\n\(fence(pieces.joined(separator: "\n\n"), path: path))") }
        if let failure { parts.append("Running it gives:\n```\n\(Self.quoted(String(failure.output.suffix(700))))\n```") }
        parts.append("Task: \(task)")
        if let note { parts.append(note) }
        parts.append("Reply with only the functions you change or add. Add any import you need at the top of your reply.")
        let reply = await complete(system: rules(path, partial: true), user: parts.joined(separator: "\n\n"), temperature: temperature)
        if Task.isCancelled { return nil }
        if let error = reply.error { backendError = error; return nil }
        guard let code = usable(reply.text, path: path) else { return nil }
        let allowed = chosen.isEmpty ? ["-"] : chosen.flatMap { [$0.name] + $0.name.components(separatedBy: ".") }
        let merged = await DevPython.merge(DevRepair.withoutPlaceholders(code), into: source, only: allowed)
        return merged.ok ? merged.source : nil
    }

    private func relevant(_ definitions: [DevPython.Definition], task: String, failure: DevFailure?) -> [DevPython.Definition] {
        let words = Set(task.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "_" }.map(String.init))
        var chosen = definitions.filter { definition in
            guard definition.kind != "class" else { return false }
            let name = definition.name.lowercased()
            return words.contains(name) || words.contains(name.components(separatedBy: ".").last ?? name)
        }
        if let line = failure?.line, let holder = definitions.filter({ $0.kind != "class" && $0.start <= line && line <= $0.end }).last,
           !chosen.contains(where: { $0.name == holder.name }) {
            chosen.insert(holder, at: 0)
        }
        return Array(chosen.prefix(3))
    }

    // MARK: - Running

    /// A copy of the project with the agent's versions in it. Hidden files stay behind, and so does
    /// anything big, so a run can't reach a .env or take its time on a dataset.
    private func workingCopy() -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("prometheus-dev-run-\(UUID().uuidString)", isDirectory: true)
        let manager = FileManager.default
        guard (try? manager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return nil }
        for entry in project.entries() {
            let target = folder.appendingPathComponent(entry.path)
            if entry.isFolder {
                try? manager.createDirectory(at: target, withIntermediateDirectories: true)
            } else if let source = try? project.url(for: entry.path),
                      ((try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) < 20 << 20 {
                try? manager.copyItem(at: source, to: target)
            }
        }
        for (path, text) in versions where (try? project.url(for: path)) != nil {
            let target = folder.appendingPathComponent(path)
            try? manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: target, atomically: true, encoding: .utf8)
        }
        return folder
    }

    private func execute(_ arguments: [String], label: String, tests: Bool = false) async -> Verdict {
        guard let folder = workingCopy() else {
            return .failed(DevFailure(kind: "Exit", message: "Couldn't make a copy of the project to run.", output: ""))
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        return await execute(arguments, label: label, in: folder, tests: tests)
    }

    private func execute(_ arguments: [String], label: String, in folder: URL, quiet: Bool = false, tests: Bool = false) async -> Verdict {
        let program = arguments.first.flatMap { $0.hasSuffix(".py") ? source($0) : nil }
        var result = await DevRunner.run(arguments, in: folder, input: Self.sampleInput(for: program))
        result.output = cleaned(result.output, folder: folder)
        if !quiet { emit(.ran(label, result)) }
        if result.succeeded { return .worked(result.output) }
        if let limit = result.limit, limit.contains("second limit"), result.output.contains("Traceback") == false {
            return .failed(.ending(result))
        }
        guard let failure = DevFailure.parse(result.output) else { return .failed(.ending(result)) }
        // A test run asks nobody anything, so running out of input there is a real failure.
        return failure.kind == "EOFError" && !tests ? .needsInput(result.output) : .failed(failure)
    }

    private func cleaned(_ output: String, folder: URL) -> String {
        var path = folder.path
        if let real = realpath(path, nil) {
            path = String(cString: real)
            free(real)
        }
        return output.replacingOccurrences(of: path + "/", with: "")
    }

    /// What shows whether the work is right: the failed run itself if there was one, or else the programs
    /// among what changed, or one that uses it. With no clear program every changed file runs, since
    /// a script's code runs at the top of the file, and a file that never runs proves nothing.
    private func entries(_ job: DevJob) async -> [[String]] {
        if let command = job.command { return [command] }
        let changed = order.filter { isPython($0) && !isTest($0) }
        var programs: [[String]] = []
        for path in changed {
            if let text = source(path), await DevPython.outline(text).hasMain { programs.append([path]) }
        }
        if !programs.isEmpty { return Array(programs.prefix(3)) }
        for path in project.pythonFiles where !changed.contains(path) && !isTest(path) {
            guard let text = project.read(path) else { continue }
            let uses = changed.contains { used in
                let module = (used as NSString).deletingPathExtension
                return text.matches("^\\s*(import|from)\\s+\(NSRegularExpression.escapedPattern(for: module))\\b", options: .anchorsMatchLines)
            }
            if uses, await DevPython.outline(text).hasMain { return [[path]] }
        }
        return changed.prefix(3).map { [$0] }
    }

    /// Runs the program, then any tests. Tests are the better judge, so they get the last word.
    /// The page that shows whether the work is right, if the work is a page or part of one.
    private func pageToTry(_ job: DevJob) -> String? {
        if let page = order.last(where: DevWeb.isPage) { return page }
        if let page = job.command?.first(where: DevWeb.isPage) { return page }
        guard order.contains(where: DevWeb.isWebFile) else { return nil }
        let pages = project.entries().filter { !$0.isFolder && DevWeb.isPage($0.path) }.map(\.path)
        return pages.first { $0 == "index.html" } ?? pages.first
    }

    private func tryPage(_ page: String, job: DevJob) async -> Verdict {
        emit(.stage("Trying the page"))
        triedPage = page
        guard let folder = workingCopy() else {
            return .failed(DevFailure(kind: "Exit", message: "Couldn't make a copy of the project to try.", output: ""))
        }
        defer { try? FileManager.default.removeItem(at: folder) }
        let report = await setup.pageCheck(folder, page, pageKind(page, job: job))
        // v2 reads more of this afterwards. v1 only reads whether it failed.
        lastReport = report
        let output = ([report.summary] + report.console.suffix(6)).filter { !$0.isEmpty }.joined(separator: "\n")
        emit(.ran("preview \(page)", DevRunResult(output: output, exitCode: report.failure == nil ? 0 : 1, seconds: 0)))
        if let failure = report.failure { return .failed(failure) }
        return .worked(report.summary)
    }

    func verify(_ job: DevJob) async -> Verdict {
        lastReport = nil
        if let page = pageToTry(job) {
            if let failure = linkCheck(page) { return .failed(failure) }
            return await tryPage(page, job: job)
        }
        emit(.stage("Running it"))
        var verdict = Verdict.notRun
        for command in await entries(job) {
            verdict = await execute(command, label: "python " + command.joined(separator: " "))
            if case .failed = verdict { return verdict }
        }
        let tests = Set(project.pythonFiles + order).filter(isTest).sorted()
        guard !tests.isEmpty else { return verdict }
        emit(.stage("Running the tests"))
        let result = await execute(DevRunner.testArguments(Array(tests.prefix(6))), label: "python -m tests " + tests.prefix(6).joined(separator: " "), tests: true)
        guard case .worked = result else { return result }
        if case .notRun = verdict { return result }
        return verdict
    }

    // MARK: - Fixing

    private func target(of failure: DevFailure, job: DevJob) -> String? {
        if let file = failure.file, source(file) != nil {
            if isTest(file) {
                // A test that was already here is the person's, and rewriting it would only hide the failure.
                let isNew = (originals[file] ?? nil) == nil && order.contains(file)
                if !isNew, !job.request.lowercased().contains("test") {
                    return order.last { !isTest($0) && isPython($0) } ?? testedFile(by: file) ?? file
                }
                // A test written just now is the likelier one to be wrong, and fixing it leaves the person's
                // code alone. Otherwise the test stands, and the code it tests is what needs the fix.
                let trustsTest = job.failure != nil || order.contains { !isTest($0) && isPython($0) }
                if failure.kind == "AssertionError", trustsTest, let tested = testedFile(by: file) { return tested }
            }
            return file
        }
        return order.last { isPython($0) || DevWeb.isWebFile($0) } ?? job.command?.first { $0.hasSuffix(".py") || DevWeb.isPage($0) }
    }

    /// The project's file that a test file imports.
    private func testedFile(by test: String) -> String? {
        guard let text = source(test) else { return nil }
        return (order + project.pythonFiles).first { path in
            let module = (path as NSString).deletingPathExtension.replacingOccurrences(of: "/", with: ".")
            return !isTest(path) && text.matches("^\\s*(from|import)\\s+\(NSRegularExpression.escapedPattern(for: module))\\b", options: .anchorsMatchLines)
        }
    }

    private func hint(for failure: DevFailure, path: String) -> String? {
        if failure.kind == "AssertionError", isTest(path) {
            guard let values = failure.message.groups(of: #"^(.+) != (.+)$"#) else { return "A check failed. If it expects the wrong result, correct the check." }
            return "The code returned \(values[1]), but the check expected \(values[2]). The code is right, so correct the check."
        }
        switch failure.kind {
        case "ModuleNotFoundError", "ImportError":
            if failure.message.matches(#"(?i)pygame|tkinter|turtle|arcade|kivy|pyqt|pyside|matplotlib|pyglet"#) {
                return "There's no display here and that module isn't installed. Rewrite it as a real text program using print() and input(). Don't simulate keys or events."
            }
            return "Only the Python standard library is installed. Do the same thing without that module."
        case "UnboundLocalError":
            guard let name = failure.message.groups(of: #"variable '(\w+)'"#)?[1] else { return nil }
            return "Here \(name) is both a local variable and something else, such as a function. Give the variable a different name."
        case "RecursionError":
            return "The recursion never reaches its end. Check the base case."
        case "Limit":
            return "The program didn't finish. Look for a loop that never ends, or one waiting on something that won't come."
        case "AssertionError":
            return "A check failed, so the code gave a wrong result. Work out the right result and fix the code."
        case "Exit":
            return "It ended with an error but printed no traceback."
        case "Resource":
            if pageLinking(path) != nil || path.hasSuffix(".js") {
                return "Everything has to be in the project. Nothing can load from the internet: no libraries, fonts or images. Do it with plain JavaScript and the page's own files."
            }
            return "Everything has to be in the project. Draw with the canvas instead of loading anything, and put all the code in this one file."
        case "Link" where failure.message.hasPrefix("render() adds"):
            return "Add that listener once, outside render(), next to the other event listeners. render() should only draw the page from state."
        case "Link":
            return "\(failure.message) Use only what's there.\(failure.output.isEmpty ? "" : " The page's elements:\n\(failure.output)")"
        case "SyntaxError" where path.hasSuffix(".js"):
            return "It doesn't parse, so nothing in it runs. Check the brackets, quotes and commas around that line."
        case "Output" where DevWeb.isWebFile(path):
            if failure.message.hasPrefix("Nothing moves") {
                return "A game needs things that change by themselves: create enemies or objects in update(), move them every frame, and make the keys or mouse change what's drawn."
            }
            if failure.message.contains("doesn't listen") {
                return "Add addEventListener calls for the keyboard or the mouse, and use them to control the game."
            }
            if failure.message.contains("template tags") {
                return "Nothing here runs a server, so there's no Flask, Jinja, PHP or Node. Write plain HTML, and fill it in with JavaScript in the browser."
            }
            if failure.message.contains("nothing on the page changed") {
                return "When a form is submitted or a button is clicked, change state, then call save() and render(), and make render() show state on the page. Listen for a form's submit, not its button's click, and call event.preventDefault() first."
            }
            return "Something has to be drawn on the page when it opens."
        case "Output":
            if failure.message.hasPrefix("Nothing changes") {
                return "\(failure.message) Every move has to reach the code that updates the game. A continue in the main loop can skip it, so put that update where every turn runs it."
            }
            return "\(failure.message) It has to really work when someone runs it: show what's happening with print(), and for anything interactive keep asking with input() in a loop. Don't simulate keys or events, and don't quit straight away."
        case "Review":
            return "It runs, but a reviewer says it doesn't do what was asked: \(failure.message)"
        default:
            return nil
        }
    }

    /// A name the program used that another file in the project defines.
    private func importedFromProject(_ failure: DevFailure, into path: String, source current: String) async -> String? {
        guard failure.kind == "NameError", let name = failure.message.groups(of: #"name '(\w+)' is not defined"#)?[1] else { return nil }
        for other in Set(project.pythonFiles + order).sorted() where other != path && !isTest(other) {
            guard let text = source(other) else { continue }
            let module = (other as NSString).deletingPathExtension.replacingOccurrences(of: "/", with: ".")
            let line = "from \(module) import \(name)"
            if !current.contains(line), await DevPython.outline(text).definitions.contains(where: { $0.name == name }) {
                return DevRepair.adding(line, to: current)
            }
        }
        return nil
    }

    /// One attempt at one failure. Tries what code can settle first. Handed a whole file, a small model
    /// tends to type it back unchanged, so a second try splits the job: say the cause in plain words, then
    /// rewrite only the part that holds the bug.
    func fix(_ path: String, failure: DevFailure, job: DevJob, round: Int, repeats: Int) async -> String? {
        guard let current = source(path) else { return nil }
        if originals[path] == nil { originals[path] = .some(project.read(path)) }
        if let repaired = await importedFromProject(failure, into: path, source: current) ?? DevRepair.repair(failure, source: current) {
            emit(.stage("Fixing \(path)"))
            emit(.note("Added the missing import myself."))
            return repaired
        }
        if repeats > 1, let trimmed = await withoutFailingTest(failure, path: path, source: current) { return trimmed }
        emit(.stage("Fixing \(path)"))
        if DevWeb.isWebFile(path) { return await fixPage(path, source: current, failure: failure, job: job, round: round, repeats: repeats) }
        guard isPython(path) else { return nil }
        let temperature = [0.2, 0.3, 0.5, 0.7][min(repeats - 1 + (round > 3 ? 1 : 0), 3)]
        let task = job.failure == nil ? job.request : "Fix this error: \(failure.title)"
        var note: String?
        if repeats > 1 {
            let cause = await diagnose(current, failure: failure, path: path)
            note = "Cause: \(cause)\nThe code you gave before still fails, so this time it has to be different."
        }
        if !fitsWhole(current) || repeats > 1 {
            let edited = await editPieces(of: current, path: path, task: task, job: job, note: note, temperature: temperature, failure: failure)
            if let edited, edited != current, await DevPython.check(edited, name: path).ok { return DevRepair.callingMain(edited) ?? edited }
            if !fitsWhole(current) { return nil }
        }

        var parts = ["\(path):\n\(fence(current, path: path))"]
        parts.append("Running it gives:\n```\n\(Self.quoted(String(failure.output.suffix(700))))\n```")
        if let line = failure.line, failure.file == path {
            let lines = current.components(separatedBy: "\n")
            if line > 0, line <= lines.count {
                parts.append("The error is on line \(line): \(lines[line - 1].trimmingCharacters(in: .whitespaces))")
            }
        }
        if job.failure == nil { parts.append("The file is meant to do this: \(job.request)") }
        if isTest(path), let tested = testedFile(by: path), let text = source(tested), Self.tokens(text) * 3 < setup.context {
            parts.append("The code it tests, \(tested):\n\(fence(text, path: tested))")
        }
        if let hint = hint(for: failure, path: path) { parts.append(hint) }
        if let note { parts.append(note) }
        parts.append("Fix the cause of the error and keep everything else the same. Reply with the whole corrected \(path).")
        let reply = await complete(system: rules(path), user: parts.joined(separator: "\n\n"), temperature: temperature)
        if Task.isCancelled { return nil }
        if let error = reply.error { backendError = error; return nil }
        guard let code = usable(reply.text, path: path), let fitted = await fit(code, path: path, request: "") else { return nil }
        guard await DevPython.check(fitted, name: path).ok else { return nil }
        // The same code back means the model has nothing more on this path, so take the other one now.
        if fitted == current { return repeats == 1 ? await fix(path, failure: failure, job: job, round: round, repeats: 2) : nil }
        return DevRepair.callingMain(fitted) ?? fitted
    }

    /// A program's own output, made safe to put in a code block, where it could otherwise end the block
    /// and carry on as if it were part of the instructions.
    static func quoted(_ output: String) -> String {
        output.replacingOccurrences(of: "```", with: "~~~")
    }

    /// The same job for a web page, where the whole file comes back, since nothing here can yet fit a
    /// piece of JavaScript into a page the way Python's parser fits a function into a file.
    private func fixPage(_ path: String, source current: String, failure: DevFailure, job: DevJob, round: Int, repeats: Int) async -> String? {
        let temperature = [0.2, 0.3, 0.5, 0.7][min(repeats - 1 + (round > 3 ? 1 : 0), 3)]
        if path.hasSuffix(".js"), !fitsWhole(current) {
            var note: String?
            if repeats > 1 { note = "Cause: \(await diagnose(current, failure: failure, path: path))\nThe code you gave before still fails, so this time it has to be different." }
            let task = job.failure == nil ? job.request : "Fix this error: \(failure.title)"
            let edited = await editScriptPieces(of: current, path: path, task: task, job: job, note: [hint(for: failure, path: path), note].compactMap { $0 }.joined(separator: "\n"), temperature: temperature, failure: failure)
            return edited == current ? nil : edited
        }
        var parts = ["\(path):\n\(fence(current, path: path))"]
        parts += webContext(for: path)
        parts.append("Trying it gives:\n```\n\(Self.quoted(failure.title))\n\(Self.quoted(String(failure.output.suffix(500))))\n```")
        if let line = failure.line, failure.file == path {
            let lines = current.components(separatedBy: "\n")
            if line > 0, line <= lines.count { parts.append("The error is on line \(line): \(lines[line - 1].trimmingCharacters(in: .whitespaces))") }
        }
        if job.failure == nil { parts.append("It's meant to do this: \(job.request)") }
        if let hint = hint(for: failure, path: path) { parts.append(hint) }
        if repeats > 1 {
            parts.append("Cause: \(await diagnose(current, failure: failure, path: path))\nThe code you gave before still fails, so this time it has to be different.")
        }
        parts.append("Fix it and keep everything else the same. Reply with the whole corrected \(path).")
        let reply = await complete(system: rules(path), user: parts.joined(separator: "\n\n"), temperature: temperature)
        if Task.isCancelled { return nil }
        if let error = reply.error { backendError = error; return nil }
        guard !reply.cutOff, let text = DevWeb.isPage(path) ? DevWeb.page(from: reply.text, current: current).map({ tidied($0, was: current) }) : webCode(reply.text, path: path), !DevWeb.hasPlaceholders(text) else { return nil }
        if text == current { return repeats == 1 ? await fixPage(path, source: current, failure: failure, job: job, round: round, repeats: 2) : nil }
        return text
    }

    /// Why it fails, in a sentence. On its own the question gets a real answer, where a request for the
    /// fixed code gets the same code back.
    private func diagnose(_ source: String, failure: DevFailure, path: String) async -> String {
        emit(.stage("Working out the cause"))
        let lines = source.components(separatedBy: "\n")
        var nearby = source
        if let line = failure.line, !fitsWhole(source) {
            let start = min(max(line - 6, 0), lines.count)
            nearby = lines[start..<min(start + 10, lines.count)].joined(separator: "\n")
        }
        let reply = await complete(system: "You find bugs in code. Reply with one short sentence: what causes the error, and what to change.",
                                   user: "\(fence(nearby, path: path))\n\nError:\n\(failure.title)\n\nWhat causes it, and what should change?", temperature: 0.2, limit: 96, quiet: true)
        // The useful part often comes last, as in "What to change: ...".
        let words = reply.text.replacingOccurrences(of: "**", with: "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(words.prefix(320))
    }

    /// A test this job wrote that still fails after a fix usually expects the wrong thing, and small models
    /// get expected values wrong far more often than a working function. It goes, and the report says so.
    private func withoutFailingTest(_ failure: DevFailure, path: String, source: String) async -> String? {
        guard isTest(path), failure.kind == "AssertionError", failure.file == path, let line = failure.line,
              originals[path] == .some(nil), let outline = Optional(await DevPython.outline(source)), outline.ok,
              let test = outline.definitions.last(where: { $0.kind != "class" && $0.start <= line && line <= $0.end }),
              outline.definitions.filter({ $0.name.components(separatedBy: ".").last?.hasPrefix("test") == true }).count > 1 else { return nil }
        var lines = source.components(separatedBy: "\n")
        guard test.start >= 1, test.start <= lines.count else { return nil }
        lines.removeSubrange((test.start - 1)..<min(max(test.end, test.start), lines.count))
        let name = test.name.components(separatedBy: ".").last ?? test.name
        dropped.append("I left out \(name), since it didn't hold: \(failure.message). Check which side is right.")
        emit(.note("Left out \(name): \(failure.message)"))
        return lines.joined(separator: "\n")
    }

    // MARK: - The model

    /// A small model can fall into repeating one line until it runs out of tokens, which on a slow Mac is
    /// minutes spent on nothing.
    static func isLooping(_ text: String) -> Bool {
        // The same with a story that branches deeper on every line, which never comes back out.
        if let last = text.suffix(600).components(separatedBy: "\n").last(where: { !$0.isEmpty }), last.prefix(while: { $0 == " " }).count >= 60 { return true }
        let lines = text.suffix(600).components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count >= 10, let last = lines.last else { return false }
        return lines.suffix(10).allSatisfy { $0 == last }
    }

    /// `limit` is the most tokens the reply may run to. A step that doesn't set one gets the budget's: 4,096
    /// in v1 and v2, more in v3 when the context window is large (`DevBudget`).
    func complete(system: String, user: String, temperature: Double, limit: Int? = nil, quiet: Bool = false, think: Bool?? = .none,
                  onText: (String) -> Void = { _ in }) async -> Reply {
        calls += 1
        let prompt = Self.tokens(system) + Self.tokens(user) + 16
        let room = max(min(limit ?? budget.reply, setup.context - prompt - 16), 96)
        let request = ChatRequest(model: setup.model, messages: [ChatTurn(role: "system", content: system), ChatTurn(role: "user", content: user)],
                                  temperature: temperature, contextLength: setup.context, maxTokens: room, think: think ?? setup.think)
        var reply = Reply()
        var parser = ThinkTagParser()
        var chunks = 0
        do {
            for try await event in setup.backend.chat(request) {
                if Task.isCancelled { break }
                if reply.cutOff, !reply.text.isEmpty, Self.isLooping(reply.text) { break }
                switch event {
                case .content(let chunk):
                    reply.text += parser.feed(chunk).answer
                    chunks += 1
                    if chunks % 6 == 0 {
                        onText(reply.text)
                        if !quiet { emit(.writing(reply.text)) }
                        if Self.isLooping(reply.text) {
                            reply.cutOff = true
                        }
                    }
                case .finished(let stats):
                    reply.cutOff = stats.stopReason?.lowercased().contains("length") == true
                default:
                    break
                }
            }
            reply.text += parser.flush().answer
            onText(reply.text)
        } catch {
            reply.error = error.localizedDescription
        }
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["LOCALAI_DEV_TRACE"], let file = FileHandle(forWritingAtPath: path) ?? {
            FileManager.default.createFile(atPath: path, contents: nil)
            return FileHandle(forWritingAtPath: path)
        }() {
            file.seekToEndOfFile()
            file.write(Data("\n===== t=\(temperature)\n\(user)\n----- reply\n\(reply.text)\n".utf8))
            try? file.close()
        }
        #endif
        return reply
    }
}
