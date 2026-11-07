import AppKit
import Foundation
import Observation

/// The Update button. It runs the update script that ships inside the app: once to update the
/// frameworks Homebrew installed and to download the newest code and build it while this copy keeps
/// working, then again to swap the new copy in after this one quits. Nothing goes online until the
/// button is pressed.
@MainActor
@Observable
final class AppUpdater {
    enum Phase: Equatable {
        case idle
        case working(String)
        case upToDate
        /// Waiting for a test, reply or download to finish before restarting, saying what will restart.
        case waitingForWork(String)
        case failed(String)
    }

    /// How the script says there's nothing to do. Matches EXIT_UP_TO_DATE in scripts/update-app.sh.
    private static let upToDateStatus: Int32 = 3
    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Prometheus-update.log")
    private static let script = Bundle.main.path(forResource: "update-app", ofType: "sh")

    /// The commit this copy was built from. Only copies made by the build script have one.
    static let commit: String? = {
        let value = Bundle.main.object(forInfoDictionaryKey: "PrometheusCommit") as? String
        return value?.isEmpty == false ? value : nil
    }()

    private(set) var phase: Phase = .idle
    /// What the update brings, one line for each change.
    private(set) var changes: [String] = []
    /// Frameworks the update upgraded, by their Homebrew names. They run the old version until restarted.
    private var upgraded: Set<String> = []
    private let isBusy: @MainActor () -> Bool
    /// Restarts the MLX LM server the app runs, so it picks up a new version.
    private let restartMLX: @MainActor () async -> Void

    init(isBusy: @escaping @MainActor () -> Bool, restartMLX: @escaping @MainActor () async -> Void) {
        self.isBusy = isBusy
        self.restartMLX = restartMLX
        // The last step runs after this copy has quit, so the log is the only way to hear it failed.
        if let failure = Self.lastFailure() { phase = .failed(failure) }
    }

    var canUpdate: Bool {
        switch phase {
        case .working, .waitingForWork: return false
        default: return Self.script != nil
        }
    }

    func update() {
        guard canUpdate, let script = Self.script else { return }
        changes = []
        upgraded = []
        phase = .working("Looking for updates")
        Task {
            do {
                var failure: String?
                let status = try await run(script, ["--build-only", "--app", Bundle.main.bundlePath], failure: &failure)
                if status == 0 {
                    // The script restarts the frameworks once this copy has quit.
                    await restartWhenIdle(with: script)
                    return
                }
                // Frameworks can be upgraded even when the app has nothing new or its build failed.
                if !upgraded.isEmpty { await restartFrameworksWhenIdle(with: script) }
                if status == Self.upToDateStatus {
                    phase = .upToDate
                } else {
                    phase = .failed(failure ?? "The update stopped before it finished.")
                }
            } catch {
                phase = .failed("Couldn't start the update: \(error.localizedDescription)")
            }
        }
    }

    /// Runs the script, showing its progress as it goes. Returns its exit code.
    private func run(_ script: String, _ arguments: [String], failure: inout String?) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        try process.run()
        for try await line in output.fileHandleForReading.bytes.lines {
            if line.hasPrefix("→ ") {
                phase = .working(String(line.dropFirst(2)))
            } else if line.hasPrefix("• ") {
                changes.append(String(line.dropFirst(2)))
            } else if line.hasPrefix("↻ ") {
                upgraded.insert(String(line.dropFirst(2)))
            } else if line.hasPrefix("✗ ") {
                failure = String(line.dropFirst(2))
            }
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// The app stays as it is, but upgraded frameworks still need a restart to run their new version.
    /// That waits for the same work a restart of the app would, since a test could be using them.
    private func restartFrameworksWhenIdle(with script: String) async {
        if isBusy() { phase = .waitingForWork("Frameworks updated. Restarting them when the current work finishes.") }
        while isBusy() { try? await Task.sleep(for: .seconds(1)) }
        phase = .working("Restarting the frameworks")
        var ignored: String?
        _ = try? await run(script, ["--restart-frameworks"], failure: &ignored)
        if upgraded.contains("mlx-lm") { await restartMLX() }
    }

    /// Hands over to the script, which outlives this copy, replaces it and opens the new one.
    private func restartWhenIdle(with script: String) async {
        if isBusy() { phase = .waitingForWork("Ready. Restarting when the current work finishes.") }
        while isBusy() { try? await Task.sleep(for: .seconds(1)) }
        phase = .working("Restarting")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script, "--install-when-closed", "\(ProcessInfo.processInfo.processIdentifier)",
                             "--app", Bundle.main.bundlePath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            phase = .failed("Couldn't finish the update: \(error.localizedDescription)")
        }
    }

    private static func lastFailure() -> String? {
        guard let log = try? String(contentsOf: logURL, encoding: .utf8),
              let last = log.split(whereSeparator: \.isNewline).last, last.hasPrefix("✗ ") else { return nil }
        return String(last.dropFirst(2))
    }
}
