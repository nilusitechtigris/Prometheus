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

    static var isInstalled: Bool { tool(in: serverPaths) != nil }

    private static func environment(_ extra: [String: String]) -> [String: String] {
        ProcessInfo.processInfo.environment.merging(extra.merging(["HF_HUB_DISABLE_TELEMETRY": "1"]) { new, _ in new }) { _, new in new }
    }

    /// Offline, because the server otherwise asks Hugging Face about a model each time it loads one.
    /// Only downloads someone chose should go online.
    static func startServer(port: Int) -> Process? {
        guard let path = tool(in: serverPaths) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--host", "127.0.0.1", "--port", "\(port)"]
        process.environment = environment(["HF_HUB_OFFLINE": "1"])
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        return (try? process.run()) == nil ? nil : process
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
        let blobs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub/models--\(repo.replacingOccurrences(of: "/", with: "--"))/blobs")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: blobs.path)) ?? []
        return names.reduce(0) { total, name in
            let file = blobs.appendingPathComponent(name).resolvingSymlinksInPath()
            let size = (try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0
            return total + Int64(size)
        }
    }
}
