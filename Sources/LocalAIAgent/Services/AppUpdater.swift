import AppKit
import Foundation
import Observation

/// The Update button. It runs the update script that ships inside the app: once to download the
/// newest code and build it while this copy keeps working, then again to swap the new copy in after
/// this one quits. Nothing goes online until the button is pressed.
@MainActor
@Observable
final class AppUpdater {
    enum Phase: Equatable {
        case idle
        case working(String)
        case upToDate
        /// Built, and waiting for a test, reply or download to finish before restarting.
        case waitingForWork
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
    private let isBusy: @MainActor () -> Bool

    init(isBusy: @escaping @MainActor () -> Bool) {
        self.isBusy = isBusy
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
        phase = .working("Looking for updates")
        Task {
            do {
                var failure: String?
                let status = try await build(with: script, failure: &failure)
                if status == 0 {
                    await restartWhenIdle(with: script)
                } else if status == Self.upToDateStatus {
                    phase = .upToDate
                } else {
                    phase = .failed(failure ?? "The update stopped before it finished.")
                }
            } catch {
                phase = .failed("Couldn't start the update: \(error.localizedDescription)")
            }
        }
    }

    /// Downloads and builds, showing the script's progress as it goes. Returns its exit code.
    private func build(with script: String, failure: inout String?) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script, "--build-only", "--app", Bundle.main.bundlePath]
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
            } else if line.hasPrefix("✗ ") {
                failure = String(line.dropFirst(2))
            }
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Hands over to the script, which outlives this copy, replaces it and opens the new one.
    private func restartWhenIdle(with script: String) async {
        if isBusy() { phase = .waitingForWork }
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
