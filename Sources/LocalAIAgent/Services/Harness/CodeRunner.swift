import Darwin
import Foundation

/// Runs model-written code for the harness behind hard limits, enforced by macOS rather than by
/// anything the code or the model can talk its way around:
/// - a deny-by-default sandbox: no network, no other programs, no forking, and no reading or
///   writing anything except its own empty temporary folder and the language's own files;
/// - kernel limits on CPU time and file size, plus a wall clock and a memory ceiling here;
/// - a capped amount of output, and a folder that's deleted afterwards.
enum CodeRunner {
    enum Language: String {
        case python, javascript
    }

    struct Outcome {
        var output: String
        var succeeded: Bool
        /// Why it was stopped, if a limit ended it.
        var limit: String?
    }

    static let wallSeconds = 10.0
    private static let cpuSeconds = 10
    private static let maxFootprint: UInt64 = 1 << 30
    private static let maxOutputBytes = 8_000
    private static let maxFileBytes = 10 << 20

    private struct Interpreter {
        let executable: String
        let environment: [String: String]
        var arguments: [String] = []
        let readable: [String]
        let fileName: String
    }

    private static func interpreter(_ language: Language) -> Interpreter? {
        switch language {
        case .python: return python
        case .javascript: return node
        }
    }

    /// The real interpreter binary: the launcher in front of it would have to start another program.
    private static let python: Interpreter? = {
        let manager = FileManager.default
        var roots = ["/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions",
                     "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions"]
        let homebrew = "/opt/homebrew/opt"
        for name in (try? manager.contentsOfDirectory(atPath: homebrew)) ?? [] where name.hasPrefix("python@") {
            roots.append("\(homebrew)/\(name)/Frameworks/Python.framework/Versions")
        }
        for root in roots {
            for version in ((try? manager.contentsOfDirectory(atPath: root)) ?? []).sorted().reversed() where version != "Current" {
                let home = URL(fileURLWithPath: "\(root)/\(version)").resolvingSymlinksInPath().path
                let binary = "\(home)/Resources/Python.app/Contents/MacOS/Python"
                if manager.isExecutableFile(atPath: binary) {
                    return Interpreter(executable: binary,
                                       environment: ["PYTHONHOME": home, "PYTHONDONTWRITEBYTECODE": "1"],
                                       arguments: ["-I", "-S"], readable: [home], fileName: "main.py")
                }
            }
        }
        return nil
    }()

    private static let node: Interpreter? = {
        for candidate in ["/opt/homebrew/bin/node", "/usr/local/bin/node"] {
            let binary = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
            if FileManager.default.isExecutableFile(atPath: binary) {
                let prefix = candidate.hasPrefix("/opt") ? "/opt/homebrew" : "/usr/local"
                return Interpreter(executable: binary, environment: ["OPENSSL_CONF": "/dev/null"],
                                   readable: ["\(prefix)/Cellar", "\(prefix)/opt"], fileName: "main.js")
            }
        }
        return nil
    }()

