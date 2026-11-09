import Foundation

/// Copies the saved data before a build of the app first touches it. A build that reads a file wrongly shows
/// it empty, and its next save replaces the only copy. So every build, newer or older, starts by keeping one.
enum DataBackup {
    /// What the app reads back, and so what's worth keeping.
    static let items = ["conversations.json", "tests.json", "Dev", "Shared Notes"]
    /// Copies this code made carry this prefix, so tidying up never touches a folder someone else put there.
    static let prefix = "auto "
    static let kept = 5
    private static let stampName = ".last-build"

    static var folder: URL { ConversationStore.directory.appendingPathComponent("Backups", isDirectory: true) }

    /// The build that's running: its version, and its commit when it knows one.
    static var build: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return [version, AppUpdater.commit.map { String($0.prefix(7)) }].compactMap { $0 }.joined(separator: " ")
    }

    /// Call before anything loads. Returns the copy it made, or nil when this build already has one or there
    /// was nothing to copy.
    @discardableResult
    static func runIfNeeded(in directory: URL = ConversationStore.directory, build: String = DataBackup.build, now: Date = Date()) -> URL? {
        let files = FileManager.default
        let backups = directory.appendingPathComponent("Backups", isDirectory: true)
        let stamp = backups.appendingPathComponent(stampName)
        if (try? String(contentsOf: stamp, encoding: .utf8)) == build { return nil }

        func remember() {
            try? files.createDirectory(at: backups, withIntermediateDirectories: true)
            try? build.write(to: stamp, atomically: true, encoding: .utf8)
        }
        let present = items.filter { files.fileExists(atPath: directory.appendingPathComponent($0).path) }
        guard !present.isEmpty else {
            remember()
            return nil
        }

        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HHmmss"
        let name = build.map { $0.isLetter || $0.isNumber || $0 == "." ? $0 : " " }
        let copy = backups.appendingPathComponent("\(prefix)\(format.string(from: now)) before \(String(name))", isDirectory: true)
        do {
            try files.createDirectory(at: copy, withIntermediateDirectories: true)
            for item in present {
                try files.copyItem(at: directory.appendingPathComponent(item), to: copy.appendingPathComponent(item))
            }
        } catch {
            // Half a copy would pass for a whole one. Leave the stamp alone, so the next launch tries again.
            try? files.removeItem(at: copy)
            return nil
        }
        remember()
        prune(backups)
        return copy
    }

    /// Keeps the newest few of its own copies. Their names start with the date, so they sort by age.
    private static func prune(_ backups: URL) {
        let files = FileManager.default
        let own = ((try? files.contentsOfDirectory(atPath: backups.path)) ?? []).filter { $0.hasPrefix(prefix) }.sorted()
        for name in own.dropLast(kept) { try? files.removeItem(at: backups.appendingPathComponent(name)) }
    }

    #if DEBUG
    /// Checks the copying, the once-per-build rule and the tidying up, in a folder of its own.
    static func selfCheck() -> [String] {
        var lines: [String] = []
        func expect(_ name: String, _ ok: Bool) { lines.append("\(ok ? "PASS" : "FAIL") \(name)") }
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("prometheus-backup-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: root) }
        try? files.createDirectory(at: root, withIntermediateDirectories: true)
        let backups = root.appendingPathComponent("Backups")
        func copies() -> [String] { ((try? files.contentsOfDirectory(atPath: backups.path)) ?? []).filter { $0.hasPrefix(prefix) }.sorted() }
        let day = Date(timeIntervalSince1970: 1_800_000_000)

        expect("nothing saved yet: no copy", runIfNeeded(in: root, build: "2.0.0 aaa", now: day) == nil && copies().isEmpty)

        try? "[{\"chat\":1}]".write(to: root.appendingPathComponent("conversations.json"), atomically: true, encoding: .utf8)
        try? "{\"model\":[]}".write(to: root.appendingPathComponent("tests.json"), atomically: true, encoding: .utf8)
        try? files.createDirectory(at: root.appendingPathComponent("Dev"), withIntermediateDirectories: true)
        try? "[1]".write(to: root.appendingPathComponent("Dev/comparisons.json"), atomically: true, encoding: .utf8)
        expect("same build again: still no copy", runIfNeeded(in: root, build: "2.0.0 aaa", now: day) == nil && copies().isEmpty)

        let first = runIfNeeded(in: root, build: "2.0.0 bbb", now: day.addingTimeInterval(60))
        let kept = first.map { (try? String(contentsOf: $0.appendingPathComponent("conversations.json"), encoding: .utf8)) == "[{\"chat\":1}]" } ?? false
        let nested = first.map { files.fileExists(atPath: $0.appendingPathComponent("Dev/comparisons.json").path) } ?? false
        expect("a new build copies the files as they are: \(first?.lastPathComponent ?? "none")", kept && nested && copies().count == 1)
        expect("the original stays", files.fileExists(atPath: root.appendingPathComponent("conversations.json").path))
        expect("that build doesn't copy twice", runIfNeeded(in: root, build: "2.0.0 bbb", now: day.addingTimeInterval(120)) == nil && copies().count == 1)
        expect("an older build copies too", runIfNeeded(in: root, build: "1.0.0 old", now: day.addingTimeInterval(180)) != nil && copies().count == 2)

        try? files.createDirectory(at: backups.appendingPathComponent("2026-11-05"), withIntermediateDirectories: true)
        for number in 0..<7 { runIfNeeded(in: root, build: "2.0.0 n\(number)", now: day.addingTimeInterval(Double(300 + number * 60))) }
        expect("only the newest \(Self.kept) of its own copies stay: \(copies().count)", copies().count == Self.kept && copies().last?.contains("n6") == true)
        expect("a folder it didn't make is left alone", files.fileExists(atPath: backups.appendingPathComponent("2026-11-05").path))

        // A copy that can't finish must not count as made.
        let blocked = root.appendingPathComponent("blocked", isDirectory: true)
        try? files.createDirectory(at: blocked, withIntermediateDirectories: true)
        try? "x".write(to: blocked.appendingPathComponent("conversations.json"), atomically: true, encoding: .utf8)
        try? "not a folder".write(to: blocked.appendingPathComponent("Backups"), atomically: true, encoding: .utf8)
        expect("a copy that fails leaves no stamp", runIfNeeded(in: blocked, build: "2.0.0 ccc", now: day) == nil
               && !files.fileExists(atPath: blocked.appendingPathComponent("Backups/\(stampName)").path))
        return lines
    }
    #endif
}
