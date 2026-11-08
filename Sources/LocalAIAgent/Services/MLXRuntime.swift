import Foundation

/// The parts of MLX LM its chat server doesn't cover: starting that server, and downloading and removing
/// models in the Hugging Face cache it reads from.
enum MLXRuntime {
    enum Failure: LocalizedError {
        case missingTool
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .missingTool: return "MLX LM isn't installed. Install it with: brew install mlx-lm"
            case .failed(let reason): return reason
            }
        }
    }

    private static let serverPaths = ["/opt/homebrew/bin/mlx_lm.server", "/usr/local/bin/mlx_lm.server"]
    /// Homebrew keeps the `hf` tool that comes with MLX LM inside the package.
    private static let hfPaths = ["/opt/homebrew/opt/mlx-lm/libexec/bin/hf", "/usr/local/opt/mlx-lm/libexec/bin/hf",
                                  "/opt/homebrew/bin/hf", "/usr/local/bin/hf"]

    private static func tool(in paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The server to run. A debug build can be pointed at another one, to try what happens when it fails.
    private static var serverTool: String? {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["LOCALAI_MLX_SERVER"], FileManager.default.isExecutableFile(atPath: path) { return path }
        #endif
        return tool(in: serverPaths)
    }

    static var isInstalled: Bool { serverTool != nil }

    /// Where the server and `hf` keep models, worked out the way they do it.
    static var cache: URL {
        let env = ProcessInfo.processInfo.environment
        if let hub = env["HF_HUB_CACHE"], !hub.isEmpty { return URL(fileURLWithPath: hub) }
        if let home = env["HF_HOME"], !home.isEmpty { return URL(fileURLWithPath: home).appendingPathComponent("hub") }
        let base = env["XDG_CACHE_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache")
        return base.appendingPathComponent("huggingface/hub")
    }

    /// The server's model list fails outright when the cache folder doesn't exist yet, which is the case
    /// on a Mac that has never downloaded a model. It answers its health check fine, so without the
    /// folder the app saw it come online and go offline again on every check.
    static func prepareCache() {
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    }

    private static func environment(_ extra: [String: String]) -> [String: String] {
        ProcessInfo.processInfo.environment.merging(extra.merging(["HF_HUB_DISABLE_TELEMETRY": "1"]) { new, _ in new }) { _, new in new }
    }

    /// What the server prints, kept so a failure can be explained. The run before sits next to it.
    static var log: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Prometheus/mlx-server.log")
    }

    /// The server keeps the conversations it has read, so the next request can skip what they share. It keeps
    /// ten of them however big they are, and keeps them after switching to another model. A day of long tests
    /// on big models fills the memory that way, and the request that can't get any more stops the server's
    /// generation for good. This keeps them to an eighth of the memory, which still holds a few long ones.
    static var promptCacheBytes: UInt64 { ProcessInfo.processInfo.physicalMemory / 8 }

    /// Offline, because the server otherwise asks Hugging Face about a model each time it loads one.
    /// Only downloads someone chose should go online.
    static func startServer(port: Int) -> Process? {
        guard let path = serverTool else { return nil }
        prepareCache()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--host", "127.0.0.1", "--port", "\(port)", "--prompt-cache-bytes", "\(promptCacheBytes)"]
        process.environment = environment(["HF_HUB_OFFLINE": "1"])
        let output = startLog()
        process.standardOutput = output ?? FileHandle.nullDevice
        process.standardError = output ?? FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        return (try? process.run()) == nil ? nil : process
    }

    private static func startLog() -> FileHandle? {
        let fm = FileManager.default
        try? fm.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        let previous = log.deletingPathExtension().appendingPathExtension("previous.log")
        try? fm.removeItem(at: previous)
        try? fm.moveItem(at: log, to: previous)
        fm.createFile(atPath: log.path, contents: nil)
        return try? FileHandle(forWritingTo: log)
    }

    /// Why the server's generation stopped, from the line it logs when that happens.
    static func stopReason() -> String? {
        guard let handle = try? FileHandle(forReadingFrom: log) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 200_000 ? size - 200_000 : 0)
        let text = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
        let marker = "generation thread died: "
        guard let line = text.split(whereSeparator: \.isNewline).last(where: { $0.contains(marker) }),
              let range = line.range(of: marker) else { return nil }
        let reason = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return reason.isEmpty ? nil : String(reason.prefix(300))
    }

    /// Waits for a server to exit, forcing it after a few seconds, so a new one can have its port.
    static func waitForExit(_ process: Process) async {
        for _ in 0..<50 where process.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        for _ in 0..<20 where process.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
    }

    /// Stops an MLX LM server the app didn't start that holds the port, such as one left behind when the app
    /// crashed. Only called once that server has said its generation stopped, so nothing is lost. Anything
    /// else on the port is left alone. Returns whether the port is free now.
    @discardableResult
    static func stopStrayServer(port: Int) async -> Bool {
        let pids = await Task.detached { () -> [pid_t] in
            let listening = run("/usr/sbin/lsof", ["-nP", "-t", "-iTCP:\(port)", "-sTCP:LISTEN"])
            return listening.split(whereSeparator: \.isNewline).compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
                .filter { run("/bin/ps", ["-o", "command=", "-p", "\($0)"]).contains("mlx_lm") }
        }.value
        guard !pids.isEmpty else { return false }
        for pid in pids { kill(pid, SIGTERM) }
        for _ in 0..<50 {
            if pids.allSatisfy({ kill($0, 0) != 0 }) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        for pid in pids { kill(pid, SIGKILL) }
        try? await Task.sleep(for: .milliseconds(500))
        return true
    }

    private static func run(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Downloads a repo, reporting how much of `bytes` has arrived. Stopping the stream stops the download,
    /// and the next attempt carries on from what's there.
    static func download(_ repo: String, bytes: Int64) -> AsyncThrowingStream<OllamaBackend.PullUpdate, Error> {
        AsyncThrowingStream { continuation in
            guard let path = tool(in: hfPaths) else {
                continuation.finish(throwing: Failure.missingTool)
                return
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["download", repo]
            process.environment = environment(["HF_HUB_DISABLE_PROGRESS_BARS": "1"])
            process.standardOutput = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            let log = FileManager.default.temporaryDirectory.appendingPathComponent("prometheus-hf-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            process.standardError = try? FileHandle(forWritingTo: log)
            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
                return
            }
            continuation.onTermination = { _ in
                if process.isRunning { process.terminate() }
            }
            Task.detached {
                defer { try? FileManager.default.removeItem(at: log) }
                while process.isRunning {
                    continuation.yield(.init(status: "downloading", completed: min(onDisk(repo), bytes), total: bytes))
                    try? await Task.sleep(for: .milliseconds(500))
                }
                if process.terminationReason == .exit, process.terminationStatus != 0 {
                    let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                    let reason = output.split(whereSeparator: \.isNewline).first { $0.hasPrefix("Error: ") }
                    continuation.finish(throwing: Failure.failed(reason.map { String($0.dropFirst(7)) } ?? "The download failed."))
                } else {
                    continuation.finish()
                }
            }
        }
    }

    /// Goes through `hf`, because a repo's folder only holds links: the files themselves sit in a store
    /// that every repo shares, and deleting the folder would leave them on disk.
    static func remove(_ repo: String) async throws {
        guard let path = tool(in: hfPaths) else { throw Failure.missingTool }
        let status: Int32 = try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["cache", "rm", "model/\(repo)", "--yes"]
            process.environment = environment([:])
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }.value
        if status != 0 { throw Failure.failed("Couldn't remove \(repo).") }
    }

    /// How much of a repo is on disk. A file on its way in sits in the repo's folder, and a finished one
    /// is a link to the shared store, so following the links counts both.
    private static func onDisk(_ repo: String) -> Int64 {
        let blobs = cache.appendingPathComponent("models--\(repo.replacingOccurrences(of: "/", with: "--"))/blobs")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: blobs.path)) ?? []
        return names.reduce(0) { total, name in
            let file = blobs.appendingPathComponent(name).resolvingSymlinksInPath()
            let size = (try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0
            return total + Int64(size)
        }
    }
}
