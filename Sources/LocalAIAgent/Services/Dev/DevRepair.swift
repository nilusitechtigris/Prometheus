import Foundation

extension String {
    /// The groups of the first match, with the whole match first.
    func groups(of pattern: String, options: NSRegularExpression.Options = []) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: self).map { String(self[$0]) } ?? "" }
    }

    func matches(_ pattern: String, options: NSRegularExpression.Options = []) -> Bool {
        groups(of: pattern, options: options) != nil
    }
}

/// Why a program failed, read from what it printed.
struct DevFailure: Codable, Equatable, Sendable {
    /// Inside the project. Nil when the failure is in no file of its own.
    var file: String?
    var line: Int?
    var function: String?
    var kind: String
    var message: String
    /// The end of the output, for the model to read.
    var output: String

    /// Two failures with the same one are the same problem.
    var signature: String { "\(kind)|\(message)|\(file ?? "")|\(line ?? 0)" }

    var title: String {
        var place = ""
        if let file { place = line.map { " on line \($0) of \(file)" } ?? " in \(file)" }
        return message.isEmpty ? "\(kind)\(place)" : "\(kind)\(place): \(message)"
    }

    /// Network and files outside the project are blocked on purpose, so a fix can't get past them.
    var isSandboxLimit: Bool {
        kind.hasSuffix("PermissionError") || kind.hasSuffix("URLError") || kind.hasSuffix("gaierror")
    }

