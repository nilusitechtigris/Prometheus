import Darwin
import Foundation

/// How a program ended.
struct DevRunResult: Sendable, Equatable {
    var output: String
    var exitCode: Int32
    /// Why it was ended, if a limit did it.
    var limit: String?
    var stoppedByUser = false
    var seconds: Double

    var succeeded: Bool { exitCode == 0 && limit == nil && !stoppedByUser }
}

/// A program running in the sandbox. Model-written code runs here without anyone reading it first, so
/// macOS holds it to the project folder: no network, no other programs, and nothing else on disk.
final class DevProcess: @unchecked Sendable {
    struct Limits: Sendable {
        var seconds: Double
        var memory: UInt64 = 2 << 30
        var outputBytes = 256_000
        var fileBytes = 100 << 20
    }

    static let agentLimits = Limits(seconds: 15)
    static let terminalLimits = Limits(seconds: 600)

    private let process = Process()
    private let input = Pipe()
    private let lock = NSLock()
    private let scratch: URL
    private let limits: Limits
    private let onOutput: @Sendable (String) -> Void
    private var text = ""
    private var bytes = 0
    private var stopped = false
    private var inputClosed = false
    private var limit: String?
    private let started = Date()
    /// Without this, typing into a program that just ended would end the app with it.
    private static let ignoreBrokenPipes: Void = { signal(SIGPIPE, SIG_IGN) }()

    /// Everything the interpreter is given. `arguments` come after the interpreter's own.
    init?(arguments: [String], in project: URL, limits: Limits, onOutput: @escaping @Sendable (String) -> Void = { _ in }) {
        guard let python = CodeRunner.pythonRuntime,
              let projectPath = realpath(project.path, nil).map({ pointer -> String in
                  defer { free(pointer) }
                  return String(cString: pointer)
              }) else { return nil }
        _ = Self.ignoreBrokenPipes
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("prometheus-dev-\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
              let resolved = realpath(folder.path, nil) else { return nil }
        let scratchPath = String(cString: resolved)
        free(resolved)
        scratch = folder
        self.limits = limits
        self.onOutput = onOutput

        // The shell sets the kernel limits, then becomes the sandboxed interpreter, keeping the same pid.
        let script = """
        ulimit -c 0; ulimit -t \(max(Int(limits.seconds) + 5, 10)); ulimit -f \(limits.fileBytes / 512); ulimit -n 256
        profile=$1; shift
        exec /usr/bin/sandbox-exec -p "$profile" "$@"
        """
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", Self.profile(python: python.executable, home: python.home, project: projectPath, scratch: scratchPath),
                             python.executable, "-B", "-u"] + arguments
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        process.environment = ["PYTHONHOME": python.home, "PYTHONPATH": projectPath, "PYTHONDONTWRITEBYTECODE": "1", "PYTHONUNBUFFERED": "1",
                               "PYTHONIOENCODING": "utf-8", "HOME": scratchPath, "TMPDIR": scratchPath, "PATH": "/nonexistent", "LANG": "en_US.UTF-8"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = input
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.received(handle.availableData)
        }
    }

    /// Deny everything, then allow only the interpreter, the project and a throwaway folder.
    private static func profile(python: String, home: String, project: String, scratch: String) -> String {
        func quoted(_ path: String) -> String {
            "\"\(path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        let readable = ["/usr/lib", "/usr/share", "/System", "/private/var/db/dyld", project, scratch, home]
            .map { "(subpath \(quoted($0)))" }.joined(separator: " ")
        // Later rules win. The folder itself can't be replaced, say with a link for the next run to follow.
        // Hidden files can't be written either: a program that plants .git/hooks/pre-commit would get
        // to run outside the sandbox at the next commit.
        return """
        (version 1)
        (deny default)
        (allow process-exec (literal \(quoted(python))))
        (allow file-read-metadata)
        (allow file-read* (literal "/") (literal "/dev/null") (literal "/dev/urandom") (literal "/dev/random") \(readable))
        (allow file-write* (subpath \(quoted(project))) (subpath \(quoted(scratch))) (literal "/dev/null"))
        (deny file-write* (literal \(quoted(project))) (literal \(quoted(scratch))))
        (deny file-write* (regex #"^\(pattern(for: project))/(.*/)?\\.[^/]*(/.*)?$"))
        (allow sysctl-read)
        """
    }

    /// A path as a sandbox regex. A quote would end the literal, so it matches any character instead.
    private static func pattern(for path: String) -> String {
        var escaped = ""
        for character in path {
            if character == "\"" {
                escaped.append(".")
            } else {
                if "\\.*+?()[]{}^$|".contains(character) { escaped.append("\\") }
                escaped.append(character)
            }
        }
        return escaped
    }

    private func received(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        let room = limits.outputBytes - bytes
        let chunk = String(decoding: data.prefix(max(room, 0)), as: UTF8.self)
        bytes += data.count
        text += chunk
        let overflowed = bytes > limits.outputBytes
        if overflowed, limit == nil { limit = "printed too much output" }
        lock.unlock()
        if !chunk.isEmpty { onOutput(chunk) }
        if overflowed { end() }
    }

    /// Before launch the pid is 0, and kill(0) would end every process in the app's group, the app
    /// included. After exit the pid may belong to something else by now.
    private func end() {
        guard process.isRunning else { return }
        kill(process.processIdentifier, SIGKILL)
    }

    /// Types into the program, for one that's waiting at `input()`. A program that has already
    /// ended just doesn't get it.
    func send(_ text: String) {
        lock.lock()
        let closed = inputClosed
        lock.unlock()
        guard !closed else { return }
        try? input.fileHandleForWriting.write(contentsOf: Data(text.utf8))
    }

    /// Tells the program no more input is coming, so `input()` raises EOFError rather than waiting.
    func closeInput() {
        lock.lock()
        let closed = inputClosed
        inputClosed = true
        lock.unlock()
        if !closed { try? input.fileHandleForWriting.close() }
    }

    /// Works at any time. Stopped before it starts, the program never starts.
    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        end()
    }

