import Foundation

/// Persists conversations as JSON in the app's data folder in ~/Library/Application Support.
struct ConversationStore {
    let fileURL: URL

    /// The app's data folder (also holds test results).
    ///
    /// Prometheus keeps "LocalAIAgent" and Prometheus Lab keeps its own, "LocalAIAgent Lab". Each app reads
    /// its files once at launch and writes the whole list back when it saves, so in one shared folder
    /// whichever saved last would erase what the other had just saved: a test run finished in one app
    /// would be gone after a chat in the other. The lab's folder starts as a copy of the public app's,
    /// made the first time the lab runs. After that the two go their own ways.
    static let directory: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var base = support.appendingPathComponent(folderName(labBuild: Edition.isLabBuild), isDirectory: true)
        var overridden = false
        #if DEBUG
        // Keeps automated UI test runs away from the user's real chats.
        if let dir = ProcessInfo.processInfo.environment["LOCALAI_DATA_DIR"] {
            base = URL(fileURLWithPath: dir, isDirectory: true)
            overridden = true
        }
        #endif
        if Edition.isLabBuild, !overridden {
            seed(base, from: support.appendingPathComponent(folderName(labBuild: false), isDirectory: true))
        }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static func folderName(labBuild: Bool) -> String { labBuild ? "LocalAIAgent Lab" : "LocalAIAgent" }

    /// Gives a new data folder a copy of another one's chats, test results, Dev files and shared notes.
    /// Only when the new folder doesn't exist yet, so it happens once and never writes over anything.
    /// Backups stay behind: they are the other app's own record of itself.
    ///
    /// The copy is made beside the folder and moved into place when it is whole, so a copy that fails
    /// halfway leaves no half-filled folder to be taken for the real one.
    @discardableResult
    static func seed(_ folder: URL, from source: URL) -> Bool {
        let files = FileManager.default
        guard !files.fileExists(atPath: folder.path),
              let items = try? files.contentsOfDirectory(atPath: source.path) else { return false }
        let draft = folder.deletingLastPathComponent().appendingPathComponent(folder.lastPathComponent + ".copying", isDirectory: true)
        try? files.removeItem(at: draft)
        do {
            try files.createDirectory(at: draft, withIntermediateDirectories: true)
            for item in items where item != "Backups" {
                try files.copyItem(at: source.appendingPathComponent(item), to: draft.appendingPathComponent(item))
            }
            try files.moveItem(at: draft, to: folder)
            return true
        } catch {
            try? files.removeItem(at: draft)
            return false
        }
    }

    #if DEBUG
    /// The lab's first copy of the public app's data, in folders made for the check.
    static func seedCheck() -> [String] {
        var lines: [String] = []
        func expect(_ name: String, _ ok: Bool) { lines.append("\(ok ? "PASS" : "FAIL") \(name)") }
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("prometheus-seed-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: root) }
        let shared = root.appendingPathComponent(folderName(labBuild: false), isDirectory: true)
        let lab = root.appendingPathComponent(folderName(labBuild: true), isDirectory: true)
        func text(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

        expect("the two apps keep different folders", folderName(labBuild: true) != folderName(labBuild: false))
        expect("nothing to copy from: no folder is made", !seed(lab, from: shared) && !files.fileExists(atPath: lab.path))

        try? files.createDirectory(at: shared.appendingPathComponent("Dev"), withIntermediateDirectories: true)
        try? files.createDirectory(at: shared.appendingPathComponent("Backups/2.0.0"), withIntermediateDirectories: true)
        try? "[{\"chat\":1}]".write(to: shared.appendingPathComponent("conversations.json"), atomically: true, encoding: .utf8)
        try? "{\"model\":[1]}".write(to: shared.appendingPathComponent("tests.json"), atomically: true, encoding: .utf8)
        try? "[]".write(to: shared.appendingPathComponent("Dev/comparisons.json"), atomically: true, encoding: .utf8)
        try? "old".write(to: shared.appendingPathComponent("Backups/2.0.0/tests.json"), atomically: true, encoding: .utf8)

        expect("the first run copies the data", seed(lab, from: shared))
        expect("chats and test results arrive whole", text(lab.appendingPathComponent("conversations.json")) == "[{\"chat\":1}]"
               && text(lab.appendingPathComponent("tests.json")) == "{\"model\":[1]}")
        expect("folders inside come too", text(lab.appendingPathComponent("Dev/comparisons.json")) == "[]")
        expect("backups stay behind", !files.fileExists(atPath: lab.appendingPathComponent("Backups").path))
        expect("nothing is left of the copy in progress", !files.fileExists(atPath: lab.path + ".copying"))
        expect("the source is untouched", text(shared.appendingPathComponent("tests.json")) == "{\"model\":[1]}"
               && files.fileExists(atPath: shared.appendingPathComponent("Backups/2.0.0/tests.json").path))

        // From here on the two folders are separate: a save in one must not reach the other.
        try? "{\"model\":[1,2]}".write(to: lab.appendingPathComponent("tests.json"), atomically: true, encoding: .utf8)
        try? "{\"model\":[1,9]}".write(to: shared.appendingPathComponent("tests.json"), atomically: true, encoding: .utf8)
        expect("a second run copies nothing", !seed(lab, from: shared))
        expect("so the lab's newer results are still there", text(lab.appendingPathComponent("tests.json")) == "{\"model\":[1,2]}")
        expect("and the public app's are its own", text(shared.appendingPathComponent("tests.json")) == "{\"model\":[1,9]}")
        return lines
    }
    #endif

    init() {
        fileURL = Self.directory.appendingPathComponent("conversations.json")
    }

    func load() -> [Conversation] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let conversations = try? decoder.decode([Conversation].self, from: data) else {
            Self.setAside(fileURL)
            return []
        }
        return conversations
    }

    /// Keeps a copy of a file that couldn't be read, because the next save would replace the only one.
    static func setAside(_ url: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let copy = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        try? FileManager.default.copyItem(at: url, to: copy)
    }

    func save(_ conversations: [Conversation]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(conversations) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Splits `<think>…</think>` blocks out of streamed text, even when tags are split across chunks.
struct ThinkTagParser {
    private var inThink = false
    private var pending = ""
    private static let open = "<think>", close = "</think>"

    var isThinking: Bool { inThink }

    mutating func feed(_ chunk: String) -> (thinking: String, answer: String) {
        pending += chunk
        var thinking = "", answer = ""
        while true {
            let tag = inThink ? Self.close : Self.open
            if let range = pending.range(of: tag) {
                let before = String(pending[..<range.lowerBound])
                if inThink { thinking += before } else { answer += before }
                pending = String(pending[range.upperBound...])
                inThink.toggle()
                continue
            }
            // Hold back a trailing partial tag such as "<thi".
            var keep = 0
            for n in stride(from: min(tag.count - 1, pending.count), through: 1, by: -1) where tag.hasPrefix(pending.suffix(n)) {
                keep = n
                break
            }
            let emit = String(pending.dropLast(keep))
            if inThink { thinking += emit } else { answer += emit }
            pending = String(pending.suffix(keep))
            return (thinking, answer)
        }
    }

    mutating func flush() -> (thinking: String, answer: String) {
        defer { pending = "" }
        return inThink ? (pending, "") : ("", pending)
    }
}