    /// `output` must already have the run's own folder taken out of its paths.
    static func parse(_ output: String) -> DevFailure? {
        let lines = output.components(separatedBy: "\n")
        var start = lines.lastIndex { $0.hasPrefix("Traceback (most recent call last)") } ?? 0
        if !lines[start...].contains(where: { $0.matches(#"^\s*File ".+", line \d+"#) }) { start = 0 }
        var frame: (file: String, line: Int, function: String?)?
        var lastFrame: Int?
        for index in start..<lines.count {
            guard let parts = lines[index].groups(of: #"^\s*File "(.+?)", line (\d+)(?:, in (.+))?\s*$"#) else { continue }
            lastFrame = index
            let path = parts[1]
            // The text is the program's own, so a number here can be anything.
            if !path.hasPrefix("/"), !path.hasPrefix("<"), let line = Int(parts[2]), line > 0, line < 10_000_000 {
                frame = (path, line, parts[3].isEmpty || parts[3] == "<module>" ? nil : parts[3])
            }
        }
        guard let lastFrame else { return nil }
        guard let errorLine = lines[(lastFrame + 1)...].first(where: { !$0.isEmpty && !$0.hasPrefix(" ") && !$0.hasPrefix("\t") }),
              let parts = errorLine.groups(of: #"^([A-Za-z_][\w.]*)(?:: (.*))?$"#) else { return nil }
        return DevFailure(file: frame?.file, line: frame?.line, function: frame?.function, kind: parts[1], message: parts[2],
                          output: String(output.suffix(1_500)))
    }

    /// For a run that ended without a traceback.
    static func ending(_ result: DevRunResult) -> DevFailure {
        if let limit = result.limit {
            return DevFailure(kind: "Limit", message: "The program \(limit).", output: String(result.output.suffix(800)))
        }
        return DevFailure(kind: "Exit", message: "It ended with exit code \(result.exitCode).", output: String(result.output.suffix(800)))
    }
}

/// Mistakes code can put right by itself, which costs no model time and can't go wrong the way a
/// model's fix can.
enum DevRepair {
    private static let plainModules: Set<String> = [
        "argparse", "base64", "bisect", "collections", "copy", "csv", "dataclasses", "decimal", "enum", "fractions", "functools", "glob",
        "hashlib", "heapq", "itertools", "json", "logging", "math", "operator", "os", "pathlib", "random", "re", "shutil", "sqlite3",
        "statistics", "string", "struct", "sys", "textwrap", "time", "typing", "unittest", "uuid",
    ]

    private static let fromModule: [String: String] = {
        var table: [String: String] = [:]
        let groups: [(String, [String])] = [
            ("collections", ["Counter", "OrderedDict", "defaultdict", "deque", "namedtuple"]),
            ("dataclasses", ["asdict", "dataclass", "field"]),
            ("datetime", ["date", "timedelta"]),
            ("decimal", ["Decimal"]),
            ("enum", ["Enum"]),
            ("fractions", ["Fraction"]),
            ("functools", ["lru_cache", "partial", "reduce", "wraps"]),
            ("math", ["ceil", "floor", "gcd", "pi", "sqrt"]),
            ("pathlib", ["Path"]),
            ("random", ["choice", "randint", "shuffle"]),
            ("time", ["sleep"]),
            ("typing", ["Any", "Callable", "Dict", "Iterable", "List", "Optional", "Set", "Tuple", "Union"]),
        ]
        for (module, names) in groups {
            for name in names { table[name] = module }
        }
        return table
    }()

    /// The import that defines a name the program used without importing it.
    static func importLine(for name: String, source: String) -> String? {
        if name == "datetime" {
            let classCalls = source.matches(#"\bdatetime\.(now|today|strptime|fromisoformat|utcnow|fromtimestamp)\("#)
            return classCalls ? "from datetime import datetime" : "import datetime"
        }
        if plainModules.contains(name) { return "import \(name)" }
        return fromModule[name].map { "from \($0) import \(name)" }
    }

    /// Puts an import below any opening comments and docstring.
    static func adding(_ line: String, to source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        var index = 0
        while index < lines.count, lines[index].hasPrefix("#") || lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index += 1 }
        if index < lines.count, let quote = ["\"\"\"", "'''"].first(where: { lines[index].hasPrefix($0) }) {
            let rest = lines[index].dropFirst(3)
            if !rest.contains(quote) {
                index += 1
                while index < lines.count, !lines[index].contains(quote) { index += 1 }
            }
            index = min(index + 1, lines.count)
        }
        lines.insert(line, at: index)
        return lines.joined(separator: "\n")
    }

    /// The whole file with one mistake put right, or nil if this one needs thought.
    static func repair(_ failure: DevFailure, source: String) -> String? {
        switch failure.kind {
        case "NameError":
            guard let name = failure.message.groups(of: #"name '(\w+)' is not defined"#)?[1],
                  let line = importLine(for: name, source: source), !source.contains(line) else { return nil }
            return adding(line, to: source)
        case "TabError":
            return source.replacingOccurrences(of: "\t", with: "    ")
        default:
            return nil
        }
    }

    /// Small models often define `main()` and never call it, so the program runs and does nothing.
    static func callingMain(_ source: String) -> String? {
        guard source.matches(#"^def main\(\s*\)\s*(->.*)?:"#, options: .anchorsMatchLines),
              !source.matches(#"^\s*main\(\)"#, options: .anchorsMatchLines) else { return nil }
        let ending = source.hasSuffix("\n") ? "" : "\n"
        return source + ending + "\n\nif __name__ == \"__main__\":\n    main()\n"
    }

    /// The code in a model's reply: the largest fenced block, or else the text from its first line of
    /// code. A block cut off by the token limit still counts, so the caller can find it broken.
    static func code(in reply: String, python: Bool = true) -> String? {
        var blocks: [[String]] = []
        var current: [String]?
        var wanted = true
        for line in reply.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let open = current {
                    if wanted { blocks.append(open) }
                    current = nil
                } else {
                    let tag = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
                    wanted = !python || ["", "python", "python3", "py"].contains(tag)
                    current = []
                }
            } else {
                current?.append(line)
            }
        }
        if let open = current, wanted { blocks.append(open) }
        if let largest = blocks.max(by: { $0.joined().count < $1.joined().count }) {
            let text = largest.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !text.isEmpty { return text + "\n" }
        }
        guard reply.contains("```") == false else { return nil }
        guard python else {
            let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text + "\n"
        }
        let lines = reply.components(separatedBy: "\n")
        guard let first = lines.firstIndex(where: { $0.matches(#"^(import |from \S+ import |def |class |@\w|#!|if __name__|print\()"#) }) else { return nil }
        return lines[first...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static let placeholder = #"^\s*\.\.\.\s*$|#\s*\.\.\.|#.*\b(rest of|remaining|existing|unchanged|same as (before|above)|previous code|other (functions|methods)|code here|implement this|add your)\b"#

    static func hasPlaceholders(_ code: String) -> Bool {
        code.matches(placeholder, options: [.caseInsensitive, .anchorsMatchLines])
    }

    /// The reply without lines that stand in for code, ready to be fitted into the file it came from.
    static func withoutPlaceholders(_ code: String) -> String {
        code.components(separatedBy: "\n").filter { !hasPlaceholders($0) }.joined(separator: "\n")
    }
}