    /// Runs the program to its end, or to the limit that ends it.
    func run() async -> DevRunResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                continuation.resume(returning: runBlocking())
            }
        }
    }

    private func runBlocking() -> DevRunResult {
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        lock.lock()
        let cancelled = stopped
        lock.unlock()
        guard !cancelled else {
            try? FileManager.default.removeItem(at: scratch)
            return DevRunResult(output: "", exitCode: -1, stoppedByUser: true, seconds: 0)
        }
        do {
            try process.run()
        } catch {
            return DevRunResult(output: "Couldn't start the sandbox: \(error.localizedDescription)", exitCode: -1, seconds: 0)
        }
        // A stop that came in just as it started found nothing running yet.
        lock.lock()
        let late = stopped
        lock.unlock()
        if late { end() }
        while finished.wait(timeout: .now() + 0.1) == .timedOut {
            var reason: String?
            if Date().timeIntervalSince(started) > limits.seconds {
                reason = "ran over the \(Int(limits.seconds)) second limit"
            } else if CodeRunner.footprint(of: process.processIdentifier) > limits.memory {
                reason = "used over the \(limits.memory >> 30) GB memory limit"
            }
            if let reason {
                lock.lock()
                if limit == nil { limit = reason }
                lock.unlock()
                end()
                finished.wait()
                break
            }
        }
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if let rest = (process.standardOutput as? Pipe)?.fileHandleForReading.availableData { received(rest) }
        try? FileManager.default.removeItem(at: scratch)
        lock.lock()
        defer { lock.unlock() }
        var ending = limit
        if ending == nil, !stopped, process.terminationReason == .uncaughtSignal { ending = "was stopped by a system limit" }
        return DevRunResult(output: text, exitCode: process.terminationStatus, limit: ending, stoppedByUser: stopped,
                            seconds: Date().timeIntervalSince(started))
    }
}

/// Runs short Python programs to their end, with nobody at the keyboard.
enum DevRunner {
    /// Anything `input()` asks past the end of `input` raises EOFError.
    static func run(_ arguments: [String], in folder: URL, input: String? = nil, limits: DevProcess.Limits = DevProcess.agentLimits) async -> DevRunResult {
        guard let process = DevProcess(arguments: arguments, in: folder, limits: limits) else {
            return DevRunResult(output: "Python isn't available. Install the Command Line Tools with: xcode-select --install", exitCode: -1, seconds: 0)
        }
        // On its own thread: a long input fills the pipe and waits for the program to read it.
        DispatchQueue.global(qos: .userInitiated).async {
            if let input { process.send(input) }
            process.closeInput()
        }
        return await withTaskCancellationHandler {
            await process.run()
        } onCancel: {
            process.stop()
        }
    }

    /// Runs a project's tests, both unittest classes and plain test_ functions, so a project
    /// needs nothing installed. Takes module names after the script.
    static let testScript = #"""
    import importlib, inspect, os, sys, traceback, unittest
    sys.path.insert(0, os.getcwd())
    ran, failed = 0, 0
    for name in sys.argv[1:]:
        module = importlib.import_module(name)
        suite = unittest.defaultTestLoader.loadTestsFromModule(module)
        if suite.countTestCases():
            result = unittest.TextTestRunner(stream=sys.stdout, verbosity=0).run(suite)
            ran += result.testsRun
            failed += len(result.failures) + len(result.errors)
        for key, value in list(vars(module).items()):
            if key.startswith("test") and inspect.isfunction(value) and value.__module__ == name and not inspect.signature(value).parameters:
                ran += 1
                try:
                    value()
                except Exception:
                    failed += 1
                    traceback.print_exc(file=sys.stdout)
    print("%d tests, %d failed" % (ran, failed))
    sys.exit(1 if failed else 0)
    """#

    static func testArguments(_ paths: [String]) -> [String] {
        ["-c", testScript] + paths.map { ($0 as NSString).deletingPathExtension.replacingOccurrences(of: "/", with: ".") }
    }
}
