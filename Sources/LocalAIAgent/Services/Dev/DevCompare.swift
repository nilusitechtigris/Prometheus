import Foundation

/// One line of a scorecard. Nil when the line doesn't apply, such as using a page with nothing to use.
struct DevScoreLine: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var passed: Bool?
    var detail: String?
    var id: String { name }
}

struct DevCompareFile: Codable, Equatable, Sendable {
    var path: String
    var lines: Int
}

/// One way of building it: the harness off or on.
struct DevCompareSide: Codable, Equatable, Sendable {
    var folder: String
    var harness: Bool
    var seconds: Double?
    var calls: Int?
    var files: [DevCompareFile] = []
    var page: String?
    var score: [DevScoreLine] = []
    /// What the agent or the one reply said at the end.
    var text = ""
    var finished = false
    var stopped = false

    var passed: Int { score.filter { $0.passed == true }.count }
    var total: Int { score.filter { $0.passed != nil }.count }
    var picture: String { (folder as NSString).deletingLastPathComponent + "/\(harness ? "harness-on" : "harness-off").png" }
}

/// The same request built twice on the same model, with the harness off and on, in folders of their own.
struct DevComparison: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var request: String
    var date = Date()
    var model: String
    var framework: String
    var context: Int
    var folder: String
    var off: DevCompareSide
    var on: DevCompareSide
}

enum DevCompare {
    /// Where new projects and comparisons go unless someone picks another place.
    static var projectsRoot: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        return documents.appendingPathComponent("Prometheus Projects", isDirectory: true)
    }

    static var comparisonsRoot: URL { projectsRoot.appendingPathComponent("Comparisons", isDirectory: true) }

    static func folderName(for request: String, date: Date) -> String {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd HHmm"
        let words = request.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { !["a", "an", "the", "me", "make", "create", "build", "write", "please", "with", "for", "and", "that", "of"].contains($0) }
        let name = words.prefix(5).joined(separator: "-")
        return "\(format.string(from: date)) \(name.isEmpty ? "app" : name)"
    }

    // MARK: - Saving

    private static var file: URL {
        ConversationStore.directory.appendingPathComponent("Dev", isDirectory: true).appendingPathComponent("comparisons.json")
    }

    static func load() -> [DevComparison] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([DevComparison].self, from: data)) ?? []
    }

    static func save(_ list: [DevComparison]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Array(list.prefix(100))) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    // MARK: - Running

    /// Loads the model before the clock starts, so the side that goes first doesn't pay for it.
    static func warmUp(_ setup: DevSetup) async {
        let request = ChatRequest(model: setup.model, messages: [ChatTurn(role: "user", content: "Reply with OK.")], temperature: 0,
                                  contextLength: setup.context, maxTokens: 4, think: setup.think)
        do {
            for try await _ in setup.backend.chat(request) { if Task.isCancelled { break } }
        } catch {}
    }

    // MARK: - Grading

    /// Scores what a folder holds with the same checks for both sides, whatever either one claimed.
    /// A page is opened, played and used out of sight. A program is run with sample input.
    @MainActor
    static func grade(folder: URL, request: String, picture: URL?) async -> (page: String?, files: [DevCompareFile], score: [DevScoreLine]) {
        let project = DevProject(root: folder)
        let entries = project.entries().filter { !$0.isFolder }
        let files = entries.map { entry in
            DevCompareFile(path: entry.path, lines: project.read(entry.path).map { $0.split(separator: "\n", omittingEmptySubsequences: false).count } ?? 0)
        }
        let pages = entries.filter(\.isPage).map(\.path)
        if let page = pages.first(where: { $0 == "index.html" }) ?? pages.first {
            let kind: DevPageKind = DevAgent.isGame(request) ? .game : .app
            let report = await DevPageCheck.run(folder: folder, page: page, kind: kind, picture: picture)
            var score = [
                DevScoreLine(name: "Shows something", passed: report.hasContent && !report.rawTemplate,
                             detail: report.rawTemplate ? "It shows template tags that only a server fills in." : report.hasContent ? nil : "The page is blank."),
                DevScoreLine(name: "Opens without errors", passed: report.loaded, detail: report.loaded ? nil : report.failure?.title),
                DevScoreLine(name: "Styled", passed: report.styled, detail: report.styled ? nil : "It shows in the browser's plain default look."),
                DevScoreLine(name: "Works offline", passed: report.offline, detail: report.offline ? nil : "It asks the internet for something, which isn't there."),
            ]
            if kind == .game {
                score.append(DevScoreLine(name: "Plays", passed: report.loaded ? (report.moved || report.responded) && report.listens : false))
            } else if report.controls > 0 {
                let works = report.used ?? (report.loaded ? report.responded : false)
                score.append(DevScoreLine(name: "Works when used", passed: works, detail: works ? nil : report.failure?.kind == "Output" ? report.failure?.message : "Filling it in and pressing its buttons changed nothing."))
            } else {
                score.append(DevScoreLine(name: "Works when used", passed: nil, detail: "It has nothing to use."))
            }
            score.append(DevScoreLine(name: "Fits the window", passed: report.fits, detail: report.fits ? nil : "Something on it is wider than the window."))
            return (page, files, score)
        }
        let programs = entries.filter(\.isPython).map(\.path).filter { !$0.hasPrefix("test_") }
        if let program = programs.first(where: { $0 == "main.py" }) ?? programs.first, let text = project.read(program) {
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("prometheus-compare-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.copyItem(at: folder, to: copy)
            defer { try? FileManager.default.removeItem(at: copy) }
            let result = await DevRunner.run([program], in: copy, input: DevAgent.sampleInput(for: text))
            let failure = result.succeeded ? nil : DevFailure.parse(result.output)
            let ranOut = failure?.kind == "EOFError"
            return (nil, files, [
                DevScoreLine(name: "Runs without errors", passed: result.succeeded || ranOut, detail: result.succeeded || ranOut ? nil : (failure?.title ?? result.limit ?? "exit code \(result.exitCode)")),
                DevScoreLine(name: "Shows something", passed: !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
            ])
        }
        return (nil, files, [DevScoreLine(name: "Wrote a page or a program", passed: false)])
    }
}
