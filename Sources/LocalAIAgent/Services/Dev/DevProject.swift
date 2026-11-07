import Darwin
import Foundation

/// One thing in the project's file list.
struct DevEntry: Identifiable, Hashable, Sendable {
    let path: String
    let isFolder: Bool
    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var depth: Int { path.filter { $0 == "/" }.count }
    var isPython: Bool { !isFolder && path.hasSuffix(".py") }
    var isPage: Bool { !isFolder && DevWeb.isPage(path) }
    var isRunnable: Bool { isPython || isPage }
}

/// A project folder. Everything the agent touches goes through here, so a path a model made up can't
/// reach outside the folder, whatever it says.
struct DevProject: Sendable, Equatable {
    enum Problem: LocalizedError {
        case outside(String)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .outside(let path): return "\(path) isn't inside the project."
            case .unreadable(let path): return "\(path) can't be read as text."
            }
        }
    }

    let root: URL
    var name: String { root.lastPathComponent }

    /// The folder as a program sees it, which is how paths appear in tracebacks.
    var realPath: String {
        guard let real = realpath(root.path, nil) else { return root.path }
        defer { free(real) }
        return String(cString: real)
    }

    private static let skipped: Set<String> = ["__pycache__", "node_modules", "venv", "env", "build", "dist", "site-packages"]
    private static let maxEntries = 3_000
    /// Longer files stay out of the agent's reach, since no small model could read one.
    static let maxTextBytes = 2 << 20

    init(root: URL) {
        self.root = root.resolvingSymlinksInPath()
    }

    /// The real location of a path inside the project. Refuses anything that would lead out of it,
    /// including through a link inside the project, and hidden files such as .git.
    func url(for path: String) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !path.hasPrefix("/"), !path.hasPrefix("~"), !parts.isEmpty,
              parts.allSatisfy({ !$0.hasPrefix(".") && !$0.contains("\0") && !$0.contains("\\") }) else { throw Problem.outside(path) }
        let url = parts.reduce(root) { $0.appendingPathComponent($1) }
        var existing = url
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != root.path {
            existing.deleteLastPathComponent()
        }
        let real = existing.resolvingSymlinksInPath().path
        guard real == root.path || real.hasPrefix(root.path + "/") else { throw Problem.outside(path) }
        return url
    }

    func exists(_ path: String) -> Bool {
        (try? url(for: path)).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// Nil for a file that's missing, but also for one that isn't text or is too large, so "nil" alone
    /// doesn't mean a file is new. That's what `exists` is for.
    func read(_ path: String) -> String? {
        contents(of: path, limit: Self.maxTextBytes).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// A file's bytes, safe against the file changing under the check. A program running in the Terminal
    /// can swap a file for a link to somewhere else just after `url(for:)` looks at it, so that only
    /// narrows it down: the file is opened first, and it's the open file whose real place gets checked.
    func contents(of path: String, limit: Int) -> Data? {
        guard let url = try? url(for: path) else { return nil }
        return opened(url, limit: limit)
    }

    func opened(_ url: URL, limit: Int) -> Data? {
        // O_NONBLOCK so that a named pipe can't hang this.
        let file = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { return nil }
        defer { close(file) }
        var place = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(file, F_GETPATH, &place) != -1 else { return nil }
        let real = String(cString: place), inside = realPath + "/"
        guard real.hasPrefix(inside), !real.dropFirst(inside.count).split(separator: "/").contains(where: { $0.hasPrefix(".") }) else { return nil }
        var details = stat()
        guard fstat(file, &details) == 0, details.st_mode & S_IFMT == S_IFREG, details.st_size <= limit else { return nil }
        return FileHandle(fileDescriptor: file, closeOnDealloc: false).readDataToEndOfFile()
    }

    func write(_ text: String, to path: String) throws {
        let url = try url(for: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Only for undoing a file the agent created.
    func remove(_ path: String) throws {
        try FileManager.default.removeItem(at: url(for: path))
    }

    /// Every file and folder worth showing, folders first.
    func entries() -> [DevEntry] {
        var found: [DevEntry] = []
        walk(root, prefix: "", into: &found)
        return found
    }

    var pythonFiles: [String] { entries().filter(\.isPython).map(\.path) }

    private func walk(_ folder: URL, prefix: String, into found: inout [DevEntry]) {
        guard found.count < Self.maxEntries else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var folders: [String] = [], files: [String] = []
        for name in names where !name.hasPrefix(".") && !Self.skipped.contains(name) {
            let item = folder.appendingPathComponent(name)
            var isFolder: ObjCBool = false
            // A link that leads outside stays out of the list, and no link gets followed as a folder,
            // since one could lead back to itself.
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isFolder), (try? url(for: prefix + name)) != nil else { continue }
            let isLink = (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
            if isFolder.boolValue {
                if !isLink { folders.append(name) }
            } else {
                files.append(name)
            }
        }
        for name in folders.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) where found.count < Self.maxEntries {
            found.append(DevEntry(path: prefix + name, isFolder: true))
            walk(folder.appendingPathComponent(name), prefix: prefix + name + "/", into: &found)
        }
        for name in files.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) where found.count < Self.maxEntries {
            found.append(DevEntry(path: prefix + name, isFolder: false))
        }
    }
}

/// What the agent did to one file, kept so it can be seen and undone.
struct DevChange: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var path: String
    /// Nil when the agent created the file.
    var before: String?
    var after: String

    var isNew: Bool { before == nil }

    /// Lines added and removed.
    var counts: (added: Int, removed: Int) {
        let old = (before ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let new = after.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let difference = new.difference(from: old)
        return (difference.insertions.count, difference.removals.count)
    }
}