    /// Deny everything, then allow only what the interpreter needs to start.
    private static func profile(for interpreter: Interpreter, workFolder: String) -> String {
        func quoted(_ path: String) -> String {
            "\"\(path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        let readable = (["/usr/lib", "/usr/share", "/System", "/private/var/db/dyld", workFolder] + interpreter.readable)
            .map { "(subpath \(quoted($0)))" }
            .joined(separator: " ")
        return """
        (version 1)
        (deny default)
        (allow process-exec (literal \(quoted(interpreter.executable))))
        (allow file-read-metadata)
        (allow file-read* (literal "/") (literal "/dev/null") (literal "/dev/urandom") (literal "/dev/random") \(readable))
        (allow file-write* (subpath \(quoted(workFolder))) (literal "/dev/null"))
        (allow sysctl-read)
        """
    }

    /// Runs `code`, with `files` placed beside it. Never takes longer than the wall clock limit.
    static func run(_ code: String, language: Language, files: [String: String] = [:]) async -> Outcome {
        await Task.detached(priority: .userInitiated) { execute(code, language: language, files: files) }.value
    }

    private final class Output: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private(set) var overflowed = false

        func append(_ chunk: Data) {
            lock.lock()
            defer { lock.unlock() }
            data.append(chunk.prefix(CodeRunner.maxOutputBytes - min(data.count, CodeRunner.maxOutputBytes)))
            if chunk.count > 0, data.count >= CodeRunner.maxOutputBytes { overflowed = true }
        }

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }
    }

    /// Where the sandbox's Python lives, for running a project's own files.
    static var pythonRuntime: (executable: String, home: String)? {
        python.flatMap { interpreter in interpreter.readable.first.map { (interpreter.executable, $0) } }
    }

    static func footprint(of pid: pid_t) -> UInt64 {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return result == 0 ? info.ri_phys_footprint : 0
    }

    private static func execute(_ code: String, language: Language, files: [String: String]) -> Outcome {
        guard let interpreter = interpreter(language) else {
            return Outcome(output: "\(language.rawValue) isn't available on this Mac.", succeeded: false, limit: nil)
        }
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent("prometheus-code-\(UUID().uuidString)", isDirectory: true)
        guard (try? manager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else {
            return Outcome(output: "Couldn't create a work folder.", succeeded: false, limit: nil)
        }
        defer { try? manager.removeItem(at: folder) }
        // realpath keeps the /private prefix that resolvingSymlinksInPath drops, and the sandbox needs it.
        guard let resolved = realpath(folder.path, nil) else {
            return Outcome(output: "Couldn't find the work folder.", succeeded: false, limit: nil)
        }
        let workPath = String(cString: resolved)
        free(resolved)
        do {
            try code.write(to: folder.appendingPathComponent(interpreter.fileName), atomically: true, encoding: .utf8)
            for (name, contents) in files where name == URL(fileURLWithPath: name).lastPathComponent {
                try contents.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
        } catch {
            return Outcome(output: "Couldn't write the code.", succeeded: false, limit: nil)
        }

        // The shell sets the kernel limits, then becomes the sandboxed interpreter, keeping the same pid.
        let script = """
        ulimit -c 0; ulimit -t \(cpuSeconds); ulimit -f \(maxFileBytes / 512); ulimit -n 64
        profile=$1; shift
        exec /usr/bin/sandbox-exec -p "$profile" "$@"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", profile(for: interpreter, workFolder: workPath), interpreter.executable]
            + interpreter.arguments + [interpreter.fileName]
        process.currentDirectoryURL = URL(fileURLWithPath: workPath)
        process.environment = interpreter.environment.merging(
            ["HOME": workPath, "TMPDIR": workPath, "PATH": "/nonexistent", "LANG": "en_US.UTF-8"]) { current, _ in current }

        let pipe = Pipe()
        let output = Output()
        pipe.fileHandleForReading.readabilityHandler = { handle in output.append(handle.availableData) }
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return Outcome(output: "Couldn't start the sandbox.", succeeded: false, limit: nil)
        }

        let start = Date()
        var limit: String?
        while finished.wait(timeout: .now() + 0.1) == .timedOut {
            if Date().timeIntervalSince(start) > wallSeconds {
                limit = "ran over the \(Int(wallSeconds)) second limit"
            } else if footprint(of: process.processIdentifier) > maxFootprint {
                limit = "used over the 1 GB memory limit"
            } else if output.overflowed {
                limit = "printed too much output"
            }
            if limit != nil {
                kill(process.processIdentifier, SIGKILL)
                finished.wait()
                break
            }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        output.append(pipe.fileHandleForReading.availableData)

        let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if limit == nil, process.terminationReason == .uncaughtSignal { limit = "was stopped by a system limit" }
        return Outcome(output: limit.map { text.isEmpty ? "The program \($0)." : "\(text)\n[The program \($0).]" } ?? text,
                       succeeded: limit == nil && process.terminationStatus == 0, limit: limit)
    }
}
